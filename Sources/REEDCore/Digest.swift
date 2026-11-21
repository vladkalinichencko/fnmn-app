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
        public let attachments: [Attachment]
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
            attachments: [Attachment] = [],
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
            self.attachments = attachments
            self.context = context
            self.comments = comments
            self.stats = stats
            self.folders = folders
            self.mediaErrors = mediaErrors
        }

        private enum CodingKeys: String, CodingKey {
            case id, network, author, permalink, postedAt, text, attachments
            case context, comments, stats, folders, mediaErrors
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            network = try container.decode(Network.self, forKey: .network)
            author = try container.decode(Author.self, forKey: .author)
            permalink = try container.decode(URL.self, forKey: .permalink)
            postedAt = try container.decode(Date.self, forKey: .postedAt)
            text = try container.decodeIfPresent(String.self, forKey: .text)
            attachments = try container.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
            context = try container.decodeIfPresent(Context.self, forKey: .context)
            comments = try container.decodeIfPresent([Comment].self, forKey: .comments) ?? []
            stats = try container.decodeIfPresent(Stats.self, forKey: .stats)
            folders = try container.decodeIfPresent([String].self, forKey: .folders) ?? []
            mediaErrors = try container.decodeIfPresent(Int.self, forKey: .mediaErrors)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(network, forKey: .network)
            try container.encode(author, forKey: .author)
            try container.encode(permalink, forKey: .permalink)
            try container.encode(postedAt, forKey: .postedAt)
            try container.encodeIfPresent(text, forKey: .text)
            try container.encode(attachments, forKey: .attachments)
            try container.encodeIfPresent(context, forKey: .context)
            try container.encode(comments, forKey: .comments)
            try container.encodeIfPresent(stats, forKey: .stats)
            try container.encode(folders, forKey: .folders)
            try container.encodeIfPresent(mediaErrors, forKey: .mediaErrors)
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

        public struct Card: Equatable, Sendable {
            public let title: String?
            public let description: String?
            public let domain: String?
            public let url: URL?
            public let image: Media?

            public init(title: String? = nil, description: String? = nil, domain: String? = nil, url: URL? = nil, image: Media? = nil) {
                self.title = title
                self.description = description
                self.domain = domain
                self.url = url
                self.image = image
            }
        }

        public enum Attachment: Equatable, Sendable {
            case image(Media)
            case video(Video)
            case card(Card)

            public enum Kind: String, Codable, Sendable {
                case image, video, card
            }

            public var image: Media? {
                if case .image(let media) = self {
                    return media
                }
                return nil
            }

            public var video: Video? {
                if case .video(let video) = self {
                    return video
                }
                return nil
            }

            public var card: Card? {
                if case .card(let card) = self {
                    return card
                }
                return nil
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
            public let attachments: [Attachment]
            public let stats: Stats?

            public init(
                id: String,
                network: Network,
                author: Author,
                permalink: URL,
                postedAt: Date,
                text: String? = nil,
                attachments: [Attachment] = [],
                stats: Stats? = nil
            ) {
                self.id = id
                self.network = network
                self.author = author
                self.permalink = permalink
                self.postedAt = postedAt
                self.text = text
                self.attachments = attachments
                self.stats = stats
            }

            private enum CodingKeys: String, CodingKey {
                case id, network, author, permalink, postedAt, text, attachments, stats
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                id = try container.decode(String.self, forKey: .id)
                network = try container.decode(Network.self, forKey: .network)
                author = try container.decode(Author.self, forKey: .author)
                permalink = try container.decode(URL.self, forKey: .permalink)
                postedAt = try container.decode(Date.self, forKey: .postedAt)
                text = try container.decodeIfPresent(String.self, forKey: .text)
                attachments = try container.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
                stats = try container.decodeIfPresent(Stats.self, forKey: .stats)
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(id, forKey: .id)
                try container.encode(network, forKey: .network)
                try container.encode(author, forKey: .author)
                try container.encode(permalink, forKey: .permalink)
                try container.encode(postedAt, forKey: .postedAt)
                try container.encodeIfPresent(text, forKey: .text)
                try container.encode(attachments, forKey: .attachments)
                try container.encodeIfPresent(stats, forKey: .stats)
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

    public func sections() -> [NetworkSection] {
        return Self.networkOrder.compactMap { network in
            let own = posts.filter { $0.network == network }
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

    public func posts(matching query: String) -> [Post] {
        let query = query
        guard query.contains(where: { !$0.isWhitespace }) else {
            return posts
        }
        let folded = TextFold.folded(query)
        return posts.filter { post in
            post.searchTexts.contains { TextFold.folded($0).contains(folded) }
        }
    }
}

extension DigestPackage.Post.Card: Codable {
    private enum CodingKeys: String, CodingKey {
        case title, description, domain, url, image
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        domain = try container.decodeIfPresent(String.self, forKey: .domain)
        let raw = try container.decodeIfPresent(String.self, forKey: .url)
        url = raw.flatMap(URL.init(string:))
        image = try container.decodeIfPresent(DigestPackage.Post.Media.self, forKey: .image)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(domain, forKey: .domain)
        try container.encodeIfPresent(url?.absoluteString, forKey: .url)
        try container.encodeIfPresent(image, forKey: .image)
    }
}

extension DigestPackage.Post.Attachment: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, path, width, height, poster, file, title, description, domain, url, image
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .image:
            self = .image(try DigestPackage.Post.Media(from: decoder))
        case .video:
            self = .video(try DigestPackage.Post.Video(from: decoder))
        case .card:
            self = .card(try DigestPackage.Post.Card(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .image(let media):
            try container.encode(Kind.image, forKey: .kind)
            try container.encode(media.path, forKey: .path)
            try container.encode(media.width, forKey: .width)
            try container.encode(media.height, forKey: .height)
        case .video(let video):
            try container.encode(Kind.video, forKey: .kind)
            try container.encodeIfPresent(video.poster, forKey: .poster)
            try container.encodeIfPresent(video.file, forKey: .file)
        case .card(let card):
            try container.encode(Kind.card, forKey: .kind)
            try container.encodeIfPresent(card.title, forKey: .title)
            try container.encodeIfPresent(card.description, forKey: .description)
            try container.encodeIfPresent(card.domain, forKey: .domain)
            try container.encodeIfPresent(card.url?.absoluteString, forKey: .url)
            try container.encodeIfPresent(card.image, forKey: .image)
        }
    }
}

extension DigestPackage.Post {
    public var searchTexts: [String] {
        var texts = [text ?? "", author.name, "@\(author.handle)"]
        texts += attachments.compactMap { attachment -> String? in
            guard case .card(let card) = attachment else {
                return nil
            }
            return [card.title, card.description, card.domain, card.url?.host()].compactMap { $0 }.joined(separator: " ")
        }
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
    public var folded: Set<DigestFold>

    public init(imported: [Imported] = [], folded: Set<DigestFold> = []) {
        self.imported = imported
        self.folded = folded
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        imported = try container.decodeIfPresent([Imported].self, forKey: .imported) ?? []
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


