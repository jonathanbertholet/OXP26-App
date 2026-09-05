import Foundation
import Testing
@testable import OXP

struct CatalogFeedTests {
    @Test @MainActor func automaticChecksOnlyRunDuringEventsAtTwoHourIntervals() throws {
        let formatter = ISO8601DateFormatter()
        for (raw, expected) in [
            ("2026-09-05T12:00:00Z", false),
            ("2026-09-08T18:29:59Z", false),
            ("2026-09-08T18:30:00Z", true),
            ("2026-09-12T18:30:00Z", false),
            ("2026-09-21T22:00:00Z", true),
            ("2026-09-26T22:00:00Z", false),
            ("2027-09-09T12:00:00Z", false)
        ] {
            let now = try #require(formatter.date(from: raw))
            #expect(CatalogStore.automaticRefreshIsDue(at: now, lastAttempt: nil) == expected)
            #expect(!CatalogStore.automaticRefreshIsDue(at: now, lastAttempt: now.addingTimeInterval(-7199)))
            #expect(CatalogStore.automaticRefreshIsDue(at: now, lastAttempt: now.addingTimeInterval(-7200)) == expected)
        }
    }

    private func remote() throws -> CatalogBundle {
        var bundle = try CatalogDecoder.loadBundled()
        bundle.schemaVersion = 1
        bundle.generatedAt = Date(timeIntervalSinceNow: -60)
        return bundle
    }

    private func data(_ bundle: CatalogBundle) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(bundle)
    }

    @Test func acceptsCompleteFeedRejectsMissingEditionDuplicateIDsAndRollback() throws {
        let baseline = try CatalogDecoder.loadBundled()
        let good = try remote()
        #expect(try CatalogFeedClient.validate(data(good), comparedTo: baseline).events.count == 5)
        var missing = good
        missing.events.removeLast()
        #expect(throws: (any Error).self) { try CatalogFeedClient.validate(data(missing), comparedTo: baseline) }
        var duplicate = good
        duplicate.events[4].tracks.append(duplicate.events[4].tracks[0])
        #expect(throws: (any Error).self) { try CatalogFeedClient.validate(data(duplicate), comparedTo: baseline) }
        var stale = good
        stale.generatedAt = good.generatedAt!.addingTimeInterval(-3600)
        #expect(throws: (any Error).self) { try CatalogFeedClient.validate(data(stale), comparedTo: good) }
    }

    @Test @MainActor func refreshPreservesSelectedEditionAndRemovedSavedTalkLookup() throws {
        let store = CatalogStore()
        var bundle = try remote()
        store.apply(bundle: bundle, persist: false)
        store.selectEvent(10174, persist: false)
        let id = bundle.events[3].tracks[0].id
        bundle.events[3].tracks[0].unavailable = true
        store.apply(bundle: bundle, persist: false)
        #expect(store.selectedEventID == 10174)
        #expect(!store.tracks.contains { $0.id == id })
        #expect(store.track(id: id)?.isUnavailable == true)
    }

    @Test func downloadedFeedSurvivesRelaunchNotModifiedAndBadResponse() async throws {
        let path = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let baseline = try CatalogDecoder.loadBundled()
        let body = try data(remote())
        let first = CatalogFeedClient(cacheURL: path) { request in
            #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)
            return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["ETag": "v1"])!)
        }
        let downloaded = try await first.refresh(comparedTo: baseline)
        let next = CatalogFeedClient(cacheURL: path) { request in
            #expect(request.value(forHTTPHeaderField: "If-None-Match") == "v1")
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 304, httpVersion: nil, headerFields: [:])!)
        }
        let restored = await next.restore(comparedTo: baseline)
        #expect(restored?.bundle.generatedAt == downloaded.bundle.generatedAt)
        let unchanged = try await next.refresh(comparedTo: downloaded.bundle)
        #expect(unchanged.bundle.generatedAt == downloaded.bundle.generatedAt)
        let invalid = CatalogFeedClient(cacheURL: path) { request in
            (Data("<html>unavailable</html>".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["ETag": "bad"])!)
        }
        _ = await invalid.restore(comparedTo: baseline)
        do {
            _ = try await invalid.refresh(comparedTo: downloaded.bundle)
            Issue.record("Invalid feed should fail")
        } catch { }
        let afterFailure = await invalid.restore(comparedTo: baseline)
        #expect(afterFailure?.bundle.generatedAt == downloaded.bundle.generatedAt)
        let offline = CatalogFeedClient(cacheURL: path) { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await offline.refresh(comparedTo: baseline)
            Issue.record("Offline request should fail")
        } catch { }
        #expect(await offline.restore(comparedTo: baseline) != nil)
    }

    @Test func invalidCacheFallsBackWithoutThrowing() async throws {
        let path = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try Data("invalid cache".utf8).write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }
        let client = CatalogFeedClient(cacheURL: path)
        let restored = await client.restore(comparedTo: try CatalogDecoder.loadBundled())
        #expect(restored == nil)
    }
}
