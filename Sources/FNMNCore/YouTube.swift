import CryptoKit
import Foundation

public struct YouTubeCue: Equatable, Sendable {
    public var startSeconds: Double
    public var text: String

    public init(startSeconds: Double, text: String) {
        self.startSeconds = startSeconds
        self.text = text
    }
}

public struct YouTubeWatch: Equatable, Sendable {
    public var title: String?
    public var author: String?
    public var captionBaseURL: String?
}

public enum YouTube {
    public static func videoID(in url: URL) -> String? {
        let host = (url.host ?? "").lowercased()
        if host == "youtu.be" {
            let candidate = url.path.split(separator: "/").first.map(String.init) ?? ""
            return isVideoID(candidate) ? candidate : nil
        }
        guard host == "youtube.com" || host.hasSuffix(".youtube.com") else { return nil }
        if let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let value = query.first(where: { $0.name == "v" })?.value,
           isVideoID(value) {
            return value
        }
        let parts = url.path.split(separator: "/").map(String.init)
        if parts.count >= 2, ["embed", "shorts", "live", "v"].contains(parts[0]), isVideoID(parts[1]) {
            return parts[1]
        }
        return nil
    }

    public static func oembed(in json: String) -> (title: String?, author: String?) {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil)
        }
        return (nonEmpty(object["title"]), nonEmpty(object["author_name"]))
    }

    public static func watch(in page: String) -> YouTubeWatch {
        guard let object = playerResponse(in: page) else { return YouTubeWatch(title: nil, author: nil, captionBaseURL: nil) }
        let details = object["videoDetails"] as? [String: Any]
        let tracks = ((object["captions"] as? [String: Any])?["playerCaptionsTracklistRenderer"] as? [String: Any])?["captionTracks"] as? [[String: Any]] ?? []
        return YouTubeWatch(
            title: nonEmpty(details?["title"]),
            author: nonEmpty(details?["author"]),
            captionBaseURL: preferredTrack(tracks)?["baseUrl"] as? String
        )
    }

    public static func cues(inTimedText payload: String) -> [YouTubeCue] {
        let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return [] }
        if text.hasPrefix("{") { return cues(inJSON3: text) }
        if text.hasPrefix("WEBVTT") { return cues(inVTT: text) }
        if text.hasPrefix("<") { return cues(inXML: text) }
        return []
    }

    public static func package(videoID: String, sourceURL: URL, title: String, author: String?, cues: [YouTubeCue]) -> ImportPackage {
        let materialID = "youtube:\(videoID)"
        let sectionID = stableID("section", "\(materialID):video")
        let videoBlockID = stableID("block", "\(materialID):video")
        var blocks = [
            Block(
                id: videoBlockID,
                sectionID: sectionID,
                kind: .video,
                html: title,
                mediaURL: URL(string: "https://www.youtube.com/embed/\(videoID)"),
                startSeconds: 0
            )
        ]
        var paragraphs: [String] = []
        for (index, cue) in cues.enumerated() {
            let blockID = stableID("block", "\(materialID):cue:\(index):\(cue.startSeconds):\(cue.text)")
            blocks.append(
                Block(
                    id: blockID,
                    sectionID: sectionID,
                    kind: .transcript,
                    html: cue.text,
                    startSeconds: cue.startSeconds
                )
            )
            paragraphs.append(cue.text)
        }
        return ImportPackage(
            material: Material(
                id: materialID,
                kind: .video,
                title: title,
                sourceURL: sourceURL,
                byline: author
            ),
            sections: [
                Section(id: sectionID, parentID: nil, title: title, level: 1, firstBlockID: videoBlockID)
            ],
            blocks: blocks,
            body: paragraphs.joined(separator: "\n\n")
        )
    }

    private static func isVideoID(_ value: String) -> Bool {
        value.count == 11 && value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func stableID(_ prefix: String, _ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(prefix):\(hex.prefix(24))"
    }

    private static func playerResponse(in page: String) -> [String: Any]? {
        guard let marker = page.range(of: "ytInitialPlayerResponse") else { return nil }
        guard let brace = page[marker.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var end = brace
        for index in page[brace...].indices {
            let character = page[index]
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 {
                    end = index
                    break
                }
            }
        }
        guard depth == 0 else { return nil }
        let slice = page[brace...end]
        guard let data = String(slice).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    private static func preferredTrack(_ tracks: [[String: Any]]) -> [String: Any]? {
        tracks.min { lhs, rhs in
            score(lhs) < score(rhs)
        }
    }

    private static func score(_ track: [String: Any]) -> (Int, Int, String) {
        let language = ((track["languageCode"] as? String) ?? "").lowercased()
        let automatic = (track["kind"] as? String) == "asr" ? 1 : 0
        let english = language.hasPrefix("en") ? 0 : 1
        return (automatic, english, language)
    }

    private static func cues(inJSON3 payload: String) -> [YouTubeCue] {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = object["events"] as? [[String: Any]] else { return [] }
        return events.compactMap { event in
            guard let start = event["tStartMs"] as? Double ?? (event["tStartMs"] as? Int).map(Double.init) else { return nil }
            let segments = event["segs"] as? [[String: Any]] ?? []
            let text = clean(segments.compactMap { $0["utf8"] as? String }.joined())
            guard !text.isEmpty else { return nil }
            return YouTubeCue(startSeconds: start / 1000, text: text)
        }
    }

    private static func cues(inVTT payload: String) -> [YouTubeCue] {
        payload.components(separatedBy: "\n\n").compactMap { block in
            let lines = block.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard let timing = lines.first(where: { $0.contains("-->") }) else { return nil }
            let start = timing.split(separator: "-").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
            let text = clean(lines.filter { $0 != timing && Int($0) == nil }.joined(separator: " "))
            guard !text.isEmpty else { return nil }
            return YouTubeCue(startSeconds: vttSeconds(start), text: text)
        }
    }

    private static func vttSeconds(_ stamp: String) -> Double {
        let parts = stamp.replacingOccurrences(of: ",", with: ".").split(separator: ":").compactMap { Double($0) }
        let padded = Array(repeating: 0.0, count: max(0, 3 - parts.count)) + parts
        let hours = padded[padded.count - 3]
        let minutes = padded[padded.count - 2]
        let seconds = padded[padded.count - 1]
        return hours * 3600 + minutes * 60 + seconds
    }

    private static func cues(inXML payload: String) -> [YouTubeCue] {
        let parser = XMLCueParser()
        let xml = XMLParser(data: Data(payload.utf8))
        xml.delegate = parser
        xml.parse()
        return parser.cues
    }

    private static func clean(_ text: String) -> String {
        let stripped = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return stripped
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

private final class XMLCueParser: NSObject, XMLParserDelegate {
    var cues: [YouTubeCue] = []
    private var start: Double?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        let name = elementName.lowercased()
        guard name == "text" || name == "p" else { return }
        text = ""
        start = seconds(attributes)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard start != nil else { return }
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        guard name == "text" || name == "p", let start else { return }
        let cue = text.replacingOccurrences(of: "\n", with: " ").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        if !cue.isEmpty {
            cues.append(YouTubeCue(startSeconds: start, text: cue))
        }
        self.start = nil
        text = ""
    }

    private func seconds(_ attributes: [String: String]) -> Double? {
        if let start = attributes["start"], let value = Double(start) { return value }
        guard let raw = attributes["t"], let value = Double(raw) else { return nil }
        if !raw.contains("."), value > 1000 { return value / 1000 }
        return value
    }
}
