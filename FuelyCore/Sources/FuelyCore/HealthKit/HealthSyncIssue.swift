import Foundation
import HealthKit

/// Why a HealthKit write failed, coarse enough for the UI (e.g. "Health access off") and for
/// `HealthSync` to decide whether to keep pushing.
public enum HealthSyncIssue: String, Codable, Sendable, Hashable {
    /// Protected data unavailable (phone locked). Transient: the push stops and retries later.
    case locked
    /// Health access denied or not yet asked. Shown as "Health access off".
    case notAuthorized
    /// Health data is unavailable or restricted on this device.
    case unavailable
    /// Anything else.
    case other

    public init(_ error: any Error) {
        if let error = error as? HealthKitClientError {
            switch error {
            case .unavailable: self = .unavailable
            }
            return
        }
        let nsError = error as NSError
        if nsError.domain == HKErrorDomain, let code = HKError.Code(rawValue: nsError.code) {
            switch code {
            case .errorDatabaseInaccessible: self = .locked
            case .errorAuthorizationDenied, .errorAuthorizationNotDetermined: self = .notAuthorized
            case .errorHealthDataUnavailable, .errorHealthDataRestricted: self = .unavailable
            default: self = .other
            }
            return
        }
        // Protected data unavailable for files (e.g. before the first unlock after a reboot).
        if nsError.domain == NSCocoaErrorDomain,
           [CocoaError.fileReadNoPermission.rawValue, CocoaError.fileWriteNoPermission.rawValue].contains(nsError.code) {
            self = .locked
            return
        }
        self = .other
    }

    /// Only a locked phone stops the push (every later job would fail the same way). Other
    /// issues skip that job, which stays queued, and the push moves on.
    public var stopsPush: Bool { self == .locked }
}
