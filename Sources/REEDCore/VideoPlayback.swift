import Foundation

public enum VideoPlayback: Equatable {
    case youTube(String)
    case stream(URL)
    case unavailable

    public static func of(mediaURL: URL?, sourceURL: URL?) -> VideoPlayback {
        for url in [mediaURL, sourceURL].compactMap({ $0 }) {
            if let id = YouTube.videoID(in: url) {
                return .youTube(id)
            }
        }
        if let mediaURL {
            return .stream(mediaURL)
        }
        return .unavailable
    }
}
