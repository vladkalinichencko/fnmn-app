import Foundation
import Testing
@testable import FNMNCore

@Test func aYouTubeAddressPlaysThroughTheEmbed() {
    let embed = URL(string: "https://www.youtube.com/embed/abcdefghijk")!
    #expect(VideoPlayback.of(mediaURL: embed, sourceURL: nil) == .youTube("abcdefghijk"))
    #expect(VideoPlayback.of(mediaURL: nil, sourceURL: URL(string: "https://youtu.be/abcdefghijk")!) == .youTube("abcdefghijk"))
}

@Test func aDirectStreamAddressPlaysInTheSystemPlayer() {
    let stream = URL(string: "https://video.twimg.com/amplify_video/1/pl/x.m3u8?v=1")!
    #expect(VideoPlayback.of(mediaURL: stream, sourceURL: URL(string: "https://x.com/a/status/1")) == .stream(stream))
}

@Test func aVideoWithoutAnyPlayableAddressIsUnavailable() {
    #expect(VideoPlayback.of(mediaURL: nil, sourceURL: URL(string: "https://x.com/a/status/1")) == .unavailable)
    #expect(VideoPlayback.of(mediaURL: nil, sourceURL: nil) == .unavailable)
}
