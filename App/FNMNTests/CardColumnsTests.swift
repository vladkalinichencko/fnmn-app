import SwiftUI
import XCTest
@testable import FNMN

final class CardColumnsTests: XCTestCase {
    private struct Card: Identifiable {
        let id: Int
        let height: Double
    }

    func testColumnCountFollowsTheIdealWidth() {
        XCTAssertEqual(CardColumns<Card, EmptyView>.columns(forWidth: 0, idealWidth: 170, spacing: 14), 1)
        XCTAssertEqual(CardColumns<Card, EmptyView>.columns(forWidth: 372, idealWidth: 170, spacing: 14), 2)
        XCTAssertEqual(CardColumns<Card, EmptyView>.columns(forWidth: 750, idealWidth: 170, spacing: 14), 4)
        XCTAssertEqual(CardColumns<Card, EmptyView>.columns(forWidth: 372, idealWidth: 330, spacing: 14), 1)
        XCTAssertEqual(CardColumns<Card, EmptyView>.columns(forWidth: 834, idealWidth: 330, spacing: 14), 2)
    }

    func testShortCardsFillTheShorterColumn() {
        let cards = [Card(id: 0, height: 300), Card(id: 1, height: 100), Card(id: 2, height: 100)]
        let columns = CardColumns<Card, EmptyView>.split(cards, into: 2, columnWidth: 300) { card, _ in card.height }
        XCTAssertEqual(columns.map { $0.map(\.id) }, [[0], [1, 2]])
    }

    func testEvenCardsDealRoundRobin() {
        let cards = (0 ..< 5).map { Card(id: $0, height: 1) }
        let columns = CardColumns<Card, EmptyView>.split(cards, into: 2, columnWidth: 300) { card, _ in card.height }
        XCTAssertEqual(columns.map { $0.map(\.id) }, [[0, 2, 4], [1, 3]])
    }
}
