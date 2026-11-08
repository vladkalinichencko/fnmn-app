enum LoadState: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}
