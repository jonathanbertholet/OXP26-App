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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
            .refreshable { await catalog.refresh(force: true) }
            .oxpBackground()
            .navigationTitle("Schedule")
            .oxpPreviewStatus()
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
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
            .onChange(of: catalog.days) { _, days in
                if !days.contains(selectedDay) {
                    selectedDay = suggestedDay
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
        .scrollContentBackground(.hidden)
        .overlay {
            if groupedSlots.isEmpty {
                ContentUnavailableView {
                    Label("No matching talks", systemImage: "calendar.badge.exclamationmark")
                } description: {
                    Text("Try another day or clear your search and filters.")
                } actions: {
                    Button("Clear filters") {
                        query = ""
                        kindFilter = nil
                        tagID = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OxpTheme.accent)
                    .controlSize(.large)
                }
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
            if dynamicTypeSize.isAccessibilitySize {
                Menu {
                    Picker("Conference day", selection: $selectedDay) {
                        ForEach(catalog.days, id: \.self) { day in
                            Text("\(weekday(day)) \(day)").tag(day)
                        }
                    }
                } label: {
                    Label(selectedDay.isEmpty ? "Day" : "\(weekday(selectedDay)) \(Self.shortDay(selectedDay))",
                          systemImage: "calendar")
                        .font(.headline)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                Spacer(minLength: 0)
            } else {
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
            FilterChip(title: title, selected: selected)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(label).lineLimit(1)
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                modePicker
                actions
            }
            VStack(spacing: 8) {
                modePicker
                actions
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var modePicker: some View {
        Picker("Schedule layout", selection: $layoutMode) {
            ForEach(ScheduleLayout.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(minWidth: 180, maxWidth: 320)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if savedCount > 0, layoutMode == .agenda {
                Button {
                    withAnimation(.snappy) { emphasizeSaved.toggle() }
                } label: {
                    Image(systemName: emphasizeSaved ? "heart.fill" : "heart")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .tint(emphasizeSaved ? .pink : OxpTheme.accent)
                .accessibilityLabel(emphasizeSaved ? "Show every talk" : "Highlight saved talks")
                .accessibilityAddTraits(emphasizeSaved ? .isSelected : [])
            }
            if showNow {
                Button(action: onJumpToNow) {
                    Image(systemName: "clock")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Jump to the current time")
            }
        }
    }
}
