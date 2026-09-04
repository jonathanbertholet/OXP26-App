import SwiftUI

struct SavedView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(FavoritesStore.self) private var favorites
    @Environment(TabRouter.self) private var router

    var body: some View {
        NavigationStack(path: Bindable(router).savedPath) {
            Group {
                if saved.isEmpty {
                    ContentUnavailableView {
                        Label("Your lineup is empty", systemImage: "heart")
                    } description: {
                        Text("Save talks from Today or the schedule. OXP will notify you before they start.")
                    }
                } else {
                    List {
                        Section("Reminders") {
                            Stepper(
                                "Notify \(favorites.remindMinutesBefore) min before",
                                value: Bindable(favorites).remindMinutesBefore,
                                in: 5 ... 60,
                                step: 5
                            )
                            .onChange(of: favorites.remindMinutesBefore) {
                                Task { await favorites.rescheduleAll(using: catalog) }
                            }
                        }
                        ForEach(groupedSaved, id: \.event.id) { group in
                            Section(sectionTitle(for: group.event)) {
                                ForEach(group.tracks) { track in
                                    NavigationLink(value: AppRoute.track(track.id)) {
                                        TalkRow(
                                            track: track,
                                            isSaved: true,
                                            showsDay: true
                                        )
                                    }
                                    .swipeActions {
                                        Button("Remove", role: .destructive) {
                                            Task { await favorites.unsave(trackID: track.id) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Saved")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EventSwitcher()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Link("Privacy Policy", destination: AppLinks.privacy)
                }
            }
            .navigationDestination(for: AppRoute.self) { Destinations.view(for: $0) }
        }
    }

    private var saved: [Track] {
        favorites.allSavedTracks(in: catalog)
    }

    private var groupedSaved: [(event: EventInfo, tracks: [Track])] {
        catalog.availableEvents.compactMap { event in
            let items = saved.filter { catalog.event(forTrackID: $0.id)?.id == event.id }
            return items.isEmpty ? nil : (event, items)
        }
    }

    private func sectionTitle(for event: EventInfo) -> String {
        catalog.availableEvents.count > 1 ? event.menuLabel : "Saved talks"
    }
}
