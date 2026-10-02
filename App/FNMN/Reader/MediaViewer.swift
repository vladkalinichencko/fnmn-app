import AVKit
import SwiftUI

extension EnvironmentValues {
    /// The reader's namespace a picture or video on the whole screen grows out of.
    @Entry var mediaZoom: Namespace.ID?
}

extension View {
    /// Every picture and video of the text opens the same way: a tap sends it to the reader, and the viewer grows
    /// out of this view. Over a picture inside a paragraph the text takes the tap and sends it as a link instead.
    func opensMedia(_ url: URL) -> some View {
        modifier(MediaSource(url: url))
    }
}

private struct MediaSource: ViewModifier {
    let url: URL
    @Environment(ReaderCoordinator.self) private var reader: ReaderCoordinator?
    @Environment(\.mediaZoom) private var zoom

    func body(content: Content) -> some View {
        if let reader, let zoom {
            content.contentShape(.rect).onTapGesture { reader.send(.openMedia(url)) }.matchedTransitionSource(id: url, in: zoom)
        } else {
            content
        }
    }
}

/// A picture on the whole screen, as in Photos: pinching enlarges it, a finger moves it, a double tap zooms into
/// the tapped point and back out.
struct ImageViewer: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                ZoomingImage(image: image).ignoresSafeArea()
            } else {
                Loading()
            }
        }
        .overlay(alignment: .top) {
            MediaBar(url: url) {
                if let image { UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil) }
            }
        }
        .environment(\.colorScheme, .dark)
        .task { image = await Self.load(url) }
    }

    @concurrent
    private static func load(_ url: URL) async -> UIImage? {
        if url.isFileURL { return UIImage(contentsOfFile: url.path) }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }
}

/// A video on the whole screen, playing from the start, under a bar that closes it.
struct VideoViewer: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 0) {
            MediaBar(url: url) {
                if url.isFileURL { UISaveVideoAtPathToSavedPhotosAlbum(url.path, nil, nil, nil) }
            }
            VideoPlayer(player: player)
        }
        .background(.black)
        .environment(\.colorScheme, .dark)
        .task {
            player = AVPlayer(url: url)
            player?.play()
        }
        .onDisappear { player?.pause() }
    }
}

/// Close on the left; saving to Photos and sharing on the right. Each icon is laid in a fixed square, so the glass
/// circle around it is as large as a toolbar's.
private struct MediaBar: View {
    let url: URL
    let save: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            Button { dismiss() } label: { icon("xmark") }
                .accessibilityLabel("Close")
            Spacer()
            Button(action: save) { icon("square.and.arrow.down") }
                .accessibilityLabel("Save to Photos")
            ShareLink(item: url) { icon("square.and.arrow.up") }
                .accessibilityLabel("Share")
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .padding(.horizontal, Tokens.gutter)
        .padding(.vertical, 8)
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.title2)
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
    }
}

private struct ZoomingImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ZoomingImageView {
        ZoomingImageView(image: image)
    }

    func updateUIView(_ view: ZoomingImageView, context: Context) {}
}

/// The picture fits the screen at the smallest zoom and stays in its middle while it is smaller than the screen.
final class ZoomingImageView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    /// The size the picture was last fitted to; a new size, such as a turned phone, fits it again.
    private var fitted = CGSize.zero

    init(image: UIImage) {
        super.init(frame: .zero)
        imageView.image = image
        addSubview(imageView)
        delegate = self
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != fitted { fit() }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { center() }

    /// At the smallest zoom the picture fits the screen. The largest shows it at twice its own size, and never less
    /// than four times the fit, so a small picture still enlarges like a large one.
    private func fit() {
        fitted = bounds.size
        guard let size = imageView.image?.size, size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else { return }
        zoomScale = 1
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        imageView.frame = CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
        contentSize = imageView.frame.size
        minimumZoomScale = 1
        maximumZoomScale = max(4, 2 / scale)
        center()
    }

    private func center() {
        let horizontal = max((bounds.width - contentSize.width) / 2, 0)
        let vertical = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    @objc private func toggleZoom(_ tap: UITapGestureRecognizer) {
        guard zoomScale <= minimumZoomScale else {
            setZoomScale(minimumZoomScale, animated: true)
            return
        }
        let point = tap.location(in: imageView)
        let scale = min(maximumZoomScale, 3)
        let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
        zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
    }
}
