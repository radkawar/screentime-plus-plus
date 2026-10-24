import Foundation

public struct AppSettings: Codable, Hashable, Sendable {
    /// Daily budget for distracting time (time matched by any rule).
    public var dailyGoalMinutes: Int
    /// No input for this long stops the clock.
    public var idleThresholdSeconds: Int
    /// Nil preserves the global policy for configurations saved before app overrides.
    public var appIdleOverrides: [String: AppIdleOverride]?
    /// Read page text for content rules. Off means title and address only.
    public var inspectsPageText: Bool
    /// Replace blocked tabs with a blank page in scriptable browsers.
    public var parksBrowserTabs: Bool
    public var retentionDays: Int
    /// Until then, existing rules cannot be edited, disabled or deleted.
    public var rulesLockedUntil: Date?
    /// Until then, no rule applies (the menu bar safety valve).
    public var rulesPausedUntil: Date?
    public var hasCompletedSetup: Bool
    /// Optional for older saved configurations; nil means notifications are off.
    public var weeklyReviewNotifications: Bool?
    public var sessionEndingNotifications: Bool?
    public var goalNotifications: Bool?

    public init(
        dailyGoalMinutes: Int = 90, idleThresholdSeconds: Int = 120, inspectsPageText: Bool = true,
        parksBrowserTabs: Bool = true, retentionDays: Int = 180, rulesLockedUntil: Date? = nil,
        hasCompletedSetup: Bool = false
    ) {
        self.dailyGoalMinutes = dailyGoalMinutes
        self.idleThresholdSeconds = idleThresholdSeconds
        self.inspectsPageText = inspectsPageText
        self.parksBrowserTabs = parksBrowserTabs
        self.retentionDays = retentionDays
        self.rulesLockedUntil = rulesLockedUntil
        self.hasCompletedSetup = hasCompletedSetup
    }

    public func rulesAreLocked(at date: Date) -> Bool {
        rulesLockedUntil.map { $0 > date } ?? false
    }
}

public struct AppConfiguration: Codable, Hashable, Sendable {
    public var rules: [Rule]
    public var focus: FocusSession?
    public var grants: [AccessGrant]
    public var settings: AppSettings

    public init(
        rules: [Rule] = [], focus: FocusSession? = nil, grants: [AccessGrant] = [],
        settings: AppSettings = AppSettings()
    ) {
        self.rules = rules
        self.focus = focus
        self.grants = grants
        self.settings = settings
    }

    public static let starter = AppConfiguration(
        rules: [RuleTemplate.mindfulSocial.make(), RuleTemplate.minimalYouTube.make()]
    )
}

/// Atomic JSON persistence for rules and settings.
public struct ConfigStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static func defaultURL() throws -> URL {
        try UsageStore.defaultURL().deletingLastPathComponent().appendingPathComponent("configuration.json")
    }

    public func load() throws -> AppConfiguration? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try Self.decoder.decode(AppConfiguration.self, from: data)
    }

    public func save(_ configuration: AppConfiguration) throws {
        let data = try Self.encoder.encode(configuration)
        try data.write(to: url, options: [.atomic])
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
