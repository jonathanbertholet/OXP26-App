import Foundation

actor CatalogFeedClient {
    struct Snapshot: Sendable {
        let bundle: CatalogBundle
        let checkedAt: Date
    }
    private struct Cache: Codable {
        var data: Data
        var etag: String?
        var checkedAt: Date
    }
    typealias Loader = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let loader: Loader
    private let cacheURL: URL
    private var cache: Cache?
    static let endpoint = URL(string: "https://oxp-site.jonathanbertholet.workers.dev/agenda/catalog.json")!

    init(cacheURL: URL? = nil, loader: @escaping Loader = CatalogFeedClient.download) {
        self.loader = loader
        self.cacheURL = cacheURL ?? URL.applicationSupportDirectory.appending(path: "agenda-cache.json")
    }

    func restore(comparedTo baseline: CatalogBundle) -> Snapshot? {
        guard let data = try? Data(contentsOf: cacheURL),
              let saved = try? JSONDecoder().decode(Cache.self, from: data),
              let bundle = try? Self.validate(saved.data, comparedTo: baseline) else { return nil }
        cache = saved
        return Snapshot(bundle: bundle, checkedAt: saved.checkedAt)
    }

    func refresh(comparedTo baseline: CatalogBundle) async throws -> Snapshot {
        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag = cache?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (downloaded, http) = try await loader(request)
        try Task.checkCancellation()
        let data: Data
        if http.statusCode == 304, let cache {
            data = cache.data
        } else {
            guard http.statusCode == 200, !downloaded.isEmpty, downloaded.count <= 8_000_000 else { throw FeedError.invalidResponse }
            data = downloaded
        }
        let bundle = try Self.validate(data, comparedTo: baseline)
        let saved = Cache(data: data, etag: http.value(forHTTPHeaderField: "ETag") ?? (http.statusCode == 304 ? cache?.etag : nil), checkedAt: .now)
        let encoded = try JSONEncoder().encode(saved)
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded.write(to: cacheURL, options: .atomic)
        cache = saved
        return Snapshot(bundle: bundle, checkedAt: saved.checkedAt)
    }

    private static func download(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (file, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: file) }
        guard let http = response as? HTTPURLResponse else { throw FeedError.invalidResponse }
        if http.statusCode == 304 { return (Data(), http) }
        guard http.statusCode == 200 else { throw FeedError.invalidResponse }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 8_000_000 else { throw FeedError.invalidResponse }
        return (try Data(contentsOf: file), http)
    }

    static func validate(_ data: Data, comparedTo baseline: CatalogBundle) throws -> CatalogBundle {
        let bundle = try CatalogDecoder.decode(data)
        guard bundle.schemaVersion == 1, let generated = bundle.generatedAt,
              generated >= (baseline.generatedAt ?? .distantPast),
              generated < Date.now.addingTimeInterval(3600),
              !bundle.events.isEmpty,
              Set(bundle.events.map { $0.event.id }).isSuperset(of: baseline.events.map { $0.event.id }),
              Set(bundle.events.map { $0.event.id }).count == bundle.events.count else { throw FeedError.invalidResponse }
        let tracks = bundle.events.flatMap(\.tracks)
        guard Set(tracks.map(\.id)).count == tracks.count else { throw FeedError.invalidResponse }
        for event in bundle.events {
            if let previous = baseline.events.first(where: { $0.event.id == event.event.id }) {
                guard event.tracks.count >= Int(Double(previous.tracks.count) * 0.9),
                      (event.event.sourceCheckedAt ?? .distantPast) >= (previous.event.sourceCheckedAt ?? .distantPast) else { throw FeedError.invalidResponse }
            }
            for track in event.tracks {
                guard !track.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      TimeZone(identifier: track.timezone) != nil else { throw FeedError.invalidResponse }
                if let start = track.startsAt, let end = track.endsAt, end < start { throw FeedError.invalidResponse }
            }
        }
        return bundle
    }

    enum FeedError: Error { case invalidResponse }
}
