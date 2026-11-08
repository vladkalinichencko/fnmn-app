import XCTest
@testable import FNMN

final class ImportJobTests: XCTestCase {
    private let id = UUID()
    private let url = URL(string: "https://example.com/a")!

    func testALinkStartsOnATileAndMovesToItsCard() {
        var jobs = importReduce([], .submit(.link(url), id: id))
        XCTAssertEqual(jobs.first?.phase, .preparing(.sending, on: .tile))
        XCTAssertNil(jobs.first?.itemID)

        jobs = importReduce(jobs, .placed(id, itemID: "link:x"))
        XCTAssertEqual(jobs.first?.phase, .preparing(.sending, on: .card("link:x")))
        XCTAssertEqual(jobs.first?.itemID, "link:x")
    }

    func testAJobThatFailedCannotBePlacedOnACard() {
        var jobs = importReduce([], .submit(.link(url), id: id))
        jobs = importReduce(jobs, .failed(id, "no server"))
        XCTAssertEqual(jobs.first?.phase, .failed("no server", on: .tile))

        jobs = importReduce(jobs, .placed(id, itemID: "link:x"))
        XCTAssertEqual(jobs.first?.phase, .failed("no server", on: .tile))
        XCTAssertNil(jobs.first?.itemID)
    }

    func testRetryKeepsThePlaceAndStartsAtTheFirstStep() {
        var jobs = importReduce([], .submit(.link(url), id: id))
        jobs = importReduce(jobs, .placed(id, itemID: "link:x"))
        jobs = importReduce(jobs, .failed(id, "no server"))
        jobs = importReduce(jobs, .retry(id))
        XCTAssertEqual(jobs.first?.phase, .preparing(.sending, on: .card("link:x")))
    }

    func testFinishedRemovesOnlyAJobStillPreparing() {
        var jobs = importReduce([], .submit(.link(url), id: id))
        jobs = importReduce(jobs, .failed(id, "no server"))
        XCTAssertEqual(importReduce(jobs, .finished(id)).count, 1)

        let preparing = importReduce([], .submit(.link(url), id: id))
        XCTAssertTrue(importReduce(preparing, .finished(id)).isEmpty)
    }

    func testProgressKeepsThePlaceItHas() {
        var jobs = importReduce([], .submit(.link(url), id: id))
        jobs = importReduce(jobs, .placed(id, itemID: "link:x"))
        jobs = importReduce(jobs, .progressed(id, .saving))
        XCTAssertEqual(jobs.first?.phase, .preparing(.saving, on: .card("link:x")))
    }

    func testAVideoIsOnItsCardFromTheStart() {
        let video = importReduce([], .submit(.videoFile(itemID: "video:1", url: url), id: id))
        XCTAssertEqual(video.first?.phase, .preparing(.sending, on: .card("video:1")))
    }

    func testDeletingTheCardStopsTheJob() {
        var jobs = importReduce([], .submit(.link(url), id: id))
        jobs = importReduce(jobs, .placed(id, itemID: "link:x"))
        XCTAssertTrue(importReduce(jobs, .deleted(itemID: "link:x")).isEmpty)
    }
}
