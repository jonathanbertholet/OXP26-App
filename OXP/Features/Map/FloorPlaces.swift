import SwiftUI

struct RoomDetailView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(FavoritesStore.self) private var favorites
    @Environment(ConferenceClock.self) private var clock

    var roomName: String

    private var locations: [String] {
        VenueLayout.catalogLocations(for: roomName)
    }

    var body: some View {
        let live = catalog.nowAndNext(in: roomName, at: clock.now)
        let day = clock.now.oxpDay
        let talks = catalog.tracks(in: roomName, on: catalog.days.contains(day) ? day : nil)
        List {
            if roomName == "Auditorium 500" {
                Section {
                    Text("This room is in the agenda but isn’t labeled on the published floorplan. Hall 10 is the closest match on the map.")
                        .foregroundStyle(.secondary)
                }
            }
            if locations.count > 1 {
                Section("Stages") {
                    ForEach(locations, id: \.self) { name in
                        Text(name)
                    }
                }
            }
            Section {
                if let now = live.now {
                    NavigationLink(value: AppRoute.track(now.id)) {
                        TalkRow(track: now, isSaved: favorites.isSaved(now.id))
                    }
                } else {
                    Text("Nothing on stage here right now.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Now")
            }
            if let next = live.next {
                Section("Next") {
                    NavigationLink(value: AppRoute.track(next.id)) {
                        TalkRow(track: next, isSaved: favorites.isSaved(next.id), showsDay: true)
                    }
                }
            }
            Section("In this room") {
                ForEach(talks) { track in
                    NavigationLink(value: AppRoute.track(track.id)) {
                        TalkRow(track: track, isSaved: favorites.isSaved(track.id), showsDay: true)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .oxpBackground()
        .navigationTitle(roomName)
        .navigationDestination(for: AppRoute.self) { Destinations.view(for: $0) }
    }
}

struct AmenityDetailView: View {
    @Environment(TabRouter.self) private var router

    var amenityID: String

    var body: some View {
        let amenity = VenueLayout.amenity(amenityID)
        List {
            if let amenity {
                Section {
                    Label(amenity.detail, systemImage: amenity.symbol)
                }
                if amenityID == "startup-area" {
                    Section {
                        Button("Browse startups") {
                            router.tab = .expo
                        }
                    }
                }
            } else {
                Text("This place isn’t in the directory.")
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .oxpBackground()
        .navigationTitle(amenity?.title ?? "Place")
    }
}

struct BoothRowDetailView: View {
    var letter: String

    var body: some View {
        let row = VenueLayout.boothRow(letter)
        List {
            if let row {
                Section {
                    LabeledContent("Hall", value: row.hall.title)
                    LabeledContent("Type", value: row.kindLabel)
                    LabeledContent("Stalls", value: "\(row.letter)1–\(row.letter)\(row.stallCount)")
                }
                Section {
                    Text("Exhibitor names for each stall aren’t on the public list yet. The numbered boxes on the floorplan are the official layout.")
                        .foregroundStyle(.secondary)
                }
                Section("Stalls") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 8)], spacing: 8) {
                        ForEach(1...row.stallCount, id: \.self) { number in
                            Text("\(row.letter)\(number)")
                                .font(.caption.weight(.semibold).monospaced())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }
            } else {
                Text("Unknown booth row.")
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .oxpBackground()
        .navigationTitle(row.map { "Booths \($0.letter)" } ?? "Booths")
    }
}

struct BoothStallDetailView: View {
    var code: String

    var body: some View {
        let stall = VenueLayout.stall(code: code)
        let row = stall.flatMap { VenueLayout.boothRow($0.letter) }
        List {
            if let stall, let row {
                Section {
                    LabeledContent("Stall", value: stall.code)
                    LabeledContent("Hall", value: row.hall.title)
                    LabeledContent("Type", value: stall.kind.title)
                    LabeledContent("Row", value: "\(row.letter)1–\(row.letter)\(row.stallCount)")
                }
                Section {
                    Text("Exhibitor names for each stall aren’t on the public list yet.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    NavigationLink(value: AppRoute.boothRow(stall.letter)) {
                        Label("All booths in row \(stall.letter)", systemImage: "square.grid.3x3")
                    }
                }
            } else {
                Text("Unknown booth.")
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .oxpBackground()
        .navigationTitle(code)
        .navigationDestination(for: AppRoute.self) { Destinations.view(for: $0) }
    }
}
