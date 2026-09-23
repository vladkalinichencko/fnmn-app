import Foundation

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

    private static func isVideoID(_ value: String) -> Bool {
        value.count == 11 && value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
    }
}
