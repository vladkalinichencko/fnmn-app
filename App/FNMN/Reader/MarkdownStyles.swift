import SwiftUI
import Textual

extension View {
    /// How tables, quotes and code look inside a paragraph plate.
    func plateMarkdownStyles() -> some View {
        textual.tableStyle(HairlineTable())
            .textual.blockQuoteStyle(BarQuote())
            .textual.codeBlockStyle(PlateCode())
    }
}

/// A table ruled with hairlines, the width of a list separator.
private struct HairlineTable: StructuredText.TableStyle {
    @Environment(\.pixelLength) private var line

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textual.tableCellSpacing(horizontal: line, vertical: line)
            .textual.blockSpacing(.fontScaled(top: 1.2, bottom: 1.2))
            .textual.tableOverlay { layout in
                Canvas { context, _ in
                    for divider in layout.dividers() {
                        context.fill(Path(divider), with: .color(Color(uiColor: .separator)))
                    }
                }
            }
    }
}

/// A quote marked only by a bar at its left, on the plate itself.
private struct BarQuote: StructuredText.BlockQuoteStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .textual.lineSpacing(.fontScaled(0.471))
            .padding(.leading, 14)
            .overlay(alignment: .leading) {
                Capsule().fill(.tertiary).frame(width: 3)
            }
    }
}

/// A code block whose corners share their center with the plate's, since its edge is the plate's padding in.
private struct PlateCode: StructuredText.CodeBlockStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.codeRadius, style: .continuous)
        Overflow {
            configuration.label
                .textual.lineSpacing(.fontScaled(0.39))
                .textual.fontScale(0.882)
                .fixedSize(horizontal: false, vertical: true)
                .monospaced()
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
        }
        // A shade of whatever plate it sits on, so it follows the reader's background.
        .background(Color.primary.opacity(0.05), in: shape)
        .clipShape(shape)
        .textual.blockSpacing(.fontScaled(top: 0.88, bottom: 0))
    }
}
