import SwiftUI

struct ExhibitorListView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(TabRouter.self) private var router
    @State private var query = ""
    @State private var startupsOnly = false

    var body: some View {
        NavigationStack(path: Bindable(router).expoPath) {
            List {
                ForEach(filtered) { exhibitor in
                    NavigationLink(value: AppRoute.exhibitor(exhibitor.id)) {
                        ExhibitorRow(exhibitor: exhibitor)
                    }
                }
            }
            .navigationTitle("Expo")
            .searchable(text: $query, prompt: "Partners and startups")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EventSwitcher()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle("Startups", isOn: $startupsOnly)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityLabel("Show startups only")
                }
            }
            .navigationDestination(for: AppRoute.self) { Destinations.view(for: $0) }
            .onChange(of: catalog.selectedEventID) {
                query = ""
                startupsOnly = false
            }
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }

    private var filtered: [Exhibitor] {
        var items = catalog.searchExhibitors(query)
        if startupsOnly {
            items = items.filter(\.isStartup)
        }
        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

struct ExhibitorRow: View {
    var exhibitor: Exhibitor

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: exhibitor.logoURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    RoundedRectangle(cornerRadius: 8)
                        .fill(OxpTheme.accent.opacity(0.15))
                        .overlay {
                            Text(String(exhibitor.name.prefix(1)))
                                .font(.headline)
                                .foregroundStyle(OxpTheme.accent)
                        }
                }
            }
            .frame(width: 48, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(exhibitor.name).font(.headline)
                HStack(spacing: 6) {
                    Text(exhibitor.isStartup ? "Startup" : "Sponsor")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(exhibitor.isStartup ? .teal : OxpTheme.accent)
                    if let country = exhibitor.country {
                        Text(country).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let slogan = exhibitor.slogan {
                    Text(slogan).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
    }
}

struct ExhibitorDetailView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(TabRouter.self) private var router
    var exhibitorID: Int

    private var exhibitor: Exhibitor? { catalog.exhibitor(id: exhibitorID) }

    var body: some View {
        Group {
            if let exhibitor {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        AsyncImage(url: exhibitor.logoURL) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFit()
                            }
                        }
                        .frame(maxHeight: 120)
                        .frame(maxWidth: .infinity)
                        .padding(20)
                        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                        Text(exhibitor.name).font(.largeTitle.bold())
                        if let slogan = exhibitor.slogan {
                            Text(slogan).font(.title3).foregroundStyle(.secondary)
                        }
                        HStack {
                            TagChip(text: exhibitor.isStartup ? "Startup Village" : "Sponsors")
                            if let country = exhibitor.country {
                                TagChip(text: country)
                            }
                        }
                        if let hours = exhibitor.hours {
                            Label("Open \(hours)", systemImage: "clock")
                        }
                        if catalog.hasMap {
                            Button {
                                router.showOnMap(
                                    plan: VenueLayout.floorPlan(forExhibitor: exhibitor),
                                    exhibitorID: exhibitor.id
                                )
                            } label: {
                                Label("Show expo halls", systemImage: "map")
                            }
                            .buttonStyle(.glassProminent)
                            .tint(OxpTheme.accent)
                        }

                        if let website = exhibitor.website {
                            Link(destination: website) {
                                Label(website.host ?? "Website", systemImage: "globe")
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    .padding(20)
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Exhibitor")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("Exhibitor unavailable", systemImage: "building.2")
            }
        }
    }
}
