import ATContracts
import AppKit
import SwiftUI

/// New, Open, Save, Undo, Redo, the roof, and exports.
extension ContentView {
    /// Replaces the model with an empty one: one building, one ground storey, no walls. Nothing before it can
    /// be undone. The new session has no file, so the file from the last Open or Save is forgotten. A cancelled
    /// discard leaves that file in place.
    func newModel() {
        guard confirmDiscard() else { return }
        clearDrawing()
        do {
            session = EditSession(model: try HestiaModel.blank())
            roomWalls = []
            selection = nil
            resetView()
            tool = .room
            status = "New model. " + Tool.room.hint
        } catch {
            status = HestiaModel.describe(error)
        }
    }

    /// Replaces the model with one read from a saved file, and remembers that file. Nothing before it can be
    /// undone. A cancelled panel, or a file that cannot be read, leaves the remembered file as it was.
    func openModel() {
        guard confirmDiscard() else { return }
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["json"]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        clearDrawing()
        do {
            session = EditSession(model: try HestiaModel.open(Data(contentsOf: url)), fileURL: url)
            roomWalls = []
            selection = nil
            resetView()
            status = "Opened \(url.lastPathComponent)."
        } catch {
            status = HestiaModel.describe(error)
        }
    }

    /// Back to the whole plan, orbiting.
    func resetView() {
        zoom = 1
        pan = .zero
        houseMode = .orbit
    }

    /// Writes the model's JSON where the person chooses. The undo history is not saved. Returns whether it was
    /// written. The Save… button always opens this panel. A cancelled panel leaves the remembered file as it was.
    @discardableResult
    func saveModel() -> Bool {
        guard let model = session?.model else { return false }
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["json"]
        panel.nameFieldStringValue = fileName(model, ".json")
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return save(to: url)
    }

    /// Command-S. Writes the document to the file remembered from a successful Open or Save, and does not open a
    /// panel. With no remembered file, opens the save panel.
    func saveToCurrentFile() {
        guard let url = session?.fileURL else {
            saveModel()
            return
        }
        save(to: url)
    }

    /// Writes the document to `url` and remembers that file. A failed write leaves the document unsaved and the
    /// remembered file as it was.
    @discardableResult
    func save(to url: URL) -> Bool {
        guard var current = session else { return false }
        do {
            try current.save(to: url)
            session = current
            status = "Saved \(url.lastPathComponent)."
            return true
        } catch {
            status = HestiaModel.describe(error)
            return false
        }
    }

    /// Asks before the document is replaced or its window closes, when it differs from the last New, Open, or
    /// successful Save. Save writes it through the save panel, and a cancelled panel stays; Don't Save goes
    /// ahead; Cancel stays. A document with no changes does not ask. Returns whether to go ahead.
    func confirmDiscard() -> Bool {
        guard let current = session, current.hasUnsavedChanges else { return true }
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes to \u{201C}\(current.model.document.project.name)\u{201D}?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return saveModel()
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func undo() {
        guard var current = session else { return }
        clearDrawing()
        do {
            try current.undo()
            session = current
            forgetRemoved()
            status = "Undone."
        } catch {
            status = HestiaModel.describe(error)
        }
    }

    func redo() {
        guard var current = session else { return }
        clearDrawing()
        do {
            try current.redo()
            session = current
            forgetRemoved()
            status = "Redone."
        } catch {
            status = HestiaModel.describe(error)
        }
    }

    /// Drops picked walls and the selection when what they name is no longer in the model.
    func forgetRemoved() {
        guard let document = session?.model.document else { return }
        let walls = Set(document.walls.map(\.id))
        roomWalls = roomWalls.filter { walls.contains($0) }
        switch selection {
        case let .wall(id) where !walls.contains(id):
            selection = nil
        case let .placement(id) where !document.placements.contains(where: { $0.id == id }):
            selection = nil
        case let .patch(id) where !document.terrainPatches.contains(where: { $0.id == id }):
            selection = nil
        default:
            break
        }
    }

    /// Removes the ground storey's roof when it has one; otherwise puts a hip roof over the ground walls, when
    /// they close one rectangle.
    func toggleRoof() {
        guard var current = session else { return }
        clearDrawing()
        do {
            if current.model.groundRoof != nil {
                try current.removeRoof()
                session = current
                status = "Removed the roof. Undo puts it back."
            } else {
                try current.addRoof()
                session = current
                status = "Added a hip roof. Undo removes it."
            }
        } catch {
            status = HestiaModel.describe(error)
        }
    }

    func fileName(_ model: HestiaModel, _ suffix: String) -> String {
        let name = model.document.project.name.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: "-")
        return (name.isEmpty ? "hestia" : name) + suffix
    }

    func exportPDF(_ model: HestiaModel) {
        writeExport(name: fileName(model, "-schematic-set.pdf")) {
            try model.pdf()
        }
    }

    func exportDXF(_ model: HestiaModel) {
        writeExport(name: fileName(model, "-ground-plan.dxf")) {
            try model.dxf()
        }
    }

    /// The house's geometry and basic materials as OpenUSD. Blender import is tested; other programs are not yet.
    func exportUSD(_ model: HestiaModel) {
        writeExport(name: fileName(model, ".usda")) {
            Data(HouseUSD.export(document: model.document, meshes: model.meshes).utf8)
        }
    }

    /// A photoreal still of the house from Blender's Cycles renderer, saved in ~/Hestia-exports and opened.
    /// Without Blender installed, offers to get it.
    func renderPhoto(_ model: HestiaModel, view: PhotoRender.View) {
        guard !rendering else { return }
        guard let blender = PhotoRender.blender() else {
            askForBlender()
            return
        }
        guard let script = PhotoRender.script() else {
            status = "The render script is missing from this copy of Hestia."
            return
        }
        guard PhotoRender.hasAssets || confirmFirstDownload() else { return }
        do {
            let directory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Hestia-exports", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let output = Self.unusedURL(for: fileName(model, "-\(view.rawValue).png"), in: directory)
            let usd = FileManager.default.temporaryDirectory.appendingPathComponent("hestia-\(UUID()).usda")
            try Data(HouseUSD.export(document: model.document, meshes: model.meshes).utf8).write(to: usd)
            rendering = true
            status = "Rendering the \(view == .exterior ? "outside" : "inside") with Blender. The first render "
                + "downloads materials and models, so it takes a few minutes."
            Task {
                do {
                    try await PhotoRender.render(blender: blender, script: script, usd: usd, output: output,
                                                 view: view)
                    exportMessage = output.path
                    status = "Rendered \(output.lastPathComponent), with its asset manifest beside it. Assets: Poly "
                        + "Haven, CC0. Schematic visualization, not for construction."
                    NSWorkspace.shared.open(output)
                } catch {
                    status = HestiaModel.describe(error)
                }
                try? FileManager.default.removeItem(at: usd)
                rendering = false
            }
        } catch {
            status = HestiaModel.describe(error)
        }
    }

    /// Before the first photo: what will be downloaded, from where, and where it is kept. Returns whether to go
    /// ahead.
    func confirmFirstDownload() -> Bool {
        let alert = NSAlert()
        alert.messageText = "The first photo downloads its materials"
        alert.informativeText = "Hestia fetches about 120 MB of free CC0 materials, furniture and tree models, and a "
            + "sky image from Poly Haven (polyhaven.com), checks each file against Poly Haven's size and checksum, "
            + "and keeps them in ~/Library/Caches/Hestia/assets. Later photos reuse them and work offline."
        alert.addButton(withTitle: "Download and Render")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Hestia renders photos with Blender, which is free; offers to open its download page.
    func askForBlender() {
        let alert = NSAlert()
        alert.messageText = "Photo renders use Blender"
        alert.informativeText = "Blender is a free 3D program. Install it in Applications, then choose Render Photo "
            + "again. Hestia runs it in the background; you never have to open it."
        alert.addButton(withTitle: "Get Blender")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: "https://www.blender.org/download/") {
            NSWorkspace.shared.open(url)
        }
    }

    /// `name` in `directory`, or, when a file of that name is already there, the name with the lowest free
    /// number before its extension ("rect-cottage-schematic-set 2.pdf", then 3), so an export never replaces
    /// an earlier one.
    static func unusedURL(for name: String, in directory: URL) -> URL {
        let first = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: first.path) else { return first }
        let stem = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var number = 2
        while true {
            let candidate = directory.appendingPathComponent("\(stem) \(number)" + (ext.isEmpty ? "" : ".\(ext)"))
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }

    func writeExport(name: String, body: () throws -> Data) {
        do {
            let directory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Hestia-exports", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = Self.unusedURL(for: name, in: directory)
            try body().write(to: url, options: .atomic)
            exportMessage = url.path
        } catch {
            exportMessage = HestiaModel.describe(error)
        }
    }
}
