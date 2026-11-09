import Foundation

/// Who wrote a water entry. Only Fuely's own entries can be deleted (DECISIONS W7).
public enum WaterSource: Codable, Sendable, Hashable {
    case fuely
    /// Written by another app; read-only. `name` is the source shown in the UI.
    case external(name: String)
}

/// One drink, in millilitres.
public struct WaterEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var date: Date
    public var amountML: Int
    public var source: WaterSource
    /// The matching HealthKit sample, once synced (entries are stored locally first, DECISIONS W4).
    public var healthKitSampleID: UUID?
    /// When Fuely last saw this entry stored in HealthKit (its save finished, or a read found it).
    /// A read that started earlier can't prove the sample is gone.
    public var syncedAt: Date?

    public init(id: UUID = UUID(), date: Date, amountML: Int, source: WaterSource = .fuely,
                healthKitSampleID: UUID? = nil, syncedAt: Date? = nil) {
        self.id = id
        self.date = date
        self.amountML = amountML
        self.source = source
        self.healthKitSampleID = healthKitSampleID
        self.syncedAt = syncedAt
    }

    public var isDeletable: Bool { source == .fuely }
}

extension WaterEntry {
    private enum CodingKeys: String, CodingKey {
        case id, date, amountML, source, healthKitSampleID, syncedAt
    }

    /// Tolerant: missing fields take defaults, unknown ones are ignored (schema evolution).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
                  date: try c.decodeIfPresent(Date.self, forKey: .date) ?? .distantPast,
                  amountML: try c.decodeIfPresent(Int.self, forKey: .amountML) ?? 0,
                  source: (try? c.decodeIfPresent(WaterSource.self, forKey: .source)) ?? .fuely,
                  healthKitSampleID: try c.decodeIfPresent(UUID.self, forKey: .healthKitSampleID),
                  syncedAt: try c.decodeIfPresent(Date.self, forKey: .syncedAt))
    }
}

/// Fixed logging amounts (DECISIONS W5, W6).
public enum WaterLogging {
    public static let quickAddAmountsML = [150, 250, 500]
    public static let defaultWidgetAmountML = 250
}
