import ATContracts
import ATDrawings
import ATGeometry
import Foundation
import Testing

private let storeyID = StoreyID(UUID(uuidString: "00000000-0000-4000-8000-000000000003")!)
private let wallThickness = Length.inches(6)

@Test func tenByTwelveFootRectangleSchematicPDF() throws {
    let width = Length.feet(10)
    let height = Length.feet(12)

    func p(x: Int64, y: Int64) -> Point2 {
        Point2(x: Length(ticks: x), y: Length(ticks: y))
    }

    let walls = [
        Wall(
            id: WallID(UUID(uuidString: "00000000-0000-4000-8000-000000000041")!),
            storeyID: storeyID,
            start: p(x: 0, y: 0),
            end: p(x: width.ticks, y: 0),
            thickness: wallThickness,
            height: Length.feet(8)
        ),
        Wall(
            id: WallID(UUID(uuidString: "00000000-0000-4000-8000-000000000042")!),
            storeyID: storeyID,
            start: p(x: width.ticks, y: 0),
            end: p(x: width.ticks, y: height.ticks),
            thickness: wallThickness,
            height: Length.feet(8)
        ),
        Wall(
            id: WallID(UUID(uuidString: "00000000-0000-4000-8000-000000000043")!),
            storeyID: storeyID,
            start: p(x: width.ticks, y: height.ticks),
            end: p(x: 0, y: height.ticks),
            thickness: wallThickness,
            height: Length.feet(8)
        ),
        Wall(
            id: WallID(UUID(uuidString: "00000000-0000-4000-8000-000000000044")!),
            storeyID: storeyID,
            start: p(x: 0, y: height.ticks),
            end: p(x: 0, y: 0),
            thickness: wallThickness,
            height: Length.feet(8)
        ),
    ]

    let pdf = try SchematicFloorPlanPDF.export(walls: walls)
    let text = String(decoding: pdf, as: UTF8.self)

    #expect(text.hasPrefix("%PDF-1.4"))
    #expect(text.contains(SchematicFloorPlanPDF.schematicStamp))
    #expect(text.contains(" m\n") || text.contains(" l\n") || text.contains(" S\n"))

    let objectOffsets = objectByteOffsets(in: pdf)
    let xrefOffsets = xrefEntryOffsets(in: pdf)
    #expect(xrefOffsets.count == objectOffsets.count + 1)

    for objectNumber in objectOffsets.keys.sorted() {
        #expect(xrefOffsets[objectNumber] == objectOffsets[objectNumber])
    }
}

private func objectByteOffsets(in pdf: Data) -> [Int: Int] {
    guard let ascii = String(data: pdf, encoding: .ascii) else { return [:] }
    var result: [Int: Int] = [:]
    let marker = " 0 obj"
    var searchStart = ascii.startIndex
    while let range = ascii.range(of: marker, range: searchStart..<ascii.endIndex) {
        let lineStart = ascii[..<range.lowerBound].lastIndex(of: "\n").map { ascii.index(after: $0) } ?? ascii.startIndex
        let numberText = ascii[lineStart..<range.lowerBound]
        if let number = Int(numberText) {
            let offset = ascii.distance(from: ascii.startIndex, to: lineStart)
            result[number] = offset
        }
        searchStart = range.upperBound
    }
    return result
}

private func xrefEntryOffsets(in pdf: Data) -> [Int: Int] {
    guard let ascii = String(data: pdf, encoding: .ascii) else { return [:] }
    guard let xrefRange = ascii.range(of: "xref\n") else { return [:] }
    var index = xrefRange.upperBound
    guard let firstLineEnd = ascii[index...].firstIndex(of: "\n") else { return [:] }
    let header = ascii[index..<firstLineEnd]
    let parts = header.split(separator: " ")
    guard parts.count == 2, let start = Int(parts[0]), let count = Int(parts[1]) else { return [:] }
    index = ascii.index(after: firstLineEnd)
    var result: [Int: Int] = [:]
    for entryIndex in 0 ..< count {
        guard let lineEnd = ascii[index...].firstIndex(of: "\n") else { break }
        let line = ascii[index..<lineEnd]
        let fields = line.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 3, let offset = Int(fields[0]) else { break }
        result[start + entryIndex] = offset
        index = ascii.index(after: lineEnd)
    }
    return result
}
