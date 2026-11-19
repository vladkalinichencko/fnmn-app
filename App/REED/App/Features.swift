enum Features {
    static let videoDownload: Bool = {
        #if DEBUG
        true
        #else
        false
        #endif
    }()
}
