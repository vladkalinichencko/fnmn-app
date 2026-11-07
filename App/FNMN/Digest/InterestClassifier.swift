import CoreML
import FNMNCore
import NaturalLanguage

/// The topic classifier a digest carries: a CoreML text model the Mac trained from the sources' folders and the
/// engagement, compiled here once per sync and asked for one label per post.
enum InterestClassifier {
    /// The folder each post's text belongs to. A model that will not compile or load leaves every post without
    /// a label, and the magazine keeps the sources' own folders; the reader sees that, since the sections then
    /// follow the subscriptions.
    @concurrent
    static func labels(modelURL: URL, posts: [DigestPackage.Post]) async -> [String: String] {
        guard let model = model(at: modelURL) else {
            return [:]
        }
        var labels: [String: String] = [:]
        for post in posts {
            guard let text = post.text, !text.isEmpty else {
                continue
            }
            if let label = model.predictedLabel(for: text) {
                labels[post.id] = label
            }
        }
        return labels
    }

    private static func model(at url: URL) -> NLModel? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let compiled = try MLModel.compileModel(at: url)
            return try NLModel(mlModel: MLModel(contentsOf: compiled))
        } catch {
            return nil
        }
    }
}
