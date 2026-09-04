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
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
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
        VStack(alignment: .leading, spacing: 8) {
            Text(catalog.event?.name ?? "Odoo Experience")
                .font(.largeTitle.bold())
            Text(heroSubtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
            if let address = catalog.event?.venueAddress {
                Label(address, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .oxpGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var heroSubtitle: String {
        if isDuringEvent {
            return clock.now.formatted(date: .complete, time: .shortened)
        }
        if let start = catalog.event?.startsOn, let days = daysUntil(start) {
            if days > 0 {
                return "Opens in \(days) day\(days == 1 ? "" : "s") · \(catalog.event?.venueName ?? "")"
            }
            return "It’s conference week."
        }
        return catalog.event?.venueName ?? "Odoo Experience"
    }

    private var topicFilters: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Topics")
                .font(.title2.bold())
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.snappy) { topicID = nil }
                    } label: {
                        TagChip(text: "All", selected: topicID == nil)
                    }
                    .buttonStyle(.plain)
                    ForEach(catalog.topicTags) { tag in
                        Button {
                            withAnimation(.snappy) { topicID = tag.id }
                        } label: {
                            TagChip(text: tag.name, selected: topicID == tag.id)
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
            Text("Your lineup")
                .font(.title2.bold())
                .padding(.horizontal, 20)
            if saved.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "heart")
                        .font(.title2)
                        .foregroundStyle(.pink)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nothing saved yet")
                            .font(.headline)
                        Text("Heart a talk and OXP will remind you 15 minutes before it starts.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
            Text(title)
                .font(.title2.bold())
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

    private func talkCard(_ track: Track, showsDay: Bool) -> some View {
        NavigationLink(value: AppRoute.track(track.id)) {
            TalkRow(track: track, isSaved: favorites.isSaved(track.id), showsDay: showsDay)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                Text("Preview only changes what Today shows. Saved-talk notifications still fire at the real start time.")
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
