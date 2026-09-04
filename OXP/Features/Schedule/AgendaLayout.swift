import CoreGraphics
import Foundation

/// Column in the official agenda grid: a named room, or a parallel masterclass.
struct AgendaColumn: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var shortTitle: String
    /// Catalog location when this column is a real room (used for color / map).
    var locationName: String?
}

struct AgendaBlock: Identifiable, Hashable, Sendable {
    var track: Track
    /// `nil` means the session spans every column (keynote, lunch, concert).
    var columnID: String?
    var startMinute: Int
    var endMinute: Int

    var id: Int { track.id }
    var spansAllColumns: Bool { columnID == nil }
    var durationMinutes: Int { max(endMinute - startMinute, 15) }
}

struct AgendaDayLayout: Hashable, Sendable {
    /// Room order on https://www.odoo.com/event/odoo-experience-2026-9099/agenda
    static let officialRoomOrder = [
        "Hall 6.A", "Hall 6.B", "Hall 6.C", "Hall 6.D", "Hall 6.E",
        "Hall 7.A", "Hall 7.B",
        "Auditorium 500",
        "Auditorium 2000 A", "Auditorium 2000 B", "Auditorium 2000 C",
        "Auditorium 4000 A", "Auditorium 4000 B", "Auditorium 4000 C", "Auditorium 4000 D",
        "Education Village",
    ]

    var dayStartMinute: Int
    var dayEndMinute: Int
    var columns: [AgendaColumn]
    var blocks: [AgendaBlock]

    var durationMinutes: Int { max(dayEndMinute - dayStartMinute, 60) }

    var hourMarks: [Int] {
        stride(from: dayStartMinute, through: dayEndMinute, by: 60).map { $0 }
    }

    func y(for minute: Int, minuteHeight: CGFloat) -> CGFloat {
        CGFloat(minute - dayStartMinute) * minuteHeight
    }

    func canvasHeight(minuteHeight: CGFloat) -> CGFloat {
        CGFloat(durationMinutes) * minuteHeight
    }

    func canvasWidth(columnWidth: CGFloat, columnGap: CGFloat) -> CGFloat {
        let count = max(columns.count, 1)
        return CGFloat(count) * columnWidth + CGFloat(count - 1) * columnGap
    }

    func frame(
        for block: AgendaBlock,
        columnWidth: CGFloat,
        columnGap: CGFloat,
        minuteHeight: CGFloat
    ) -> CGRect {
        let y = y(for: block.startMinute, minuteHeight: minuteHeight)
        let height = max(CGFloat(block.durationMinutes) * minuteHeight - 4, 44)
        if block.spansAllColumns {
            return CGRect(x: 0, y: y, width: canvasWidth(columnWidth: columnWidth, columnGap: columnGap), height: height)
        }
        guard let columnID = block.columnID,
              let index = columns.firstIndex(where: { $0.id == columnID })
        else {
            return .zero
        }
        let x = CGFloat(index) * (columnWidth + columnGap)
        return CGRect(x: x, y: y, width: columnWidth, height: height)
    }

    func showing(columnIDs: Set<String>) -> AgendaDayLayout {
        guard !columnIDs.isEmpty else { return self }
        var copy = self
        copy.columns = columns.filter { columnIDs.contains($0.id) }
        copy.blocks = blocks.filter { $0.spansAllColumns || $0.columnID.map(columnIDs.contains) == true }
        return copy
    }

    static func build(tracks: [Track]) -> AgendaDayLayout {
        let timed = tracks.compactMap { track -> (Track, Int, Int)? in
            guard let start = minutes(from: track.startTime) else { return nil }
            let end = minutes(from: track.endTime)
                ?? start + (track.durationMinutes ?? 30)
            return (track, start, max(end, start + 15))
        }

        var roomNames = Set<String>()
        var untitled: [Track] = []
        for (track, _, _) in timed {
            if let location = track.location {
                roomNames.insert(location)
            } else if !track.isVenueWide {
                untitled.append(track)
            }
        }

        var columns: [AgendaColumn] = officialRoomOrder
            .filter(roomNames.contains)
            .map { AgendaColumn(id: $0, title: $0, shortTitle: shortRoomName($0), locationName: $0) }

        let extras = roomNames.subtracting(officialRoomOrder).sorted()
        columns.append(contentsOf: extras.map {
            AgendaColumn(id: $0, title: $0, shortTitle: shortRoomName($0), locationName: $0)
        })

        // Parallel masterclasses have no room — each one becomes its own column.
        for track in untitled.sorted(by: { $0.name < $1.name }) {
            let title = shortRoomName(track.name)
            columns.append(AgendaColumn(id: "track:\(track.id)", title: title, shortTitle: title, locationName: nil))
        }

        if columns.isEmpty {
            columns = [AgendaColumn(id: "venue", title: "Venue", shortTitle: "Venue", locationName: nil)]
        }

        let untitledIDs = Dictionary(uniqueKeysWithValues: untitled.map { ($0.id, "track:\($0.id)") })
        let blocks = timed.map { track, start, end in
            let columnID: String?
            if let location = track.location {
                columnID = location
            } else if let untitledID = untitledIDs[track.id] {
                columnID = untitledID
            } else {
                columnID = nil
            }
            return AgendaBlock(track: track, columnID: columnID, startMinute: start, endMinute: end)
        }

        let starts = timed.map(\.1)
        let ends = timed.map(\.2)
        let rawStart = starts.min() ?? 8 * 60
        let rawEnd = ends.max() ?? 18 * 60

        return AgendaDayLayout(
            dayStartMinute: (rawStart / 60) * 60,
            dayEndMinute: ((rawEnd + 59) / 60) * 60,
            columns: columns,
            blocks: blocks
        )
    }

    static func minutes(from time: String?) -> Int? {
        guard let time else { return nil }
        let parts = time.split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return hour * 60 + minute
    }

    static func minuteOfDay(for date: Date, timeZone: TimeZone = TimeZone(identifier: "Europe/Brussels") ?? .gmt) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    static func clockLabel(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    static func shortRoomName(_ name: String) -> String {
        if name.hasPrefix("Hall ") { return String(name.dropFirst(5)) }
        if name.hasPrefix("Auditorium ") { return String(name.dropFirst(11)) }
        if name == "Education Village" { return "Edu" }
        if name.hasPrefix("Masterclass - ") { return String(name.dropFirst(14)) }
        if name.hasPrefix("Masterclass ") { return String(name.dropFirst(12)) }
        return name
    }

    /// Saved talks that share a time window — you cannot watch both.
    static func conflictingIDs(in tracks: [Track]) -> Set<Int> {
        var ids = Set<Int>()
        for i in tracks.indices {
            for j in tracks.indices where j > i {
                guard let startA = minutes(from: tracks[i].startTime),
                      let startB = minutes(from: tracks[j].startTime)
                else { continue }
                let endA = minutes(from: tracks[i].endTime) ?? startA + (tracks[i].durationMinutes ?? 30)
                let endB = minutes(from: tracks[j].endTime) ?? startB + (tracks[j].durationMinutes ?? 30)
                if startA < endB && startB < endA {
                    ids.insert(tracks[i].id)
                    ids.insert(tracks[j].id)
                }
            }
        }
        return ids
    }
}

extension Track {
    /// Plenary sessions sit across every room, matching the official agenda.
    var isVenueWide: Bool {
        location == nil && kind != .masterclass
    }
}
