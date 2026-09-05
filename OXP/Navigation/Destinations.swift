import SwiftUI

@MainActor
enum Destinations {
    @ViewBuilder
    static func view(for route: AppRoute) -> some View {
        switch route {
        case .track(let id):
            TalkDetailView(trackID: id)
                .oxpPreviewStatus()
        case .exhibitor(let id):
            ExhibitorDetailView(exhibitorID: id)
                .oxpPreviewStatus()
        case .room(let name):
            RoomDetailView(roomName: name)
                .oxpPreviewStatus()
        case .amenity(let id):
            AmenityDetailView(amenityID: id)
                .oxpPreviewStatus()
        case .boothRow(let letter):
            BoothRowDetailView(letter: letter)
                .oxpPreviewStatus()
        case .booth(let code):
            BoothStallDetailView(code: code)
                .oxpPreviewStatus()
        }
    }
}
