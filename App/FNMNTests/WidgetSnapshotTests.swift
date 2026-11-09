import FNMNCore
import XCTest
@testable import FNMN

final class WidgetSnapshotTests: XCTestCase {
    private func item(_ id: String, piece: Int?) -> WidgetItem {
        WidgetItem(id: id, title: id, source: "Source", progress: 0.4, piece: piece, cover: nil, kind: "article")
    }

    func testTheSpareStandsForHalfADayAndThenAnotherTakesItsPlace() {
        let snapshot = WidgetSnapshot(items: [], spares: [item("a", piece: 1), item("b", piece: 2), item("c", piece: 3)], digest: nil)
        let morning = Date(timeIntervalSince1970: 0)
        let later = morning.addingTimeInterval(3_600)
        let tomorrow = morning.addingTimeInterval(43_200 * 2)

        XCTAssertEqual(snapshot.spare(at: morning)?.id, snapshot.spare(at: later)?.id)
        XCTAssertEqual(Set([snapshot.spare(at: morning)?.id, snapshot.spare(at: tomorrow)?.id]).count, 2)
        XCTAssertNil(WidgetSnapshot().spare(at: morning))
    }

    func testAWidgetItemOpensTheMaterialAtItsPlate() {
        let link = item("article:one", piece: 12).deepLink
        XCTAssertEqual(link.scheme, "fnmn")
        XCTAssertEqual(link.host, "item")
        let components = URLComponents(url: link, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.queryItems?.first { $0.name == "id" }?.value, "article:one")
        XCTAssertEqual(components?.queryItems?.first { $0.name == "piece" }?.value, "12")
        XCTAssertEqual(item("video:one", piece: nil).deepLink.absoluteString, "fnmn://item?id=video:one")
    }

    func testASnapshotIsWrittenAndReadBack() throws {
        try XCTSkipIf(WidgetStore.container == nil, "no app group container here")
        let snapshot = WidgetSnapshot(items: [item("a", piece: 3)], spares: [], digest: nil, generatedAt: Date(timeIntervalSince1970: 100))
        WidgetStore.write(snapshot)
        XCTAssertEqual(WidgetStore.read(), snapshot)
    }
}
