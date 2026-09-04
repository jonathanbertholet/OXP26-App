import SwiftUI

struct AgendaTalkCard: View {
    var track: Track
    var isSaved: Bool
    var isConflict: Bool
    var isLive: Bool
    var isDimmed: Bool
    var isWide: Bool
    /// Visible viewport width. Wide venue cards span every room, so titles
    /// must wrap inside this — not the full multi-column canvas.
    var readableWidth: CGFloat = 280
    var cardSize: CGSize = CGSize(width: 152, height: 104)

    private var agendaTags: [Tag] { track.topicTags + track.audienceTags }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if !isWide {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accent)
                    .frame(width: 3)
            }
            cardBody(in: innerSize)
        }
        .padding(.horizontal, isWide ? 10 : 8)
        .padding(.vertical, isWide ? 8 : 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            if showsBadges { badgeCluster }
        }
        .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSaved ? Color.pink.opacity(0.55) : Color.clear, lineWidth: 1.5)
        }
        .opacity(isDimmed ? 0.28 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var innerSize: CGSize {
        CGSize(
            width: max(cardSize.width - (isWide ? 20 : 30), 80),
            height: max(cardSize.height - (isWide ? 16 : 12), 36)
        )
    }

    private func cardBody(in size: CGSize) -> some View {
        let width = isWide ? min(readableWidth, size.width) : size.width
        let showTags = size.height >= 48 && !agendaTags.isEmpty
        // Narrow columns keep the title; speaker lives on the detail screen.
        let showSpeaker = isWide && size.height >= 64 && track.speakerLine != nil
        let reserved: CGFloat = (showTags ? 20 : 0) + (showSpeaker ? 14 : 0) + 4
        let lineHeight: CGFloat = isWide ? 19 : 15
        let maxLines = isWide ? 3 : 5
        let rawLines = Int((size.height - reserved) / lineHeight)
        let titleLines = rawLines < 1 ? 1 : (rawLines > maxLines ? maxLines : rawLines)

        return VStack(alignment: .leading, spacing: 3) {
            Text(track.name)
                .font(isWide ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(titleLines)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: width, alignment: .leading)
            if showSpeaker, let speaker = track.speakerLine {
                Text(speaker)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: width, alignment: .leading)
            }
            if showTags {
                TalkTagStrip(
                    track: track,
                    compact: true,
                    limit: isWide ? 4 : 3,
                    shortNames: true,
                    singleLine: true,
                    topicAndAudienceOnly: true
                )
                .frame(maxWidth: width, alignment: .leading)
            }
        }
        .frame(width: width, alignment: .topLeading)
        .padding(.trailing, showsBadges ? 16 : 0)
    }

    private var showsBadges: Bool { isSaved || isConflict || isLive }

    private var badgeCluster: some View {
        HStack(spacing: 3) {
            if isLive {
                Text("Now")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .foregroundStyle(.white)
                    .background(OxpTheme.accent, in: Capsule())
            }
            if isConflict {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Overlaps another saved talk")
            }
            if isSaved {
                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(.pink)
                    .accessibilityLabel("Saved")
            }
        }
        .padding(.top, isWide ? 8 : 6)
        .padding(.trailing, isWide ? 8 : 6)
    }

    private var accent: Color {
        track.location.map(OxpTheme.roomColor) ?? OxpTheme.accent
    }

    private var fill: Color {
        if isWide {
            return Color.secondary.opacity(0.14)
        }
        return accent.opacity(0.16)
    }

    private var accessibilityText: String {
        var parts = [track.name, track.timeRangeLabel]
        if let location = track.location { parts.append(location) }
        if let speaker = track.speakerLine { parts.append(speaker) }
        let tagNames = agendaTags.map(\.name)
        if !tagNames.isEmpty { parts.append(tagNames.joined(separator: ", ")) }
        if isSaved { parts.append("Saved") }
        if isConflict { parts.append("Overlaps another saved talk") }
        if isLive { parts.append("Happening now") }
        return parts.joined(separator: ", ")
    }
}
