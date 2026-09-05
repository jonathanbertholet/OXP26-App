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
                Divider()
                if let checked = catalog.event?.sourceCheckedAt {
                    Text("Odoo checked \(checked.formatted(date: .abbreviated, time: .shortened))")
                } else {
                    Text("Using the included agenda")
                }
                if let error = catalog.refreshError { Text(error) }
                Button {
                    Task { await catalog.refresh(force: true) }
                } label: {
                    Label(catalog.isRefreshing ? "Checking for updates…" : "Refresh agenda", systemImage: "arrow.clockwise")
                }
                .disabled(catalog.isRefreshing)
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


private struct PreviewStatusBar: View {
    @Environment(ConferenceClock.self) private var clock

    var body: some View {
        if clock.isPreviewing {
            HStack(spacing: 12) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Preview mode").font(.caption.weight(.semibold))
                        Text(clock.now, format: Date.FormatStyle(date: .abbreviated, time: .shortened,
                                                                 timeZone: clock.timeZone))
                            .font(.caption2)
                    }
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                Spacer(minLength: 0)
                Button("End preview") { clock.clearPreview() }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .foregroundStyle(OxpTheme.accentInk)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(.bar)
        }
    }
}

extension View {
    /// Place inside the navigation content so toolbar actions remain available.
    func oxpPreviewStatus() -> some View {
        safeAreaInset(edge: .top, spacing: 0) { PreviewStatusBar() }
    }
}
