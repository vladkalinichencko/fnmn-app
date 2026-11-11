import Foundation

struct SourceIndex {
    private struct Home {
        let path: [String]
        let ref: SourceRef
    }

    private var saved: [String: SourceRef] = [:]
    private var homes: [String: [Home]] = [:]
    private var sites: [String: SourceRef] = [:]

    init(catalog: BrowserCatalog?, declared: [PageSource] = []) {
        for source in catalog?.sources ?? [] {
            let ref = SourceRef(name: source.name, homepage: URL(string: source.url))
            for material in source.materials {
                for url in [material.url] + material.savedURLs {
                    saved[Self.key(url)] = ref
                }
            }
            if let homepage = ref.homepage {
                enter(ref, at: homepage)
            }
        }
        for page in declared {
            guard let host = page.homepage.host() else {
                continue
            }
            enter(SourceRef(name: page.name ?? Self.siteName(host), homepage: page.homepage), at: page.homepage)
        }
    }

    mutating func source(for url: URL) -> SourceRef? {
        if let known = saved[Self.key(url)] {
            return known
        }
        guard let host = url.host(), let hostKey = Self.hostKey(url) else {
            return nil
        }
        let path = Self.segments(url)
        let above = homes[hostKey]?.filter { path.starts(with: $0.path) }
        if let home = above?.max(by: { $0.path.count < $1.path.count }) {
            return home.ref
        }
        if let known = sites[hostKey] {
            return known
        }
        let ref = SourceRef(name: Self.siteName(host), homepage: URL(string: "\(url.scheme ?? "https")://\(host)"))
        sites[hostKey] = ref
        return ref
    }

    private mutating func enter(_ ref: SourceRef, at page: URL) {
        guard let host = Self.hostKey(page) else {
            return
        }
        let path = Self.segments(page)
        guard !homes[host, default: []].contains(where: { $0.path == path }) else {
            return
        }
        homes[host, default: []].append(Home(path: path, ref: ref))
    }

    private static func hostKey(_ url: URL) -> String? {
        guard let host = url.host()?.lowercased() else {
            return nil
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func segments(_ url: URL) -> [String] {
        url.pathComponents.filter { $0 != "/" }
    }

    static func siteName(_ host: String) -> String {
        let labels = host.split(separator: ".").filter { $0 != "www" }
        guard labels.count > 1 else {
            return host
        }
        if labels.suffix(2).joined(separator: ".") == "github.io" {
            return String(labels[0])
        }
        let secondLevel = ["co", "com", "org", "ac", "net"]
        if labels.count > 2, secondLevel.contains(String(labels[labels.count - 2])) {
            return String(labels[labels.count - 3])
        }
        return String(labels[labels.count - 2])
    }

    static func key(_ url: String) -> String {
        URL(string: url).map(key) ?? url
    }

    static func key(_ url: URL) -> String {
        if let video = YouTube.videoID(in: url) {
            return "youtube:\(video)"
        }
        return url.withoutFragment.absoluteString
    }
}

extension URL {
    public var withoutFragment: URL {
        guard fragment != nil, var parts = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }
        parts.fragment = nil
        return parts.url ?? self
    }
}
