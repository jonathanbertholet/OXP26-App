import SwiftUI

struct TagChip: View {
    var text: String
    var selected: Bool = false
    var compact: Bool = false

    var body: some View {
        Text(text)
            .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
            .padding(.horizontal, compact ? 6 : 10)
            .padding(.vertical, compact ? 2 : 6)
            .foregroundStyle(selected ? Color.white : .primary)
            .background(
                selected ? OxpTheme.accent : Color.primary.opacity(compact ? 0.10 : 0.08),
                in: Capsule()
            )
            .lineLimit(1)
    }
}

/// Topic and audience chips for list and agenda cards.
struct TalkTagStrip: View {
    var track: Track
    var compact: Bool = false
    var limit: Int? = nil
    /// Horizontal scroll. Off by default so list rows can wrap without a nested scroll view.
    var scrolls: Bool = false
    var shortNames: Bool = false
    /// Drop chips that do not fit instead of wrapping onto a second line.
    var singleLine: Bool = false
    var topicAndAudienceOnly: Bool = false

    var body: some View {
        let shown = tagsToShow
        if !shown.isEmpty {
            Group {
                if scrolls {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: compact ? 4 : 6) {
                            chips(shown)
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                } else if singleLine {
                    FittingChipRow(spacing: compact ? 4 : 6) {
                        chips(shown)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ChipFlow(spacing: compact ? 4 : 6) {
                        chips(shown)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(shown.map(\.name).joined(separator: ", "))
        }
    }

    @ViewBuilder
    private func chips(_ tags: [Tag]) -> some View {
        ForEach(tags) { tag in
            TagChip(text: shortNames ? tag.shortName : tag.name, compact: compact)
        }
    }

    private var tagsToShow: [Tag] {
        let ordered = track.topicTags + track.audienceTags
        let all = topicAndAudienceOnly
            ? ordered
            : ordered + track.tags.filter { tag in
                !ordered.contains { $0.id == tag.id }
            }
        if let limit {
            return Array(all.prefix(limit))
        }
        return all
    }
}

/// Places chips left to right and hides any that would overflow the line.
private struct FittingChipRow: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var width: CGFloat = 0
        var height: CGFloat = 0
        var placed = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let next = placed == 0 ? size.width : width + spacing + size.width
            if placed > 0, next > maxWidth { break }
            width = next
            height = max(height, size.height)
            placed += 1
        }
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var overflow = false
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if overflow || (x > bounds.minX && x + size.width > bounds.maxX + 0.5) {
                overflow = true
                subview.place(at: CGPoint(x: bounds.maxX, y: bounds.minY), proposal: .zero)
                continue
            }
            subview.place(
                at: CGPoint(x: x, y: bounds.midY - size.height / 2),
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
        }
    }
}

/// Wraps chips to the available width instead of clipping a single HStack.
private struct ChipFlow: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .greatestFiniteMagnitude
        return arrange(in: width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let origins = arrange(in: bounds.width, subviews: subviews).origins
        for (subview, origin) in zip(subviews, origins) {
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(in maxWidth: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        let unlimited = maxWidth <= 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if !unlimited, x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            usedWidth = max(usedWidth, x - spacing)
        }
        return (CGSize(width: usedWidth, height: y + rowHeight), origins)
    }
}

struct SaveButton: View {
    var isSaved: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "heart.fill" : "heart")
                .symbolEffect(.bounce, value: isSaved)
        }
        .buttonStyle(.glassProminent)
        .tint(isSaved ? .pink : OxpTheme.accent)
        .sensoryFeedback(.impact(weight: .medium), trigger: isSaved)
        .accessibilityLabel(isSaved ? "Remove from saved talks" : "Save talk and remind me")
    }
}

struct RoomBadge: View {
    var name: String

    var body: some View {
        Label(name, systemImage: "mappin.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(OxpTheme.roomColor(name))
            .labelStyle(.titleAndIcon)
    }
}

struct SpeakerAvatar: View {
    var speaker: Speaker
    var size: CGFloat = 44

    var body: some View {
        AsyncImage(url: speaker.imageURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(OxpTheme.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
