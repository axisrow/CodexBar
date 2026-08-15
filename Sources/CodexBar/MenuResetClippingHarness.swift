import CodexBarCore
import Foundation

/// DEBUG-only visual regression harness for the Russian reset-countdown clipping report.
/// It uses no account credentials, provider requests, or persisted user settings.
enum MenuResetClippingHarness {
    static let launchArgument = "--repro-menu-reset-clipping"
    static let languageArgument = "--language"
    static let resetStyleArgument = "--reset-style"

    static let supportedLanguageCodes = AppLanguage.allCases
        .filter { $0 != .system }
        .map(\.rawValue)

    /// Resolved once: the launch arguments cannot change for the lifetime of the process,
    /// and this is read from menu-rendering paths.
    static let isEnabled: Bool = {
        #if DEBUG
        return MenuResetClippingHarness.isRequested(arguments: CommandLine.arguments)
        #else
        return false
        #endif
    }()

    static func isRequested(arguments: [String]) -> Bool {
        arguments.dropFirst().contains(self.launchArgument)
    }

    static func language(arguments: [String] = CommandLine.arguments) -> String {
        self.value(for: self.languageArgument, in: arguments) ?? "ru"
    }

    static func resetStyle(arguments: [String] = CommandLine.arguments) -> ResetTimeDisplayStyle {
        self.value(for: self.resetStyleArgument, in: arguments) == "absolute" ? .absolute : .countdown
    }

    private static func value(for argument: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: argument), arguments.indices.contains(arguments.index(after: index))
        else { return nil }
        return arguments[arguments.index(after: index)]
    }

    static func makeDefaults() -> UserDefaults {
        let suiteName = "com.steipete.codexbar.menu-reset-clipping.\(ProcessInfo.processInfo.processIdentifier)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create isolated reset clipping harness defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(self.language(), forKey: "appLanguage")
        defaults.set(true, forKey: "mergeIcons")
        defaults.set(self.resetStyle() == .absolute, forKey: "resetTimesShowAbsolute")
        defaults.set(false, forKey: "refreshAllProvidersOnMenuOpen")
        defaults.set(UsageProvider.antigravity.rawValue, forKey: "selectedMenuProvider")
        return defaults
    }

    static func makeConfig() -> CodexBarConfig {
        let visibleProviders: [UsageProvider] = [.antigravity, .codex, .claude, .zai, .ollama]
        var config = CodexBarConfig.makeDefault()
        // Partition once, in screenshot order: the visible providers first, everything else disabled.
        var remaining = config.providers
        var ordered: [ProviderConfig] = []
        for provider in visibleProviders {
            guard let index = remaining.firstIndex(where: { $0.id.firstPartyProvider == provider }) else { continue }
            var entry = remaining.remove(at: index)
            entry.enabled = true
            ordered.append(entry)
        }
        config.providers = ordered + remaining.map {
            var entry = $0
            entry.enabled = false
            return entry
        }
        return config
    }

    #if DEBUG
    @MainActor
    static func installFixture(in store: UsageStore, force: Bool = false) {
        guard force || self.isEnabled else { return }
        store._setSnapshotForTesting(self.snapshot(), provider: .antigravity)
    }
    #endif

    static func snapshot(
        now: Date = .init(),
        style: ResetTimeDisplayStyle? = nil) -> UsageSnapshot
    {
        let style = style ?? self.resetStyle()
        let resetDate = now.addingTimeInterval(7 * 24 * 60 * 60 + 23 * 60 * 60)
        return UsageSnapshot(
            primary: nil,
            secondary: nil,
            extraRateWindows: [
                NamedRateWindow(
                    id: "antigravity-quota-summary-gemini-weekly",
                    title: "Gemini weekly",
                    window: RateWindow(
                        usedPercent: 99.5,
                        windowMinutes: 7 * 24 * 60,
                        resetsAt: style == .absolute ? resetDate : nil,
                        resetDescription: style == .absolute ? nil : "fully refresh in 7d 23h")),
                NamedRateWindow(
                    id: "antigravity-quota-summary-claude-gpt-weekly",
                    title: "Claude/GPT weekly",
                    window: RateWindow(
                        usedPercent: 0,
                        windowMinutes: 7 * 24 * 60,
                        resetsAt: style == .absolute ? resetDate : nil,
                        resetDescription: style == .absolute ? nil : "fully refresh in 7d 23h")),
            ],
            updatedAt: now,
            identity: ProviderIdentitySnapshot(
                providerID: .antigravity,
                accountEmail: "axisrow@gmail.com",
                accountOrganization: nil,
                loginMethod: "Google AI Plus"),
            dataConfidence: .exact)
    }
}
