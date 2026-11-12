import Foundation

public struct DigestPackage: Codable, Equatable, Sendable {
    public static let supportedSchema = 1

    public let schema: Int
    public let id: String
    public let window: Window
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

    public struct Window: Codable, Equatable, Sendable {
        public let from: Date
        public let to: Date

        public init(from: Date, to: Date) {
            self.from = from
            self.to = to
        }
    }

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
        public let folders: [String]
        public let mediaErrors: Int?

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
            folders: [String] = [],
            mediaErrors: Int? = nil
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
            self.mediaErrors = mediaErrors
        }

        public struct Author: Codable, Equatable, Sendable {
            public let handle: String
            public let name: String

            public init(handle: String, name: String) {
                self.handle = handle
                self.name = name
            }
        }

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

        public struct Video: Codable, Equatable, Sendable {
            public let poster: Media?
            public let duration: Double?

            public init(poster: Media? = nil, duration: Double? = nil) {
                self.poster = poster
                self.duration = duration
            }
        }

        public struct Context: Codable, Equatable, Sendable {
            public let kind: Kind
            public let post: ContextPost?

            public init(kind: Kind, post: ContextPost? = nil) {
                self.kind = kind
                self.post = post
            }

            public enum Kind: String, Codable, CaseIterable, Sendable {
                case quote, reply, repost

                public var action: String {
                    switch self {
                    case .quote: "Quoting"
                    case .reply: "Replying to"
                    case .repost: "Reposting"
                    }
                }
            }
        }

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
            public let handle: String?
            public let avatar: Media?
            public let text: String
            public let permalink: URL?

            public init(author: String, handle: String? = nil, avatar: Media? = nil, text: String, permalink: URL? = nil) {
                self.author = author
                self.handle = handle
                self.avatar = avatar
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

    public func sections(labels: [String: String], hidden: Set<String>) -> [Section] {
        OrderedGroups.of(posts.filter { !hidden.contains($0.id) }, startingWith: folders) { post in
            let folder = folder(of: post, labels: labels)
            return (folder, folder)
        }
        .map { group in
            Section(folder: group.key, posts: group.items.sorted { $0.postedAt > $1.postedAt })
        }
    }

    public func folder(of post: Post, labels: [String: String]) -> String {
        if let label = labels[post.id], folders.contains(label) {
            return label
        }
        return post.folders.first ?? Self.otherFolder
    }

    public func posts(matching query: String, hidden: Set<String> = []) -> [Post] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return posts.filter { !hidden.contains($0.id) }
        }
        let folded = TextFold.folded(query)
        return posts.filter { post in
            guard !hidden.contains(post.id) else {
                return false
            }
            let fields = [post.text ?? "", post.author.name, post.author.handle]
            return fields.contains { TextFold.folded($0).contains(folded) }
        }
    }
}

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

    public func url(of path: String) -> URL {
        folder.appending(path: path)
    }
}

public struct DigestIndex: Codable, Equatable, Sendable {
    public var imported: [Imported]
    public var hidden: Set<String>

    public init(imported: [Imported] = [], hidden: Set<String> = []) {
        self.imported = imported
        self.hidden = hidden
    }

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
