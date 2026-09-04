import Foundation

enum CatalogDecoder {
    static func loadBundled() throws -> CatalogBundle {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json") else {
            throw CatalogError.missingFile
        }
        let data = try Data(contentsOf: url)
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> CatalogBundle {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let isoColon = ISO8601DateFormatter()
        isoColon.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        let posix = DateFormatter()
        posix.locale = Locale(identifier: "en_US_POSIX")
        posix.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = iso.date(from: raw) ?? isoColon.date(from: raw) ?? posix.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized date \(raw)"
            )
        }

        let peek = try JSONSerialization.jsonObject(with: data)
        if let object = peek as? [String: Any], object["events"] != nil {
            return try decoder.decode(CatalogBundle.self, from: data)
        }
        // Legacy single-event catalog.json from the first Belgium-only seed.
        let single = try decoder.decode(CatalogPayload.self, from: data)
        return CatalogBundle(defaultEventID: single.event.id, events: [single])
    }
}

enum CatalogError: LocalizedError {
    case missingFile

    var errorDescription: String? {
        "The Odoo Experience catalog is missing from the app bundle."
    }
}
