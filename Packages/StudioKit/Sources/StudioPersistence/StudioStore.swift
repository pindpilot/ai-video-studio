import Foundation
import SwiftData
import StudioCore
import ProviderKit

public enum JobState: String, Codable, Sendable, CaseIterable {
    case queued, running, waitingOnProvider, succeeded, failed, needsAttention, cancelled
}

@Model
public final class ProjectRecord {
    @Attribute(.unique) public var id: UUID
    public var schemaVersion: Int
    public var name: String
    public var idea: String
    public var scriptVersionsData: Data
    public var createdAt: Date
    public var updatedAt: Date
    public init(id: UUID, name: String, idea: String) {
        self.id = id
        self.schemaVersion = StudioProject.currentSchemaVersion
        self.name = name
        self.idea = idea
        self.scriptVersionsData = (try? JSONEncoder().encode([String]())) ?? Data()
        self.createdAt = Date(); self.updatedAt = Date()
    }
}

@Model
public final class StageJob {
    @Attribute(.unique) public var id: UUID
    public var projectID: UUID
    public var stageRaw: String
    public var sceneIndex: Int?
    public var stateRaw: String
    public var dependsOnData: Data
    public var providerJobID: String?
    public var retryCount: Int
    public var lastErrorClassRaw: String?
    public var lastErrorMessage: String?
    public var attemptsData: Data
    public var createdAt: Date
    public var updatedAt: Date
    public init(id: UUID, projectID: UUID, stage: PipelineStage, sceneIndex: Int?, dependsOn: [UUID]) {
        self.id = id
        self.projectID = projectID
        self.stageRaw = stage.rawValue
        self.sceneIndex = sceneIndex
        self.stateRaw = JobState.queued.rawValue
        self.dependsOnData = (try? JSONEncoder().encode(dependsOn)) ?? Data()
        self.providerJobID = nil
        self.retryCount = 0
        self.lastErrorClassRaw = nil
        self.lastErrorMessage = nil
        self.attemptsData = (try? JSONEncoder().encode([Attempt]())) ?? Data()
        self.createdAt = Date(); self.updatedAt = Date()
    }
}

public struct JobSnapshot: Sendable {
    public let id: UUID
    public let projectID: UUID
    public let stage: PipelineStage
    public let sceneIndex: Int?
    public let state: JobState
    public let dependsOn: [UUID]
    public let providerJobID: String?
    public let retryCount: Int
    public let lastErrorClass: ProviderErrorClass?
    public let lastErrorMessage: String?
    public let attempts: [Attempt]
    public let updatedAt: Date
}

public struct ProjectSnapshot: Sendable {
    public let id: UUID
    public let schemaVersion: Int
    public let name: String
    public let idea: String
    public let scriptVersions: [String]
}

public typealias StageOperation = @Sendable (JobSnapshot) async throws -> GenerationResult

extension StageJob {
    var stage: PipelineStage { PipelineStage(rawValue: stageRaw) ?? .script }
    var state: JobState { JobState(rawValue: stateRaw) ?? .queued }
    var dependsOn: [UUID] { (try? JSONDecoder().decode([UUID].self, from: dependsOnData)) ?? [] }
    var attempts: [Attempt] { (try? JSONDecoder().decode([Attempt].self, from: attemptsData)) ?? [] }
    func snapshot() -> JobSnapshot {
        JobSnapshot(id: id, projectID: projectID, stage: stage, sceneIndex: sceneIndex, state: state,
                    dependsOn: dependsOn, providerJobID: providerJobID, retryCount: retryCount,
                    lastErrorClass: lastErrorClassRaw.flatMap { ProviderErrorClass(rawValue: $0) },
                    lastErrorMessage: lastErrorMessage, attempts: attempts, updatedAt: updatedAt)
    }
}
