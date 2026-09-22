import Foundation

enum YouTubeImportError: LocalizedError {
    case missingID

    var errorDescription: String? {
        "This YouTube address has no video id."
    }
}

enum YouTubeImport {
    static func package(for url: URL) async throws -> ImportPackage {
        guard let videoID = YouTube.videoID(in: url),
              let watchURL = URL(string: "https://www.youtube.com/watch?v=\(videoID)") else {
            throw YouTubeImportError.missingID
        }
        let watch = await text(from: watchURL).map(YouTube.watch(in:))
        let listed = await oembed(for: watchURL)
        let title = watch?.title ?? listed?.title ?? videoID
        let author = watch?.author ?? listed?.author
        let cues = await captions(baseURL: watch?.captionBaseURL)
        return YouTube.package(videoID: videoID, sourceURL: watchURL, title: title, author: author, cues: cues)
    }

    private static func oembed(for watchURL: URL) async -> (title: String?, author: String?)? {
        guard let url = URL(string: "https://www.youtube.com/oembed?url=\(watchURL.absoluteString)&format=json"),
              let json = await text(from: url) else { return nil }
        return YouTube.oembed(in: json)
    }

    private static func captions(baseURL: String?) async -> [YouTubeCue] {
        guard let baseURL else { return [] }
        for suffix in ["&fmt=json3", "&fmt=srv3", ""] {
            guard let url = URL(string: baseURL + suffix), let payload = await text(from: url) else { continue }
            let cues = YouTube.cues(inTimedText: payload)
            if !cues.isEmpty { return cues }
        }
        return []
    }

    private static func text(from url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.setValue("FNMN/1.0 article reader", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
