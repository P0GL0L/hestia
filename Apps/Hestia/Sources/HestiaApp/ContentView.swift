import ATContracts
import SwiftUI

struct ContentView: View {
    private let loaded = Result { try HestiaModel.cottage() }
    @State private var exportMessage = "Schematic exports land in ~/Hestia-exports"

    var body: some View {
        switch loaded {
        case .failure(let error):
            Text(error.localizedDescription)
                .padding()
        case .success(let model):
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.document.project.name)
                        .font(.title2.weight(.semibold))
                    Text(OutputHonesty.schematicStamp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    PlanCanvas(items: model.plan)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white)
                    OrbitScene(meshes: model.meshes)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                HStack {
                    Button("Export PDF") { exportPDF(model) }
                    Button("Export DXF") { exportDXF(model) }
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

    private func fileName(_ model: HestiaModel, _ suffix: String) -> String {
        let name = model.document.project.name.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: "-")
        return (name.isEmpty ? "hestia" : name) + suffix
    }

    private func exportPDF(_ model: HestiaModel) {
        writeExport(name: fileName(model, "-schematic-set.pdf")) {
            try model.pdf()
        }
    }

    private func exportDXF(_ model: HestiaModel) {
        writeExport(name: fileName(model, "-ground-plan.dxf")) {
            try model.dxf()
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
