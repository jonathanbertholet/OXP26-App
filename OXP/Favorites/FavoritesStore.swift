import Foundation
import SwiftData
import UserNotifications

@MainActor
@Observable
final class FavoritesStore {
    private var context: ModelContext?
    private(set) var savedIDs: Set<Int> = []
    var remindMinutesBefore: Int = 15 {
        didSet { UserDefaults.standard.set(remindMinutesBefore, forKey: "oxp.remindMinutes") }
    }

    init() {
        let stored = UserDefaults.standard.object(forKey: "oxp.remindMinutes") as? Int
        remindMinutesBefore = stored ?? 15
    }

    func attach(context: ModelContext) {
        self.context = context
        refresh()
    }

    func isSaved(_ trackID: Int) -> Bool {
        savedIDs.contains(trackID)
    }

    func toggle(track: Track) async {
        if isSaved(track.id) {
            await unsave(trackID: track.id)
        } else {
            await save(track: track)
        }
    }

    func save(track: Track) async {
        guard let context, !isSaved(track.id) else { return }
        context.insert(
            SavedTalk(trackID: track.id, remindMinutesBefore: remindMinutesBefore)
        )
        try? context.save()
        refresh()
        await TalkReminders.schedule(track: track, minutesBefore: remindMinutesBefore)
    }

    func unsave(trackID: Int) async {
        guard let context else { return }
        let target = trackID
        let found = try? context.fetch(
            FetchDescriptor<SavedTalk>(predicate: #Predicate { $0.trackID == target })
        )
        found?.forEach { context.delete($0) }
        try? context.save()
        refresh()
        TalkReminders.cancel(trackID: trackID)
    }

    func savedTracks(in catalog: CatalogStore) -> [Track] {
        (catalog.payload?.tracks ?? [])
            .filter { savedIDs.contains($0.id) }
            .sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
    }

    func allSavedTracks(in catalog: CatalogStore) -> [Track] {
        savedIDs.compactMap { catalog.allTracksByID[$0] }
            .sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
    }

    func rescheduleAll(using catalog: CatalogStore, requestPermission: Bool = true) async {
        if requestPermission { _ = await TalkReminders.requestAccess() }
        let tracks = allSavedTracks(in: catalog).filter {
            !$0.isUnavailable && ($0.startsAt?.addingTimeInterval(TimeInterval(-remindMinutesBefore * 60)) ?? .distantPast) > .now
        }.prefix(64)
        let wanted = Set(tracks.map { TalkReminders.identifier(for: $0.id) })
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("oxp.talk.") && !wanted.contains($0) })
        for track in tracks {
            await TalkReminders.schedule(track: track, minutesBefore: remindMinutesBefore, requestPermission: false)
        }
    }

    private func refresh() {
        guard let context else { return }
        let items = (try? context.fetch(FetchDescriptor<SavedTalk>())) ?? []
        savedIDs = Set(items.map(\.trackID))
    }
}
