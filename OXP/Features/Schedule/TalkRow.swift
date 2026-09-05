import SwiftUI

struct TalkRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var timeWidth: CGFloat = 56

    var track: Track
    var isSaved: Bool
    var showsDay: Bool = false

    var body: some View {
        let rowLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        let metadataLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 8))
        return rowLayout {
            VStack(alignment: .leading, spacing: 2) {
                Text(track.startTime ?? "TBA")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let end = track.endTime {
                    Text(end)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.leading, 8)
            .frame(width: timeWidth + 8, alignment: .leading)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill((track.location.map(OxpTheme.roomColor) ?? OxpTheme.accent).gradient)
                    .frame(width: 3)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(track.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                if let speaker = track.speakerLine {
                    Text(speaker)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                }
                metadataLayout {
                    if showsDay, let weekday = track.weekday {
                        Text(weekday).font(.caption).foregroundStyle(.secondary)
                    }
                    if let location = track.location {
                        Text(location)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(OxpTheme.roomColor(location))
                    }
                    if let duration = track.durationLabel {
                        Text(duration).font(.caption).foregroundStyle(.tertiary)
                    }
                    if isSaved {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.pink)
                            .accessibilityLabel("Saved")
                    }
                }
                TalkTagStrip(track: track, compact: true)
            }
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
