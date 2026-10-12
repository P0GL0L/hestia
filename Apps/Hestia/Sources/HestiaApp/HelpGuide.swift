import Foundation

/// The built-in guide: how to use Hestia, as short topics that the Help window lists and searches.
enum HelpGuide {
    struct Topic: Equatable, Sendable, Identifiable {
        var title: String
        /// Other words someone might search for.
        var keywords: [String]
        /// One line per step or fact.
        var lines: [String]

        var id: String { title }
    }

    static let topics: [Topic] = [
        Topic(title: "Views: plan and 3D", keywords: ["layout", "split", "switch", "flip"], lines: [
            "Plan, Plan + 3D, and 3D at the top right choose what the window shows.",
            "Draw in the plan, then look at the house in 3D. Every change shows in both at once.",
        ]),
        Topic(title: "Draw walls", keywords: ["wall", "line", "length", "exact", "chain"], lines: [
            "Choose Wall, click where the wall starts, then click each corner. Each click adds a wall.",
            "For an exact wall, type its length and press Return: 12'6\", 12' 6-1/2\", 150\", or a plain 12 for "
                + "feet; in metric plans 3.8 m, 380 cm, 3800 mm, or a plain 3.8 for meters.",
            "Points snap to wall ends and the grid. Esc or a right-click ends the chain.",
        ]),
        Topic(title: "Draw rooms", keywords: ["room", "rectangle", "size", "name", "pick walls"], lines: [
            "Choose Room, name it, then drag out the room or click two corners. Its four walls come with it.",
            "For an exact size, click the first corner, type a size such as 12 x 10, and press Return.",
            "To make a room from walls already drawn, click Pick Walls…, click its walls, then Add Room.",
            "Kitchens, baths, and laundries get tile floors; bedrooms carpet; other rooms wood.",
        ]),
        Topic(title: "Doors, windows, and openings", keywords: ["door", "window", "opening", "cased"], lines: [
            "Choose Door, Window, or Opening and click a wall. A cased opening is a doorway with no door.",
        ]),
        Topic(title: "Stairs", keywords: ["stair", "steps"], lines: [
            "Choose Stair, click where the stair starts at the bottom, then click the way it climbs.",
        ]),
        Topic(title: "Furniture and planting", keywords: ["furniture", "sofa", "bed", "tree", "place", "turn",
                                                          "rotate"], lines: [
            "Choose Furniture, pick an item from the menu by room, and click to place it.",
            "R, or the Turn button, turns it a quarter turn before you place it.",
            "Trees, shrubs, the car, and patio sets are under Outdoor.",
        ]),
        Topic(title: "Landscape and site", keywords: ["site", "lawn", "driveway", "path", "patio", "deck", "pond",
                                                     "garden", "gravel", "lot", "landscape"], lines: [
            "Choose Site, pick a kind (Lot, Lawn, Driveway, Path, Patio, Deck, Gravel, Pond, Garden bed), and drag "
                + "out the area. Type a size such as 40 x 20 and press Return for an exact one.",
        ]),
        Topic(title: "Select, move, turn, and delete", keywords: ["select", "move", "drag", "delete", "remove",
                                                                 "rotate", "turn"], lines: [
            "Choose Select and click a wall, an item, or a site area. Drag it to move it.",
            "R turns a selected item a quarter turn. Delete or Backspace removes what is selected.",
            "The Delete tool removes whatever you click: a door, window, opening, stair, wall, item, area, or room.",
        ]),
        Topic(title: "Undo, save, and open", keywords: ["undo", "redo", "save", "open", "new", "file"], lines: [
            "Command-Z undoes and Shift-Command-Z redoes. Command-S saves to the current file.",
            "New starts an empty plan; Open… and Save… read and write Hestia model files.",
        ]),
        Topic(title: "Move around the plan", keywords: ["zoom", "pan", "scroll", "pinch", "plan"], lines: [
            "The scroll wheel zooms the plan toward the pointer. On a trackpad, pinch to zoom and scroll with two "
                + "fingers to pan.",
        ]),
        Topic(title: "Look around in 3D", keywords: ["orbit", "zoom", "rotate", "3d", "roof", "camera", "scroll"],
              lines: [
            "Drag to turn the house. The scroll wheel zooms in and out; on a trackpad, pinch.",
            "The + and − buttons, or Command-= and Command-−, zoom too.",
            "Turn off Roof to look down into the rooms.",
        ]),
        Topic(title: "Walk inside", keywords: ["walk", "inside", "wasd", "first person", "keys"], lines: [
            "Click Walk Inside. You start in the largest room at eye height.",
            "W and S, or the up and down arrows, walk forward and back. A and D step sideways.",
            "The left and right arrows, or Q and E, turn. Drag to look around. Hold Shift to go faster.",
            "Walls stop you; doors and openings let you through. Esc or Stop Walking leaves.",
        ]),
        Topic(title: "Render a photo", keywords: ["render", "photo", "blender", "picture", "realistic"], lines: [
            "Render Photo makes a still from outside or inside, with Blender, the free 3D program.",
            "Install Blender from blender.org first. The first photo fetches about 120 MB of materials, models, and "
                + "sky from Poly Haven (CC0); later photos reuse them.",
            "Photos are saved in your Hestia-exports folder and open when done.",
        ]),
        Topic(title: "Export drawings and models", keywords: ["export", "pdf", "dxf", "usd", "cad"], lines: [
            "Export PDF and Export DXF write the plan drawings; Export USD writes the house for 3D programs such as "
                + "Blender.",
            "Drawings are schematic and not for construction.",
        ]),
    ]

    /// The topics that match every word of the search, in guide order; all of them for an empty search.
    static func search(_ text: String) -> [Topic] {
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard !words.isEmpty else { return topics }
        return topics.filter { topic in
            let haystack = ([topic.title] + topic.keywords + topic.lines).joined(separator: " ").lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }
}
