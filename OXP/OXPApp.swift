import SwiftData
import SwiftUI
import UserNotifications

@main
struct OXPApp: App {
    @State private var catalog = CatalogStore()
    @State private var favorites = FavoritesStore()
    @State private var clock = ConferenceClock()
    @State private var router = TabRouter()

    private let container: ModelContainer

    init() {
        TalkReminders.registerCategories()
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        if let support {
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        }
        do {
            container = try ModelContainer(for: SavedTalk.self)
        } catch {
            fatalError("SwiftData container failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(catalog)
                .environment(favorites)
                .environment(clock)
                .environment(router)
                .task {
                    favorites.attach(context: container.mainContext)
                    await catalog.load()
                    clock.adopt(event: catalog.event)
                    // Screenshot / review automation: -previewDay=2026-09-24
                    if let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-previewDay=") }) {
                        let day = String(raw.dropFirst("-previewDay=".count))
                        clock.preview(day, hour: 11, minute: 40)
                    }
                    NotificationDelegate.shared.onOpenTrack = { id in
                        router.openTrack(id, on: .saved)
                    }
                    NotificationDelegate.shared.onDropTrack = { id in
                        Task { await favorites.unsave(trackID: id) }
                    }
                    if let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-seedSaved=") }) {
                        let ids = raw.dropFirst("-seedSaved=".count).split(separator: ",").compactMap { Int($0) }
                        for id in ids {
                            if let track = catalog.track(id: id) {
                                await favorites.save(track: track)
                            }
                        }
                    }
                    if let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-openTrack=") }),
                       let id = Int(raw.dropFirst("-openTrack=".count)) {
                        router.openTrack(id, on: .today)
                    }
                    await clock.startTicking()
                }
                .preferredColorScheme(.none)
        }
        .modelContainer(container)
    }
}
