import SwiftUI

struct TalkDetailView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(FavoritesStore.self) private var favorites
    @Environment(TabRouter.self) private var router

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
                .background(Color(.systemGroupedBackground))
                .navigationTitle(track.kind.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        SaveButton(isSaved: favorites.isSaved(track.id)) {
                            Task { await favorites.toggle(track: track) }
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
                .buttonStyle(.glass)
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
            .oxpGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else if let line = track.speakerLine {
            Text(line).font(.headline)
        }
    }

    private func tagCloud(_ track: Track) -> some View {
        FlowTags(tags: track.tags)
    }

    @ViewBuilder
    private func bottomBar(_ track: Track) -> some View {
        HStack(spacing: 12) {
            SaveButton(isSaved: favorites.isSaved(track.id)) {
                Task { await favorites.toggle(track: track) }
            }
            if let url = track.url {
                Link(destination: url) {
                    Label("Official page", systemImage: "safari")
                }
                .buttonStyle(.glass)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

private struct FlowTags: View {
    var tags: [Tag]

    var body: some View {
        FlexibleTags(tags: tags)
    }
}

private struct FlexibleTags: View {
    var tags: [Tag]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row) { tag in
                        TagChip(text: tag.name)
                    }
                }
            }
        }
    }

    private var rows: [[Tag]] {
        var result: [[Tag]] = [[]]
        var width = 0
        for tag in tags {
            let estimate = tag.name.count
            if width + estimate > 28, !result[result.count - 1].isEmpty {
                result.append([tag])
                width = estimate
            } else {
                result[result.count - 1].append(tag)
                width += estimate
            }
        }
        return result
    }
}
