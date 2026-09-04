import SwiftUI

enum ScheduleLayout: String, CaseIterable, Identifiable {
    case list
    case agenda

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: "List"
        case .agenda: "Agenda"
        }
    }
}

struct ScheduleView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(FavoritesStore.self) private var favorites
    @Environment(TabRouter.self) private var router
    @Environment(ConferenceClock.self) private var clock

    @AppStorage("oxp.scheduleLayout") private var layoutMode: ScheduleLayout = .list
    @State private var selectedDay: String = ""
    @State private var query = ""
    @State private var kindFilter: TalkKind?
    @State private var tagID: Int?
    @State private var emphasizeSaved = false
    @State private var jumpToNow = 0

    var body: some View {
        NavigationStack(path: Bindable(router).schedulePath) {
            VStack(spacing: 0) {
                dayStrip
                if layoutMode == .list {
                    filterStrip
                }
                if layoutMode == .agenda {
                    AgendaGridView(
                        tracks: filtered,
                        now: clock.now,
                        timeZone: clock.timeZone,
                        day: selectedDay,
                        query: query,
                        savedIDs: favorites.savedIDs,
                        emphasizeSaved: $emphasizeSaved,
                        jumpToNow: jumpToNow
                    )
                    .id(selectedDay)
                } else {
                    scheduleList
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EventSwitcher()
                }
            }
            .navigationDestination(for: AppRoute.self) { Destinations.view(for: $0) }
            .searchable(text: $query, prompt: "Talks, speakers, rooms")
            .searchToolbarBehavior(.minimize)
            .safeAreaPadding(.bottom, 58)
            .overlay(alignment: .bottom) {
                ScheduleModeBar(
                    layoutMode: $layoutMode,
                    emphasizeSaved: $emphasizeSaved,
                    savedCount: favorites.savedIDs.count,
                    showNow: layoutMode == .agenda && clock.nowDay == selectedDay
                ) {
                    jumpToNow += 1
                }
            }
            .onAppear {
                if selectedDay.isEmpty {
                    if let override = ProcessInfo.processInfo.arguments
                        .first(where: { $0.hasPrefix("-agendaDay=") })?
                        .dropFirst("-agendaDay=".count) {
                        selectedDay = String(override)
                    } else {
                        selectedDay = suggestedDay
                    }
                }
            }
            .onChange(of: catalog.selectedEventID) {
                selectedDay = suggestedDay
                kindFilter = nil
                tagID = nil
            }
        }
    }

    private var scheduleList: some View {
        List {
            ForEach(groupedSlots, id: \.time) { slot in
                Section(slot.time) {
                    ForEach(slot.tracks) { track in
                        NavigationLink(value: AppRoute.track(track.id)) {
                            TalkRow(track: track, isSaved: favorites.isSaved(track.id))
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if groupedSlots.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private var suggestedDay: String {
        let today = clock.nowDay
        if catalog.days.contains(today) {
            return today
        }
        return catalog.days.first ?? ""
    }

    private var dayStrip: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(catalog.days, id: \.self) { day in
                        let selected = day == selectedDay
                        Button {
                            withAnimation(.snappy) { selectedDay = day }
                        } label: {
                            VStack(spacing: 2) {
                                Text(weekday(day))
                                    .font(.caption.weight(.semibold))
                                Text(Self.shortDay(day))
                                    .font(.headline)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .foregroundStyle(selected ? Color.white : .primary)
                            .background(selected ? OxpTheme.accent : Color.secondary.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(weekday(day)) \(day)")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            ScheduleTagFilter(tagID: $tagID)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(nil, title: "All")
                ForEach([TalkKind.keynote, .masterclass, .talk, .session, .social, TalkKind.break], id: \.self) { kind in
                    filterChip(kind, title: kind.title)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func filterChip(_ kind: TalkKind?, title: String) -> some View {
        let selected = kindFilter == kind
        return Button {
            withAnimation(.snappy) { kindFilter = kind }
        } label: {
            TagChip(text: title, selected: selected)
        }
        .buttonStyle(.plain)
    }

    private var filtered: [Track] {
        var items = catalog.tracks(on: selectedDay)
        if let kindFilter {
            items = items.filter { $0.kind == kindFilter }
        }
        if let tagID {
            items = items.filter { $0.tagIDs.contains(tagID) || $0.isVenueWide }
        }
        if !query.isEmpty {
            let needle = query.lowercased()
            items = items.filter {
                $0.name.lowercased().contains(needle)
                    || ($0.speakerLine?.lowercased().contains(needle) == true)
                    || ($0.location?.lowercased().contains(needle) == true)
            }
        }
        return items
    }

    private var groupedSlots: [(time: String, tracks: [Track])] {
        let groups = Dictionary(grouping: filtered) { $0.startTime ?? "TBA" }
        return groups.keys.sorted().map { ($0, groups[$0]!.sorted { ($0.location ?? "") < ($1.location ?? "") }) }
    }

    private func weekday(_ day: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = catalog.timeZone
        guard let date = formatter.date(from: day) else { return day }
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }

    private static func shortDay(_ day: String) -> String {
        String(day.suffix(2))
    }
}

/// Compact tag picker parked beside the day chips.
private struct ScheduleTagFilter: View {
    @Environment(CatalogStore.self) private var catalog
    @Binding var tagID: Int?

    var body: some View {
        Menu {
            Picker("Tag", selection: $tagID) {
                Text("All topics").tag(Optional<Int>.none)
                Section("Topics") {
                    ForEach(catalog.topicTags) { tag in
                        Text(tag.name).tag(Optional(tag.id))
                    }
                }
                Section("Audience") {
                    ForEach(catalog.audienceTags) { tag in
                        Text(tag.name).tag(Optional(tag.id))
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease")
                Text(label)
                    .lineLimit(1)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .foregroundStyle(tagID == nil ? Color.primary : Color.white)
            .background(tagID == nil ? Color.secondary.opacity(0.12) : OxpTheme.accent, in: Capsule())
            .frame(maxWidth: 132)
        }
        .menuOrder(.fixed)
        .accessibilityLabel(tagID == nil ? "Filter by topic" : "Filtered by \(label)")
    }

    private var label: String {
        if let tagID, let tag = (catalog.topicTags + catalog.audienceTags).first(where: { $0.id == tagID }) {
            return tag.name
        }
        return "Topics"
    }
}

/// Floating List / Agenda control. Sits on the canvas so the day chips stay the only chrome.
private struct ScheduleModeBar: View {
    @Binding var layoutMode: ScheduleLayout
    @Binding var emphasizeSaved: Bool
    var savedCount: Int
    var showNow: Bool
    var onJumpToNow: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 0) {
                    ForEach(ScheduleLayout.allCases) { mode in
                        Button(mode.title) {
                            withAnimation(.snappy) { layoutMode = mode }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .foregroundStyle(layoutMode == mode ? Color.white : .primary)
                        .background(layoutMode == mode ? OxpTheme.accent : Color.clear, in: Capsule())
                    }
                }
                .padding(4)
                .glassEffect(.regular.interactive(), in: Capsule())
                .accessibilityElement(children: .contain)
                .accessibilityHint("Agenda is a room-by-time grid. List groups talks that start together.")

                if savedCount > 0, layoutMode == .agenda {
                    Button {
                        withAnimation(.snappy) { emphasizeSaved.toggle() }
                    } label: {
                        Image(systemName: emphasizeSaved ? "heart.fill" : "heart")
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.glass)
                    .tint(emphasizeSaved ? .pink : OxpTheme.accent)
                    .accessibilityLabel(emphasizeSaved ? "Show every talk" : "Highlight saved talks")
                }

                if showNow {
                    Button("Now", systemImage: "circle.inset.filled", action: onJumpToNow)
                        .labelStyle(.iconOnly)
                        .frame(width: 36, height: 36)
                        .buttonStyle(.glass)
                        .tint(.red)
                        .accessibilityLabel("Jump to the current time")
                }
            }
        }
        .padding(.bottom, 6)
    }
}
