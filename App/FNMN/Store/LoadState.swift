/// What a screen knows of its data: nothing yet, a read running, the data, or why it failed.
enum LoadState: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}
