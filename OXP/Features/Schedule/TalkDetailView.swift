import SwiftUI

struct TalkDetailView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(FavoritesStore.self) private var favorites
    @Environment(TabRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var trackID: Int

    private var track: Track? { catalog.track(id: trackID) }

    var body: some View {
        Group {
            if let track {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(track)
                        speakerBlock(track)
                        if let description = track.descriptionText, !description.isEmpty {
                            Text(description)
                                .font(.body)
                                .foregroundStyle(.primary)
                        } else {
                            Text("The official page doesn’t have a description yet.")
                                .foregroundStyle(.secondary)
                        }
                        if !track.tags.isEmpty {
                            tagCloud(track)
                        }
                    }
                    .padding(20)
                }
                .oxpBackground()
                .navigationTitle(track.kind.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if let url = track.url {
                        ToolbarItem(placement: .topBarTrailing) {
                            ShareLink(item: url, subject: Text(track.name)) {
                                Label("Share talk", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    bottomBar(track)
                }
            } else {
                ContentUnavailableView("Talk unavailable", systemImage: "sparkles.rectangle.stack")
            }
        }
    }

    private func header(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(track.name)
                .font(.title.bold())
                .fixedSize(horizontal: false, vertical: true)
            Text(track.scheduleLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if catalog.hasMap, catalog.event(forTrackID: track.id)?.hasMap == true, let location = track.location {
                Button {
                    router.openRoom(location)
                } label: {
                    Label("Show on map", systemImage: "map")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    @ViewBuilder
    private func speakerBlock(_ track: Track) -> some View {
        if !track.speakers.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(track.speakers) { speaker in
                    HStack(alignment: .top, spacing: 12) {
                        SpeakerAvatar(speaker: speaker, size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(speaker.name).font(.headline)
                            if !speaker.affiliation.isEmpty {
                                Text(speaker.affiliation)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if let bio = speaker.biographyText {
                                Text(bio).font(.callout)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .oxpCard()
        } else if let line = track.speakerLine {
            Text(line).font(.headline)
        }
    }

    private func tagCloud(_ track: Track) -> some View {
        TalkTagStrip(track: track)
    }

    @ViewBuilder
    private func bottomBar(_ track: Track) -> some View {
        actionButtons(track)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.bar)
    }

    private func actionButtons(_ track: Track) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            SaveButton(isSaved: favorites.isSaved(track.id)) {
                Task { await favorites.toggle(track: track) }
            }
            if let url = track.url {
                Link(destination: url) {
                    Label("Official page", systemImage: "safari")
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
    }
}
