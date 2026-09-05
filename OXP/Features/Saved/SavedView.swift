import SwiftUI
import UserNotifications

struct SavedView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(FavoritesStore.self) private var favorites
    @Environment(TabRouter.self) private var router
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationStatus: UNAuthorizationStatus?

    var body: some View {
        NavigationStack(path: Bindable(router).savedPath) {
            Group {
                if saved.isEmpty {
                    ContentUnavailableView {
                        OxpIconTile(symbol: "heart", color: OxpTheme.accentInk)
                        Text("Make it your experience")
                    } description: {
                        Text("Build your own lineup by saving talks from the schedule.")
                    } actions: {
                        Button("Explore schedule", systemImage: "calendar") { router.tab = .schedule }
                            .buttonStyle(.borderedProminent)
                            .tint(OxpTheme.accent)
                            .controlSize(.large)
                    }
                } else {
                    List {
                        OxpPageIntro(title: "Your conference, your way",
                                     subtitle: "\(saved.count) saved \(saved.count == 1 ? "talk" : "talks") in your lineup",
                                     symbol: "heart")
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        Section("Reminders") {
                            reminderStatus
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
                            let conflicts = conflictingIDs(in: group.tracks)
                            Section(sectionTitle(for: group.event)) {
                                ForEach(group.tracks) { track in
                                    NavigationLink(value: AppRoute.track(track.id)) {
                                        VStack(alignment: .leading, spacing: 8) {
                                            TalkRow(track: track, isSaved: true, showsDay: true)
                                            if conflicts.contains(track.id) {
                                                Label("Overlaps another saved talk", systemImage: "clock.badge.exclamationmark")
                                                    .font(.caption.weight(.medium))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
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
            .scrollContentBackground(.hidden)
            .oxpBackground()
            .navigationTitle("Saved")
            .oxpPreviewStatus()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EventSwitcher()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Link("Privacy Policy", destination: AppLinks.privacy)
                }
            }
            .navigationDestination(for: AppRoute.self) { Destinations.view(for: $0) }
            .task { await refreshNotificationStatus() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await refreshNotificationStatus() }
                }
            }
        }
    }

    @ViewBuilder
    private var reminderStatus: some View {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            Label("Reminders enabled", systemImage: "bell.badge")
                .foregroundStyle(OxpTheme.accentInk)
        case .denied:
            VStack(alignment: .leading, spacing: 8) {
                Label("Reminders are off", systemImage: "bell.slash")
                    .font(.subheadline.weight(.semibold))
                Text("Your talks are saved. Allow notifications in Settings to receive reminders.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Open notification settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        case .notDetermined:
            Button("Enable reminders", systemImage: "bell.badge") {
                Task {
                    if await TalkReminders.requestAccess() {
                        await favorites.rescheduleAll(using: catalog)
                    }
                    await refreshNotificationStatus()
                }
            }
        default:
            EmptyView()
        }
    }

    private func refreshNotificationStatus() async {
        let previous = notificationStatus
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus
        // Rebuild reminders after returning from Settings with access restored.
        if previous == .denied, settings.authorizationStatus == .authorized {
            await favorites.rescheduleAll(using: catalog)
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

    private func conflictingIDs(in tracks: [Track]) -> Set<Int> {
        let days = Dictionary(grouping: tracks.filter { $0.day != nil }, by: { $0.day! })
        return days.values.reduce(into: Set<Int>()) { ids, day in
            ids.formUnion(AgendaDayLayout.conflictingIDs(in: day))
        }
    }

    private func sectionTitle(for event: EventInfo) -> String {
        catalog.availableEvents.count > 1 ? event.menuLabel : "Saved talks"
    }
}
