import Foundation

enum AppRoute: Hashable {
    case track(Int)
    case exhibitor(Int)
    case room(String)
    case amenity(String)
    case boothRow(String)
    case booth(String)
}

enum AppTab: Hashable {
    case today, schedule, map, expo, saved
}

@MainActor
@Observable
final class TabRouter {
    var tab: AppTab = .today
    var todayPath: [AppRoute] = []
    var schedulePath: [AppRoute] = []
    var mapPath: [AppRoute] = []
    var expoPath: [AppRoute] = []
    var savedPath: [AppRoute] = []

    var selectedRoom: String?
    var highlightedExhibitorID: Int?
    var selectedFloor: FloorPlan = .overview

    init() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-openAgenda") || args.contains("-openSchedule") || args.contains("-openList") {
            tab = .schedule
        }
        if args.contains("-openExpo") {
            tab = .expo
        }
        if args.contains("-openSaved") {
            tab = .saved
        }
        if args.contains("-openAgenda") {
            UserDefaults.standard.set(ScheduleLayout.agenda.rawValue, forKey: "oxp.scheduleLayout")
        }
        if args.contains("-openList") {
            UserDefaults.standard.set(ScheduleLayout.list.rawValue, forKey: "oxp.scheduleLayout")
        }
        if args.contains("-openMap") || args.contains("-openHall6") || args.contains("-openHall7")
            || args.contains("-openHall11") || args.contains("-openHall10") {
            tab = .map
        }
        if args.contains("-openHall6") {
            selectedFloor = .hall6
        } else if args.contains("-openHall7") {
            selectedFloor = .hall7
        } else if args.contains("-openHall11") {
            selectedFloor = .hall11
        } else if args.contains("-openHall10") {
            selectedFloor = .hall10
        }
    }

    func openTrack(_ id: Int, on tab: AppTab? = nil) {
        let target = tab ?? self.tab
        self.tab = target
        push(.track(id), on: target)
    }

    func openExhibitor(_ id: Int) {
        tab = .map
        highlightedExhibitorID = id
        push(.exhibitor(id), on: .map)
    }

    func showOnMap(plan: FloorPlan, exhibitorID: Int? = nil) {
        tab = .map
        selectedFloor = plan
        highlightedExhibitorID = exhibitorID
        selectedRoom = nil
    }

    /// Drop the room/exhibitor lock so the map can unzoom and stop highlighting a hotspot.
    func clearMapFocus() {
        selectedRoom = nil
        highlightedExhibitorID = nil
    }

    func openRoom(_ name: String) {
        tab = .map
        selectedRoom = name
        selectedFloor = VenueLayout.floorPlan(forLocation: name)
        push(.room(name), on: .map)
    }

    func push(_ route: AppRoute, on tab: AppTab? = nil) {
        switch tab ?? self.tab {
        case .today: todayPath.append(route)
        case .schedule: schedulePath.append(route)
        case .map: mapPath.append(route)
        case .expo: expoPath.append(route)
        case .saved: savedPath.append(route)
        }
    }
}
