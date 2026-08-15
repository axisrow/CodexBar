import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct MenuResetClippingHarnessTests {
    @Test
    func `detects reset clipping harness launch argument`() {
        #expect(MenuResetClippingHarness.isRequested(arguments: [
            "CodexBar",
            "--repro-menu-reset-clipping",
        ]))
        #expect(!MenuResetClippingHarness.isRequested(arguments: ["CodexBar"]))
    }

    @Test
    func `parses language and reset style arguments`() {
        let arguments = [
            "CodexBar",
            "--repro-menu-reset-clipping",
            "--language", "zh-Hans",
            "--reset-style", "absolute",
        ]

        #expect(MenuResetClippingHarness.language(arguments: arguments) == "zh-Hans")
        #expect(MenuResetClippingHarness.resetStyle(arguments: arguments) == .absolute)
    }

    @Test
    func `lists every non-system app language`() {
        // Assert the property, not a literal count: adding a language must not fail this test.
        #expect(MenuResetClippingHarness.supportedLanguageCodes.count == AppLanguage.allCases.count - 1)
        #expect(!MenuResetClippingHarness.supportedLanguageCodes.contains(AppLanguage.system.rawValue))
        #expect(MenuResetClippingHarness.supportedLanguageCodes.contains("ru"))
        #expect(MenuResetClippingHarness.supportedLanguageCodes.contains("zh-Hans"))
        #expect(!MenuResetClippingHarness.supportedLanguageCodes.contains(""))
    }

    @Test
    func `detects the language list request`() {
        #expect(MenuResetClippingHarness.isLanguageListRequested(arguments: ["CodexBar", "--list-languages"]))
        #expect(!MenuResetClippingHarness.isLanguageListRequested(arguments: ["CodexBar"]))
    }

    @Test
    func `uses the screenshot provider ordering`() {
        let enabled = MenuResetClippingHarness.makeConfig().providers
            .filter { $0.enabled == true }
            .compactMap(\.id.firstPartyProvider)

        #expect(enabled == [.antigravity, .codex, .claude, .zai, .ollama])
    }

    @Test
    func `supplies two long weekly reset lines`() throws {
        let snapshot = MenuResetClippingHarness.snapshot(now: Date(timeIntervalSince1970: 0))
        let windows = try #require(snapshot.extraRateWindows)

        #expect(windows.map(\.title) == ["Gemini weekly", "Claude/GPT weekly"])
        #expect(windows.allSatisfy { $0.window.resetDescription == "fully refresh in 7d 23h" })
        #expect(windows.first?.window.usedPercent == 99.5)
        #expect(windows.last?.window.usedPercent == 0)
    }

    @Test
    @MainActor
    func `fixture installs without starting a provider refresh`() {
        let defaults = MenuResetClippingHarness.makeDefaults()
        let settings = SettingsStore(userDefaults: defaults, performInitialProviderDetection: false)
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: .zero),
            settings: settings,
            startupBehavior: .testing)

        MenuResetClippingHarness.installFixture(in: store, force: true)

        #expect(store.snapshot(for: .antigravity)?.extraRateWindows?.count == 2)
        #expect(store.refreshingProviders.isEmpty)
        #expect(!store.isRefreshing)
    }

    @Test
    func `absolute fixture uses fixed reset dates`() throws {
        let snapshot = MenuResetClippingHarness.snapshot(
            now: Date(timeIntervalSince1970: 0),
            style: .absolute)
        let windows = try #require(snapshot.extraRateWindows)

        #expect(windows
            .allSatisfy { $0.window.resetsAt == Date(timeIntervalSince1970: 7 * 24 * 60 * 60 + 23 * 60 * 60) })
        #expect(windows.allSatisfy { $0.window.resetDescription == nil })
    }
}
