import Foundation

public enum DigestFold: Hashable, Codable, Sendable {
    case digest(String)
    case network(digest: String, network: DigestPackage.Network)
    case topic(digest: String, network: DigestPackage.Network, folder: String)

    public var parent: DigestFold? {
        switch self {
        case .digest:
            nil
        case let .network(digest, _):
            .digest(digest)
        case let .topic(digest, network, _):
            .network(digest: digest, network: network)
        }
    }

    public func collapsed(in folded: Set<DigestFold>) -> Bool {
        sequence(first: self, next: \.parent).contains { folded.contains($0) }
    }
}
