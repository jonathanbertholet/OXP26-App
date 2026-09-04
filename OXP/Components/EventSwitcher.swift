import SwiftUI

struct EventSwitcher: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(ConferenceClock.self) private var clock
    @Environment(TabRouter.self) private var router

    var body: some View {
        if catalog.availableEvents.count > 1 {
            Menu {
                ForEach(catalog.availableEvents) { event in
                    Button {
                        switchTo(event)
                    } label: {
                        if event.id == catalog.selectedEventID {
                            Label(event.menuLabel, systemImage: "checkmark")
                        } else {
                            Text(event.menuLabel)
                        }
                    }
                }
            } label: {
                Label(catalog.event?.shortName ?? "Event", systemImage: "globe")
            }
            .accessibilityLabel("Switch Odoo Experience")
        }
    }

    private func switchTo(_ event: EventInfo) {
        // Leave Map before the tab disappears on non-Belgium editions.
        if !event.hasMap, router.tab == .map {
            router.tab = .today
        }
        catalog.selectEvent(event.id)
        clock.adopt(event: catalog.event)
        clock.clearPreview()
    }
}
