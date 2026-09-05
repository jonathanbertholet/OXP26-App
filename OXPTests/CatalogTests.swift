import CoreGraphics
import Foundation
import Testing
@testable import OXP

struct CatalogTests {
    @Test func decodesBundledCatalog() throws {
        let bundle = try CatalogDecoder.loadBundled()
        #expect(!bundle.events.isEmpty)
        let belgium = try #require(bundle.belgium)
        #expect(belgium.event.timezone == "Europe/Brussels")
        #expect(belgium.event.hasMap)
        if bundle.events.count == 1 {
            #expect(belgium.tracks.count == 480)
            #expect(belgium.exhibitors.count == 342)
        } else {
            #expect(bundle.events.count >= 5)
            #expect(belgium.tracks.count == 480)
            let india = try #require(bundle.events.first { $0.event.id == 10174 })
            #expect(india.tracks.count > 50)
            #expect(india.event.hasMap == false)
            #expect(india.tracks.contains { $0.startsAt != nil })
        }
        let gmail = try #require(belgium.tracks.first { $0.id == 10380 })
        #expect(gmail.location == "Hall 6.A")
        #expect(gmail.speakers.contains { $0.name == "Simon Stappen" })
        #expect(gmail.startsAt != nil)
        #expect(Tag(id: 2, name: "Odoo Beginners", category: "Audience").shortName == "Beginners")
        #expect(Tag(id: 47, name: "Logistic & Manufacturing", category: "Topics").shortName == "Logistics")
        #expect(Tag(id: 1, name: "Developers", category: "Audience").shortName == "Developers")
    }

    @Test @MainActor func happeningNowMatchesThursdaySlot() throws {
        let bundle = try CatalogDecoder.loadBundled()
        let belgium = try #require(bundle.belgium)
        let store = CatalogStore()
        store.apply(belgium)
        let moment = try #require(ConferenceClock.date(day: "2026-09-24", minuteOfDay: 11 * 60 + 40))
        let live = store.happening(at: moment)
        #expect(live.contains { $0.id == 10380 })
        #expect(live.count >= 10)
    }

    @Test @MainActor func switchingEventDoesNotMergeTalks() throws {
        let bundle = try CatalogDecoder.loadBundled()
        guard bundle.events.count > 1 else { return }
        let store = CatalogStore()
        store.apply(bundle: bundle, persist: false)
        store.selectEvent(9099, persist: false)
        let other = try #require(bundle.events.first { $0.event.id != 9099 && !$0.tracks.isEmpty })
        store.selectEvent(other.event.id, persist: false)
        #expect(store.hasMap == false)
        #expect(store.event?.id == other.event.id)
        #expect(store.tracks.count == other.tracks.count)
        #expect(Set(store.tracks.map(\.id)) == Set(other.tracks.map(\.id)))
    }
}

struct AgendaLayoutTests {
    @Test func thursdayGridMatchesOfficialRooms() throws {
        let belgium = try #require(CatalogDecoder.loadBundled().belgium)
        let thursday = belgium.tracks.filter { $0.day == "2026-09-24" }
        let layout = AgendaDayLayout.build(tracks: thursday)
        #expect(layout.columns.map(\.title) == AgendaDayLayout.officialRoomOrder)

        let lunch = try #require(layout.blocks.first { $0.track.name == "Lunch break" })
        #expect(lunch.spansAllColumns)

        let keynote = try #require(layout.blocks.first { $0.track.id == 10881 })
        #expect(keynote.spansAllColumns)
        #expect(keynote.startMinute == 8 * 60 + 30)

        let gmail = try #require(layout.blocks.first { $0.track.id == 10380 })
        #expect(gmail.columnID == "Hall 6.A")
        #expect(gmail.startMinute == 11 * 60 + 30)
        #expect(gmail.endMinute == 12 * 60)
    }

    @Test func masterclassDayUsesParallelColumns() throws {
        let belgium = try #require(CatalogDecoder.loadBundled().belgium)
        let tuesday = belgium.tracks.filter { $0.day == "2026-09-22" }
        let layout = AgendaDayLayout.build(tracks: tuesday)
        #expect(layout.columns.count >= 8)
        #expect(layout.blocks.allSatisfy { !$0.spansAllColumns })
        #expect(layout.columns.contains { $0.shortTitle == "Accounting" })
    }

    @Test func overlappingSavedTalksAreFlagged() throws {
        let belgium = try #require(CatalogDecoder.loadBundled().belgium)
        let gmail = try #require(belgium.tracks.first { $0.id == 10380 })
        let neighbor = try #require(belgium.tracks.first {
            $0.day == gmail.day
                && $0.id != gmail.id
                && $0.startTime == gmail.startTime
                && $0.location != gmail.location
        })
        let conflicts = AgendaDayLayout.conflictingIDs(in: [gmail, neighbor])
        #expect(conflicts == [gmail.id, neighbor.id])
        #expect(AgendaDayLayout.conflictingIDs(in: [gmail]).isEmpty)
    }
}

struct VenueLayoutTests {
    @Test func compactStageSearchFindsTheSharedAuditorium() throws {
        let mainStage = try #require(VenueLayout.feature(ref: "Main stage", on: .hall11))
        for suffix in ["A", "B", "C", "D"] {
            #expect(VenueLayout.matchesFeature(mainStage, query: "4000\(suffix)"))
            #expect(VenueLayout.matchesFeature(mainStage, query: "4000 \(suffix)"))
            #expect(mainStage.accessibilityTitle.contains("Auditorium 4000 \(suffix)"))
        }
        #expect(!VenueLayout.matchesFeature(mainStage, query: "4000E"))
        let auditorium = try #require(VenueLayout.feature(ref: "Auditorium 2000", on: .hall10))
        let village = try #require(VenueLayout.feature(ref: "odoo-village", on: .hall10))
        let welcome = try #require(VenueLayout.feature(ref: "welcome-hall10", on: .hall10))
        let entrance = try #require(VenueLayout.feature(ref: "entrance-hall10", on: .hall10))
        #expect(auditorium.frame.maxY < village.frame.minY)
        #expect(village.frame.maxY < welcome.frame.minY)
        #expect(welcome.frame.maxY < entrance.frame.minY)
    }

    @Test func officialPlansCoverTalkRooms() {
        #expect(VenueLayout.feature(ref: "Hall 6.A", on: .hall6) != nil)
        #expect(VenueLayout.feature(ref: "Hall 7.B", on: .hall7) != nil)
        #expect(VenueLayout.feature(ref: "Main stage", on: .hall11) != nil)
        #expect(VenueLayout.feature(ref: "Education Village", on: .hall7) != nil)
        #expect(VenueLayout.catalogLocations(for: "Main stage").count == 4)
        #expect(VenueLayout.floorPlan(forLocation: "Hall 6.A") == .hall6)
        #expect(VenueLayout.floorPlan(forLocation: "Auditorium 4000 A") == .hall11)
        #expect(VenueLayout.floorPlan(forLocation: "Auditorium 2000 B") == .hall10)
        #expect(VenueLayout.hotspotID(forLocation: "Auditorium 4000 C") == "Main stage")
        #expect(VenueLayout.boothRow("H")?.stallCount == 14)
        #expect(VenueLayout.stalls(on: .hall6).filter { $0.letter == "A" }.count == 24)
        #expect(VenueLayout.stalls(on: .hall7).filter { $0.letter == "H" }.count == 14)
        #expect(Set(VenueLayout.stalls.map(\.code)).count == VenueLayout.stalls.count)
        #expect(VenueLayout.stalls.allSatisfy { $0.frame.width > 0 && $0.frame.height > 0 })
        #expect(VenueLayout.boothRows.count == 17)
        #expect(VenueLayout.stalls.allSatisfy { stall in
            stall.frame.minX >= 0 && stall.frame.minY >= 0
                && stall.frame.maxX <= 1.001 && stall.frame.maxY <= 1.001
        })
        let room6a = VenueLayout.feature(ref: "Hall 6.A", on: .hall6)!
        let roomHit = VenueLayout.hit(
            at: CGPoint(x: room6a.frame.midX, y: room6a.frame.midY),
            on: .hall6
        )
        #expect(roomHit?.ref == "Hall 6.A")
    }
}


struct FloorPresentationTests {
    @Test func wideHallsUsePortraitSpaceWithoutStretching() {
        for plan in [FloorPlan.hall6, .hall7] {
            let portrait = FloorPresentation(plan: plan, viewport: CGSize(width: 390, height: 600))
            #expect(portrait.rotated)
            #expect(abs(portrait.drawingFrame.width / portrait.drawingFrame.height - 1 / plan.aspect) < 0.001)
            #expect(portrait.size.height == 576)
            let landscape = FloorPresentation(plan: plan, viewport: CGSize(width: 900, height: 500))
            #expect(!landscape.rotated)
            #expect(abs(landscape.drawingFrame.width / landscape.drawingFrame.height - plan.aspect) < 0.001)
        }
    }

    @Test func roomFocusAndArtworkShareRotatedCoordinates() {
        let presentation = FloorPresentation(plan: .hall6, viewport: CGSize(width: 390, height: 600))
        let topLeft = presentation.normalized(CGRect(x: 0, y: 0, width: 0.2, height: 0.3))
        #expect(abs(topLeft.minX - 0.7) < 0.001)
        #expect(topLeft.minY == 0)
        #expect(topLeft.width == 0.3)
        #expect(topLeft.height == 0.2)
        for feature in VenueLayout.features(on: .hall6) {
            let frame = presentation.frame(feature.frame)
            #expect(frame.minX >= 0 && frame.minY >= 0)
            #expect(frame.maxX <= presentation.size.width + 0.01)
            #expect(frame.maxY <= presentation.size.height + 0.01)
        }
    }

    @Test func tallPlansAndOverviewKeepTheirProportionsAcrossWindowSizes() {
        for viewport in [CGSize(width: 320, height: 480), CGSize(width: 1024, height: 700), .zero] {
            for plan in [FloorPlan.overview, .hall10, .hall11] {
                let layout = FloorPresentation(plan: plan, viewport: viewport)
                #expect(!layout.rotated)
                #expect(layout.size.width > 0 && layout.size.height > 0)
                #expect(abs(layout.drawingFrame.width / layout.drawingFrame.height - plan.aspect) < 0.001)
                #expect(layout.size.width <= max(viewport.width - 24, 1))
                #expect(layout.size.height <= max(viewport.height - 24, 1) + 0.001)
            }
        }
    }

    @Test func hallDirectionsStayOutsideTheDrawingAndInsideTheViewport() {
        for viewport in [CGSize(width: 390, height: 600), CGSize(width: 900, height: 500)] {
            for plan in FloorPlan.allCases where plan != .overview {
                let presentation = FloorPresentation(plan: plan, viewport: viewport)
                for feature in VenueLayout.features(on: plan) {
                    guard case .hall = feature.kind else { continue }
                    let direction = presentation.directionFrame(for: feature.frame)
                    #expect(direction.intersection(presentation.drawingFrame).isEmpty)
                    #expect(direction.width == 44 && direction.height == 44)
                    #expect(direction.minX >= 0 && direction.minY >= 0)
                    #expect(direction.maxX <= presentation.size.width + 0.001)
                    #expect(direction.maxY <= presentation.size.height + 0.001)
                }
            }
        }
    }
}


struct MapNavigationTests {
    @Test @MainActor func showOnMapRevealsTheMapInsteadOfPushingAnotherDetail() {
        let router = TabRouter()
        router.mapPath = [.room("Hall 7.A")]
        router.highlightedExhibitorID = 42
        router.openRoom("Hall 6.A")
        #expect(router.tab == .map)
        #expect(router.mapPath.isEmpty)
        #expect(router.selectedFloor == .hall6)
        #expect(router.selectedRoom == "Hall 6.A")
        #expect(router.highlightedExhibitorID == nil)
        router.mapPath = [.room("Hall 6.A")]
        router.showOnMap(plan: .hall7, exhibitorID: 42)
        #expect(router.mapPath.isEmpty)
        #expect(router.selectedRoom == nil)
        #expect(router.highlightedExhibitorID == 42)
    }
}
