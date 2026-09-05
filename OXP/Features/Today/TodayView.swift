import SwiftUI

struct TodayView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(FavoritesStore.self) private var favorites
    @Environment(TabRouter.self) private var router
    @Environment(ConferenceClock.self) private var clock

    @State private var topicID: Int?
    @State private var showSettings = false

    var body: some View {
        NavigationStack(path: Bindable(router).todayPath) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    hero
                    topicFilters
                    if clock.isPreviewing || isDuringEvent {
                        happeningNow
                        upNext
                    }
                    yourLineup
                    featured
                }
                .padding(.bottom, 32)
            }
            .refreshable { await catalog.refresh(force: true) }
            .oxpBackground()
            .navigationTitle("Today")
            .oxpPreviewStatus()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EventSwitcher()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Preview", systemImage: "clock.arrow.circlepath") {
                        showSettings = true
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                PreviewSettingsSheet()
            }
            .navigationDestination(for: AppRoute.self) { Destinations.view(for: $0) }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onChange(of: catalog.selectedEventID) {
                topicID = nil
            }
        }
    }

    private var isDuringEvent: Bool {
        catalog.days.contains(clock.nowDay)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("YOUR CONFERENCE COMPANION", systemImage: "sparkles")
                .font(.caption2.weight(.semibold))
                .tracking(1.3)
                .foregroundStyle(.white.opacity(0.8))
            Text(catalog.event?.name ?? "Odoo Experience")
                .font(.title.bold())
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(heroSubtitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
            if let address = catalog.event?.venueAddress {
                Label(address, systemImage: "mappin.and.ellipse")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .oxpHero()
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var heroSubtitle: String {
        if isDuringEvent {
            return clock.now.formatted(
                Date.FormatStyle(date: .complete, time: .shortened, timeZone: catalog.timeZone)
            )
        }
        if let start = catalog.event?.startsOn, let days = daysUntil(start) {
            if days > 0 {
                return "Opens in \(days) day\(days == 1 ? "" : "s") · \(catalog.event?.venueName ?? "")"
            }
            if let end = catalog.event?.endsOn, clock.nowDay > end {
                return "Thanks for being part of \(catalog.event?.shortName ?? "the experience")."
            }
            return catalog.event?.venueName ?? "Your conference starts here."
        }
        return catalog.event?.venueName ?? "Odoo Experience"
    }

    private var topicFilters: some View {
        VStack(alignment: .leading, spacing: 10) {
            OxpSectionHeading(title: "Topics", symbol: "square.grid.2x2")
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.snappy) { topicID = nil }
                    } label: {
                        FilterChip(title: "All", selected: topicID == nil)
                    }
                    .buttonStyle(.plain)
                    ForEach(catalog.topicTags) { tag in
                        Button {
                            withAnimation(.snappy) { topicID = tag.id }
                        } label: {
                            FilterChip(title: tag.name, selected: topicID == tag.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    @ViewBuilder
    private var happeningNow: some View {
        let now = catalog.happening(at: clock.now, topicID: topicID)
        if !now.isEmpty {
            section("Happening now", tracks: now, showsDay: false)
        }
    }

    private var upNext: some View {
        section("Up next", tracks: catalog.upcoming(at: clock.now, limit: 8, topicID: topicID), showsDay: true)
    }

    @ViewBuilder
    private var yourLineup: some View {
        let saved = favorites.savedTracks(in: catalog).filter { track in
            topicID == nil || track.tagIDs.contains(topicID!)
        }
        VStack(alignment: .leading, spacing: 12) {
            OxpSectionHeading(title: "Your lineup", symbol: "heart")
                .padding(.horizontal, 20)
            if saved.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    OxpIconTile(symbol: "heart", color: OxpTheme.accentInk)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nothing saved yet")
                            .font(.headline)
                        Text("Save talks to build your lineup and choose a reminder.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Explore schedule", systemImage: "arrow.right") {
                            router.tab = .schedule
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .padding(.top, 6)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .oxpCard()
                .padding(.horizontal, 16)
            } else {
                ForEach(saved.prefix(8)) { track in
                    talkCard(track, showsDay: true)
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var featured: some View {
        section("Featured", tracks: Array(catalog.featured(at: clock.now, topicID: topicID).prefix(10)), showsDay: true)
    }

    private func section(_ title: String, tracks: [Track], showsDay: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            OxpSectionHeading(title: title, symbol: sectionSymbol(title))
                .padding(.horizontal, 20)
            if tracks.isEmpty {
                Text("Nothing in this topic right now.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            } else {
                ForEach(tracks) { track in
                    talkCard(track, showsDay: showsDay)
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func sectionSymbol(_ title: String) -> String {
        switch title {
        case "Happening now": "dot.radiowaves.left.and.right"
        case "Up next": "clock"
        default: "sparkles"
        }
    }

    private func talkCard(_ track: Track, showsDay: Bool) -> some View {
        NavigationLink(value: AppRoute.track(track.id)) {
            TalkRow(track: track, isSaved: favorites.isSaved(track.id), showsDay: showsDay)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .oxpCard()
                .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    private func daysUntil(_ ymd: String) -> Int? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = catalog.timeZone
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        guard let date = calendar.date(from: components) else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: clock.now), to: date).day
    }
}

struct PreviewSettingsSheet: View {
    @Environment(ConferenceClock.self) private var clock
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Live clock") {
                    Button("Use the real date") {
                        clock.clearPreview()
                        dismiss()
                    }
                }
                Section("Preview a conference moment") {
                    ForEach(catalog.days, id: \.self) { day in
                        Button("\(day) · 11:40") {
                            clock.preview(day, hour: 11, minute: 40)
                            dismiss()
                        }
                    }
                }
                Text("Preview changes live timing in Today, Schedule, and Map. Saved-talk reminders still use the real date.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Section("About") {
                    Link("Privacy Policy", destination: AppLinks.privacy)
                    Link("Support", destination: AppLinks.support)
                }
            }
            .navigationTitle("Preview")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
