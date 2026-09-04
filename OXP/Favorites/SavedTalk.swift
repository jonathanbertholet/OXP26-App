import Foundation
import SwiftData

@Model
final class SavedTalk {
    @Attribute(.unique) var trackID: Int
    var savedAt: Date
    var remindMinutesBefore: Int

    init(trackID: Int, savedAt: Date = .now, remindMinutesBefore: Int = 15) {
        self.trackID = trackID
        self.savedAt = savedAt
        self.remindMinutesBefore = remindMinutesBefore
    }
}
