import Foundation

public enum CaptureHandoff {
    public static func link(for shared: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "reed"
        components.host = "add"
        components.queryItems = [URLQueryItem(name: "url", value: shared.absoluteString)]
        return components.url
    }

    public static func sharedURL(from handoff: URL) -> URL? {
        guard handoff.scheme == "reed", handoff.host == "add" else {
            return nil
        }
        guard let components = URLComponents(url: handoff, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let shared = URL(string: value),
              let scheme = shared.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return shared
    }
}
