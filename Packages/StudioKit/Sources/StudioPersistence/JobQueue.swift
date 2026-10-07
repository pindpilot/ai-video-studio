import Foundation
import SwiftData
import StudioCore
import ProviderKit

/// Single-writer persistence actor: project records plus the persistent stage-job queue.
/// A pipeline is a DAG of idempotent stage jobs; finished work is never redone.
@ModelActor
public actor StudioStore {
    private var draining = false
    public static let maxRetries = 3
    public static let schemaVersion = 2

    public static func makeContainer(inMemory: Bool = false, storeURL: URL? = nil) throws -> ModelContainer {
        let schema = Schema([ProjectRecord.self, StageJob.self])
        let configuration: SwiftData.ModelConfiguration
        if let storeURL { configuration = SwiftData.ModelConfiguration(url: storeURL) }
        else { configuration = SwiftData.ModelConfiguration(isStoredInMemoryOnly: inMemory) }
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    // MARK: Projects

    @discardableResult
    public func createProject(name: String, idea: String) -> ProjectSnapshot {
        let record = ProjectRecord(id: UUID(), name: name, idea: idea)
        modelContext.insert(record)
        try? modelContext.save()
        return projectSnapshot(record)
    }

    public func projects() -> [ProjectSnapshot] {
        let records = (try? modelContext.fetch(FetchDescriptor<ProjectRecord>())) ?? []
        return records.map(projectSnapshot).sorted { $0.name < $1.name }
    }

    public func saveScriptVersion(_ version: String, projectID: UUID) {
        guard let record = fetchProject(projectID) else { return }
        var versions = (try? JSONDecoder().decode([String].self, from: record.scriptVersionsData)) ?? []
        versions.append(version)
        record.scriptVersionsData = (try? JSONEncoder().encode(versions)) ?? Data()
        record.updatedAt = Date()
        try? modelContext.save()
    }

    private func projectSnapshot(_ record: ProjectRecord) -> ProjectSnapshot {
        let versions = (try? JSONDecoder().decode([String].self, from: record.scriptVersionsData)) ?? []
        return ProjectSnapshot(id: record.id, schemaVersion: record.schemaVersion, name: record.name, idea: record.idea, scriptVersions: versions)
    }

    // MARK: Queue writes

    /// Idempotent: a job for the same project, stage and scene returns the existing one.
    @discardableResult
    public func enqueue(projectID: UUID, stage: PipelineStage, sceneIndex: Int? = nil, dependsOn: [UUID] = []) -> JobSnapshot {
        if let existing = allJobs().first(where: { $0.projectID == projectID && $0.stageRaw == stage.rawValue && $0.sceneIndex == sceneIndex }) {
            return existing.snapshot()
        }
        let job = StageJob(id: UUID(), projectID: projectID, stage: stage, sceneIndex: sceneIndex, dependsOn: dependsOn)
        modelContext.insert(job)
        try? modelContext.save()
        return job.snapshot()
    }

    public func jobs(projectID: UUID? = nil) -> [JobSnapshot] {
        allJobs().filter { projectID == nil || $0.projectID == projectID }.map { $0.snapshot() }
    }

    /// Queued jobs whose dependencies all succeeded. Cancelled or failed dependencies block forever until retried.
    public func runnable() -> [JobSnapshot] {
        let all = allJobs()
        let succeeded = Set(all.filter { $0.state == .succeeded }.map(\.id))
        return all.filter { $0.state == .queued && $0.dependsOn.allSatisfy(succeeded.contains) }.map { $0.snapshot() }
    }

    public func markRunning(_ id: UUID) {
        mutate(id) { $0.stateRaw = JobState.running.rawValue }
    }

    public func markWaitingOnProvider(_ id: UUID, providerJobID: String) {
        mutate(id) { job in
            job.stateRaw = JobState.waitingOnProvider.rawValue
            job.providerJobID = providerJobID
        }
    }

    public func markSucceeded(_ id: UUID) {
        mutate(id) { job in
            job.stateRaw = JobState.succeeded.rawValue
            job.providerJobID = nil
        }
    }

    /// Requeue a failed or needs-attention job. Per-scene retry never touches succeeded siblings.
    @discardableResult
    public func retry(_ id: UUID) -> JobSnapshot? {
        var result: JobSnapshot?
        mutate(id) { job in
            guard job.state == .failed || job.state == .needsAttention, job.retryCount < Self.maxRetries else { return }
            job.retryCount += 1
            job.stateRaw = JobState.queued.rawValue
            result = job.snapshot()
        }
        return result
    }

    public func cancel(_ id: UUID) {
        mutate(id) { job in
            guard job.state != .succeeded else { return }
            job.stateRaw = JobState.cancelled.rawValue
        }
    }

    /// Call once on launch. In-memory running work is lost on relaunch, so running jobs requeue
    /// (stage operations are idempotent). Jobs waiting on a provider keep their provider job ID
    /// and are returned for re-polling; they are never resubmitted.
    @discardableResult
    public func resumeAfterLaunch() -> [JobSnapshot] {
        for job in allJobs() where job.state == .running {
            job.stateRaw = job.providerJobID == nil ? JobState.queued.rawValue : JobState.waitingOnProvider.rawValue
            job.updatedAt = Date()
        }
        try? modelContext.save()
        return allJobs().filter { $0.state == .waitingOnProvider }.map { $0.snapshot() }
    }

    // MARK: Execution

    /// Sequentially drains runnable jobs with the injected stage operations.
    /// Sequential execution is an honest concurrency cap of one until real async adapters land.
    /// Returns the snapshots of jobs that reached a terminal state this pass.
    @discardableResult
    public func drain(operations: [PipelineStage: StageOperation]) async throws -> [JobSnapshot] {
        guard !draining else { return [] }
        draining = true
        defer { draining = false }
        var finished: [JobSnapshot] = []
        while let snapshot = runnable().first {
            try Task.checkCancellation()
            guard let operation = operations[snapshot.stage] else {
                failInternal(snapshot.id, errorClass: nil, message: "No operation registered for stage")
                if let updated = snapshotFor(snapshot.id) { finished.append(updated) }
                continue
            }
            mutate(snapshot.id) { $0.stateRaw = JobState.running.rawValue }
            let started = Date()
            do {
                let result = try await operation(snapshot)
                // Cancellation during the suspended operation must not be overwritten.
                guard snapshotFor(snapshot.id)?.state == .running else { continue }
                if let providerJobID = result.providerJobID {
                    // Async provider job: persist the ID immediately, stop local work, re-poll after relaunch.
                    markWaitingOnProvider(snapshot.id, providerJobID: providerJobID)
                } else {
                    markSucceeded(snapshot.id)
                    appendAttempt(snapshot.id, started: started, errorClass: nil, reason: "Succeeded")
                    if let updated = snapshotFor(snapshot.id) { finished.append(updated) }
                }
            } catch is CancellationError {
                if snapshotFor(snapshot.id)?.state == .running {
                    mutate(snapshot.id) { $0.stateRaw = JobState.queued.rawValue }
                }
                throw CancellationError()
            } catch {
                guard snapshotFor(snapshot.id)?.state == .running else { continue }
                let failure = error as? ProviderFailure ?? ProviderFailure(.transient, message: "Unknown stage error")
                if failure.kind == .invalidRequest || failure.kind == .policyRefused {
                    // User must see invalid-input and policy refusals; never reroute or retry them.
                    mutate(snapshot.id) { job in
                        job.stateRaw = JobState.needsAttention.rawValue
                        job.lastErrorClassRaw = failure.kind.rawValue
                        job.lastErrorMessage = failure.message
                    }
                } else {
                    failInternal(snapshot.id, errorClass: failure.kind, message: failure.message)
                }
                appendAttempt(snapshot.id, started: started, errorClass: failure.kind, reason: failure.message)
                if let updated = snapshotFor(snapshot.id) { finished.append(updated) }
            }
        }
        return finished
    }

    // MARK: Internals

    private func allJobs() -> [StageJob] {
        (try? modelContext.fetch(FetchDescriptor<StageJob>())) ?? []
    }

    private func fetchProject(_ id: UUID) -> ProjectRecord? {
        let records = (try? modelContext.fetch(FetchDescriptor<ProjectRecord>())) ?? []
        return records.first { $0.id == id }
    }

    private func snapshotFor(_ id: UUID) -> JobSnapshot? {
        allJobs().first { $0.id == id }?.snapshot()
    }

    private func mutate(_ id: UUID, _ change: (StageJob) -> Void) {
        guard let job = allJobs().first(where: { $0.id == id }) else { return }
        change(job)
        job.updatedAt = Date()
        try? modelContext.save()
    }

    private func failInternal(_ id: UUID, errorClass: ProviderErrorClass?, message: String) {
        mutate(id) { job in
            job.stateRaw = JobState.failed.rawValue
            job.lastErrorClassRaw = errorClass?.rawValue
            job.lastErrorMessage = message
        }
    }

    private func appendAttempt(_ id: UUID, started: Date, errorClass: ProviderErrorClass?, reason: String) {
        mutate(id) { job in
            var attempts = job.attempts
            attempts.append(Attempt(modelID: job.stageRaw, date: started, latency: Date().timeIntervalSince(started), errorClass: errorClass, reason: reason))
            job.attemptsData = (try? JSONEncoder().encode(attempts)) ?? Data()
        }
    }
}
