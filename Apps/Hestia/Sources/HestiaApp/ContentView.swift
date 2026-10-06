import ATDrawings
import ATExchange
import ATGeometry
import SwiftUI

struct ContentView: View {
    private let loaded = Result { try CottageFixture.sixRoom() }
    @State private var exportMessage = "Schematic exports land in ~/Hestia-exports"

    var body: some View {
        switch loaded {
        case .failure(let error):
            Text(error.localizedDescription)
                .padding()
        case .success(let cottage):
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hestia cottage")
                        .font(.title2.weight(.semibold))
                    Text(SchematicFloorPlanPDF.schematicStamp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    PlanCanvas(cottage: cottage)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(white: 0.96))
                    OrbitScene(cottage: cottage)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                HStack {
                    Button("Export PDF") { exportPDF(cottage) }
                    Button("Export DXF") { exportDXF(cottage) }
                    Text(exportMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(16)
            .frame(minWidth: 1100, minHeight: 720)
        }
    }

    private func exportPDF(_ cottage: SixRoomCottage) {
        writeExport(name: "cottage-schematic.pdf") {
            try SchematicFloorPlanPDF.export(walls: cottage.walls)
        }
    }

    private func exportDXF(_ cottage: SixRoomCottage) {
        writeExport(name: "cottage-schematic.dxf") {
            Data(try SchematicWallOutlineDXF.export(walls: cottage.walls).utf8)
        }
    }

    private func writeExport(name: String, body: () throws -> Data) {
        do {
            let directory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Hestia-exports", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(name)
            try body().write(to: url)
            exportMessage = url.path
        } catch {
            exportMessage = error.localizedDescription
        }
    }
}
