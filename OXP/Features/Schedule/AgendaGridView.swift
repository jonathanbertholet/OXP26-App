import SwiftUI

/// Native time × room canvas. Rooms are columns, time runs down — so a vertical
/// scan is sequential and a horizontal scan is concurrent.
struct AgendaGridView: View {
    var tracks: [Track]
    var now: Date
    var timeZone: TimeZone
    var day: String
    var query: String
    var savedIDs: Set<Int>
    @Binding var emphasizeSaved: Bool
    var jumpToNow: Int

    @State private var focusedColumns: Set<String> = []

    var body: some View {
        let layout = AgendaDayLayout.build(tracks: tracks).showing(columnIDs: focusedColumns)
        Group {
            if layout.columns.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                AgendaScrollCanvas(
                    layout: layout,
                    now: now,
                    timeZone: timeZone,
                    day: day,
                    query: query,
                    savedIDs: savedIDs,
                    emphasizeSaved: emphasizeSaved,
                    conflictIDs: AgendaDayLayout.conflictingIDs(in: tracks.filter { savedIDs.contains($0.id) }),
                    focusedColumns: $focusedColumns,
                    jumpToNow: jumpToNow
                )
            }
        }
        .onAppear {
            if let room = ProcessInfo.processInfo.arguments
                .first(where: { $0.hasPrefix("-agendaRoom=") })?
                .dropFirst("-agendaRoom=".count) {
                focusedColumns = [String(room)]
            }
        }
        .onChange(of: day) {
            focusedColumns = []
        }
    }
}

/// Keeps scroll-offset state here so talk cards are not rebuilt while panning.
private struct AgendaScrollCanvas: View {
    var layout: AgendaDayLayout
    var now: Date
    var timeZone: TimeZone
    var day: String
    var query: String
    var savedIDs: Set<Int>
    var emphasizeSaved: Bool
    var conflictIDs: Set<Int>
    @Binding var focusedColumns: Set<String>
    var jumpToNow: Int

    @ScaledMetric(relativeTo: .caption) private var compactColumnWidth: CGFloat = 152
    @ScaledMetric(relativeTo: .caption) private var minuteHeight: CGFloat = 3.6

    @State private var scrollOrigin = CGPoint.zero
    @State private var containerWidth: CGFloat = 0

    private let gutterWidth: CGFloat = 52
    private let headerHeight: CGFloat = 48
    private let columnGap: CGFloat = 4

    var body: some View {
        let columnWidth = resolvedColumnWidth
        let canvasWidth = layout.canvasWidth(columnWidth: columnWidth, columnGap: columnGap)
        let canvasHeight = layout.canvasHeight(minuteHeight: minuteHeight)

        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                AgendaCardsLayer(
                    layout: layout,
                    columnWidth: columnWidth,
                    columnGap: columnGap,
                    minuteHeight: minuteHeight,
                    canvasWidth: canvasWidth,
                    canvasHeight: canvasHeight,
                    now: now,
                    nowMinute: nowMinute,
                    savedIDs: savedIDs,
                    conflictIDs: conflictIDs,
                    emphasizeSaved: emphasizeSaved,
                    query: query,
                    readableWidth: max(containerWidth - gutterWidth - 24, 240)
                )
                .padding(.leading, gutterWidth)
                .padding(.top, headerHeight)
                .padding(.trailing, 10)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGPoint.self) { geo in
                geo.contentOffset
            } action: { _, new in
                if new != scrollOrigin {
                    scrollOrigin = new
                }
            }
            .onAppear {
                scrollToNow(proxy)
            }
            .onChange(of: jumpToNow) {
                scrollToNow(proxy)
            }
        }
        .overlay(alignment: .topLeading) {
            AgendaRoomHeaderBar(
                columns: layout.columns,
                columnWidth: columnWidth,
                columnGap: columnGap,
                gutterWidth: gutterWidth,
                focusedColumns: $focusedColumns
            )
            .offset(x: -scrollOrigin.x)
        }
        .overlay(alignment: .topLeading) {
            AgendaTimeGutter(
                marks: layout.hourMarks,
                dayStartMinute: layout.dayStartMinute,
                minuteHeight: minuteHeight,
                gutterWidth: gutterWidth,
                headerHeight: headerHeight
            )
            .offset(y: -scrollOrigin.y)
        }
        .overlay(alignment: .topLeading) {
            Button {
                withAnimation(.snappy) { focusedColumns = [] }
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(focusedColumns.isEmpty ? Color.secondary : OxpTheme.accent)
                    .frame(width: gutterWidth, height: headerHeight)
                    .background(.background)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("All rooms")
        }
        .clipped()
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            if width != containerWidth {
                containerWidth = width
            }
        }
    }

    private var nowMinute: Int? {
        guard now.oxpDay(in: timeZone) == day else { return nil }
        let minute = AgendaDayLayout.minuteOfDay(for: now, timeZone: timeZone)
        guard minute >= layout.dayStartMinute, minute <= layout.dayEndMinute else { return nil }
        return minute
    }

    /// One or two rooms expand to fill the phone; the full 16-room day stays compact.
    private var resolvedColumnWidth: CGFloat {
        let available = max(containerWidth - gutterWidth - 10, compactColumnWidth)
        let count = max(layout.columns.count, 1)
        let packed = CGFloat(count) * compactColumnWidth + CGFloat(count - 1) * columnGap
        if packed < available {
            return (available - CGFloat(count - 1) * columnGap) / CGFloat(count)
        }
        return compactColumnWidth
    }

    private func scrollToNow(_ proxy: ScrollViewProxy) {
        guard nowMinute != nil else { return }
        withAnimation(.snappy) {
            proxy.scrollTo("now", anchor: UnitPoint(x: 0, y: 0.28))
        }
    }

}

private struct AgendaCardsLayer: View {
    var layout: AgendaDayLayout
    var columnWidth: CGFloat
    var columnGap: CGFloat
    var minuteHeight: CGFloat
    var canvasWidth: CGFloat
    var canvasHeight: CGFloat
    var now: Date
    var nowMinute: Int?
    var savedIDs: Set<Int>
    var conflictIDs: Set<Int>
    var emphasizeSaved: Bool
    var query: String
    var readableWidth: CGFloat

    @Environment(TabRouter.self) private var router

    var body: some View {
        ZStack(alignment: .topLeading) {
            AgendaHourGrid(
                marks: layout.hourMarks,
                width: canvasWidth,
                minuteHeight: minuteHeight,
                dayStartMinute: layout.dayStartMinute
            )
            ForEach(layout.blocks) { block in
                let frame = layout.frame(
                    for: block,
                    columnWidth: columnWidth,
                    columnGap: columnGap,
                    minuteHeight: minuteHeight
                )
                Button {
                    router.openTrack(block.track.id, on: .schedule)
                } label: {
                    AgendaTalkCard(
                        track: block.track,
                        isSaved: savedIDs.contains(block.track.id),
                        isConflict: conflictIDs.contains(block.track.id),
                        isLive: block.track.isHappening(at: now),
                        isDimmed: isDimmed(block.track),
                        isWide: block.spansAllColumns,
                        readableWidth: readableWidth,
                        cardSize: frame.size
                    )
                }
                .buttonStyle(.plain)
                .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                .padding(.leading, frame.minX)
                .padding(.top, frame.minY)
                .id("talk-\(block.track.id)")
            }
            if let nowMinute {
                AgendaNowNeedle(width: canvasWidth)
                    .padding(.top, layout.y(for: nowMinute, minuteHeight: minuteHeight) - 4)
                    .id("now")
                    .allowsHitTesting(false)
            }
        }
        .frame(width: canvasWidth, height: canvasHeight, alignment: .topLeading)
    }

    private func isDimmed(_ track: Track) -> Bool {
        if emphasizeSaved, !savedIDs.contains(track.id) { return true }
        if query.isEmpty { return false }
        let needle = query.lowercased()
        let matches = track.name.lowercased().contains(needle)
            || (track.speakerLine?.lowercased().contains(needle) == true)
            || (track.location?.lowercased().contains(needle) == true)
        return !matches
    }
}

private struct AgendaRoomHeaderBar: View {
    var columns: [AgendaColumn]
    var columnWidth: CGFloat
    var columnGap: CGFloat
    var gutterWidth: CGFloat
    @Binding var focusedColumns: Set<String>

    var body: some View {
        HStack(spacing: columnGap) {
            ForEach(columns) { column in
                let pinned = focusedColumns.contains(column.id)
                let color = column.locationName.map(OxpTheme.roomColor) ?? OxpTheme.accent
                Button {
                    toggle(column.id)
                } label: {
                    Text(column.shortTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(pinned ? Color.white : color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: columnWidth, height: 44)
                        .background(
                            pinned ? color : Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(column.title)
                .accessibilityAddTraits(pinned ? .isSelected : [])
                .accessibilityHint("Pin this room so you can walk its talks in sequence.")
            }
        }
        .padding(.leading, gutterWidth)
        .padding(.trailing, 10)
        .padding(.bottom, 4)
        .frame(height: 48, alignment: .bottom)
        .background(.background)
    }

    private func toggle(_ id: String) {
        withAnimation(.snappy) {
            focusedColumns = focusedColumns == [id] ? [] : [id]
        }
    }
}

private struct AgendaTimeGutter: View {
    var marks: [Int]
    var dayStartMinute: Int
    var minuteHeight: CGFloat
    var gutterWidth: CGFloat
    var headerHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(marks, id: \.self) { minute in
                Text(AgendaDayLayout.clockLabel(minute))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: gutterWidth - 6, alignment: .trailing)
                    .offset(y: max(2, CGFloat(minute - dayStartMinute) * minuteHeight - 7))
            }
        }
        .padding(.top, headerHeight)
        .frame(width: gutterWidth, alignment: .top)
        .background(.background)
        .allowsHitTesting(false)
    }
}

private struct AgendaHourGrid: View {
    var marks: [Int]
    var width: CGFloat
    var minuteHeight: CGFloat
    var dayStartMinute: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(marks, id: \.self) { minute in
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: width, height: 1)
                    .offset(y: CGFloat(minute - dayStartMinute) * minuteHeight)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct AgendaNowNeedle: View {
    var width: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
            Rectangle()
                .fill(.red)
                .frame(width: width, height: 2)
        }
        .accessibilityLabel("Current time")
    }
}
