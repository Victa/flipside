import Foundation

struct CollectionStatus: Codable, Equatable, Sendable {
    let isInCollection: Bool
    let isInWantlist: Bool

    init(isInCollection: Bool, isInWantlist: Bool) {
        self.isInCollection = isInCollection
        self.isInWantlist = isInWantlist
    }
}
