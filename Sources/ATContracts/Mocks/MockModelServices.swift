import Foundation

/// Canned geometry so app and drawing work can start before ATGeometry is complete.
///
/// It computes nothing: every call returns what the test or preview configured, after checking the storey exists.
public struct MockGeometryEngine: GeometryEngine {
    public var planOutlines: [StoreyID: [ClassifiedOutline]]
    public var areas: [StoreyID: [RoomID: Area]]
    public var meshList: [Mesh]
    public var sectionOutlines: [ClassifiedOutline]

    public init(
        planOutlines: [StoreyID: [ClassifiedOutline]] = [:], areas: [StoreyID: [RoomID: Area]] = [:],
        meshes: [Mesh] = [], sectionOutlines: [ClassifiedOutline] = []
    ) {
        self.planOutlines = planOutlines
        self.areas = areas
        self.meshList = meshes
        self.sectionOutlines = sectionOutlines
    }

    public func planView(of document: ModelDocument, storey: StoreyID) throws -> [ClassifiedOutline] {
        _ = try document.storeyIndex(storey)
        return planOutlines[storey] ?? []
    }

    public func roomAreas(of document: ModelDocument, storey: StoreyID) throws -> [RoomID: Area] {
        _ = try document.storeyIndex(storey)
        return areas[storey] ?? [:]
    }

    public func meshes(of document: ModelDocument) throws -> [Mesh] {
        meshList
    }

    public func section(of document: ModelDocument, along line: SectionLine) throws -> [ClassifiedOutline] {
        sectionOutlines
    }
}

/// Canned drawing set: returns the configured sheets unchanged.
public struct MockDrawingGenerator: DrawingGenerator {
    public var sheetList: [SheetDrawing]

    public init(sheets: [SheetDrawing] = []) {
        self.sheetList = sheets
    }

    public func sheets(for document: ModelDocument, geometry: any GeometryEngine) throws -> [SheetDrawing] {
        sheetList
    }
}

/// Stand-in exporter that writes the payload as JSON, so pipelines can be tested without a real format.
public struct MockExporter: Exporter {
    public static let mockFormat = ExchangeFormat(id: "mock-json", fileExtension: "json", mediaType: "application/json")

    public init() {}

    public var format: ExchangeFormat { Self.mockFormat }

    public func export(_ payload: ExportPayload) throws -> Data {
        try ModelDocument.makeJSONEncoder().encode(payload)
    }
}

/// Stand-in importer that reads `MockExporter` output back: drawings become an underlay, meshes stay meshes.
public struct MockImporter: Importer {
    public init() {}

    public var format: ExchangeFormat { MockExporter.mockFormat }

    public func importFile(_ data: Data, into document: ModelDocument) throws -> ImportResult {
        let payload: ExportPayload
        do {
            payload = try ModelDocument.makeJSONDecoder().decode(ExportPayload.self, from: data)
        } catch {
            throw ExchangeError.malformedInput("not mock-json export output")
        }
        switch payload {
        case let .drawing(list): return ImportResult(underlay: list)
        case let .sheets(sheets): return ImportResult(underlay: sheets.first?.content)
        case let .meshes(meshes, materials): return ImportResult(meshes: meshes, materials: materials)
        }
    }
}
