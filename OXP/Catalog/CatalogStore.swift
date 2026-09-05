import Foundation

@MainActor
@Observable
final class CatalogStore {
    private let feed = CatalogFeedClient()
    private(set) var isRefreshing = false
    private(set) var lastCheckedAt: Date?
    private(set) var refreshError: String?
    private var lastAttempt: Date? = UserDefaults.standard.object(forKey: "oxp.agendaLastAttempt") as? Date
    private(set) var bundle: CatalogBundle?
    private(set) var payload: CatalogPayload?
    private(set) var loadError: String?
    private(set) var tracksByID: [Int: Track] = [:]
    private(set) var exhibitorsByID: [Int: Exhibitor] = [:]
    private(set) var topicTags: [Tag] = []
    private(set) var audienceTags: [Tag] = []
    private(set) var days: [String] = []
    /// All saved-talk lookups across editions (Odoo ids are global).
    private(set) var allTracksByID: [Int: Track] = [:]

    var selectedEventID: Int = 9099
    private let selectedEventKey = "oxp.selectedEventID"

    var event: EventInfo? { payload?.event }
    var tracks: [Track] { (payload?.tracks ?? []).filter { !$0.isUnavailable } }
    var exhibitors: [Exhibitor] { payload?.exhibitors ?? [] }
    var locations: [String] { payload?.locations ?? [] }
    var availableEvents: [EventInfo] {
        let defaultID = bundle?.defaultEventID ?? 9099
        return (bundle?.events.map(\.event) ?? []).sorted {
            if $0.id == defaultID { return true }
            if $1.id == defaultID { return false }
            return ($0.startsOn ?? "", $0.shortName) < ($1.startsOn ?? "", $1.shortName)
        }
    }
    var hasMap: Bool { event?.hasMap == true }
    var timeZone: TimeZone { event?.timeZone ?? TimeZone(identifier: "Europe/Brussels") ?? .gmt }

    func load() async {
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try CatalogDecoder.loadBundled()
            }.value
            apply(bundle: loaded)
            if let cached = await feed.restore(comparedTo: loaded) {
                apply(bundle: cached.bundle)
                lastCheckedAt = cached.checkedAt
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    static func automaticRefreshIsDue(at now: Date, lastAttempt: Date?) -> Bool {
        // Published 2026 program dates, including masterclasses, in UTC.
        let windows = [
            ("2026-09-08T18:30:00Z", "2026-09-12T18:30:00Z"),
            ("2026-09-21T22:00:00Z", "2026-09-26T22:00:00Z")
        ]
        let formatter = ISO8601DateFormatter()
        let active = windows.contains { start, end in
            guard let start = formatter.date(from: start), let end = formatter.date(from: end) else { return false }
            return now >= start && now < end
        }
        return active && (lastAttempt.map { now.timeIntervalSince($0) >= 7200 } ?? true)
    }

    func refresh(force: Bool = false) async {
        guard let baseline = bundle, !isRefreshing else { return }
        if !force {
            guard Self.automaticRefreshIsDue(at: .now, lastAttempt: lastAttempt ?? lastCheckedAt) else { return }
        }
        isRefreshing = true
        lastAttempt = .now
        UserDefaults.standard.set(lastAttempt, forKey: "oxp.agendaLastAttempt")
        defer { isRefreshing = false }
        do {
            let result = try await feed.refresh(comparedTo: baseline)
            apply(bundle: result.bundle)
            lastCheckedAt = result.checkedAt
            refreshError = nil
        } catch is CancellationError {
            // Leaving the foreground keeps the current agenda.
        } catch {
            refreshError = "Couldn’t check for updates. Your offline agenda is still available."
        }
    }

    func apply(bundle: CatalogBundle, persist: Bool = true) {
        guard !bundle.events.isEmpty else { return }
        let currentSelection = self.bundle == nil ? nil : selectedEventID
        self.bundle = bundle
        allTracksByID = Dictionary(
            bundle.events.flatMap(\.tracks).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let stored = UserDefaults.standard.object(forKey: selectedEventKey) as? Int
        let preferred = currentSelection ?? stored
        let initial = preferred.flatMap { id in bundle.events.contains { $0.event.id == id } ? id : nil }
            ?? bundle.defaultEventID
            ?? 9099
        selectEvent(initial, persist: persist)
    }

    /// Used by tests to pin a single-event catalog.
    func apply(_ payload: CatalogPayload) {
        apply(bundle: CatalogBundle(defaultEventID: payload.event.id, events: [payload]), persist: false)
    }

    func selectEvent(_ id: Int, persist: Bool = true) {
        guard let bundle else { return }
        let chosen = bundle.events.first { $0.event.id == id } ?? bundle.belgium ?? bundle.events[0]
        selectedEventID = chosen.event.id
        if persist {
            UserDefaults.standard.set(selectedEventID, forKey: selectedEventKey)
        }
        applyPayload(chosen)
    }

    private func applyPayload(_ payload: CatalogPayload) {
        self.payload = payload
        tracksByID = Dictionary(payload.tracks.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        exhibitorsByID = Dictionary(payload.exhibitors.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        days = Array(Set(tracks.compactMap(\.day))).sorted()
        let uniqueTopics = Dictionary(grouping: payload.tracks.flatMap(\.topicTags), by: \.id)
        topicTags = uniqueTopics.values.compactMap(\.first).sorted { $0.name < $1.name }
        let uniqueAudience = Dictionary(grouping: payload.tracks.flatMap(\.audienceTags), by: \.id)
        audienceTags = uniqueAudience.values.compactMap(\.first).sorted { $0.name < $1.name }
    }

    func track(id: Int) -> Track? { tracksByID[id] ?? allTracksByID[id] }
    func exhibitor(id: Int) -> Exhibitor? { exhibitorsByID[id] }

    func tracks(on day: String) -> [Track] {
        tracks.filter { $0.day == day }
            .sorted {
                ($0.startTime ?? "", $0.location ?? "", $0.name)
                    < ($1.startTime ?? "", $1.location ?? "", $1.name)
            }
    }

    func happening(at date: Date, topicID: Int? = nil) -> [Track] {
        filtered(topicID: topicID, tracks.filter { $0.isHappening(at: date) })
            .sorted { ($0.location ?? "") < ($1.location ?? "") }
    }

    func upcoming(at date: Date, limit: Int = 12, topicID: Int? = nil) -> [Track] {
        Array(
            filtered(topicID: topicID, tracks.filter { $0.isUpcoming(at: date) })
                .sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
                .prefix(limit)
        )
    }

    func featured(at date: Date, topicID: Int? = nil) -> [Track] {
        let pool = filtered(topicID: topicID, tracks)
        let keynotes = pool.filter { $0.kind == .keynote }
        let invited = pool.filter { $0.tags.contains { $0.name == "Invited Speaker" } }
        let rest = pool.filter { $0.kind == .talk || $0.kind == .session }
        var seen = Set<Int>()
        return (keynotes + invited + rest).filter { seen.insert($0.id).inserted }
    }

    func searchTracks(_ query: String) -> [Track] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return tracks }
        return tracks.filter { track in
            if track.name.lowercased().contains(needle) { return true }
            if track.speakerLine?.lowercased().contains(needle) == true { return true }
            if track.location?.lowercased().contains(needle) == true { return true }
            if track.descriptionText?.lowercased().contains(needle) == true { return true }
            return track.tags.contains { $0.name.lowercased().contains(needle) }
        }
    }

    func searchExhibitors(_ query: String) -> [Exhibitor] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return exhibitors }
        return exhibitors.filter {
            $0.name.lowercased().contains(needle)
                || ($0.slogan?.lowercased().contains(needle) == true)
                || ($0.country?.lowercased().contains(needle) == true)
        }
    }

    func tracks(in location: String, on day: String?) -> [Track] {
        tracks(inLocations: VenueLayout.catalogLocations(for: location), on: day)
    }

    func tracks(inLocations locations: [String], on day: String?) -> [Track] {
        let names = Set(locations)
        return tracks.filter { track in
            guard let location = track.location, names.contains(location) else { return false }
            return day == nil || track.day == day
        }
        .sorted {
            ($0.startTime ?? "", $0.location ?? "", $0.name)
                < ($1.startTime ?? "", $1.location ?? "", $1.name)
        }
    }

    func nowAndNext(in location: String, at date: Date) -> (now: Track?, next: Track?) {
        nowAndNext(inLocations: VenueLayout.catalogLocations(for: location), at: date)
    }

    func nowAndNext(inLocations locations: [String], at date: Date) -> (now: Track?, next: Track?) {
        let names = Set(locations)
        let here = tracks.filter { $0.location.map(names.contains) ?? false }
        let now = here.first { $0.isHappening(at: date) }
        let next = here
            .filter { $0.isUpcoming(at: date) }
            .sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
            .first
        return (now, next)
    }

    func event(forTrackID id: Int) -> EventInfo? {
        bundle?.events.first { payload in payload.tracks.contains { $0.id == id } }?.event
    }

    private func filtered(topicID: Int?, _ tracks: [Track]) -> [Track] {
        guard let topicID else { return tracks }
        return tracks.filter { $0.tagIDs.contains(topicID) }
    }
}
