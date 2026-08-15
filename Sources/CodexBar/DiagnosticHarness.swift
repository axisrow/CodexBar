import CodexBarCore
import Foundation

/// The host-only diagnostic modes. Exactly one can be active per process, selected by a launch
/// argument. All of them must avoid reading or changing the user's live state, so the app consults
/// `isIsolationEnabled` wherever it would otherwise touch real defaults, credentials, or providers.
enum DiagnosticHarness {
    case visibility
    case menuResetClipping

    /// Resolved once: launch arguments cannot change for the lifetime of the process, and this is
    /// read from menu-rendering paths.
    static let current: DiagnosticHarness? = {
        if VisibilityHarness.isRequested(arguments: CommandLine.arguments) {
            return .visibility
        }
        if MenuResetClippingHarness.isEnabled {
            return .menuResetClipping
        }
        return nil
    }()

    static var isIsolationEnabled: Bool {
        self.current != nil
    }

    static func makeDefaults() -> UserDefaults {
        switch self.current {
        case .menuResetClipping:
            MenuResetClippingHarness.makeDefaults()
        case .visibility, nil:
            VisibilityHarness.makeDefaults()
        }
    }

    static func makeConfig() -> CodexBarConfig {
        switch self.current {
        case .menuResetClipping:
            MenuResetClippingHarness.makeConfig()
        case .visibility, nil:
            VisibilityHarness.makeConfig()
        }
    }
}
