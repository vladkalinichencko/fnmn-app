import SwiftUI
import Textual

extension View {
    func plateMarkdownStyles() -> some View {
        textual.tableStyle(HairlineTable())
            .textual.blockQuoteStyle(BarQuote())
            .textual.codeBlockStyle(PlateCode())
    }
}

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
        .background(Color.primary.opacity(0.05), in: shape)
        .clipShape(shape)
        .textual.blockSpacing(.fontScaled(top: 0.88, bottom: 0))
    }
}
