import SwiftUI

struct TalkRow: View {
    var track: Track
    var isSaved: Bool
    var showsDay: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
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
            .frame(width: 56, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(track.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                if let speaker = track.speakerLine {
                    Text(speaker)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
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
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
