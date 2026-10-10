import Foundation

/// Photoreal stills through Blender's Cycles renderer. Blender is a free, separate program the person installs;
/// Hestia exports the house as OpenUSD and runs Blender in the background with `hestia_render.py`, which adds
/// CC0 materials, models, and sky from Poly Haven (credited in the app) and renders. Nothing of Blender is built
/// into Hestia. Each picture gets a manifest beside it listing every asset file used.
enum PhotoRender {
    enum View: String, CaseIterable, Sendable {
        case exterior
        case interior
    }

    struct Failure: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    /// Where Blender is installed, if it is: the usual app locations, then the shell's search path.
    static func blender() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates = ["/Applications/Blender.app/Contents/MacOS/Blender",
                          home + "/Applications/Blender.app/Contents/MacOS/Blender",
                          "/opt/homebrew/bin/blender", "/usr/local/bin/blender"]
        for directory in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            candidates.append(String(directory) + "/blender")
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }

    /// The render script: in the app's resources, or, run from the repository, in `tools/blender`.
    static func script() -> URL? {
        if let url = Bundle.main.url(forResource: "hestia_render", withExtension: "py") { return url }
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return nil }
        var directory = executable.deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = directory.appendingPathComponent("tools/blender/hestia_render.py")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            directory.deleteLastPathComponent()
        }
        return nil
    }

    /// Downloaded materials, models, and sky, kept between renders.
    static var cache: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hestia/assets", isDirectory: true)
    }

    /// Whether an earlier render already downloaded assets into the cache.
    static var hasAssets: Bool {
        FileManager.default.fileExists(atPath: cache.appendingPathComponent("index").path)
    }

    /// Renders `usd` to `output` with Blender and returns when the picture is written. Throws with Blender's last
    /// lines when it fails.
    static func render(blender: URL, script: URL, usd: URL, output: URL, view: View, samples: Int = 128,
                       size: String = "1920x1080") async throws {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("hestia-render-\(UUID()).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        let arguments = ["-b", "--factory-startup", "--python", script.path, "--",
                         "--usd", usd.path, "--out", output.path, "--view", view.rawValue,
                         "--samples", String(samples), "--size", size, "--cache", cache.path]
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = blender
            process.arguments = arguments
            process.standardOutput = handle
            process.standardError = handle
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        try? handle.close()
        let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        try? FileManager.default.removeItem(at: log)
        guard status == 0, FileManager.default.fileExists(atPath: output.path) else {
            let tail = text.split(separator: "\n").suffix(4).joined(separator: " ")
            throw Failure(message: "Blender could not render the house. \(tail)")
        }
    }
}
