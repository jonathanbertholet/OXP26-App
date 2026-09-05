import SwiftUI

struct FloorMapCanvas: View {
    var plan: FloorPlan
    var presentation: FloorPresentation
    var query: String
    var highlightedRef: String?
    var highlightedExhibitor: Exhibitor?
    var onActivate: (FloorHotspotKind, String) -> Void

    var body: some View {
        let size = presentation.size
        Group {
            if plan == .overview {
                overview(in: size)
            } else {
                hall(in: size)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .animation(.snappy(duration: 0.25), value: highlightedRef)
        .animation(.snappy(duration: 0.25), value: query)
    }

    private func overview(in size: CGSize) -> some View {
        AbsoluteMapLayout(size: size) {
            ForEach(VenueLayout.features(on: .overview)) { feature in
                if case .hall(let hall) = feature.kind {
                    let matches = query.isEmpty || VenueLayout.matchesFeature(feature, query: query)
                        || VenueLayout.features(on: hall).contains { VenueLayout.matchesFeature($0, query: query) }
                        || VenueLayout.stalls(on: hall).contains { VenueLayout.matchesStall($0, query: query) }
                    Button {
                        onActivate(feature.kind, feature.ref)
                    } label: {
                        FloorHallThumbnail(plan: hall)
                            .overlay {
                                RoundedRectangle(cornerRadius: 18)
                                    .strokeBorder(OxpTheme.accentInk, lineWidth: overviewEmphasized(hall, matches: matches) ? 2 : 0)
                            }
                    }
                    .buttonStyle(.plain)
                    .opacity(matches ? 1 : 0.3)
                    .accessibilityLabel("\(hall.title), \(hall.summary)")
                    .accessibilityHint("Open the hall map")
                    .mapFrame(floorPixelFrame(feature.frame, size: size, rotated: false))
                }
            }
        }
    }

    private func hall(in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            hallDrawing(in: presentation.drawingFrame.size)
                .offset(x: presentation.drawingFrame.minX, y: presentation.drawingFrame.minY)
            AbsoluteMapLayout(size: size) {
                ForEach(VenueLayout.features(on: plan)) { feature in
                    if case .hall = feature.kind {
                        Button {
                            onActivate(feature.kind, feature.ref)
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: presentation.directionEdge(for: feature.frame).symbol)
                                    .font(.system(size: 15, weight: .semibold))
                                Text(feature.title)
                                    .font(.system(size: 10, weight: .semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .foregroundStyle(OxpTheme.accentInk)
                            .frame(width: 44, height: 44)
                            .background(FloorPalette.card, in: .rect(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("To \(feature.title)")
                        .mapFrame(presentation.directionFrame(for: feature.frame))
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var rotated: Bool { presentation.rotated }

    private func hallDrawing(in size: CGSize) -> some View {
        ZStack {
            FloorHallBase(plan: plan, size: size, rotated: rotated)
            AbsoluteMapLayout(size: size) {
                ForEach(VenueLayout.features(on: plan).filter { if case .hall = $0.kind { false } else { true } }) { feature in
                    let frame = floorPixelFrame(feature.frame, size: size, rotated: rotated)
                    let matches = VenueLayout.matchesFeature(feature, query: query)
                    let emphasized = feature.ref == highlightedRef || (!query.isEmpty && matches)
                        || (highlightedExhibitor?.isStartup == true && feature.ref == "startup-area")
                    Button {
                        onActivate(feature.kind, feature.ref)
                    } label: {
                        FloorFeatureMark(feature: feature, size: frame.size, rotated: rotated, thumbnail: false)
                            .overlay {
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(FloorPalette.selection, lineWidth: emphasized ? 2.5 : 0)
                            }
                            .frame(width: frame.width, height: frame.height)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(!query.isEmpty && !matches ? 0.25 : 1)
                    .accessibilityLabel(feature.accessibilityTitle)
                    .mapFrame(frame)
                }
                ForEach(VenueLayout.stalls(on: plan)) { stall in
                    let frame = floorPixelFrame(stall.frame, size: size, rotated: rotated)
                    let matches = VenueLayout.matchesStall(stall, query: query)
                    let emphasized = stall.code == highlightedRef || stall.letter == highlightedRef
                        || (!query.isEmpty && matches) || highlightedExhibitor != nil
                    FloorStallMark(stall: stall, size: frame.size)
                        .overlay {
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(FloorPalette.selection, lineWidth: emphasized ? 1.5 : 0)
                        }
                        .opacity(!query.isEmpty && !matches ? 0.2 : 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .mapFrame(frame)
                }
            }
        }
    }

    private func overviewEmphasized(_ hall: FloorPlan, matches: Bool) -> Bool {
        if !query.isEmpty { return matches }
        guard let exhibitor = highlightedExhibitor else { return false }
        return hall == .hall7 || (hall == .hall6 && !exhibitor.isStartup)
    }
}

/// Titles have their own space. The miniature uses the same coordinates as the
/// interactive hall, with minor labels omitted at this scale.
private struct FloorHallThumbnail: View {
    let plan: FloorPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(plan.title).font(.headline)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
                    .foregroundStyle(OxpTheme.accentInk)
            }
            Text(plan.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            GeometryReader { geo in
                let layout = FloorPresentation(plan: plan, viewport: geo.size, padding: 0, includesDirections: false)
                ZStack {
                    FloorHallBase(plan: plan, size: layout.size, rotated: layout.rotated)
                    AbsoluteMapLayout(size: layout.size) {
                        ForEach(VenueLayout.features(on: plan).filter { if case .hall = $0.kind { false } else { true } }) { feature in
                            let frame = layout.frame(feature.frame)
                            FloorFeatureMark(feature: feature, size: frame.size, rotated: layout.rotated, thumbnail: true)
                                .mapFrame(frame)
                        }
                        ForEach(VenueLayout.stalls(on: plan)) { stall in
                            let frame = layout.frame(stall.frame)
                            FloorStallMark(stall: stall, size: frame.size, showsNumber: false)
                                .mapFrame(frame)
                        }
                    }
                }
                .frame(width: layout.size.width, height: layout.size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .accessibilityHidden(true)
        }
        .padding(12)
        .background(FloorPalette.card, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).strokeBorder(FloorPalette.stroke, lineWidth: 1)
        }
    }
}

private struct FloorHallBase: View {
    let plan: FloorPlan
    let size: CGSize
    let rotated: Bool

    var body: some View {
        FloorFootprint(plan: plan, rotated: rotated)
            .fill(FloorPalette.hallFill)
            .overlay {
                FloorFootprint(plan: plan, rotated: rotated)
                    .stroke(FloorPalette.stroke, lineWidth: 1.5)
            }
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Simplified outer walls traced from the bundled venue plans. Internal rooms
/// and booth rows retain VenueLayout's source coordinates.
private struct FloorFootprint: Shape {
    let plan: FloorPlan
    let rotated: Bool

    func path(in rect: CGRect) -> Path {
        let points: [CGPoint]
        switch plan {
        case .hall6:
            points = [.init(x: 0.05, y: 0.20), .init(x: 0.12, y: 0.06), .init(x: 0.20, y: 0.06),
                      .init(x: 0.20, y: 0.115), .init(x: 0.997, y: 0.115), .init(x: 0.997, y: 0.935),
                      .init(x: 0.82, y: 0.935), .init(x: 0.82, y: 0.995), .init(x: 0.61, y: 0.995),
                      .init(x: 0.61, y: 0.935), .init(x: 0.05, y: 0.935)]
        case .hall7:
            points = [.init(x: 0.015, y: 0.065), .init(x: 0.55, y: 0.065), .init(x: 0.55, y: 0.01),
                      .init(x: 0.60, y: 0.01), .init(x: 0.60, y: 0.065), .init(x: 0.75, y: 0.065),
                      .init(x: 0.75, y: 0.01), .init(x: 0.85, y: 0.01), .init(x: 0.85, y: 0.065),
                      .init(x: 0.997, y: 0.065), .init(x: 0.997, y: 0.935), .init(x: 0.85, y: 0.935),
                      .init(x: 0.85, y: 0.99), .init(x: 0.75, y: 0.99), .init(x: 0.75, y: 0.935),
                      .init(x: 0.60, y: 0.935), .init(x: 0.60, y: 0.99), .init(x: 0.55, y: 0.99),
                      .init(x: 0.55, y: 0.935), .init(x: 0.015, y: 0.935)]
        case .hall11:
            points = [.init(x: 0.07, y: 0.10), .init(x: 0.88, y: 0.10),
                      .init(x: 0.88, y: 0.91), .init(x: 0.07, y: 0.91)]
        case .hall10:
            points = [.init(x: 0.25, y: 0.15), .init(x: 0.32, y: 0.11), .init(x: 0.85, y: 0.11),
                      .init(x: 0.91, y: 0.15), .init(x: 0.91, y: 0.89), .init(x: 0.25, y: 0.89)]
        case .overview: points = []
        }
        let transformed = points.map { point in
            let p = rotated ? CGPoint(x: 1 - point.y, y: point.x) : point
            return CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
        }
        return Path { path in
            path.addLines(transformed)
            path.closeSubpath()
        }
    }
}

private struct FloorFeatureMark: View {
    let feature: FloorFeature
    let size: CGSize
    let rotated: Bool
    let thumbnail: Bool

    private var isDirection: Bool {
        if case .hall = feature.kind { return true }
        return feature.ref == "entrance-hall10" || feature.ref == "parking-c"
    }

    private var tint: Color {
        switch feature.kind {
        case .room: OxpTheme.roomColor(feature.ref)
        case .amenity: FloorPalette.amenityInk
        case .boothRow: OxpTheme.accentInk
        case .hall: OxpTheme.accentInk
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: feature.kind == .boothRow ? 3 : 7)
                .fill(isDirection ? FloorPalette.card : tint.opacity(feature.kind == .boothRow ? 0.15 : 0.12))
            if !isDirection && feature.kind != .boothRow {
                RoundedRectangle(cornerRadius: 7).strokeBorder(tint.opacity(0.4), lineWidth: 1)
            }
            if !thumbnail || feature.ref == "Main stage" || feature.ref == "odoo-village" || feature.ref == "Auditorium 2000" {
                label
                    .padding(thumbnail || isDirection || feature.kind == .boothRow || size.width < 36 ? 1 : 4)
                    .frame(width: size.width, height: size.height)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private var label: some View {
        if feature.ref == "Main stage" {
            VStack(spacing: thumbnail ? 4 : 12) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: thumbnail ? 14 : 26))
                    .foregroundStyle(OxpTheme.accentInk)
                Text("Main stage")
                    .font(.system(size: thumbnail ? 10 : 22, weight: .bold))
                // A directory within the shared auditorium, not invented room partitions.
                VStack(spacing: thumbnail ? 3 : 8) {
                    if thumbnail {
                        ForEach(VenueLayout.catalogLocations(for: "Main stage"), id: \.self) { stage in
                            Text(stage.replacingOccurrences(of: "Auditorium ", with: "").replacingOccurrences(of: " ", with: ""))
                                .lineLimit(1)
                        }
                    } else {
                        Text("4000A · 4000B").lineLimit(1)
                        Text("4000C · 4000D").lineLimit(1)
                    }
                }
                .font(.system(size: thumbnail ? 8 : 15, weight: .semibold, design: .rounded))
                .foregroundStyle(OxpTheme.accentInk)
            }
            .foregroundStyle(FloorPalette.label)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.center)
        } else if feature.kind == .boothRow {
            Text(feature.ref)
                .font(.system(size: min(12, min(size.width, size.height) * 0.7), weight: .bold))
                .foregroundStyle(FloorPalette.label)
                .lineLimit(1)
        } else if !thumbnail, feature.kind == .amenity, !isDirection, size.width < 36 {
            if size.height >= 42 {
                Text(shortTitle)
                    .font(.system(size: min(11, size.width * 0.65), weight: .semibold))
                    .foregroundStyle(FloorPalette.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: size.height - 6, height: size.width - 2)
                    .rotationEffect(.degrees(-90))
            } else if let symbol = VenueLayout.amenity(feature.ref)?.symbol {
                Image(systemName: symbol)
                    .font(.system(size: min(13, size.width * 0.7), weight: .semibold))
                    .foregroundStyle(FloorPalette.amenityInk)
            }
        } else if isDirection && size.width < 42 {
            VStack(spacing: 3) {
                Image(systemName: directionSymbol)
                Text(feature.ref == "parking-c" ? "C" : feature.title.replacingOccurrences(of: " ", with: "\n"))
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
            }
            .font(.system(size: min(10, size.width * 0.45), weight: .semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(FloorPalette.label)
        } else {
            let fontSize = thumbnail ? 8 : max(10, min(19, min(size.width, size.height) * 0.24))
            ViewThatFits {
                if isDirection {
                    HStack(spacing: 4) {
                        Image(systemName: directionSymbol)
                        Text(shortTitle)
                    }
                }
                VStack(spacing: 3) {
                    if !thumbnail, feature.kind == .amenity, size.height > 42, size.width > 36,
                       let symbol = VenueLayout.amenity(feature.ref)?.symbol {
                        Image(systemName: symbol).foregroundStyle(tint)
                    }
                    if isDirection { Image(systemName: directionSymbol) }
                    Text(shortTitle)
                    if feature.ref == "ceo-lounge" { Text("Upstairs").font(.system(size: 9)) }
                    if feature.ref == "Auditorium 2000", !thumbnail {
                        Text("2000A · B · C").font(.system(size: 10, weight: .medium))
                    }
                }
            }
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(FloorPalette.label)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.65)
        }
    }

    private var shortTitle: String {
        switch feature.ref {
        case "bar-hall6", "bar-hall7": "Food & drink"
        case "meeting-rooms-7": "Meetings"
        case "startup-area": "Startups"
        case "welcome-hall7", "welcome-hall10", "welcome-hall11": "Welcome"
        case "Education Village": "Education"
        default: feature.title.replacingOccurrences(of: "Hall 6.", with: "6.")
            .replacingOccurrences(of: "Hall 7.", with: "7.")
        }
    }

    private var directionSymbol: String {
        if feature.ref == "entrance-hall10" { return "arrow.up" }
        if feature.ref == "parking-c" { return "parkingsign.circle" }
        let frame = floorPixelFrame(feature.frame, size: CGSize(width: 1, height: 1), rotated: rotated)
        if frame.midX < 0.2 { return "arrow.left" }
        if frame.midX > 0.8 { return "arrow.right" }
        return frame.midY < 0.5 ? "arrow.up" : "arrow.down"
    }
}

private struct FloorStallMark: View {
    let stall: BoothStall
    let size: CGSize
    var showsNumber = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(FloorPalette.stallFill(stall.kind))
            .overlay {
                RoundedRectangle(cornerRadius: 1.5)
                    .strokeBorder(FloorPalette.stroke, lineWidth: 0.5)
            }
            .overlay {
                if showsNumber {
                    Text(stall.number, format: .number)
                        .font(.system(size: min(size.width, size.height) * 0.6, weight: .bold))
                        .foregroundStyle(FloorPalette.stallInk(stall.kind))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .frame(width: size.width, height: size.height)
    }
}

private func floorPixelFrame(_ frame: CGRect, size: CGSize, rotated: Bool) -> CGRect {
    let rect = FloorPresentation.normalized(frame, rotated: rotated)
    return CGRect(x: rect.minX * size.width, y: rect.minY * size.height,
                  width: rect.width * size.width, height: rect.height * size.height)
}

/// Places each child in its map rectangle so hit-testing matches the drawn shape.
private struct AbsoluteMapLayout: Layout {
    var size: CGSize

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { size }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let frame = subview[MapFrameKey.self]
            subview.place(at: CGPoint(x: bounds.minX + frame.midX, y: bounds.minY + frame.midY),
                          anchor: .center, proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }
}

private struct MapFrameKey: LayoutValueKey {
    static let defaultValue = CGRect.zero
}

private extension View {
    func mapFrame(_ rect: CGRect) -> some View { layoutValue(key: MapFrameKey.self, value: rect) }
}
