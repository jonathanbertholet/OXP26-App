import MapKit
import SwiftUI

struct VenueMapView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(TabRouter.self) private var router

    @State private var layer: MapLayer = .floor
    @State private var query = ""
    @State private var showLegend = false

    enum MapLayer: String, CaseIterable {
        case floor = "Floor"
        case campus = "Campus"
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.mapPath) {
            ZStack(alignment: .top) {
                if layer == .floor {
                    FloorPlanView(
                        plan: $router.selectedFloor,
                        query: query,
                        highlightedExhibitorID: router.highlightedExhibitorID,
                        selectedRoom: router.selectedRoom
                    )
                } else {
                    CampusMapView()
                }
            }
            .navigationTitle("Map")
            .searchable(text: $query, prompt: "Find a hall, room, or booth")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Map", selection: $layer) {
                        ForEach(MapLayer.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                if layer == .floor {
                    ToolbarItem(placement: .topBarLeading) {
                        roomMenu
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Booth key", systemImage: "paintpalette") {
                            showLegend.toggle()
                        }
                        .popover(isPresented: $showLegend, arrowEdge: .top) {
                            BoothLegend()
                                .padding()
                                .presentationCompactAdaptation(.popover)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if layer == .floor {
                    hallChips
                }
            }
            .navigationDestination(for: AppRoute.self) { Destinations.view(for: $0) }
            .onChange(of: router.selectedRoom) { _, name in
                if let name {
                    router.selectedFloor = VenueLayout.floorPlan(forLocation: name)
                }
            }
            .onChange(of: router.mapPath) { _, path in
                if path.isEmpty {
                    router.clearMapFocus()
                }
            }
        }
    }

    private var roomMenu: some View {
        Menu("Rooms", systemImage: "list.bullet.rectangle") {
            ForEach(catalog.locations, id: \.self) { name in
                Button(name) {
                    router.openRoom(name)
                }
            }
        }
        .accessibilityLabel("Talk rooms")
    }

    private var hallChips: some View {
        @Bindable var router = router
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FloorPlan.allCases) { item in
                    hallChip(item, selected: router.selectedFloor == item)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func hallChip(_ item: FloorPlan, selected: Bool) -> some View {
        Button {
            router.clearMapFocus()
            withAnimation(.smooth(duration: 0.42)) {
                router.selectedFloor = item
            }
        } label: {
            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? OxpTheme.accent : Color.clear, in: Capsule())
        }
        .buttonStyle(.glass)
        .animation(.snappy(duration: 0.2), value: selected)
    }
}

struct CampusMapView: View {
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(center: VenueLayout.campus, span: VenueLayout.campusSpan)
    )

    var body: some View {
        Map(position: $position) {
            Marker("Brussels Expo", coordinate: VenueLayout.campus)
                .tint(OxpTheme.accent)
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .bottom) {
            Link(destination: URL(string: "https://maps.apple.com/?ll=50.9008,4.3375&q=Brussels%20Expo")!) {
                Label("Directions to Brussels Expo", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .padding(16)
        }
    }
}

struct FloorPlanView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(TabRouter.self) private var router

    @Binding var plan: FloorPlan
    var query: String
    var highlightedExhibitorID: Int?
    var selectedRoom: String?

    @State private var isZoomed = false
    @State private var zoomGeneration = 0

    private var highlightedRef: String? {
        selectedRoom.map(VenueLayout.hotspotID(forLocation:))
    }

    private var highlightedExhibitor: Exhibitor? {
        highlightedExhibitorID.flatMap { catalog.exhibitor(id: $0) }
    }

    var body: some View {
        GeometryReader { geo in
            let mapSize = Self.contentSize(for: plan, in: geo.size)
            ZoomableScrollView(
                identity: "\(plan.rawValue)-\(zoomGeneration)",
                contentSize: mapSize,
                minimumZoomScale: 1,
                focusRect: focusRect(in: mapSize),
                isZoomed: $isZoomed
            ) {
                FloorMapCanvas(
                    plan: plan,
                    canvasSize: mapSize,
                    query: query,
                    highlightedRef: highlightedRef,
                    highlightedExhibitor: highlightedExhibitor,
                    onActivate: activate
                )
            }
        }
        .background(FloorPalette.canvas)
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if let exhibitor = highlightedExhibitor {
                    exhibitorBanner(exhibitor)
                }
                if isZoomed {
                    Button("Reset zoom", systemImage: "arrow.counterclockwise") {
                        router.clearMapFocus()
                        zoomGeneration += 1
                        isZoomed = false
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(12)
        }
    }

    /// Fit the whole simplified plan in the view; pinch in from there.
    static func contentSize(for plan: FloorPlan, in view: CGSize) -> CGSize {
        let view = CGSize(width: max(view.width, 1), height: max(view.height, 1))
        if plan == .overview {
            return view
        }
        let aspect = plan.aspect
        if view.width / view.height > aspect {
            return CGSize(width: view.height * aspect, height: view.height)
        }
        return CGSize(width: view.width, height: view.width / aspect)
    }

    private func exhibitorBanner(_ exhibitor: Exhibitor) -> some View {
        let hint = exhibitor.isStartup
            ? "Startups sit around the Hall 7 bar. Stall numbers aren’t on the public list yet."
            : "Partner booths are in Halls 6 and 7. Stall numbers aren’t on the public list yet."
        return Text("\(exhibitor.name) — \(hint)")
            .font(.footnote)
            .multilineTextAlignment(.center)
            .padding(12)
            .oxpGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 12)
    }

    private func focusRect(in size: CGSize) -> CGRect? {
        guard let ref = highlightedRef,
              let norm = VenueLayout.normalizedFrame(ref: ref, on: plan),
              norm.width * norm.height < 0.14
        else { return nil }
        return CGRect(
            x: norm.minX * size.width,
            y: norm.minY * size.height,
            width: max(norm.width * size.width, 48),
            height: max(norm.height * size.height, 48)
        )
    }

    private func activate(kind: FloorHotspotKind, ref: String) {
        switch kind {
        case .hall(let next):
            router.clearMapFocus()
            if next != plan {
                withAnimation(.smooth(duration: 0.42)) {
                    plan = next
                }
            }
        case .room:
            router.selectedRoom = ref
            router.push(.room(ref), on: .map)
        case .amenity:
            router.push(.amenity(ref), on: .map)
        case .boothRow:
            router.push(.boothRow(ref), on: .map)
        }
    }
}

private struct BoothLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            legendRow(StallKind.plugStandard)
            legendRow(StallKind.plugDouble)
            legendRow(StallKind.plugPremium)
            legendRow(StallKind.bare12)
            legendRow(StallKind.bare24)
            legendRow(StallKind.bare48)
        }
        .font(.caption2.weight(.semibold))
        .padding(10)
        .oxpGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: 220, alignment: .trailing)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func legendRow(_ kind: StallKind) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(FloorPalette.stallFill(kind))
                .frame(width: 16, height: 12)
            Text(kind.title)
                .foregroundStyle(.primary)
        }
    }
}
