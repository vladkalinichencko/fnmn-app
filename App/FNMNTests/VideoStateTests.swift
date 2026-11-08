import XCTest
@testable import FNMN

final class VideoSourceTests: XCTestCase {
    private let file = URL(fileURLWithPath: "/tmp/originals/video.mp4")

    func testAFileOnTheDevicePlays() {
        let source = VideoSource.of(original: file, downloading: nil) { _ in true }
        XCTAssertEqual(source, .local(file))
    }

    func testAFileListedOnlyByICloudComesDownFirst() {
        let source = VideoSource.of(original: file, downloading: nil) { _ in false }
        XCTAssertEqual(source, .coming(file))
    }

    func testAFileBeingFetchedIsNotPlayedYet() {
        let source = VideoSource.of(original: file, downloading: file) { _ in true }
        XCTAssertEqual(source, .coming(file))
    }

    func testAVideoWithoutAFilePlaysEmbedded() {
        XCTAssertEqual(VideoSource.of(original: nil, downloading: nil) { _ in true }, .embed)
    }
}

final class VideoStateTests: XCTestCase {
    private let cues = [
        VideoCue(id: "one", startSeconds: 0, text: "One."),
        VideoCue(id: "two", startSeconds: 30, text: "Two.")
    ]

    private var state: VideoState {
        VideoState(activeIndex: 0, pinnedCue: "one")
    }

    func testTappingALineAsksForThatSecond() {
        let next = videoReduce(state, .jumped(toCue: 1), cues: cues)
        XCTAssertEqual(next.seekTo, 30)
        XCTAssertEqual(next.activeIndex, 1)
    }

    func testAPlayerThatTookTheSeekLeavesNonePending() {
        let asked = videoReduce(state, .jumped(toCue: 1), cues: cues)
        XCTAssertNil(videoReduce(asked, .seekDone, cues: cues).seekTo)
    }

    func testAFailedPlayerDropsTheSeekInsteadOfApplyingItLater() {
        let asked = videoReduce(state, .jumped(toCue: 1), cues: cues)
        let failed = videoReduce(asked, .embed(.failed("refused")), cues: cues)
        XCTAssertNil(failed.seekTo)
        XCTAssertEqual(failed.embed, .failed("refused"))
    }

    func testAPlayerStillComingUpKeepsTheSeek() {
        let asked = videoReduce(state, .jumped(toCue: 1), cues: cues)
        XCTAssertEqual(videoReduce(asked, .embed(.loading), cues: cues).seekTo, 30)
        XCTAssertEqual(videoReduce(asked, .embed(.ready), cues: cues).seekTo, 30)
    }

    func testLeavingTheScreenDropsTheSeek() {
        let asked = videoReduce(state, .jumped(toCue: 1), cues: cues)
        XCTAssertNil(videoReduce(asked, .left, cues: cues).seekTo)
    }
}
