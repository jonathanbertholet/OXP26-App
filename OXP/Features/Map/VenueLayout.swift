import CoreGraphics
import Foundation
import MapKit
import SwiftUI

enum FloorPlan: String, CaseIterable, Identifiable, Sendable {
    case overview
    case hall6
    case hall7
    case hall11
    case hall10

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "All halls"
        case .hall6: "Hall 6"
        case .hall7: "Hall 7"
        case .hall11: "Hall 11"
        case .hall10: "Hall 10"
        }
    }

    var imageName: String? {
        switch self {
        case .overview: nil
        case .hall6: "MapHall6"
        case .hall7: "MapHall7"
        case .hall11: "MapHall11"
        case .hall10: "MapHall10"
        }
    }

    /// Width / height of the simplified plan artwork.
    var aspect: CGFloat {
        switch self {
        case .overview: 0.72
        case .hall6: 1024.0 / 468.0
        case .hall7: 1024.0 / 528.0
        case .hall11: 480.0 / 938.0
        case .hall10: 574.0 / 878.0
        }
    }
}

/// One transform for the artwork, controls, and focus rectangles.
/// Turn wide halls in tall viewports; preserve their original proportions.
struct FloorPresentation {
    let rotated: Bool
    let size: CGSize

    init(plan: FloorPlan, viewport: CGSize) {
        let available = CGSize(width: max(viewport.width - 24, 1), height: max(viewport.height - 24, 1))
        rotated = plan.aspect > 1 && available.height > available.width
        let aspect = rotated ? 1 / plan.aspect : plan.aspect
        let width = min(available.width, available.height * aspect)
        size = CGSize(width: width, height: width / aspect)
    }

    func normalized(_ rect: CGRect) -> CGRect {
        guard rotated else { return rect }
        return CGRect(x: 1 - rect.maxY, y: rect.minX, width: rect.height, height: rect.width)
    }

    func frame(_ rect: CGRect) -> CGRect {
        let rect = normalized(rect)
        return CGRect(x: rect.minX * size.width, y: rect.minY * size.height,
                      width: rect.width * size.width, height: rect.height * size.height)
    }
}

enum FloorHotspotKind: Hashable, Sendable {
    case hall(FloorPlan)
    case room
    case amenity
    case boothRow
}

enum StallKind: String, Hashable, Sendable {
    case plugStandard
    case plugDouble
    case plugPremium
    case bare12
    case bare24
    case bare48

    var title: String {
        switch self {
        case .plugStandard: "Standard · 7.5 m²"
        case .plugDouble: "Double · 12 m²"
        case .plugPremium: "Double premium · 12 m²"
        case .bare12: "Bare · 12 m²"
        case .bare24: "Bare · 24 m²"
        case .bare48: "Bare · 48 m²"
        }
    }

    var isBare: Bool {
        switch self {
        case .bare12, .bare24, .bare48: true
        default: false
        }
    }
}

struct FloorFeature: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var ref: String
    var frame: CGRect
    var kind: FloorHotspotKind
    var plan: FloorPlan

    var catalogLocations: [String] {
        VenueLayout.catalogLocations(for: ref)
    }
}

struct BoothStall: Identifiable, Hashable, Sendable {
    var id: String { code }
    var code: String
    var letter: String
    var number: Int
    var frame: CGRect
    var kind: StallKind
    var plan: FloorPlan
}

struct FloorAmenity: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var symbol: String
    var detail: String
}

struct BoothRowInfo: Identifiable, Hashable, Sendable {
    var id: String { letter }
    var letter: String
    var hall: FloorPlan
    var stallCount: Int
    var kindLabel: String
}

enum VenueLayout {
    static let campus = CLLocationCoordinate2D(latitude: 50.9008, longitude: 4.3375)
    static let campusSpan = MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)

    static let boothRows: [BoothRowInfo] = [
        .init(letter: "A", hall: .hall6, stallCount: 24, kindLabel: "Plug & Play"),
        .init(letter: "B", hall: .hall6, stallCount: 7, kindLabel: "Bare"),
        .init(letter: "C", hall: .hall6, stallCount: 24, kindLabel: "Plug & Play"),
        .init(letter: "D", hall: .hall6, stallCount: 16, kindLabel: "Plug & Play"),
        .init(letter: "E", hall: .hall6, stallCount: 4, kindLabel: "Bare"),
        .init(letter: "F", hall: .hall6, stallCount: 16, kindLabel: "Plug & Play"),
        .init(letter: "G", hall: .hall6, stallCount: 16, kindLabel: "Plug & Play"),
        .init(letter: "H", hall: .hall7, stallCount: 14, kindLabel: "Plug & Play"),
        .init(letter: "I", hall: .hall7, stallCount: 10, kindLabel: "Bare"),
        .init(letter: "J", hall: .hall7, stallCount: 10, kindLabel: "Bare"),
        .init(letter: "K", hall: .hall7, stallCount: 16, kindLabel: "Plug & Play"),
        .init(letter: "L", hall: .hall7, stallCount: 16, kindLabel: "Plug & Play"),
        .init(letter: "M", hall: .hall7, stallCount: 7, kindLabel: "Plug & Play"),
        .init(letter: "N", hall: .hall7, stallCount: 14, kindLabel: "Plug & Play"),
        .init(letter: "O", hall: .hall7, stallCount: 14, kindLabel: "Plug & Play"),
        .init(letter: "P", hall: .hall7, stallCount: 14, kindLabel: "Plug & Play"),
        .init(letter: "Q", hall: .hall7, stallCount: 7, kindLabel: "Bare"),
    ]

    static let amenities: [FloorAmenity] = [
        .init(id: "bar-hall6", title: "Bar & Catering", symbol: "cup.and.saucer.fill", detail: "Food and drinks in Hall 6, beside the booth rows and the gaming zone."),
        .init(id: "bar-hall7", title: "Bar & Catering", symbol: "cup.and.saucer.fill", detail: "The Hall 7 catering hub. Startup areas sit around this square."),
        .init(id: "shop", title: "Odoo shop", symbol: "bag.fill", detail: "Official merch on the Hall 6 side toward Hall 10."),
        .init(id: "gaming", title: "Gaming zone", symbol: "gamecontroller.fill", detail: "Arcade and games at the Hall 6 end nearest Hall 7."),
        .init(id: "welcome-hall6", title: "Welcome desk", symbol: "person.crop.rectangle", detail: "Hall 6 welcome desk, next to the Parking C entrance."),
        .init(id: "welcome-hall7", title: "Welcome desk", symbol: "person.crop.rectangle", detail: "Hall 7 welcome desk, inside the Parking C entrance."),
        .init(id: "welcome-hall11", title: "Welcome desk", symbol: "person.crop.rectangle", detail: "Hall 11 welcome desk, at the foot of the main stage."),
        .init(id: "welcome-hall10", title: "Welcome desk", symbol: "person.crop.rectangle", detail: "Hall 10 welcome desk, just inside the main entrance."),
        .init(id: "odoo-village", title: "Odoo village", symbol: "building.2.fill", detail: "Open gathering space in Hall 10, between Auditorium 2000 and the main entrance."),
        .init(id: "meeting-rooms-7", title: "Meeting rooms", symbol: "person.3.fill", detail: "Partner meeting rooms along the Hall 7 edge toward Hall 11."),
        .init(id: "startup-area", title: "Startup area", symbol: "sparkles", detail: "Startup booths clustered around the Hall 7 bar. Individual booth numbers are not on the public exhibitor list yet."),
        .init(id: "ceo-lounge", title: "CEO lounge", symbol: "arrow.up.circle.fill", detail: "Upstairs from Hall 11, via the stairs beside the main stage."),
        .init(id: "parking-c", title: "Parking C", symbol: "car.fill", detail: "Entrance from Parking C feeds Hall 6 and Hall 7."),
    ]

    static let features: [FloorFeature] = overviewFeatures + hall6Features + hall7Features + hall11Features + hall10Features
    static let stalls: [BoothStall] = hall6Stalls + hall7Stalls

    static func features(on plan: FloorPlan) -> [FloorFeature] {
        features.filter { $0.plan == plan }
    }

    static func stalls(on plan: FloorPlan) -> [BoothStall] {
        stalls.filter { $0.plan == plan }
    }

    static func feature(ref: String, on plan: FloorPlan) -> FloorFeature? {
        features.first { $0.ref == ref && $0.plan == plan }
    }

    /// Kept for call sites that still say “hotspot”.
    static func hotspot(ref: String, on plan: FloorPlan) -> FloorFeature? {
        feature(ref: ref, on: plan)
    }

    static func boothRow(_ letter: String) -> BoothRowInfo? {
        boothRows.first { $0.letter == letter }
    }

    static func stall(code: String) -> BoothStall? {
        stalls.first { $0.code == code }
    }

    static func amenity(_ id: String) -> FloorAmenity? {
        amenities.first { $0.id == id }
    }

    static func catalogLocations(for roomID: String) -> [String] {
        switch roomID {
        case "Main stage":
            ["Auditorium 4000 A", "Auditorium 4000 B", "Auditorium 4000 C", "Auditorium 4000 D"]
        case "Auditorium 2000":
            ["Auditorium 2000 A", "Auditorium 2000 B", "Auditorium 2000 C"]
        default:
            [roomID]
        }
    }

    static func floorPlan(forLocation name: String) -> FloorPlan {
        if name.hasPrefix("Hall 6") { return .hall6 }
        if name.hasPrefix("Hall 7") || name == "Education Village" { return .hall7 }
        if name.hasPrefix("Auditorium 4000") || name == "Main stage" { return .hall11 }
        if name.hasPrefix("Auditorium 2000") || name == "Auditorium 500" { return .hall10 }
        return .overview
    }

    static func hotspotID(forLocation name: String) -> String {
        if name.hasPrefix("Auditorium 4000") { return "Main stage" }
        if name.hasPrefix("Auditorium 2000") { return "Auditorium 2000" }
        if name == "Auditorium 500" { return "odoo-village" }
        return name
    }

    static func floorPlan(forExhibitor exhibitor: Exhibitor) -> FloorPlan {
        exhibitor.isStartup ? .hall7 : .overview
    }

    static func normalizedFrame(ref: String, on plan: FloorPlan) -> CGRect? {
        if let feature = features(on: plan).first(where: { $0.ref == ref }) {
            return feature.frame
        }
        let onPlan = stalls(on: plan)
        if let stall = onPlan.first(where: { $0.code.compare(ref, options: .caseInsensitive) == .orderedSame }) {
            return stall.frame
        }
        let row = onPlan.filter { $0.letter.compare(ref, options: .caseInsensitive) == .orderedSame }
        guard let first = row.first else { return nil }
        return row.dropFirst().reduce(first.frame) { $0.union($1.frame) }
    }

    static func matchesFeature(_ feature: FloorFeature, query: String) -> Bool {
        matches(query, titles: [feature.title, feature.ref] + feature.catalogLocations)
    }

    static func matchesStall(_ stall: BoothStall, query: String) -> Bool {
        matches(query, titles: [stall.code, stall.letter, "Booths \(stall.letter)"])
    }

    /// Smallest-first so a room or booth row wins over the hall floor behind it.
    static func hit(at point: CGPoint, on plan: FloorPlan) -> (kind: FloorHotspotKind, ref: String)? {
        let ranked = features(on: plan).sorted {
            $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
        }
        if let feature = ranked.first(where: { $0.frame.contains(point) }) {
            return (feature.kind, feature.ref)
        }
        return nil
    }

    private static func matches(_ query: String, titles: [String]) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        let compact = q.replacingOccurrences(of: " ", with: "")
        return titles.contains { title in
            title.localizedStandardContains(q) || title.localizedStandardContains(compact)
        }
    }

    // MARK: - Overview (2×2 of the simplified halls)

    private static let overviewFeatures: [FloorFeature] = [
        feat("Hall 6", .overview, 0.02, 0.02, 0.47, 0.46, .hall(.hall6)),
        feat("Hall 7", .overview, 0.51, 0.02, 0.47, 0.46, .hall(.hall7)),
        feat("Hall 11", .overview, 0.02, 0.50, 0.47, 0.48, .hall(.hall11), id: "Hall 11"),
        feat("Hall 10", .overview, 0.51, 0.50, 0.47, 0.48, .hall(.hall10), id: "Hall 10"),
    ]

    // MARK: - Hall 6 (simplified landscape plan)

    private static let hall6Features: [FloorFeature] = [
        feat("Hall 6.A", .hall6, 0.207, 0.171, 0.165, 0.113, .room),
        feat("Hall 6.B", .hall6, 0.430, 0.171, 0.159, 0.113, .room),
        feat("Hall 6.C", .hall6, 0.649, 0.171, 0.160, 0.113, .room),
        feat("Hall 6.D", .hall6, 0.859, 0.171, 0.138, 0.291, .room),
        feat("Hall 6.E", .hall6, 0.859, 0.468, 0.138, 0.295, .room),
        feat("A", .hall6, 0.118, 0.318, 0.028, 0.070, .boothRow, id: "row-A", ref: "A"),
        feat("B", .hall6, 0.118, 0.468, 0.028, 0.070, .boothRow, id: "row-B", ref: "B"),
        feat("C", .hall6, 0.118, 0.586, 0.028, 0.070, .boothRow, id: "row-C", ref: "C"),
        feat("D", .hall6, 0.400, 0.318, 0.028, 0.070, .boothRow, id: "row-D", ref: "D"),
        feat("E", .hall6, 0.400, 0.468, 0.028, 0.070, .boothRow, id: "row-E", ref: "E"),
        feat("F", .hall6, 0.400, 0.610, 0.028, 0.070, .boothRow, id: "row-F", ref: "F"),
        feat("G", .hall6, 0.400, 0.745, 0.028, 0.070, .boothRow, id: "row-G", ref: "G"),
        feat("Bar & Catering", .hall6, 0.649, 0.353, 0.160, 0.303, .amenity, id: "bar-hall6"),
        feat("Odoo shop", .hall6, 0.177, 0.720, 0.224, 0.209, .amenity, id: "shop"),
        feat("Gaming zone", .hall6, 0.649, 0.720, 0.160, 0.209, .amenity, id: "gaming"),
        feat("Parking C", .hall6, 0.901, 0.771, 0.096, 0.060, .amenity, id: "parking-c"),
        feat("Hall 10", .hall6, 0.008, 0.261, 0.070, 0.430, .hall(.hall10), id: "to-hall-10"),
        feat("Hall 7", .hall6, 0.820, 0.90, 0.16, 0.07, .hall(.hall7), id: "to-hall-7"),
    ]

    private static let hall6Stalls: [BoothStall] =
        pairedPlug("A", 24, r(0.147, 0.346, 0.226, 0.068), .hall6)
        + weightedBare("B", [2, 1, 1, 1, 1, 1, 2], r(0.147, 0.479, 0.270, 0.080), .hall6)
        + pairedPlug("C", 24, r(0.147, 0.596, 0.226, 0.071), .hall6)
        + pairedPlug("D", 16, r(0.427, 0.346, 0.165, 0.068), .hall6)
        + weightedBare("E", [2, 1, 1, 2], r(0.427, 0.479, 0.165, 0.080), .hall6)
        + pairedPlug("F", 16, r(0.427, 0.622, 0.165, 0.068), .hall6)
        + pairedPlug("G", 16, r(0.427, 0.756, 0.165, 0.071), .hall6)

    // MARK: - Hall 7 (simplified landscape plan)

    private static let hall7Features: [FloorFeature] = [
        feat("Education Village", .hall7, 0.120, 0.068, 0.174, 0.239, .room),
        feat("Hall 6", .hall7, 0.384, 0.108, 0.161, 0.064, .hall(.hall6), id: "to-hall-6"),
        feat("Welcome desk", .hall7, 0.887, 0.174, 0.110, 0.061, .amenity, id: "welcome-hall7"),
        feat("Hall 7.A", .hall7, 0.831, 0.242, 0.166, 0.337, .room),
        feat("Hall 7.B", .hall7, 0.831, 0.585, 0.166, 0.345, .room),
        feat("H", .hall7, 0.090, 0.375, 0.028, 0.070, .boothRow, id: "row-H", ref: "H"),
        feat("I", .hall7, 0.090, 0.500, 0.028, 0.100, .boothRow, id: "row-I", ref: "I"),
        feat("J", .hall7, 0.090, 0.653, 0.028, 0.100, .boothRow, id: "row-J", ref: "J"),
        feat("K", .hall7, 0.338, 0.231, 0.028, 0.070, .boothRow, id: "row-K", ref: "K"),
        feat("L", .hall7, 0.338, 0.703, 0.028, 0.070, .boothRow, id: "row-L", ref: "L"),
        feat("M", .hall7, 0.572, 0.123, 0.028, 0.038, .boothRow, id: "row-M", ref: "M"),
        feat("N", .hall7, 0.572, 0.206, 0.028, 0.070, .boothRow, id: "row-N", ref: "N"),
        feat("O", .hall7, 0.572, 0.324, 0.028, 0.070, .boothRow, id: "row-O", ref: "O"),
        feat("P", .hall7, 0.572, 0.561, 0.028, 0.070, .boothRow, id: "row-P", ref: "P"),
        feat("Q", .hall7, 0.572, 0.676, 0.028, 0.098, .boothRow, id: "row-Q", ref: "Q"),
        feat("Bar & Catering", .hall7, 0.370, 0.354, 0.184, 0.295, .amenity, id: "bar-hall7"),
        feat("Startup area", .hall7, 0.602, 0.445, 0.059, 0.064, .amenity, id: "startup-n", ref: "startup-area"),
        feat("Startup area", .hall7, 0.712, 0.445, 0.060, 0.064, .amenity, id: "startup-e", ref: "startup-area"),
        feat("Meeting rooms", .hall7, 0.120, 0.830, 0.174, 0.055, .amenity, id: "meeting-7-west", ref: "meeting-rooms-7"),
        feat("Meeting rooms", .hall7, 0.384, 0.824, 0.161, 0.066, .amenity, id: "meeting-7-mid", ref: "meeting-rooms-7"),
        feat("Meeting rooms", .hall7, 0.593, 0.830, 0.174, 0.055, .amenity, id: "meeting-7-east", ref: "meeting-rooms-7"),
        feat("Hall 10", .hall7, 0.015, 0.068, 0.051, 0.862, .hall(.hall10), id: "to-hall-10"),
        feat("Hall 11", .hall7, 0.370, 0.90, 0.40, 0.07, .hall(.hall11), id: "to-hall-11"),
    ]

    private static let hall7Stalls: [BoothStall] =
        pairedPlug("H", 14, r(0.118, 0.375, 0.173, 0.070), .hall7)
        + weightedBare("I", [2, 1, 1, 1, 2, 1, 1, 1, 1, 2], r(0.118, 0.500, 0.203, 0.105), .hall7)
        + weightedBare("J", [2, 1, 1, 1, 2, 1, 1, 1, 1, 2], r(0.118, 0.653, 0.203, 0.102), .hall7)
        + pairedPlug("K", 16, r(0.368, 0.231, 0.190, 0.070), .hall7)
        + pairedPlug("L", 16, r(0.368, 0.703, 0.190, 0.070), .hall7)
        + singlePlug("M", 7, r(0.600, 0.123, 0.173, 0.042), .hall7)
        + pairedPlug("N", 14, r(0.600, 0.206, 0.173, 0.070), .hall7)
        + pairedPlug("O", 14, r(0.600, 0.324, 0.173, 0.070), .hall7)
        + pairedPlug("P", 14, r(0.600, 0.561, 0.173, 0.070), .hall7)
        + weightedBare("Q", [2, 1, 1, 1, 1, 1, 2], r(0.592, 0.676, 0.181, 0.098), .hall7)

    // MARK: - Hall 11 (main stage)

    private static let hall11Features: [FloorFeature] = [
        feat("Main stage", .hall11, 0.12, 0.10, 0.76, 0.68, .room),
        feat("Welcome desk", .hall11, 0.34, 0.80, 0.32, 0.05, .amenity, id: "welcome-hall11"),
        feat("CEO lounge", .hall11, 0.248, 0.855, 0.094, 0.049, .amenity, id: "ceo-lounge"),
        feat("Hall 7", .hall11, 0.02, 0.28, 0.10, 0.36, .hall(.hall7), id: "to-hall-7"),
        feat("Hall 10", .hall11, 0.34, 0.92, 0.32, 0.05, .hall(.hall10), id: "to-hall-10"),
    ]

    // MARK: - Hall 10 (Odoo village)

    private static let hall10Features: [FloorFeature] = [
        feat("Auditorium 2000", .hall10, 0.334, 0.248, 0.497, 0.083, .room),
        feat("Odoo village", .hall10, 0.333, 0.330, 0.498, 0.481, .amenity, id: "odoo-village"),
        feat("Welcome desk", .hall10, 0.387, 0.814, 0.395, 0.073, .amenity, id: "welcome-hall10"),
        feat("Hall 7", .hall10, 0.04, 0.26, 0.20, 0.10, .hall(.hall7), id: "to-hall-7"),
        feat("Hall 11", .hall10, 0.334, 0.04, 0.497, 0.18, .hall(.hall11), id: "to-hall-11"),
    ]

    // MARK: - Geometry helpers

    private static func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }

    private static func feat(
        _ title: String,
        _ plan: FloorPlan,
        _ x: CGFloat,
        _ y: CGFloat,
        _ w: CGFloat,
        _ h: CGFloat,
        _ kind: FloorHotspotKind,
        id: String? = nil,
        ref: String? = nil
    ) -> FloorFeature {
        let resolved = id ?? title
        return FloorFeature(
            id: "\(plan.rawValue)-\(resolved)",
            title: title,
            ref: ref ?? resolved,
            frame: r(x, y, w, h),
            kind: kind,
            plan: plan
        )
    }

    /// Official plug & play rows: odds on one side, evens on the other.
    private static func pairedPlug(
        _ letter: String,
        _ count: Int,
        _ frame: CGRect,
        _ plan: FloorPlan
    ) -> [BoothStall] {
        let pairs = max(count / 2, 1)
        let gap: CGFloat = 0.003
        let alongWidth = frame.width >= frame.height
        if alongWidth {
            let cellW = (frame.width - gap * CGFloat(pairs + 1)) / CGFloat(pairs)
            let cellH = (frame.height - gap * 3) / 2
            return (0..<pairs).flatMap { col -> [BoothStall] in
                let odd = col * 2 + 1
                let even = col * 2 + 2
                guard odd <= count else { return [] }
                let x = frame.minX + gap + CGFloat(col) * (cellW + gap)
                var cells = [
                    stall(letter, odd, CGRect(x: x, y: frame.minY + gap, width: cellW, height: cellH), plugKind(odd), plan),
                ]
                if even <= count {
                    cells.append(
                        stall(
                            letter,
                            even,
                            CGRect(x: x, y: frame.minY + gap * 2 + cellH, width: cellW, height: cellH),
                            plugKind(even),
                            plan
                        )
                    )
                }
                return cells
            }
        }
        let cellH = (frame.height - gap * CGFloat(pairs + 1)) / CGFloat(pairs)
        let cellW = (frame.width - gap * 3) / 2
        return (0..<pairs).flatMap { row -> [BoothStall] in
            let odd = row * 2 + 1
            let even = row * 2 + 2
            guard odd <= count else { return [] }
            let y = frame.minY + gap + CGFloat(row) * (cellH + gap)
            var cells = [
                stall(letter, odd, CGRect(x: frame.minX + gap, y: y, width: cellW, height: cellH), plugKind(odd), plan),
            ]
            if even <= count {
                cells.append(
                    stall(
                        letter,
                        even,
                        CGRect(x: frame.minX + gap * 2 + cellW, y: y, width: cellW, height: cellH),
                        plugKind(even),
                        plan
                    )
                )
            }
            return cells
        }
    }

    private static func singlePlug(
        _ letter: String,
        _ count: Int,
        _ frame: CGRect,
        _ plan: FloorPlan
    ) -> [BoothStall] {
        let gap: CGFloat = 0.003
        if frame.width >= frame.height {
            let cellW = (frame.width - gap * CGFloat(count + 1)) / CGFloat(count)
            return (1...count).map { number in
                let x = frame.minX + gap + CGFloat(number - 1) * (cellW + gap)
                return stall(
                    letter,
                    number,
                    CGRect(x: x, y: frame.minY + gap, width: cellW, height: frame.height - gap * 2),
                    plugKind(number),
                    plan
                )
            }
        }
        let cellH = (frame.height - gap * CGFloat(count + 1)) / CGFloat(count)
        return (1...count).map { number in
            let y = frame.minY + gap + CGFloat(number - 1) * (cellH + gap)
            return stall(
                letter,
                number,
                CGRect(x: frame.minX + gap, y: y, width: frame.width - gap * 2, height: cellH),
                plugKind(number),
                plan
            )
        }
    }

    private static func weightedBare(
        _ letter: String,
        _ weights: [CGFloat],
        _ frame: CGRect,
        _ plan: FloorPlan
    ) -> [BoothStall] {
        let gap: CGFloat = 0.003
        let total = weights.reduce(0, +)
        let alongWidth = frame.width >= frame.height
        if alongWidth {
            let usable = frame.width - gap * CGFloat(weights.count + 1)
            var x = frame.minX + gap
            return weights.enumerated().map { index, weight in
                let width = usable * (weight / total)
                let cell = stall(
                    letter,
                    index + 1,
                    CGRect(x: x, y: frame.minY + gap, width: width, height: frame.height - gap * 2),
                    bareKind(weight),
                    plan
                )
                x += width + gap
                return cell
            }
        }
        let usable = frame.height - gap * CGFloat(weights.count + 1)
        var y = frame.minY + gap
        return weights.enumerated().map { index, weight in
            let height = usable * (weight / total)
            let cell = stall(
                letter,
                index + 1,
                CGRect(x: frame.minX + gap, y: y, width: frame.width - gap * 2, height: height),
                bareKind(weight),
                plan
            )
            y += height + gap
            return cell
        }
    }

    private static func bareKind(_ weight: CGFloat) -> StallKind {
        weight >= 2 ? .bare48 : (weight >= 1.5 ? .bare24 : .bare12)
    }

    private static func plugKind(_ number: Int) -> StallKind {
        if number % 11 == 0 { return .plugPremium }
        if number % 4 == 0 { return .plugDouble }
        return .plugStandard
    }

    private static func stall(
        _ letter: String,
        _ number: Int,
        _ frame: CGRect,
        _ kind: StallKind,
        _ plan: FloorPlan
    ) -> BoothStall {
        BoothStall(
            code: "\(letter)\(number)",
            letter: letter,
            number: number,
            frame: frame,
            kind: kind,
            plan: plan
        )
    }
}

enum FloorPalette {
    static let canvas = Color(red: 0.11, green: 0.06, blue: 0.18)
    static let hallFill = Color.white.opacity(0.06)
    static let roomFill = Color.white.opacity(0.12)
    static let amenityFill = Color(red: 0.35, green: 0.22, blue: 0.42).opacity(0.85)
    static let stroke = Color.white.opacity(0.55)
    static let label = Color.white

    static func stallFill(_ kind: StallKind) -> Color {
        switch kind {
        case .plugStandard: Color(red: 0.92, green: 0.62, blue: 0.72)
        case .plugDouble: Color(red: 0.86, green: 0.32, blue: 0.52)
        case .plugPremium: Color(red: 0.55, green: 0.22, blue: 0.48)
        case .bare12: Color.white.opacity(0.88)
        case .bare24: Color(red: 0.42, green: 0.78, blue: 0.78)
        case .bare48: Color(red: 0.12, green: 0.48, blue: 0.50)
        }
    }

    static func stallInk(_ kind: StallKind) -> Color {
        switch kind {
        case .bare12: Color(red: 0.18, green: 0.12, blue: 0.22)
        case .plugPremium, .bare48: .white
        default: Color(red: 0.18, green: 0.08, blue: 0.16)
        }
    }
}
