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

enum VideoSource: Equatable {
    case local(URL)
    case coming(URL)
    case embed

    static func of(original: URL?, downloading: URL?, onDevice: (URL) -> Bool) -> VideoSource {
        guard let original else {
            return .embed
        }
        guard downloading != original, onDevice(original) else {
            return .coming(original)
        }
        return .local(original)
    }
}

struct VideoState: Equatable {
    var activeIndex: Int
    var pinnedCue: String?
    var followsCaptions = true
    var seekTo: Double?
    var embed = EmbedPhase.loading
    var showsCaptions = true
}

enum VideoAction {
    case played(Double)
    case paused
    case jumped(toCue: Int)
    case seekDone
    case scrolledByHand
    case resumeFollowing
    case pinned(String?)
    case embed(EmbedPhase)
    case showCaptions(Bool)
    case left
}

private extension VideoAction {
    var movesTheLine: Bool {
        switch self {
        case .played, .jumped: true
        default: false
        }
    }
}

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
        if case .failed = phase {
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

func activeCue(in cues: [VideoCue], at seconds: Double) -> Int {
    var low = 0
    var high = cues.count
    while low < high {
        let middle = (low + high) / 2
        if cues[middle].startSeconds <= seconds + 0.05 { low = middle + 1 } else { high = middle }
    }
    return max(low - 1, 0)
}

@MainActor @Observable
final class VideoCoordinator {
    let package: ImportPackage
    let cues: [VideoCue]
    let start: Double
    private(set) var state: VideoState
    @ObservationIgnored private let library: LibraryModel
    @ObservationIgnored private var seconds: Double
    @ObservationIgnored private var savedSeconds: Double
    @ObservationIgnored private var savedAt = Date.distantPast
    @ObservationIgnored private var resumeFollowing: Task<Void, Never>?

    init(package: ImportPackage, library: LibraryModel, startSeconds: Double? = nil) {
        self.package = package
        self.library = library
        cues = package.blocks.compactMap { block in
            guard block.kind == .transcript, let start = block.startSeconds else { return nil }
            let text = block.html.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return VideoCue(id: block.id, startSeconds: start, text: text)
        }
        start = startSeconds ?? library.position(of: package.material.id)?.videoSeconds ?? 0
        seconds = start
        savedSeconds = start
        let index = activeCue(in: cues, at: start)
        state = VideoState(activeIndex: index, pinnedCue: cues.indices.contains(index) ? cues[index].id : nil)
    }

    func send(_ action: VideoAction) {
        let next = videoReduce(state, action, cues: cues)
        if next != state {
            if action.movesTheLine {
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
