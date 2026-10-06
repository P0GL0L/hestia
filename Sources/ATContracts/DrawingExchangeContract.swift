import Foundation

/// A sheet size, landscape: `width` is the long edge.
public struct PaperSize: Codable, Hashable, Sendable {
    public var name: String
    public var width: Length
    public var height: Length

    public init(name: String, width: Length, height: Length) {
        self.name = name
        self.width = width
        self.height = height
    }

    public static let ansiB = PaperSize(name: "ANSI B", width: .inches(17), height: .inches(11))
    public static let archC = PaperSize(name: "ARCH C", width: .inches(24), height: .inches(18))
    public static let archD = PaperSize(name: "ARCH D", width: .inches(36), height: .inches(24))
    public static let isoA3 = PaperSize(name: "ISO A3", width: .millimeters(420), height: .millimeters(297))
    public static let isoA1 = PaperSize(name: "ISO A1", width: .millimeters(841), height: .millimeters(594))
}

/// A drawing scale as one paper unit to `modelUnitsPerPaperUnit` model units.
public struct DrawingScale: Codable, Hashable, Sendable {
    public var label: String
    public var modelUnitsPerPaperUnit: Int64

    public init(label: String, modelUnitsPerPaperUnit: Int64) {
        self.label = label
        self.modelUnitsPerPaperUnit = modelUnitsPerPaperUnit
    }

    public static let quarterInch = DrawingScale(label: "1/4\" = 1'-0\"", modelUnitsPerPaperUnit: 48)
    public static let eighthInch = DrawingScale(label: "1/8\" = 1'-0\"", modelUnitsPerPaperUnit: 96)
    public static let oneTo50 = DrawingScale(label: "1:50", modelUnitsPerPaperUnit: 50)
    public static let oneTo100 = DrawingScale(label: "1:100", modelUnitsPerPaperUnit: 100)

    /// Paper length for a model length, rounded to the nearest tick.
    public func paper(_ model: Length) -> Length {
        let n = modelUnitsPerPaperUnit
        let t = model.ticks
        return Length(ticks: (t >= 0 ? t + n / 2 : t - n / 2) / n)
    }
}

/// One finished sheet. Its display list is entirely paper space, origin at the lower-left corner.
public struct SheetDrawing: Codable, Hashable, Sendable {
    public var number: String
    public var title: String
    public var paper: PaperSize
    /// The main view's scale, or nil for sheets without one, such as a cover or schedules.
    public var scale: DrawingScale?
    public var content: DisplayList

    public init(number: String, title: String, paper: PaperSize, scale: DrawingScale?, content: DisplayList) {
        self.number = number
        self.title = title
        self.paper = paper
        self.scale = scale
        self.content = content
    }
}

/// Produces the drawing set. Implemented by ATDrawings (Stream D).
public protocol DrawingGenerator: Sendable {
    func sheets(for document: ModelDocument, geometry: any GeometryEngine) throws -> [SheetDrawing]
}

/// A file format the exchange module reads or writes.
public struct ExchangeFormat: Codable, Hashable, Sendable {
    public var id: String
    public var fileExtension: String
    public var mediaType: String

    public init(id: String, fileExtension: String, mediaType: String) {
        self.id = id
        self.fileExtension = fileExtension
        self.mediaType = mediaType
    }

    public static let dxf = ExchangeFormat(id: "dxf", fileExtension: "dxf", mediaType: "image/vnd.dxf")
    public static let svg = ExchangeFormat(id: "svg", fileExtension: "svg", mediaType: "image/svg+xml")
    public static let pdf = ExchangeFormat(id: "pdf", fileExtension: "pdf", mediaType: "application/pdf")
    public static let glb = ExchangeFormat(id: "glb", fileExtension: "glb", mediaType: "model/gltf-binary")
    public static let obj = ExchangeFormat(id: "obj", fileExtension: "obj", mediaType: "model/obj")
    public static let stl = ExchangeFormat(id: "stl", fileExtension: "stl", mediaType: "model/stl")
    public static let usdz = ExchangeFormat(id: "usdz", fileExtension: "usdz", mediaType: "model/vnd.usdz+zip")
}

/// What an exporter is asked to write.
public enum ExportPayload: Codable, Hashable, Sendable {
    case sheets([SheetDrawing])
    case drawing(DisplayList)
    case meshes([Mesh], materials: [Material])
}

/// What an importer produced. Model changes arrive as commands, never as direct edits.
public struct ImportResult: Hashable, Sendable {
    public var underlay: DisplayList?
    public var commands: [AnyCommand]
    public var meshes: [Mesh]
    public var materials: [Material]

    public init(
        underlay: DisplayList? = nil, commands: [AnyCommand] = [],
        meshes: [Mesh] = [], materials: [Material] = []
    ) {
        self.underlay = underlay
        self.commands = commands
        self.meshes = meshes
        self.materials = materials
    }
}

public enum ExchangeError: Error, Sendable, Equatable {
    /// The format cannot carry this kind of payload, such as meshes to DXF.
    case unsupportedPayload(format: String)
    case malformedInput(String)
}

/// Writes one file format. Implemented by ATExchange (Stream E) and the PDF writer in ATDrawings.
public protocol Exporter: Sendable {
    var format: ExchangeFormat { get }
    func export(_ payload: ExportPayload) throws -> Data
}

/// Reads one file format against the current model.
public protocol Importer: Sendable {
    var format: ExchangeFormat { get }
    func importFile(_ data: Data, into document: ModelDocument) throws -> ImportResult
}
