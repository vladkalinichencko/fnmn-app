import Foundation

/// One digest of social posts, as the Mac's digest builder delivers it: an uncompressed USTAR archive whose
/// first entry is `package.json` and whose other entries are the post media and the classifier model.
/// The dates arrive as ISO 8601 in UTC, so `DigestFile` reads it with its own decoder.
public struct DigestPackage: Codable, Equatable, Sendable {
    public static let supportedSchema = 1

    public let schema: Int
    public let id: String
    public let window: Window
    /// The folders in their subscription order: one section of the magazine each.
    public let folders: [String]
    public let sources: [Source]
    public let model: ModelRef?
    public let posts: [Post]

    public init(
        schema: Int = 1,
        id: String,
        window: Window,
        folders: [String] = [],
        sources: [Source] = [],
        model: ModelRef? = nil,
        posts: [Post] = []
    ) {
        self.schema = schema
        self.id = id
        self.window = window
        self.folders = folders
        self.sources = sources
        self.model = model
        self.posts = posts
    }

    /// The network a post or a source comes from. The server writes these three; a fourth is a contract
    /// change, not an unknown string to draw.
    public enum Network: String, Codable, CaseIterable, Sendable {
        case x, telegram, instagram

        public var name: String {
            switch self {
            case .x: "X"
            case .telegram: "Telegram"
            case .instagram: "Instagram"
            }
        }
    }

    /// The stretch of time the digest covers: the posts posted after the last build.
    public struct Window: Codable, Equatable, Sendable {
        public let from: Date
        public let to: Date

        public init(from: Date, to: Date) {
            self.from = from
            self.to = to
        }
    }

    /// The text classifier the digest carries, when the Mac trained one from the folders and the engagement.
    public struct ModelRef: Codable, Equatable, Sendable {
        public let file: String
        public let trainedAt: Date
        public let examples: Int

        public init(file: String, trainedAt: Date, examples: Int) {
            self.file = file
            self.trainedAt = trainedAt
            self.examples = examples
        }
    }

    /// One channel, account or profile the monitor reads. `status` is `ok`, `stale` (the login or the page
    /// did not answer) or `failed` (the source broke), and `detail` carries the reason.
    public struct Source: Codable, Equatable, Identifiable, Sendable {
        public let id: String
        public let network: Network
        public let name: String
        public let folders: [String]
        public let status: Status
        public let detail: String?

        public init(id: String, network: Network, name: String, folders: [String], status: Status, detail: String? = nil) {
            self.id = id
            self.network = network
            self.name = name
            self.folders = folders
            self.status = status
            self.detail = detail
        }

        public enum Status: String, Codable, CaseIterable, Sendable {
            case ok, stale, failed
        }
    }

    /// One post as the digest carries it, with the post it quotes, repeats or answers kept inside.
    public struct Post: Codable, Equatable, Identifiable, Sendable {
        public let id: String
        public let network: Network
        public let author: Author
        public let permalink: URL
        public let postedAt: Date
        public let text: String?
        public let media: [Media]
        public let video: Video?
        public let context: Context?
        public let comments: [Comment]
        public let stats: Stats?
        /// The folders of the source it came from; the classifier's label wins when it names one of them.
        public let folders: [String]

        public init(
            id: String,
            network: Network,
            author: Author,
            permalink: URL,
            postedAt: Date,
            text: String? = nil,
            media: [Media] = [],
            video: Video? = nil,
            context: Context? = nil,
            comments: [Comment] = [],
            stats: Stats? = nil,
            folders: [String] = []
        ) {
            self.id = id
            self.network = network
            self.author = author
            self.permalink = permalink
            self.postedAt = postedAt
            self.text = text
            self.media = media
            self.video = video
            self.context = context
            self.comments = comments
            self.stats = stats
            self.folders = folders
        }

        public struct Author: Codable, Equatable, Sendable {
            public let handle: String
            public let name: String

            public init(handle: String, name: String) {
                self.handle = handle
                self.name = name
            }
        }

        /// A picture file in the delivery, with the size it had when the server measured it, so a card lays
        /// itself out before the file is decoded.
        public struct Media: Codable, Equatable, Sendable {
            public let path: String
            public let width: Int
            public let height: Int

            public init(path: String, width: Int, height: Int) {
                self.path = path
                self.width = width
                self.height = height
            }
        }

        /// A video the digest does not stream: its poster frame, its length, and nothing to play.
        public struct Video: Codable, Equatable, Sendable {
            public let poster: Media?
            public let duration: Double?

            public init(poster: Media? = nil, duration: Double? = nil) {
                self.poster = poster
                self.duration = duration
            }
        }

        /// The post this one quotes or answers, and which of those it is. The context post carries no context
        /// of its own: the server flattens a chain into the one post that started it.
        public struct Context: Codable, Equatable, Sendable {
            public let kind: Kind
            public let post: ContextPost?

            public init(kind: Kind, post: ContextPost? = nil) {
                self.kind = kind
                self.post = post
            }

            public enum Kind: String, Codable, CaseIterable, Sendable {
                case quote, reply
            }
        }

        /// A quoted or answered post: what a card shows of it, without a context or comments of its own.
        public struct ContextPost: Codable, Equatable, Sendable {
            public let id: String
            public let network: Network
            public let author: Author
            public let permalink: URL
            public let postedAt: Date
            public let text: String?
            public let media: [Media]
            public let video: Video?
            public let stats: Stats?

            public init(
                id: String,
                network: Network,
                author: Author,
                permalink: URL,
                postedAt: Date,
                text: String? = nil,
                media: [Media] = [],
                video: Video? = nil,
                stats: Stats? = nil
            ) {
                self.id = id
                self.network = network
                self.author = author
                self.permalink = permalink
                self.postedAt = postedAt
                self.text = text
                self.media = media
                self.video = video
                self.stats = stats
            }
        }

        public struct Comment: Codable, Equatable, Sendable {
            public let author: String
            public let text: String
            public let permalink: URL?

            public init(author: String, text: String, permalink: URL? = nil) {
                self.author = author
                self.text = text
                self.permalink = permalink
            }
        }

        public struct Stats: Codable, Equatable, Sendable {
            public let likes: Int?
            public let reposts: Int?
            public let replies: Int?

            public init(likes: Int? = nil, reposts: Int? = nil, replies: Int? = nil) {
                self.likes = likes
                self.reposts = reposts
                self.replies = replies
            }
        }
    }

    /// One section of the magazine: a folder and the posts in it, newest first.
    public struct Section: Equatable, Identifiable, Sendable {
        public let folder: String
        public let posts: [Post]

        public var id: String {
            folder
        }

        public init(folder: String, posts: [Post]) {
            self.folder = folder
            self.posts = posts
        }
    }
}

extension DigestPackage {
    public static let otherFolder = "Other"

    /// The magazine's sections: the package's folders in order, then any folder a post names that the package
    /// does not list, and never an empty one. A classifier label counts only when it names one of the package's
    /// folders.
    public func sections(labels: [String: String], hidden: Set<String>) -> [Section] {
        var order = folders
        var groups: [String: [Post]] = [:]
        for post in posts where !hidden.contains(post.id) {
            let folder = folder(of: post, labels: labels)
            if !order.contains(folder) {
                order.append(folder)
            }
            groups[folder, default: []].append(post)
        }
        return order.compactMap { folder in
            guard let posts = groups[folder], !posts.isEmpty else {
                return nil
            }
            return Section(folder: folder, posts: posts.sorted { $0.postedAt > $1.postedAt })
        }
    }

    /// The folder a post belongs to: the classifier's label when it names a folder the digest carries,
    /// else the post's own first folder, else `Other`.
    public func folder(of post: Post, labels: [String: String]) -> String {
        if let label = labels[post.id], folders.contains(label) {
            return label
        }
        return post.folders.first ?? Self.otherFolder
    }

    /// The posts whose text or author contains the query and that are not hidden; an empty query returns
    /// every shown post.
    public func posts(matching query: String, hidden: Set<String> = []) -> [Post] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return posts.filter { !hidden.contains($0.id) }
        }
        let lowered = query.lowercased()
        return posts.filter { post in
            guard !hidden.contains(post.id) else {
                return false
            }
            let text = post.text?.lowercased().contains(lowered) ?? false
            return text
                || post.author.name.lowercased().contains(lowered)
                || post.author.handle.lowercased().contains(lowered)
        }
    }
}

/// One digest unpacked on this device: the package and the folder its media and model were written to.
public struct Digest: Identifiable, Equatable, Sendable {
    public let package: DigestPackage
    public let folder: URL

    public var id: String {
        package.id
    }

    public init(package: DigestPackage, folder: URL) {
        self.package = package
        self.folder = folder
    }

    /// The file a package path names inside this digest's folder.
    public func url(of path: String) -> URL {
        folder.appending(path: path)
    }
}

/// What this device has taken in of the digests in the FNMN folder, and the posts it has read or hidden.
public struct DigestIndex: Codable, Equatable, Sendable {
    public var imported: [Imported]
    public var seen: Set<String>
    public var hidden: Set<String>

    public init(imported: [Imported] = [], seen: Set<String> = [], hidden: Set<String> = []) {
        self.imported = imported
        self.seen = seen
        self.hidden = hidden
    }

    /// The delivery file's name leads, since a listing knows the file before it reads the id inside.
    public struct Imported: Codable, Equatable, Sendable {
        public let file: String
        public let id: String
        public let at: Date

        public init(file: String, id: String, at: Date) {
            self.file = file
            self.id = id
            self.at = at
        }
    }
}

/// One thing the reader did with a post, written for the Mac's next training. The text stays on the Mac,
/// joined by the post id.
public struct DigestEngagement: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case opened, saved, hidden
    }

    public let at: Date
    public let kind: Kind
    public let postID: String
    public let digestID: String

    public init(at: Date = .now, kind: Kind, postID: String, digestID: String) {
        self.at = at
        self.kind = kind
        self.postID = postID
        self.digestID = digestID
    }
}
