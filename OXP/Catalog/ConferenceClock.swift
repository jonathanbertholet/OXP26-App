import Foundation

/// The conference-aware "now". Defaults to the real clock, with an optional
/// preview so you can walk a conference day while building the app.
@MainActor
@Observable
final class ConferenceClock {
    /// `yyyy-MM-dd` of a conference day to simulate, or nil for the real date.
    var previewDay: String?
    /// Minutes from midnight in the selected event timezone when previewing a day.
    var previewMinuteOfDay: Int = 11 * 60 + 40
    var timeZoneIdentifier: String = "Europe/Brussels"

    /// Bumped on a timer so Happening Now stays live.
    private(set) var tick: Date = .now

    var isPreviewing: Bool { previewDay != nil }

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .gmt
    }

    var now: Date {
        guard let previewDay, let date = Self.date(day: previewDay, minuteOfDay: previewMinuteOfDay, timeZone: timeZone) else {
            return tick
        }
        return date
    }

    var nowDay: String { now.oxpDay(in: timeZone) }

    func adopt(event: EventInfo?) {
        let identifier = event?.timezone ?? "Europe/Brussels"
        if identifier != timeZoneIdentifier {
            timeZoneIdentifier = identifier
        }
    }

    func startTicking() async {
        while !Task.isCancelled {
            tick = .now
            try? await Task.sleep(for: .seconds(20))
        }
    }

    func preview(_ day: String, hour: Int, minute: Int) {
        previewDay = day
        previewMinuteOfDay = hour * 60 + minute
        tick = .now
    }

    func clearPreview() {
        previewDay = nil
        tick = .now
    }

    static func date(day: String, minuteOfDay: Int, timeZone: TimeZone = TimeZone(identifier: "Europe/Brussels") ?? .gmt) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = minuteOfDay / 60
        components.minute = minuteOfDay % 60
        return calendar.date(from: components)
    }
}

extension Date {
    func oxpDay(in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }

    /// Brussels-local calendar day — used by the Belgium map only.
    var oxpDay: String {
        oxpDay(in: TimeZone(identifier: "Europe/Brussels") ?? .gmt)
    }
}
