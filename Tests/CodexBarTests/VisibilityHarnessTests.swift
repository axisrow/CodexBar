import Testing
@testable import CodexBar

struct VisibilityHarnessTests {
    @Test
    func `detects visibility harness launch argument`() {
        #expect(VisibilityHarness.isRequested(arguments: ["CodexBar", "--visibility-harness"]))
        #expect(!VisibilityHarness.isRequested(arguments: ["CodexBar"]))
    }

    @Test
    func `creates a single enabled provider configuration`() {
        let config = VisibilityHarness.makeConfig()

        #expect(config.providers.filter { $0.enabled == true }.map(\.id) == [.codex])
    }
}
