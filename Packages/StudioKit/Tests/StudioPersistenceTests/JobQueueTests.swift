import XCTest
import SwiftData
@testable import StudioPersistence
import StudioCore
import ProviderKit

final class JobQueueTests: XCTestCase {
    private func store(inMemory: Bool = true, url: URL? = nil) throws -> StudioStore {
        StudioStore(modelContainer: try StudioStore.makeContainer(inMemory: inMemory, storeURL: url))
    }

    func testDAGGatingAndSuccess() async throws {
        let store = try store()
        let project = await store.createProject(name: "Demo", idea: "Idea")
        let script = await store.enqueue(projectID: project.id, stage: .script)
        let scenes = await store.enqueue(projectID: project.id, stage: .scenes, dependsOn: [script.id])
        var runnable = await store.runnable()
        XCTAssertEqual(runnable.map(\.id), [script.id])
        let finished = try await store.drain(operations: [
            .script: { _ in GenerationResult(text: "Script") },
            .scenes: { _ in GenerationResult(text: "Scenes") }
        ])
        XCTAssertEqual(finished.count, 2)
        runnable = await store.runnable()
        XCTAssertTrue(runnable.isEmpty)
        let jobs = await store.jobs(projectID: project.id)
        XCTAssertEqual(Set(jobs.map(\.state)), [.succeeded])
        _ = scenes
    }

    func testEnqueueIsIdempotent() async throws {
        let store = try store()
        let project = await store.createProject(name: "Demo", idea: "Idea")
        let first = await store.enqueue(projectID: project.id, stage: .script)
        let second = await store.enqueue(projectID: project.id, stage: .script)
        XCTAssertEqual(first.id, second.id)
        let jobs = await store.jobs(projectID: project.id)
        XCTAssertEqual(jobs.count, 1)
    }

    func testPolicyRefusalBecomesNeedsAttentionNeverRetried() async throws {
        let store = try store()
        let project = await store.createProject(name: "Demo", idea: "Idea")
        _ = await store.enqueue(projectID: project.id, stage: .visuals)
        let finished = try await store.drain(operations: [
            .visuals: { _ in throw ProviderFailure(.policyRefused, message: "Refused by provider policy") }
        ])
        XCTAssertEqual(finished.first?.state, .needsAttention)
        XCTAssertEqual(finished.first?.lastErrorClass, .policyRefused)
        let runnable = await store.runnable()
        XCTAssertTrue(runnable.isEmpty)
    }

    func testFailureAndBoundedRetry() async throws {
        let store = try store()
        let project = await store.createProject(name: "Demo", idea: "Idea")
        let job = await store.enqueue(projectID: project.id, stage: .voiceover)
        let finished = try await store.drain(operations: [
            .voiceover: { _ in throw ProviderFailure(.quotaExceeded, message: "Quota exhausted") }
        ])
        XCTAssertEqual(finished.first?.state, .failed)
        XCTAssertEqual(finished.first?.lastErrorClass, .quotaExceeded)
        XCTAssertEqual(finished.first?.attempts.count, 1)
        for expected in 1...StudioStore.maxRetries {
            let retried = await store.retry(job.id)
            XCTAssertEqual(retried?.retryCount, expected)
            _ = try await store.drain(operations: [
                .voiceover: { _ in throw ProviderFailure(.quotaExceeded, message: "Quota exhausted") }
            ])
        }
        let beyond = await store.retry(job.id)
        XCTAssertNil(beyond)
        let attempts = await store.jobs(projectID: project.id).first?.attempts.count
        XCTAssertEqual(attempts, 1 + StudioStore.maxRetries)
    }

    func testCancelBlocksDependents() async throws {
        let store = try store()
        let project = await store.createProject(name: "Demo", idea: "Idea")
        let script = await store.enqueue(projectID: project.id, stage: .script)
        _ = await store.enqueue(projectID: project.id, stage: .scenes, dependsOn: [script.id])
        await store.cancel(script.id)
        let runnable = await store.runnable()
        XCTAssertTrue(runnable.isEmpty)
        let finished = try await store.drain(operations: [
            .script: { _ in GenerationResult(text: "Script") },
            .scenes: { _ in GenerationResult(text: "Scenes") }
        ])
        XCTAssertTrue(finished.isEmpty)
    }

    func testAsyncProviderJobPersistedThenResumedNotResubmitted() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aistudio-test-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        var jobID = UUID()
        do {
            let first = try store(url: url)
            let project = await first.createProject(name: "Demo", idea: "Idea")
            let job = await first.enqueue(projectID: project.id, stage: .visuals, sceneIndex: 0)
            jobID = job.id
            let finished = try await first.drain(operations: [
                .visuals: { _ in GenerationResult(providerJobID: "provider-job-123") }
            ])
            XCTAssertTrue(finished.isEmpty)
            let waiting = await first.jobs(projectID: project.id).first
            XCTAssertEqual(waiting?.state, .waitingOnProvider)
            XCTAssertEqual(waiting?.providerJobID, "provider-job-123")
        }
        // Simulate kill and relaunch: a new container over the same store file.
        let second = try store(url: url)
        let toRepoll = await second.resumeAfterLaunch()
        XCTAssertEqual(toRepoll.count, 1)
        XCTAssertEqual(toRepoll.first?.id, jobID)
        XCTAssertEqual(toRepoll.first?.providerJobID, "provider-job-123")
        let runnable = await second.runnable()
        XCTAssertTrue(runnable.isEmpty, "A waiting job must be re-polled, never resubmitted")
    }

    func testRunningJobRequeuesOnRelaunch() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aistudio-test-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let first = try store(url: url)
            let project = await first.createProject(name: "Demo", idea: "Idea")
            let job = await first.enqueue(projectID: project.id, stage: .edit)
            await first.markRunning(job.id)
        }
        let second = try store(url: url)
        _ = await second.resumeAfterLaunch()
        let jobs = await second.jobs()
        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(jobs.first?.state, .queued)
    }
}
