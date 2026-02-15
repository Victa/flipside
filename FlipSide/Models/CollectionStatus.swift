import Foundation

struct CollectionStatus: Codable, Equatable, Sendable {
    let isInCollection: Bool
    let isInWantlist: Bool
    let collectionInstanceId: Int?

    init(isInCollection: Bool, isInWantlist: Bool, collectionInstanceId: Int? = nil) {
        self.isInCollection = isInCollection
        self.isInWantlist = isInWantlist
        self.collectionInstanceId = collectionInstanceId
    }
}
