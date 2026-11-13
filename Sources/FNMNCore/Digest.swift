import Foundation

public struct DigestPackage: Codable, Equatable, Sendable {
    public static let supportedSchema = 1

    public let schema: Int
    public let id: String
    public let window: Window
    public let folders: [String]
    public let sources: [Source]
    public let posts: [Post]

    public init(
        schema: Int = 1,
        id: String,
        window: Window,
        folders: [String] = [],
        sources: [Source] = [],
        posts: [Post] = []
    ) {
        self.schema = schema
        self.id = id
        self.window = window
        self.folders = folders
        self.sources = sources
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

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            network = try container.decode(Network.self, forKey: .network)
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? id
            folders = try container.decodeIfPresent([String].self, forKey: .folders) ?? []
            status = try container.decode(Status.self, forKey: .status)
            detail = try container.decodeIfPresent(String.self, forKey: .detail)
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
            public let file: File?

            public init(poster: Media? = nil, file: File? = nil) {
                self.poster = poster
                self.file = file
            }

            public struct File: Codable, Equatable, Sendable {
                public let path: String

                public init(path: String) {
                    self.path = path
                }
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

    public struct NetworkSection: Equatable, Identifiable, Sendable {
        public let network: Network
        public let topics: [TopicSection]

        public var id: Network {
            network
        }

        public init(network: Network, topics: [TopicSection]) {
            self.network = network
            self.topics = topics
        }
    }

    public struct TopicSection: Equatable, Identifiable, Sendable {
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
    public static let networkOrder: [Network] = [.telegram, .x, .instagram]

    public func sections(hidden: Set<String>) -> [NetworkSection] {
        let visible = posts.filter { !hidden.contains($0.id) }
        return Self.networkOrder.compactMap { network in
            let own = visible.filter { $0.network == network }
            guard !own.isEmpty else {
                return nil
            }
            let topics = OrderedGroups.of(own, startingWith: folders) { post in
                let folder = folder(of: post)
                return (folder, folder)
            }
            .map { group in
                TopicSection(folder: group.key, posts: group.items.sorted { $0.postedAt > $1.postedAt })
            }
            return NetworkSection(network: network, topics: topics)
        }
    }

    public func folder(of post: Post) -> String {
        post.folders.first ?? Self.otherFolder
    }

    public func posts(matching query: String, hidden: Set<String> = []) -> [Post] {
        let query = query
        guard query.contains(where: { !$0.isWhitespace }) else {
            return posts.filter { !hidden.contains($0.id) }
        }
        let folded = TextFold.folded(query)
        return posts.filter { post in
            guard !hidden.contains(post.id) else {
                return false
            }
            return post.searchTexts.contains { TextFold.folded($0).contains(folded) }
        }
    }
}

extension DigestPackage.Post {
    public var searchTexts: [String] {
        var texts = [text ?? "", author.name, "@\(author.handle)"]
        if let quoted = context?.post {
            texts += [quoted.author.name, "@\(quoted.author.handle)", quoted.text ?? ""]
        }
        texts += comments.map { "\($0.author) \($0.handle ?? ""): \($0.text)" }
        return texts
    }

    public func excerpt(matching query: String) -> SearchExcerpt? {
        let needle = query
        guard needle.contains(where: { !$0.isWhitespace }) else {
            return nil
        }
        for text in searchTexts where !text.isEmpty {
            guard TextFold.folded(text).contains(TextFold.folded(needle)),
                  let span = ReadingSearch.spans(of: needle, in: text).first else {
                continue
            }
            return SearchExcerpt.around(text, span: span)
        }
        return nil
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
    public var folded: Set<DigestFold>

    public init(imported: [Imported] = [], hidden: Set<String> = [], folded: Set<DigestFold> = []) {
        self.imported = imported
        self.hidden = hidden
        self.folded = folded
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        imported = try container.decodeIfPresent([Imported].self, forKey: .imported) ?? []
        hidden = try container.decodeIfPresent(Set<String>.self, forKey: .hidden) ?? []
        folded = try container.decodeIfPresent(Set<DigestFold>.self, forKey: .folded) ?? []
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


