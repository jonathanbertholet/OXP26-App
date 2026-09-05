import Foundation

enum TalkKind: String, Codable, Sendable, Hashable, CaseIterable {
    case talk
    case session
    case masterclass
    case keynote
    case opening
    case `break`
    case social
    case tba

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TalkKind(rawValue: raw) ?? .talk
    }

    var title: String {
        switch self {
        case .talk: "Talk"
        case .session: "Session"
        case .masterclass: "Masterclass"
        case .keynote: "Keynote"
        case .opening: "Opening"
        case .break: "Break"
        case .social: "Concert"
        case .tba: "Coming soon"
        }
    }
}

struct Tag: Identifiable, Codable, Hashable, Sendable {
    var id: Int
    var name: String
    var categoryID: Int?
    var category: String?
    var color: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, color, category
        case categoryID = "category_id"
    }

    var isTopic: Bool { category == "Topics" }
    var isAudience: Bool { category == "Audience" }

    /// Tight label for agenda chips so a 150pt column can show two tags.
    var shortName: String {
        switch name {
        case "Logistic & Manufacturing": "Logistics"
        case "Accounting & Finance": "Finance"
        case "Marketing & eCommerce": "Marketing"
        case "Artificial Intelligence": "AI"
        case "Productivity & Project": "Projects"
        case "Business Intelligence": "BI"
        case "Retail & Food": "Retail"
        case "Human Resource": "HR"
        case "Odoo Beginners": "Beginners"
        case "Odoo Experts": "Experts"
        case "Students & Teachers": "Education"
        default: name
        }
    }
}

struct Speaker: Identifiable, Codable, Hashable, Sendable {
    var id: Int
    var name: String
    var function: String?
    var company: String?
    var biographyText: String?
    var imageURL: URL?

    enum CodingKeys: String, CodingKey {
        case id, name, function, company
        case biographyText = "biography_text"
        case imageURL = "image_url"
    }

    var affiliation: String {
        [function, company].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct Track: Identifiable, Codable, Hashable, Sendable {
    var id: Int
    var sequence: Int?
    var name: String
    var slug: String?
    var url: URL?
    var kind: TalkKind
    var day: String?
    var weekday: String?
    var startTime: String?
    var endTime: String?
    var startsAt: Date?
    var endsAt: Date?
    var timezone: String
    var durationMinutes: Int?
    var durationLabel: String?
    var location: String?
    var speakerLine: String?
    var descriptionText: String?
    var imageURL: URL?
    var comingSoon: Bool
    var unavailable: Bool? = nil
    var isUnavailable: Bool { unavailable == true }
    var tagIDs: [Int]
    var speakerIDs: [Int]
    var tags: [Tag]
    var speakers: [Speaker]

    enum CodingKeys: String, CodingKey {
        case id, sequence, name, slug, url, kind, day, weekday, timezone, tags, speakers
        case startTime = "start_time"
        case endTime = "end_time"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case durationMinutes = "duration_minutes"
        case durationLabel = "duration_label"
        case location
        case speakerLine = "speaker_line"
        case descriptionText = "description_text"
        case imageURL = "image_url"
        case unavailable
        case comingSoon = "coming_soon"
        case tagIDs = "tag_ids"
        case speakerIDs = "speaker_ids"
    }

    var topicTags: [Tag] { tags.filter(\.isTopic) }
    var audienceTags: [Tag] { tags.filter(\.isAudience) }

    var timeRangeLabel: String {
        switch (startTime, endTime) {
        case let (start?, end?): "\(start)–\(end)"
        case let (start?, nil): start
        default: comingSoon ? "Time TBA" : "TBA"
        }
    }

    var scheduleLabel: String {
        let dayPart = [weekday, day].compactMap { $0 }.joined(separator: " ")
        return [dayPart, timeRangeLabel, location].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    func isHappening(at date: Date) -> Bool {
        guard let startsAt, let endsAt else { return false }
        return (startsAt ... endsAt).contains(date)
    }

    func isUpcoming(at date: Date) -> Bool {
        guard let startsAt else { return false }
        return startsAt > date
    }
}

/// Sponsor pages sometimes put "http:// https://example.com" or a bare domain in website.
@propertyWrapper
struct LenientURL: Codable, Hashable, Sendable {
    var wrappedValue: URL?

    init(wrappedValue: URL?) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            wrappedValue = nil
            return
        }
        wrappedValue = Self.parse(try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let wrappedValue {
            try container.encode(wrappedValue.absoluteString)
        } else {
            try container.encodeNil()
        }
    }

    static func parse(_ raw: String) -> URL? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\t", with: " ")
        guard !value.isEmpty else { return nil }
        if let range = value.range(of: "https://", options: .caseInsensitive) {
            value = String(value[range.lowerBound...])
        } else if let range = value.range(of: "http://", options: .caseInsensitive) {
            let rest = String(value[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            value = rest.lowercased().hasPrefix("http") ? rest : "http://\(rest)"
        }
        value = value.replacingOccurrences(of: " ", with: "")
        if value.hasPrefix("/") {
            return URL(string: "https://www.odoo.com\(value)")
        }
        if let url = URL(string: value), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(value)")
    }
}

struct Exhibitor: Identifiable, Codable, Hashable, Sendable {
    var id: Int
    var sequence: Int?
    var name: String
    var slogan: String?
    var level: String
    var country: String?
    @LenientURL var logoURL: URL?
    @LenientURL var url: URL?
    @LenientURL var website: URL?
    var hours: String?

    enum CodingKeys: String, CodingKey {
        case id, sequence, name, slogan, level, country, hours, url, website
        case logoURL = "logo_url"
    }

    var isStartup: Bool { level.localizedCaseInsensitiveContains("startup") }
}

struct EventInfo: Codable, Hashable, Identifiable, Sendable {
    var id: Int
    var code: String?
    var shortNameValue: String?
    var name: String
    var slug: String
    var timezone: String
    var venueName: String
    var venueAddress: String
    var countryCode: String?
    var hasMapValue: Bool?
    var websiteURL: URL?
    var agendaURL: URL?
    var tracksURL: URL?
    var exhibitorsURL: URL?
    var startsOn: String?
    var endsOn: String?
    var sourceCheckedAt: Date? = nil

    enum CodingKeys: String, CodingKey {
        case id, code, name, slug, timezone
        case shortNameValue = "short_name"
        case venueName = "venue_name"
        case venueAddress = "venue_address"
        case countryCode = "country_code"
        case hasMapValue = "has_map"
        case websiteURL = "website_url"
        case agendaURL = "agenda_url"
        case tracksURL = "tracks_url"
        case exhibitorsURL = "exhibitors_url"
        case startsOn = "starts_on"
        case endsOn = "ends_on"
        case sourceCheckedAt = "source_checked_at"
    }

    var shortName: String { shortNameValue ?? name }
    var hasMap: Bool { hasMapValue ?? (id == 9099) }

    var timeZone: TimeZone {
        TimeZone(identifier: timezone) ?? TimeZone(identifier: "Europe/Brussels") ?? .gmt
    }

    var flag: String {
        guard let countryCode, countryCode.count == 2 else { return "🌐" }
        return countryCode.uppercased().unicodeScalars.compactMap {
            UnicodeScalar(127397 + $0.value)
        }.map(String.init).joined()
    }

    var menuLabel: String {
        if let range = dateRangeLabel {
            return "\(flag)  \(shortName)  ·  \(range)"
        }
        return "\(flag)  \(shortName)"
    }

    var dateRangeLabel: String? {
        guard let startsOn else { return nil }
        if let endsOn, endsOn != startsOn {
            return "\(Self.shortDate(startsOn))–\(Self.shortDate(endsOn))"
        }
        return Self.shortDate(startsOn)
    }

    private static func shortDate(_ ymd: String) -> String {
        let parts = ymd.split(separator: "-")
        guard parts.count == 3 else { return ymd }
        return "\(parts[2]) \(monthName(parts[1]))"
    }

    private static func monthName(_ mm: Substring) -> String {
        switch mm {
        case "01": "Jan"
        case "02": "Feb"
        case "03": "Mar"
        case "04": "Apr"
        case "05": "May"
        case "06": "Jun"
        case "07": "Jul"
        case "08": "Aug"
        case "09": "Sep"
        case "10": "Oct"
        case "11": "Nov"
        default: "Dec"
        }
    }
}

struct CatalogPayload: Codable, Sendable {
    var event: EventInfo
    var tags: [Tag]
    var locations: [String]
    var tracks: [Track]
    var exhibitors: [Exhibitor]
}

struct CatalogBundle: Codable, Sendable {
    var defaultEventID: Int?
    var events: [CatalogPayload]
    var schemaVersion: Int? = nil
    var generatedAt: Date? = nil

    enum CodingKeys: String, CodingKey {
        case events
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case defaultEventID = "default_event_id"
    }

    var belgium: CatalogPayload? {
        events.first { $0.event.id == 9099 } ?? events.first
    }
}
