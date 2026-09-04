import SwiftUI

enum Destinations {
    @ViewBuilder
    static func view(for route: AppRoute) -> some View {
        switch route {
        case .track(let id):
            TalkDetailView(trackID: id)
        case .exhibitor(let id):
            ExhibitorDetailView(exhibitorID: id)
        case .room(let name):
            RoomDetailView(roomName: name)
        case .amenity(let id):
            AmenityDetailView(amenityID: id)
        case .boothRow(let letter):
            BoothRowDetailView(letter: letter)
        case .booth(let code):
            BoothStallDetailView(code: code)
        }
    }
}
