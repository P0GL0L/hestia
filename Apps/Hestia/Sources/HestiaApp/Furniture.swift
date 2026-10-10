import ATContracts
import Foundation

/// Hestia's built-in furniture, fixtures, and planting. Each item is made of simple parts, so it draws in the
/// plan and in 3D without model files. A placement stores the item's ID (`hestia.sofa`); its position is the
/// middle of the item's footprint on the floor, and its rotation turns it counterclockwise. An item's front
/// faces local -y, which is south at rotation zero.
struct FurnitureItem: Equatable, Sendable {
    enum Category: String, CaseIterable, Sendable {
        case living = "Living"
        case dining = "Dining"
        case bedroom = "Bedroom"
        case kitchen = "Kitchen"
        case bath = "Bath"
        case office = "Office"
        case laundry = "Laundry"
        case outdoor = "Outdoor"
    }

    enum Shape: Equatable, Sendable {
        case box
        case cylinder
        case ellipsoid
        case cone
    }

    /// One piece of the item, in feet, in the item's own axes: x across its width, y across its depth, and z
    /// up from the floor. (x, y) is the piece's middle; z its bottom.
    struct Part: Equatable, Sendable {
        var shape: Shape
        var x: Double
        var y: Double
        var z: Double
        var width: Double
        var depth: Double
        var height: Double
        var look: Look
    }

    var id: String
    var name: String
    var category: Category
    /// Footprint width and depth, and overall height, in feet.
    var width: Double
    var depth: Double
    var height: Double
    var parts: [Part]
    /// Planting draws as a circle in the plan.
    var isPlant: Bool = false

    var catalogID: CatalogItemID { CatalogItemID(rawValue: id) }
}

enum Furniture {
    static func item(_ id: CatalogItemID) -> FurnitureItem? {
        byID[id.rawValue]
    }

    /// What an unknown catalog ID draws as: a 2-foot box, so a placement from elsewhere still shows.
    static func placeholder(_ id: CatalogItemID) -> FurnitureItem {
        FurnitureItem(id: id.rawValue, name: id.rawValue, category: .living, width: 2, depth: 2, height: 2,
                      parts: [box(0, 0, 0, 2, 2, 2, .structure)])
    }

    static func items(in category: FurnitureItem.Category) -> [FurnitureItem] {
        all.filter { $0.category == category }
    }

    private static let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    private static func box(_ x: Double, _ y: Double, _ z: Double, _ w: Double, _ d: Double, _ h: Double,
                            _ look: Look) -> FurnitureItem.Part {
        FurnitureItem.Part(shape: .box, x: x, y: y, z: z, width: w, depth: d, height: h, look: look)
    }

    private static func part(_ shape: FurnitureItem.Shape, _ x: Double, _ y: Double, _ z: Double, _ w: Double,
                             _ d: Double, _ h: Double, _ look: Look) -> FurnitureItem.Part {
        FurnitureItem.Part(shape: shape, x: x, y: y, z: z, width: w, depth: d, height: h, look: look)
    }

    /// Four legs under a top of the given size.
    private static func legs(_ w: Double, _ d: Double, _ h: Double, _ look: Look, inset: Double = 0.15,
                             size: Double = 0.15) -> [FurnitureItem.Part] {
        let x = w / 2 - inset, y = d / 2 - inset
        return [(-x, -y), (x, -y), (x, y), (-x, y)].map { box($0.0, $0.1, 0, size, size, h, look) }
    }

    static let all: [FurnitureItem] = living + dining + bedroom + kitchen + bath + office + laundry + outdoor

    private static let living: [FurnitureItem] = [
        FurnitureItem(id: "hestia.sofa", name: "Sofa", category: .living, width: 7, depth: 3, height: 2.8, parts: [
            box(0, -0.1, 0.4, 6.2, 2.4, 1.0, .fabric),
            box(0, 1.25, 0.4, 7, 0.5, 2.4, .fabric),
            box(-3.25, -0.1, 0.4, 0.5, 2.8, 1.7, .fabric),
            box(3.25, -0.1, 0.4, 0.5, 2.8, 1.7, .fabric),
            box(0, 0, 0, 6.8, 2.8, 0.4, .woodDark),
        ]),
        FurnitureItem(id: "hestia.loveseat", name: "Loveseat", category: .living, width: 5, depth: 3, height: 2.8,
                      parts: [
                          box(0, -0.1, 0.4, 4.2, 2.4, 1.0, .fabricDark),
                          box(0, 1.25, 0.4, 5, 0.5, 2.4, .fabricDark),
                          box(-2.25, -0.1, 0.4, 0.5, 2.8, 1.7, .fabricDark),
                          box(2.25, -0.1, 0.4, 0.5, 2.8, 1.7, .fabricDark),
                          box(0, 0, 0, 4.8, 2.8, 0.4, .woodDark),
                      ]),
        FurnitureItem(id: "hestia.armchair", name: "Armchair", category: .living, width: 3, depth: 3, height: 2.8,
                      parts: [
                          box(0, -0.1, 0.4, 2.2, 2.4, 1.0, .leather),
                          box(0, 1.25, 0.4, 3, 0.5, 2.4, .leather),
                          box(-1.25, -0.1, 0.4, 0.5, 2.8, 1.6, .leather),
                          box(1.25, -0.1, 0.4, 0.5, 2.8, 1.6, .leather),
                          box(0, 0, 0, 2.8, 2.8, 0.4, .woodDark),
                      ]),
        FurnitureItem(id: "hestia.coffee-table", name: "Coffee table", category: .living, width: 4, depth: 2,
                      height: 1.5, parts: [box(0, 0, 1.3, 4, 2, 0.2, .wood)] + legs(4, 2, 1.3, .woodDark)),
        FurnitureItem(id: "hestia.tv-stand", name: "TV and stand", category: .living, width: 5, depth: 1.5,
                      height: 4.6, parts: [
                          box(0, 0, 0, 5, 1.5, 1.8, .woodDark),
                          box(0, 0.2, 1.8, 0.6, 0.4, 0.5, .black),
                          box(0, 0.2, 2.3, 4.4, 0.15, 2.4, .black),
                      ]),
        FurnitureItem(id: "hestia.bookcase", name: "Bookcase", category: .living, width: 3, depth: 1, height: 6.5,
                      parts: [
                          box(-1.45, 0, 0, 0.1, 1, 6.5, .wood), box(1.45, 0, 0, 0.1, 1, 6.5, .wood),
                          box(0, 0.45, 0, 3, 0.1, 6.5, .wood),
                      ] + (0..<6).map { box(0, 0, Double($0) * 1.25, 2.8, 1, 0.08, .wood) }),
        FurnitureItem(id: "hestia.rug", name: "Area rug", category: .living, width: 8, depth: 5, height: 0.05,
                      parts: [box(0, 0, 0, 8, 5, 0.05, .linen)]),
        FurnitureItem(id: "hestia.floor-lamp", name: "Floor lamp", category: .living, width: 1.2, depth: 1.2,
                      height: 5.5, parts: [
                          part(.cylinder, 0, 0, 0, 1.0, 1.0, 0.1, .black),
                          part(.cylinder, 0, 0, 0.1, 0.12, 0.12, 4.4, .metal),
                          part(.cone, 0, 0, 4.5, 1.2, 1.2, 1.0, .linen),
                      ]),
    ]

    private static let dining: [FurnitureItem] = [
        FurnitureItem(id: "hestia.dining-table", name: "Dining table", category: .dining, width: 6, depth: 3.5,
                      height: 2.5, parts: [box(0, 0, 2.3, 6, 3.5, 0.2, .wood)] + legs(6, 3.5, 2.3, .wood)),
        FurnitureItem(id: "hestia.round-table", name: "Round table", category: .dining, width: 4, depth: 4,
                      height: 2.5, parts: [
                          part(.cylinder, 0, 0, 2.3, 4, 4, 0.2, .wood),
                          part(.cylinder, 0, 0, 0, 0.4, 0.4, 2.3, .woodDark),
                          part(.cylinder, 0, 0, 0, 1.6, 1.6, 0.15, .woodDark),
                      ]),
        FurnitureItem(id: "hestia.dining-chair", name: "Dining chair", category: .dining, width: 1.5, depth: 1.6,
                      height: 3, parts: [
                          box(0, 0, 1.5, 1.5, 1.6, 0.15, .wood),
                          box(0, 0.72, 1.65, 1.5, 0.15, 1.35, .wood),
                      ] + legs(1.5, 1.6, 1.5, .woodDark, inset: 0.1, size: 0.12)),
        FurnitureItem(id: "hestia.sideboard", name: "Sideboard", category: .dining, width: 5, depth: 1.5,
                      height: 2.8, parts: [box(0, 0, 0.4, 5, 1.5, 2.4, .woodDark)] + legs(5, 1.5, 0.4, .black)),
    ]

    private static let bedroom: [FurnitureItem] = [
        bed(id: "hestia.bed-king", name: "King bed", width: 6.6, length: 7),
        bed(id: "hestia.bed-queen", name: "Queen bed", width: 5, length: 6.9),
        bed(id: "hestia.bed-twin", name: "Twin bed", width: 3.4, length: 6.6),
        FurnitureItem(id: "hestia.nightstand", name: "Nightstand", category: .bedroom, width: 2, depth: 1.5,
                      height: 2.2, parts: [
                          box(0, 0, 0.3, 2, 1.5, 1.9, .wood),
                          part(.cylinder, 0.4, 0.2, 2.2, 0.5, 0.5, 0.9, .metal),
                          part(.cone, 0.4, 0.2, 2.9, 0.9, 0.9, 0.6, .linen),
                      ] + legs(2, 1.5, 0.3, .woodDark, inset: 0.1, size: 0.1)),
        FurnitureItem(id: "hestia.dresser", name: "Dresser", category: .bedroom, width: 5, depth: 1.7, height: 3,
                      parts: [box(0, 0, 0.3, 5, 1.7, 2.7, .wood)] + legs(5, 1.7, 0.3, .woodDark, size: 0.12)),
        FurnitureItem(id: "hestia.wardrobe", name: "Wardrobe", category: .bedroom, width: 4, depth: 2, height: 7,
                      parts: [box(0, 0, 0, 4, 2, 7, .white), box(0, -1.02, 0.3, 0.04, 0.04, 6.4, .woodDark)]),
    ]

    private static func bed(id: String, name: String, width: Double, length: Double) -> FurnitureItem {
        FurnitureItem(id: id, name: name, category: .bedroom, width: width + 0.3, depth: length + 0.3, height: 4,
                      parts: [
                          box(0, 0, 0, width + 0.3, length + 0.3, 1.1, .woodDark),
                          box(0, -0.05, 1.1, width, length - 0.1, 0.9, .white),
                          box(0, -0.6, 1.95, width + 0.1, length - 1.2, 0.2, .fabric),
                          box(0, length / 2 + 0.05, 0, width + 0.3, 0.2, 4, .woodDark),
                          box(-width / 4, length / 2 - 0.9, 2.0, width / 2 - 0.3, 1.2, 0.45, .linen),
                          box(width / 4, length / 2 - 0.9, 2.0, width / 2 - 0.3, 1.2, 0.45, .linen),
                      ])
    }

    private static let kitchen: [FurnitureItem] = [
        FurnitureItem(id: "hestia.base-cabinet", name: "Counter, 3 ft", category: .kitchen, width: 3, depth: 2,
                      height: 3, parts: counter(width: 3)),
        FurnitureItem(id: "hestia.counter-6", name: "Counter, 6 ft", category: .kitchen, width: 6, depth: 2,
                      height: 3, parts: counter(width: 6)),
        FurnitureItem(id: "hestia.sink-cabinet", name: "Sink counter", category: .kitchen, width: 3, depth: 2,
                      height: 3, parts: counter(width: 3) + [box(0, -0.1, 2.9, 2.2, 1.4, 0.12, .metal),
                                                              box(0, 0.75, 3, 0.15, 0.15, 1, .metal)]),
        FurnitureItem(id: "hestia.range", name: "Range", category: .kitchen, width: 2.5, depth: 2.2, height: 3.1,
                      parts: [box(0, 0, 0, 2.5, 2.2, 3, .metal), box(0, 0, 3, 2.4, 2.1, 0.05, .black),
                              box(0, 1.0, 3, 2.5, 0.2, 0.6, .metal)]),
        FurnitureItem(id: "hestia.refrigerator", name: "Refrigerator", category: .kitchen, width: 3, depth: 2.6,
                      height: 6, parts: [box(0, 0, 0, 3, 2.6, 6, .metal),
                                         box(0.1, -1.31, 2.5, 0.06, 0.06, 1.6, .black)]),
        FurnitureItem(id: "hestia.island", name: "Kitchen island", category: .kitchen, width: 6, depth: 3,
                      height: 3, parts: [box(0, 0, 0, 5.6, 2.6, 2.85, .white), box(0, 0, 2.85, 6, 3, 0.15, .stone)]),
        FurnitureItem(id: "hestia.bar-stool", name: "Bar stool", category: .kitchen, width: 1.3, depth: 1.3,
                      height: 2.6, parts: [part(.cylinder, 0, 0, 2.4, 1.3, 1.3, 0.2, .leather),
                                           part(.cylinder, 0, 0, 0, 0.2, 0.2, 2.4, .metal),
                                           part(.cylinder, 0, 0, 0, 1.1, 1.1, 0.08, .metal)]),
    ]

    private static func counter(width: Double) -> [FurnitureItem.Part] {
        [box(0, 0.05, 0, width, 1.9, 0.3, .black),
         box(0, 0.05, 0.3, width, 1.9, 2.55, .white),
         box(0, 0, 2.85, width, 2.05, 0.15, .stone)]
    }

    private static let bath: [FurnitureItem] = [
        FurnitureItem(id: "hestia.toilet", name: "Toilet", category: .bath, width: 1.6, depth: 2.4, height: 2.6,
                      parts: [
                          part(.ellipsoid, 0, -0.3, 0.6, 1.4, 1.9, 0.9, .porcelain),
                          box(0, -0.3, 0, 0.9, 1.2, 1.1, .porcelain),
                          box(0, 0.95, 1.2, 1.6, 0.6, 1.4, .porcelain),
                      ]),
        FurnitureItem(id: "hestia.bathtub", name: "Bathtub", category: .bath, width: 5, depth: 2.6, height: 1.8,
                      parts: [box(0, 0, 0, 5, 2.6, 1.6, .porcelain), box(0, 0, 1.6, 4.4, 2.0, 0.05, .water),
                              box(-2.3, 0, 1.6, 0.4, 2.6, 0.2, .porcelain)]),
        FurnitureItem(id: "hestia.shower", name: "Shower", category: .bath, width: 3, depth: 3, height: 7,
                      parts: [box(0, 0, 0, 3, 3, 0.3, .porcelain), box(0, -1.48, 0.3, 3, 0.04, 6.4, .glass),
                              box(-1.48, 0, 0.3, 0.04, 3, 6.4, .glass), box(0, 1.2, 6, 0.6, 0.6, 0.1, .metal)]),
        FurnitureItem(id: "hestia.vanity", name: "Vanity", category: .bath, width: 3, depth: 1.8, height: 3,
                      parts: [box(0, 0, 0, 3, 1.8, 2.8, .wood), box(0, 0, 2.8, 3.1, 1.9, 0.15, .stone),
                              part(.ellipsoid, 0, -0.1, 2.9, 1.4, 1.0, 0.25, .porcelain),
                              box(0, 0.85, 3.4, 2.4, 0.05, 2.4, .glass)]),
    ]

    private static let office: [FurnitureItem] = [
        FurnitureItem(id: "hestia.desk", name: "Desk", category: .office, width: 5, depth: 2.5, height: 2.5,
                      parts: [box(0, 0, 2.35, 5, 2.5, 0.15, .wood), box(1.7, 0, 0, 1.4, 2.3, 2.35, .woodDark),
                              box(-2.4, 0, 0, 0.15, 2.3, 2.35, .woodDark),
                              box(-0.6, 0.6, 2.5, 1.8, 0.1, 1.2, .black)]),
        FurnitureItem(id: "hestia.office-chair", name: "Office chair", category: .office, width: 2.2, depth: 2.2,
                      height: 3.6, parts: [part(.cylinder, 0, 0, 0, 2.0, 2.0, 0.15, .black),
                                           part(.cylinder, 0, 0, 0.15, 0.2, 0.2, 1.3, .metal),
                                           box(0, 0, 1.45, 1.7, 1.7, 0.3, .fabricDark),
                                           box(0, 0.8, 1.75, 1.6, 0.2, 1.8, .fabricDark)]),
    ]

    private static let laundry: [FurnitureItem] = [
        FurnitureItem(id: "hestia.washer", name: "Washer", category: .laundry, width: 2.3, depth: 2.3, height: 3.2,
                      parts: [box(0, 0, 0, 2.3, 2.3, 3.2, .white),
                              part(.cylinder, 0, -1.16, 1.5, 1.2, 0.05, 1.2, .glass)]),
        FurnitureItem(id: "hestia.dryer", name: "Dryer", category: .laundry, width: 2.3, depth: 2.3, height: 3.2,
                      parts: [box(0, 0, 0, 2.3, 2.3, 3.2, .white), box(0, -1.16, 2.8, 2.0, 0.05, 0.3, .black)]),
    ]

    private static let outdoor: [FurnitureItem] = [
        FurnitureItem(id: "hestia.tree-shade", name: "Shade tree", category: .outdoor, width: 18, depth: 18,
                      height: 26, parts: [part(.cylinder, 0, 0, 0, 1.2, 1.2, 10, .trunk),
                                          part(.ellipsoid, 0, 0, 8, 18, 18, 16, .foliage),
                                          part(.ellipsoid, 2, -1.5, 13, 11, 11, 10, .foliageDark)],
                      isPlant: true),
        FurnitureItem(id: "hestia.tree-pine", name: "Pine tree", category: .outdoor, width: 10, depth: 10,
                      height: 30, parts: [part(.cylinder, 0, 0, 0, 1, 1, 6, .trunk),
                                          part(.cone, 0, 0, 5, 10, 10, 14, .foliageDark),
                                          part(.cone, 0, 0, 13, 7.5, 7.5, 11, .foliageDark),
                                          part(.cone, 0, 0, 20, 5, 5, 10, .foliageDark)],
                      isPlant: true),
        FurnitureItem(id: "hestia.tree-ornamental", name: "Flowering tree", category: .outdoor, width: 10,
                      depth: 10, height: 14, parts: [part(.cylinder, 0, 0, 0, 0.6, 0.6, 5, .trunk),
                                                     part(.ellipsoid, 0, 0, 4, 10, 10, 9, .blossom)],
                      isPlant: true),
        FurnitureItem(id: "hestia.shrub", name: "Shrub", category: .outdoor, width: 4, depth: 4, height: 3.5,
                      parts: [part(.ellipsoid, 0, 0, 0, 4, 4, 3.5, .foliage)], isPlant: true),
        FurnitureItem(id: "hestia.hedge", name: "Hedge, 8 ft", category: .outdoor, width: 8, depth: 2.5, height: 4,
                      parts: [box(0, 0, 0, 8, 2.5, 4, .foliageDark)]),
        FurnitureItem(id: "hestia.flower-bed", name: "Flower bed", category: .outdoor, width: 6, depth: 3,
                      height: 1.2, parts: flowerBed),
        FurnitureItem(id: "hestia.patio-table", name: "Patio table set", category: .outdoor, width: 7, depth: 7,
                      height: 2.5, parts: patioSet),
        FurnitureItem(id: "hestia.car", name: "Car", category: .outdoor, width: 6.2, depth: 15, height: 4.8,
                      parts: car),
    ]

    private static let flowerBed: [FurnitureItem.Part] = {
        var parts = [box(0, 0, 0, 6, 3, 0.6, .mulch)]
        for index in 0..<6 {
            let look: Look = index % 2 == 0 ? .blossom : .foliage
            parts.append(part(.ellipsoid, Double(index) - 2.5, Double(index % 2) - 0.5, 0.5, 1.1, 1.1, 0.8, look))
        }
        return parts
    }()

    private static let patioSet: [FurnitureItem.Part] = {
        var parts = [part(.cylinder, 0, 0, 2.3, 3.5, 3.5, 0.15, .metal),
                     part(.cylinder, 0, 0, 0, 0.3, 0.3, 2.3, .metal)]
        let seats: [(Double, Double)] = [(0, -2.7), (2.7, 0), (0, 2.7), (-2.7, 0)]
        for seat in seats {
            parts.append(box(seat.0, seat.1, 0, 1.5, 1.5, 1.5, .metal))
        }
        return parts
    }()

    private static let car: [FurnitureItem.Part] = {
        var parts = [box(0, 0, 0.8, 6.2, 15, 2.2, .fabricDark), box(0, 0.8, 3, 5.6, 8, 1.7, .glass),
                     box(0, 0.8, 4.6, 5.6, 7.6, 0.2, .fabricDark)]
        let wheels: [(Double, Double)] = [(-2.9, -4.8), (2.9, -4.8), (-2.9, 4.8), (2.9, 4.8)]
        for wheel in wheels {
            parts.append(box(wheel.0, wheel.1, 0, 0.7, 2.2, 1.8, .black))
        }
        return parts
    }()
}

extension FurnitureItem.Part {
    /// The part's footprint corners in the plan, in feet, for an item placed at (cx, cy) turned `turn` radians.
    func footprint(cx: Double, cy: Double, turn: Double) -> [(x: Double, y: Double)] {
        let (c, s) = (cos(turn), sin(turn))
        let hw = width / 2, hd = depth / 2
        return [(-hw, -hd), (hw, -hd), (hw, hd), (-hw, hd)].map { corner in
            let lx = x + corner.0, ly = y + corner.1
            return (cx + lx * c - ly * s, cy + lx * s + ly * c)
        }
    }
}

extension FurnitureItem {
    /// The item's outline in the plan, in feet: its footprint rectangle turned about its middle.
    func outline(cx: Double, cy: Double, turn: Double) -> [(x: Double, y: Double)] {
        Part(shape: .box, x: 0, y: 0, z: 0, width: width, depth: depth, height: height, look: .wood)
            .footprint(cx: cx, cy: cy, turn: turn)
    }

    /// Adds the item's parts, placed at (cx, cy) on a floor at `floor` and turned `turn` radians, to one solid
    /// per look.
    func addSolids(to solids: inout [Look: Solid], cx: Double, cy: Double, floor: Double, turn: Double,
                   group: SolidGroup = .house) {
        let (c, s) = (cos(turn), sin(turn))
        for part in parts {
            var solid = solids[part.look] ?? Solid(look: part.look, group: group)
            let px = cx + part.x * c - part.y * s, py = cy + part.x * s + part.y * c
            switch part.shape {
            case .box:
                Shapes.box(&solid, cx: px, cy: py, z0: floor + part.z, width: part.width, depth: part.depth,
                           height: part.height, turn: turn)
            case .cylinder:
                Shapes.cylinder(&solid, cx: px, cy: py, z0: floor + part.z, radius: max(part.width, part.depth) / 2,
                                height: part.height)
            case .cone:
                Shapes.cone(&solid, cx: px, cy: py, z0: floor + part.z, radius: max(part.width, part.depth) / 2,
                            height: part.height)
            case .ellipsoid:
                Shapes.ellipsoid(&solid, cx: px, cy: py, cz: floor + part.z + part.height / 2, rx: part.width / 2,
                                 ry: part.depth / 2, rz: part.height / 2)
            }
            solids[part.look] = solid
        }
    }
}
