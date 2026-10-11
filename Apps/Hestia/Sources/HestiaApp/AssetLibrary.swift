import Foundation

/// A library of finished assets for the live 3D view: surface materials, furniture and planting models, and a
/// sky, prepared ahead of time by `tools/blender/hestia_library.py`. The default library ships inside the app;
/// the format is open, so a person's own library (models from Blender, Maya, or any program that writes USDZ)
/// can sit beside it later.
///
/// A library is a folder holding `library.json` and the files it names. Every path in it is relative to the
/// folder and must stay inside it.
struct AssetLibrary: Equatable, Sendable {
    /// A surface's texture maps and how they lie: one tile covers `tile` meters each way.
    struct Surface: Equatable, Sendable {
        var asset: String
        var tile: Double
        var diffuse: URL?
        var normal: URL?
        var rough: URL?
        /// Painted surfaces take this color; the texture gives only relief and sheen.
        var paint: [Double]?
        /// A multiplier on the texture's color.
        var tint: [Double]?
    }

    /// How a model is sized to a placed item: to its footprint (the larger scale that still fits the item's
    /// width and depth) or to its height.
    enum Fit: String, Codable, Sendable {
        case footprint
        case height
    }

    /// A finished model: y up, its footprint centered on the origin, standing on y = 0, meters, front toward +z.
    struct Model: Equatable, Sendable {
        var asset: String
        var file: URL
        var fit: Fit
        /// Extra turn about y, degrees counterclockwise seen from above, for models drawn facing elsewhere.
        var turn: Double
        /// Width (x), height (y), and depth (z) in meters.
        var size: [Double]
    }

    /// The sky: an equirectangular image whose middle column looks north, turned so its sun stands at
    /// `sunAzimuth` degrees clockwise from north and `sunElevation` degrees up.
    struct Sky: Equatable, Sendable {
        var file: URL
        var sunAzimuth: Double
        var sunElevation: Double
    }

    var root: URL
    var surfaces: [String: Surface]
    var models: [String: Model]
    var sky: Sky?

    enum LoadError: Error, Equatable {
        case unreadable
        case unsupportedVersion(Int)
        case unsafePath(String)
    }

    /// The default library inside the app, or the one `HESTIA_LIBRARY` names (for development and tests).
    static func standard(environment: [String: String] = ProcessInfo.processInfo.environment,
                         bundle: Bundle = .main) -> AssetLibrary? {
        if let path = environment["HESTIA_LIBRARY"], !path.isEmpty {
            return try? load(URL(fileURLWithPath: path, isDirectory: true))
        }
        guard let resources = bundle.resourceURL else { return nil }
        return try? load(resources.appendingPathComponent("Library", isDirectory: true))
    }

    static func load(_ root: URL) throws -> AssetLibrary {
        let folder = root.standardizedFileURL.resolvingSymlinksInPath()
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("library.json")) else {
            throw LoadError.unreadable
        }
        let file: LibraryFile
        do {
            file = try JSONDecoder().decode(LibraryFile.self, from: data)
        } catch {
            throw LoadError.unreadable
        }
        guard file.version == 1 else { throw LoadError.unsupportedVersion(file.version) }
        var surfaces: [String: Surface] = [:]
        for (look, entry) in file.surfaces ?? [:] {
            guard entry.tile > 0, entry.tile.isFinite else { continue }
            surfaces[look] = Surface(asset: entry.asset, tile: entry.tile,
                                     diffuse: try entry.maps["diffuse"].map { try inside(folder, $0) },
                                     normal: try entry.maps["normal"].map { try inside(folder, $0) },
                                     rough: try entry.maps["rough"].map { try inside(folder, $0) },
                                     paint: color(entry.paint), tint: color(entry.tint))
        }
        var models: [String: Model] = [:]
        for (item, entry) in file.models ?? [:] {
            guard entry.size.count == 3, entry.size.allSatisfy({ $0 > 0 && $0.isFinite }) else { continue }
            models[item] = Model(asset: entry.asset, file: try inside(folder, entry.file), fit: entry.fit,
                                 turn: entry.turn.isFinite ? entry.turn : 0, size: entry.size)
        }
        let sky = try file.sky.map {
            Sky(file: try inside(folder, $0.file), sunAzimuth: $0.sunAzimuth,
                sunElevation: min(max($0.sunElevation, 0), 90))
        }
        return AssetLibrary(root: folder, surfaces: surfaces, models: models, sky: sky)
    }

    func surface(_ look: Look) -> Surface? {
        surfaces[look.rawValue]
    }

    func model(_ catalogID: String) -> Model? {
        models[catalogID]
    }

    /// A file named in the library, as a URL inside its folder. Absolute paths, `..`, and links that lead out of
    /// the folder are refused, so a library can only ever point at its own files.
    static func inside(_ root: URL, _ relative: String) throws -> URL {
        let pieces = relative.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !relative.isEmpty, !relative.hasPrefix("/"), !relative.contains("\\"),
              pieces.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw LoadError.unsafePath(relative)
        }
        // Follow links one piece at a time, so a link anywhere along the way is caught even when the file it
        // would lead to does not exist. The root is resolved the same way, so a folder reached through a link
        // (as /var is on macOS) still compares equal.
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        var url = root
        for piece in pieces {
            url = url.appendingPathComponent(piece)
            if FileManager.default.fileExists(atPath: url.path) || isLink(url) {
                url = url.resolvingSymlinksInPath()
            }
            guard url.path.hasPrefix(root.path + "/") else { throw LoadError.unsafePath(relative) }
        }
        return url
    }

    private static func isLink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private static func color(_ values: [Double]?) -> [Double]? {
        guard let values, values.count == 3, values.allSatisfy({ $0 >= 0 && $0.isFinite }) else { return nil }
        return values
    }
}

/// How a library model is sized to a placed item.
enum ModelFit {
    /// The uniform scale that makes a model of `model` size (its own units: width x, height y, depth z) stand at
    /// the item's size in feet: by height, or by footprint, the largest that fits both the width and the depth.
    static func scale(fit: AssetLibrary.Fit, model: (x: Double, y: Double, z: Double), width: Double, depth: Double,
                      height: Double) -> Double {
        switch fit {
        case .height:
            return height / max(model.y, 1e-9)
        case .footprint:
            return min(width / max(model.x, 1e-9), depth / max(model.z, 1e-9))
        }
    }
}

/// `library.json` as written by the library builder.
private struct LibraryFile: Decodable {
    struct SurfaceEntry: Decodable {
        var asset: String
        var tile: Double
        var maps: [String: String]
        var paint: [Double]?
        var tint: [Double]?
    }

    struct ModelEntry: Decodable {
        var asset: String
        var file: String
        var fit: AssetLibrary.Fit
        var turn: Double
        var size: [Double]
    }

    struct SkyEntry: Decodable {
        var file: String
        var sunAzimuth: Double
        var sunElevation: Double
    }

    var version: Int
    var surfaces: [String: SurfaceEntry]?
    var models: [String: ModelEntry]?
    var sky: SkyEntry?
}
