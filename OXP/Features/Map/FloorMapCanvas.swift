import SwiftUI

struct FloorMapCanvas: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(ConferenceClock.self) private var clock

    var plan: FloorPlan
    var canvasSize: CGSize
    var rotated: Bool = false
    var query: String
    var highlightedRef: String?
    var highlightedExhibitor: Exhibitor?
    var onActivate: (FloorHotspotKind, String) -> Void

    var body: some View {
        let size = CGSize(width: max(canvasSize.width, 1), height: max(canvasSize.height, 1))
        ZStack {
            FloorPalette.canvas
            artwork(in: size)
            AbsoluteMapLayout(size: size) {
                ForEach(sortedFeatures) { feature in
                    featureButton(feature, in: size)
                        .mapFrame(pixel(feature.frame, in: size))
                }
                ForEach(VenueLayout.stalls(on: plan)) { stall in
                    stallMark(stall, in: size)
                        .mapFrame(pixel(stall.frame, in: size))
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .animation(.smooth(duration: 0.42), value: plan)
        .animation(.snappy(duration: 0.25), value: highlightedRef)
        .animation(.snappy(duration: 0.25), value: query)
    }

    private var sortedFeatures: [FloorFeature] {
        VenueLayout.features(on: plan)
            .sorted { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }
    }

    @ViewBuilder
    private func artwork(in size: CGSize) -> some View {
        if let name = plan.imageName {
            Image(name)
                .resizable()
                .interpolation(.high)
                .frame(width: rotated ? size.height : size.width, height: rotated ? size.width : size.height)
                .rotationEffect(.degrees(rotated ? 90 : 0))
                .frame(width: size.width, height: size.height)
                .opacity(query.isEmpty ? 1 : 0.28)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func featureButton(_ feature: FloorFeature, in size: CGSize) -> some View {
        let frame = pixel(feature.frame, in: size)
        let matches = VenueLayout.matchesFeature(feature, query: query)
        let selected = feature.ref == highlightedRef
        let live = feature.kind == .room
            ? catalog.nowAndNext(in: feature.ref, at: clock.now).now
            : nil
        let expo = shouldHighlightForExpo(feature: feature)
        let emphasized = selected || (matches && !query.isEmpty) || expo
        let dimmed = !query.isEmpty && !matches
        let nestedHall: FloorPlan? = {
            if case .hall(let next) = feature.kind { return next }
            return nil
        }()
        let radius: CGFloat = nestedHall != nil ? 14 : (feature.kind == .boothRow ? 4 : 6)
        let labeledPlan = plan == .hall6 || plan == .hall7 || plan == .overview

        return Button {
            onActivate(feature.kind, feature.ref)
        } label: {
            ZStack {
                if let nestedHall, let imageName = nestedHall.imageName, plan == .overview {
                    Image(imageName)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(6)
                }
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill(for: feature, emphasized: emphasized, hasArtwork: plan.imageName != nil || plan == .overview))
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(
                        emphasized ? Color.yellow : FloorPalette.stroke.opacity(plan == .overview ? 0.55 : 0),
                        lineWidth: emphasized ? 2.5 : 1
                    )
                if labeledPlan, nestedHall == nil || plan == .overview {
                    VStack(spacing: 2) {
                        Text(label(for: feature))
                            .font(.system(size: fontSize(for: frame), weight: .semibold))
                            .foregroundStyle(FloorPalette.label)
                            .shadow(color: .black.opacity(0.65), radius: 3, y: 1)
                            .minimumScaleFactor(0.4)
                            .lineLimit(3)
                            .multilineTextAlignment(.center)
                        if let live {
                            Text(live.name)
                                .font(.system(size: max(7, fontSize(for: frame) * 0.55), weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(2)
                                .minimumScaleFactor(0.4)
                        }
                    }
                    .padding(3)
                } else if let live {
                    Text(live.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.7), radius: 4, y: 1)
                        .padding(8)
                }
            }
            .frame(width: frame.width, height: frame.height)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(dimmed ? 0.2 : 1)
        .accessibilityLabel(feature.title)
    }

    /// Painted only — rooms and booth-row labels stay tappable underneath.
    private func stallMark(_ stall: BoothStall, in size: CGSize) -> some View {
        let frame = pixel(stall.frame, in: size)
        let matches = VenueLayout.matchesStall(stall, query: query)
        let selected = stall.code == highlightedRef || stall.letter == highlightedRef
        let expo = highlightedExhibitor != nil
        let emphasized = selected || (matches && !query.isEmpty) || expo
        let dimmed = !query.isEmpty && !matches
        let showCode = min(frame.width, frame.height) >= 18

        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(emphasized ? FloorPalette.stallFill(stall.kind) : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(emphasized ? Color.yellow : Color.clear, lineWidth: 2)
            }
            .overlay {
                if showCode {
                    Text(stall.code)
                        .font(.system(size: max(6, min(frame.width, frame.height) * 0.4), weight: .bold))
                        .foregroundStyle(emphasized ? FloorPalette.stallInk(stall.kind) : .white.opacity(0.9))
                        .shadow(color: .black.opacity(0.55), radius: 1)
                        .minimumScaleFactor(0.25)
                        .lineLimit(1)
                }
            }
            .opacity(dimmed ? 0.15 : 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func fill(for feature: FloorFeature, emphasized: Bool, hasArtwork: Bool) -> Color {
        if rotated, feature.kind != .hall(.hall6), feature.kind != .hall(.hall7),
           feature.kind != .hall(.hall10), feature.kind != .hall(.hall11) {
            return emphasized ? OxpTheme.accent : Color(red: 0.18, green: 0.14, blue: 0.24)
        }
        if hasArtwork, !emphasized {
            return .clear
        }
        switch feature.kind {
        case .hall:
            return FloorPalette.hallFill.opacity(plan == .overview ? 0.12 : 0.001)
        case .room:
            return OxpTheme.roomColor(feature.ref).opacity(emphasized ? 0.55 : 0.28)
        case .amenity:
            return FloorPalette.amenityFill.opacity(emphasized ? 0.7 : 0.35)
        case .boothRow:
            return Color.white.opacity(emphasized ? 0.28 : 0.12)
        }
    }

    private func label(for feature: FloorFeature) -> String {
        switch feature.kind {
        case .hall:
            feature.title
        case .boothRow:
            feature.ref
        case .room:
            feature.ref
                .replacingOccurrences(of: "Auditorium ", with: "Aud ")
                .replacingOccurrences(of: "Education Village", with: "Education")
        case .amenity:
            feature.title
        }
    }

    private func fontSize(for frame: CGRect) -> CGFloat {
        max(10, min(18, min(frame.width, frame.height) * 0.24))
    }

    private func shouldHighlightForExpo(feature: FloorFeature) -> Bool {
        guard let exhibitor = highlightedExhibitor else { return false }
        if exhibitor.isStartup {
            return feature.ref == "startup-area" || feature.kind == .boothRow
        }
        return feature.kind == .hall(.hall6) || feature.kind == .hall(.hall7) || feature.kind == .boothRow
    }

    private func pixel(_ frame: CGRect, in size: CGSize) -> CGRect {
        let frame = rotated
            ? CGRect(x: 1 - frame.maxY, y: frame.minX, width: frame.height, height: frame.width)
            : frame
        return CGRect(
            x: frame.minX * size.width,
            y: frame.minY * size.height,
            width: frame.width * size.width,
            height: frame.height * size.height
        )
    }
}

/// Places each child in its map rectangle so hit-testing matches the drawn shape.
private struct AbsoluteMapLayout: Layout {
    var size: CGSize

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let frame = subview[MapFrameKey.self]
            subview.place(
                at: CGPoint(x: bounds.minX + frame.midX, y: bounds.minY + frame.midY),
                anchor: .center,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }
}

private struct MapFrameKey: LayoutValueKey {
    static let defaultValue = CGRect.zero
}

private extension View {
    func mapFrame(_ rect: CGRect) -> some View {
        layoutValue(key: MapFrameKey.self, value: rect)
    }
}
