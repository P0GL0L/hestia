import ATContracts
import SwiftUI

struct ContentView: View {
    @State private var session: EditSession?
    @State private var loadError: String?
    /// The first click of a wall, on the plan sheet's paper, until the second click places its end.
    @State private var pendingStart: Point2?
    @State private var status = "Click two points on the plan to add a wall."
    @State private var exportMessage = "Schematic exports land in ~/Hestia-exports"

    init() {
        do {
            _session = State(initialValue: EditSession(model: try HestiaModel.cottage()))
        } catch {
            _loadError = State(initialValue: error.localizedDescription)
        }
    }

    var body: some View {
        if let session {
            editor(session.model)
        } else {
            Text(loadError ?? "No model loaded.")
                .padding()
        }
    }

    private func editor(_ model: HestiaModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.document.project.name)
                    .font(.title2.weight(.semibold))
                Text(OutputHonesty.schematicStamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                PlanCanvas(items: model.plan, pendingStart: pendingStart) { paper in click(paper) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                OrbitScene(meshes: model.meshes)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Button("Undo") { undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!(session?.canUndo ?? false))
                Text(status)
                    .font(.caption)
                Spacer()
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

    /// The first click starts a wall; the second ends it and adds it to the ground storey.
    private func click(_ paper: Point2) {
        guard var current = session else { return }
        guard let start = pendingStart else {
            pendingStart = paper
            status = "Click the wall's end point."
            return
        }
        pendingStart = nil
        do {
            try current.addWall(fromPaper: start, toPaper: paper)
            session = current
            status = "Added a wall. Undo removes it."
        } catch {
            status = error.localizedDescription
        }
    }

    private func undo() {
        guard var current = session else { return }
        pendingStart = nil
        do {
            try current.undo()
            session = current
            status = "Undone."
        } catch {
            status = error.localizedDescription
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
