import SwiftUI

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(FavoritesStore.self) private var favorites
    @Environment(CatalogStore.self) private var catalog
    @Environment(TabRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Today", systemImage: "sun.max.fill", value: AppTab.today) {
                TodayView()
            }
            Tab("Schedule", systemImage: "calendar", value: AppTab.schedule) {
                ScheduleView()
            }
            if catalog.hasMap {
                Tab("Map", systemImage: "map", value: AppTab.map) {
                    VenueMapView()
                }
            }
            Tab("Expo", systemImage: "building.2.fill", value: AppTab.expo) {
                ExhibitorListView()
            }
            Tab("Saved", systemImage: "heart.fill", value: AppTab.saved) {
                SavedView()
            }
        }
        .tint(OxpTheme.accentInk)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await catalog.refresh()
                try? await Task.sleep(for: .seconds(7200))
            }
        }
        .onChange(of: catalog.bundle?.generatedAt) {
            Task { await favorites.rescheduleAll(using: catalog, requestPermission: false) }
        }
        .overlay {
            if catalog.payload == nil, catalog.loadError == nil {
                ProgressView("Loading Odoo Experience…")
            } else if let loadError = catalog.loadError {
                ContentUnavailableView("Couldn’t load the agenda", systemImage: "wifi.slash", description: Text(loadError))
            }
        }
    }
}
