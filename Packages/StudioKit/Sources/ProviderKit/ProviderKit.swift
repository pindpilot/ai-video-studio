import Foundation
import StudioCore
/// Adapter implementations begin only after exact operation documentation is verified.
public enum ProviderEligibility: String, Codable, Sendable {
    case verifiedOperation, unverified, excluded, scopeNeedsConfirmation
}
public struct ProviderSource: Codable, Sendable {
    public let documentationURL: URL
    public let verifiedOn: String
    public let eligibility: ProviderEligibility
    public init(documentationURL: URL, verifiedOn: String, eligibility: ProviderEligibility) {
        self.documentationURL = documentationURL; self.verifiedOn = verifiedOn
        self.eligibility = eligibility
    }
}
