import CodexBarCore
import Foundation

/// A host-only diagnostic mode for #1711. It exercises the real AppKit status-item lifecycle
/// without starting provider refreshes or reading user credentials.
enum VisibilityHarness {
    static let launchArgument = "--visibility-harness"
    static let resultPathEnvironmentKey = "CODEXBAR_VISIBILITY_HARNESS_RESULT_PATH"

    static var isEnabled: Bool {
        DiagnosticHarness.current == .visibility
    }

    static func isRequested(arguments: [String]) -> Bool {
        arguments.dropFirst().contains(self.launchArgument)
    }

    static func makeDefaults() -> UserDefaults {
        let suiteName = "com.steipete.codexbar.visibility-harness.\(ProcessInfo.processInfo.processIdentifier)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create isolated visibility harness defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    static func makeConfig() -> CodexBarConfig {
        var config = CodexBarConfig.makeDefault()
        for index in config.providers.indices {
            config.providers[index].enabled = config.providers[index].id == .codex
        }
        return config
    }

    static func record(
        _ event: String,
        snapshots: [StatusItemVisibilitySnapshot] = [],
        evidence: [StatusItemStartupVisibilityEvidence] = [],
        windows: String? = nil)
    {
        guard self.isEnabled,
              let rawPath = ProcessInfo.processInfo.environment[self.resultPathEnvironmentKey],
              !rawPath.isEmpty
        else {
            return
        }

        let record = Record(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            event: event,
            pid: ProcessInfo.processInfo.processIdentifier,
            snapshots: snapshots.map(\.description),
            evidence: evidence.map(\.description),
            windows: windows)
        guard let data = try? JSONEncoder().encode(record) else { return }

        let url = URL(fileURLWithPath: rawPath)
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                _ = FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data([0x0A]))
        } catch {
            CodexBarLog.logger(LogCategories.app).error(
                "Visibility harness could not write evidence",
                metadata: ["path": rawPath])
        }
    }

    private struct Record: Encodable {
        let timestamp: String
        let event: String
        let pid: Int32
        let snapshots: [String]
        let evidence: [String]
        let windows: String?
    }
}
