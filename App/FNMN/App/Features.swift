/// Switches that differ between the build installed from Xcode and the one that goes to the App Store.
enum Features {
    /// Saving a YouTube video to the device for offline playback. Only the debug build has it:
    /// App Review guideline 5.2.3 does not let a public app download media from YouTube.
    static let videoDownload: Bool = {
        #if DEBUG
        true
        #else
        false
        #endif
    }()
}
