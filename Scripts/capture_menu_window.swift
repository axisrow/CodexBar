import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Arguments {
    let pid: Int32
    let output: URL

    init() throws {
        // Match flags by name rather than stepping in pairs, so a valueless flag
        // cannot shift every argument that follows it.
        let arguments = CommandLine.arguments
        func value(for flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        let values = ["--pid": value(for: "--pid"), "--output": value(for: "--output")]
            .compactMapValues { $0 }
        guard let pidValue = values["--pid"], let pid = Int32(pidValue),
              let output = values["--output"], !output.isEmpty
        else {
            throw NSError(domain: "CodexBarCapture", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Usage: capture_menu_window.swift --pid PID --output PATH",
            ])
        }
        self.pid = pid
        self.output = URL(fileURLWithPath: output)
    }
}

func windowID(for pid: Int32) -> CGWindowID? {
    guard let records = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
        as? [[String: Any]]
    else { return nil }

    return records.compactMap { record -> (CGWindowID, CGFloat)? in
        guard let ownerPID = record[kCGWindowOwnerPID as String] as? Int,
              ownerPID == Int(pid),
              let windowID = record[kCGWindowNumber as String] as? CGWindowID,
              let bounds = record[kCGWindowBounds as String] as? [String: CGFloat]
        else { return nil }
        let width = bounds["Width"] ?? 0
        let height = bounds["Height"] ?? 0
        guard width >= 280, height >= 100 else { return nil }
        return (windowID, width * height)
    }
    .max(by: { $0.1 < $1.1 })?.0
}

func writePNG(_ image: CGImage, to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil)
    else {
        throw NSError(domain: "CodexBarCapture", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "Could not create PNG destination",
        ])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "CodexBarCapture", code: 4, userInfo: [
            NSLocalizedDescriptionKey: "Could not finalize PNG",
        ])
    }
}

do {
    let arguments = try Arguments()
    var capturedImage: CGImage?
    for _ in 0..<40 {
        if let id = windowID(for: arguments.pid) {
            capturedImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                id,
                [.bestResolution])
            if capturedImage != nil { break }
        }
        usleep(50_000)
    }
    guard let capturedImage else {
        throw NSError(domain: "CodexBarCapture", code: 5, userInfo: [
            NSLocalizedDescriptionKey: "No menu window found for PID \(arguments.pid)",
        ])
    }
    try writePNG(capturedImage, to: arguments.output)
} catch {
    fputs("capture_menu_window.swift: \(error.localizedDescription)\n", stderr)
    exit(1)
}
