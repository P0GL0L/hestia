import Foundation

/// Incremental PDF 1.4 writer with tracked object byte offsets for xref.
struct PDF14Writer {
    private(set) var data = Data()
    /// 1-based object number → byte offset of `n 0 obj`.
    private(set) var objectByteOffsets: [Int: Int] = [:]

    init() {
        append("%PDF-1.4\n")
    }

    mutating func addObject(number: Int, body: String) {
        objectByteOffsets[number] = data.count
        append("\(number) 0 obj\n")
        append(body)
        append("\nendobj\n")
    }

    mutating func finish(rootObjectNumber: Int, objectCount: Int) {
        let xrefOffset = data.count
        append("xref\n")
        append("0 \(objectCount + 1)\n")
        append(String(format: "%010d 65535 f \n", 0))
        for objectNumber in 1 ... objectCount {
            let offset = objectByteOffsets[objectNumber] ?? 0
            append(String(format: "%010d 00000 n \n", offset))
        }
        append("trailer\n")
        append("<< /Size \(objectCount + 1) /Root \(rootObjectNumber) 0 R >>\n")
        append("startxref\n")
        append("\(xrefOffset)\n")
        append("%%EOF\n")
    }

    private mutating func append(_ string: String) {
        guard let bytes = string.data(using: .ascii) else {
            preconditionFailure("PDF content must be ASCII")
        }
        data.append(bytes)
    }
}
