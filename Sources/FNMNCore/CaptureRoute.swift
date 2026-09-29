import Foundation

public enum CaptureSource: String, Codable, Equatable, Sendable {
    case web, arxiv, youtube, x, substack, chatgpt, pdf

    public var folderName: String {
        switch self {
        case .web: "Web"
        case .arxiv: "arXiv"
        case .youtube: "YouTube"
        case .x: "X"
        case .substack: "Substack"
        case .chatgpt: "ChatGPT"
        case .pdf: "PDF"
        }
    }
}

public enum CaptureRoute {
    public static func source(for url: URL) -> CaptureSource? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        let host = url.host?.lowercased() ?? ""
        guard !host.isEmpty else { return nil }
        if host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com") { return .youtube }
        if host == "arxiv.org" || host.hasSuffix(".arxiv.org") { return .arxiv }
        if host == "x.com" || host.hasSuffix(".x.com") || host == "twitter.com" || host.hasSuffix(".twitter.com") { return .x }
        if host == "substack.com" || host.hasSuffix(".substack.com") { return .substack }
        if host == "chatgpt.com" || host.hasSuffix(".chatgpt.com") || host == "chat.openai.com" { return .chatgpt }
        if url.pathExtension.lowercased() == "pdf" { return .pdf }
        return .web
    }

    /// The Mac service is reached over HTTPS; plain HTTP only on this device, for local testing.
    public static func acceptsService(_ url: URL) -> Bool {
        if url.scheme == "https" { return true }
        guard url.scheme == "http", let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}

public enum CaptureError: Error, Equatable {
    case unprepared(CaptureSource)
    case unrecognizedDocument
}

extension CaptureError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unprepared(source): "\(source.folderName) is recognized, but the Mac service does not prepare it yet."
        case .unrecognizedDocument: "Choose a prepared material (.tar) or the FNMN folder."
        }
    }
}
