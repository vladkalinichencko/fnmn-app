import FNMNCore
import SwiftUI

struct VideoCue: Identifiable, Equatable {
    let id: String
    let startSeconds: Double
    let text: String
}

enum EmbedPhase: Equatable {
    case loading
    case ready
    case failed(String)
}

/// What plays a video: the file on this device, a file the library lists that this device still has to take from
/// iCloud, or YouTube when there is no file.
enum VideoSource: Equatable {
    case local(URL)
    case coming(URL)
    case embed

    /// The file is only a file this device plays once it is on the device: iCloud lists a name before the bytes come
    /// down, and the system may let the bytes go again.
    static func of(original: URL?, downloaded: URL?, onDevice: (URL) -> Bool) -> VideoSource {
        guard let original else {
            return .embed
        }
        guard downloaded == original, onDevice(original) else {
            return .coming(original)
        }
        return .local(original)
    }
}

extension EmbedPhase {
    /// A seek belongs to a player that is coming up; a page that failed has nothing to seek in, so the seek is not
    /// kept to be applied later on a page that has moved on.
    var keepsSeek: Bool {
        if case .failed = self {
            return false
        }
        return true
    }
}

/// What the video screen shows: the line being spoken, where the transcript is scrolled, whether it follows
/// the video, a seek the player still has to make, the embedded player's phase and whether captions show.
/// The playing second is not here: it changes twice a second, and nothing on screen draws it.
struct VideoState: Equatable {
    var activeIndex: Int
    var pinnedCue: String?
    var followsCaptions = true
    var seekTo: Double?
    var embed = EmbedPhase.loading
    var showsCaptions = true
}

enum VideoAction {
    /// The player reached this second.
    case played(Double)
    case paused
    /// A line of the transcript was tapped.
    case jumped(toCue: Int)
    case seekDone
    /// The person scrolls the transcript by hand.
    case scrolledByHand
    case resumeFollowing
    /// The transcript's scroll view settled on this line.
    case pinned(String?)
    case embed(EmbedPhase)
    case showCaptions(Bool)
    /// The screen closed or the app left the foreground.
    case left
}

private extension VideoAction {
    /// The video reached another line, or a line was tapped.
    var movesTheLine: Bool {
        switch self {
        case .played, .jumped: true
        default: false
        }
    }
}

/// Pure: the next screen state for an action, given the transcript's lines in time order.
func videoReduce(_ state: VideoState, _ action: VideoAction, cues: [VideoCue]) -> VideoState {
    var state = state
    switch action {
    case let .played(seconds):
        let index = activeCue(in: cues, at: seconds)
        guard index != state.activeIndex else { return state }
        state.activeIndex = index
        if state.followsCaptions, cues.indices.contains(index) { state.pinnedCue = cues[index].id }
    case let .jumped(index):
        state.activeIndex = index
        state.seekTo = cues[index].startSeconds
        state.followsCaptions = true
        state.pinnedCue = cues[index].id
    case .seekDone:
        state.seekTo = nil
    case .scrolledByHand:
        state.followsCaptions = false
    case .resumeFollowing:
        state.followsCaptions = true
    case let .pinned(id):
        state.pinnedCue = id
    case let .embed(phase):
        state.embed = phase
        if !phase.keepsSeek {
            state.seekTo = nil
        }
    case let .showCaptions(shows):
        state.showsCaptions = shows
    case .paused:
        break
    case .left:
        state.seekTo = nil
    }
    return state
}

/// The last line that starts at or before the second, or the first line.
func activeCue(in cues: [VideoCue], at seconds: Double) -> Int {
    var low = 0
    var high = cues.count
    while low < high {
        let middle = (low + high) / 2
        if cues[middle].startSeconds <= seconds + 0.05 { low = middle + 1 } else { high = middle }
    }
    return max(low - 1, 0)
}

/// The one owner of an open video's screen. Views read `state` and `send` actions; effects start here:
/// saving the exact second on pause, jump, leaving and every two seconds while playing, and the timer that
/// lets the transcript follow the video again five seconds after a hand scroll.
@MainActor @Observable
final class VideoCoordinator {
    let package: ImportPackage
    let cues: [VideoCue]
    /// The saved second the video opened at.
    let start: Double
    private(set) var state: VideoState
    @ObservationIgnored private let library: LibraryModel
    @ObservationIgnored private var seconds: Double
    @ObservationIgnored private var savedSeconds: Double
    @ObservationIgnored private var savedAt = Date.distantPast
    @ObservationIgnored private var resumeFollowing: Task<Void, Never>?

    init(package: ImportPackage, library: LibraryModel) {
        self.package = package
        self.library = library
        cues = package.blocks.compactMap { block in
            guard block.kind == .transcript, let start = block.startSeconds else { return nil }
            let text = block.html.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return VideoCue(id: block.id, startSeconds: start, text: text)
        }
        start = library.position(of: package.material.id)?.videoSeconds ?? 0
        seconds = start
        savedSeconds = start
        let index = activeCue(in: cues, at: start)
        state = VideoState(activeIndex: index, pinnedCue: cues.indices.contains(index) ? cues[index].id : nil)
    }

    func send(_ action: VideoAction) {
        let next = videoReduce(state, action, cues: cues)
        if next != state {
            if action.movesTheLine {
                // The plate, the line colors and the scroll to the line all move in one animation, so the plate
                // glides with the transcript instead of the transcript jumping under a plate that slides alone.
                withAnimation(Self.follow) { state = next }
            } else {
                state = next
            }
        }
        perform(action)
    }

    private static let follow = Animation.snappy(duration: 0.3)

    func binding<Value>(_ value: KeyPath<VideoState, Value>, send action: @escaping (Value) -> VideoAction) -> Binding<Value> {
        Binding(get: { self.state[keyPath: value] }, set: { self.send(action($0)) })
    }

    private func perform(_ action: VideoAction) {
        switch action {
        case let .played(second):
            seconds = second
            save(force: false)
        case let .jumped(index):
            seconds = cues[index].startSeconds
            save(force: true)
        case .paused:
            save(force: true)
        case .scrolledByHand:
            resumeFollowing?.cancel()
            resumeFollowing = Task {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                send(.resumeFollowing)
            }
        case .left:
            resumeFollowing?.cancel()
            save(force: true)
            Task { await library.saveProgress() }
        case .seekDone, .resumeFollowing, .pinned, .embed, .showCaptions:
            break
        }
    }

    private func save(force: Bool) {
        guard force || Date.now.timeIntervalSince(savedAt) >= 2, abs(seconds - savedSeconds) > 0.01 else { return }
        savedAt = .now
        savedSeconds = seconds
        let blockID = package.blocks.first { $0.kind == .video }?.id ?? package.material.id
        let progress = cues.isEmpty ? 0 : Double(state.activeIndex + 1) / Double(cues.count)
        library.apply(.savePosition(ReadingPosition(blockID: blockID, videoSeconds: seconds), itemID: package.material.id, progress: progress))
    }
}
