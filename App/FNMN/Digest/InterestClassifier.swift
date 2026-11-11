import CoreML
import FNMNCore
import NaturalLanguage

enum InterestClassifier {
    struct Labels: Sendable {
        let labels: [String: String]
        let error: String?
    }

    @concurrent
    static func labels(modelURL: URL, posts: [DigestPackage.Post]) async -> Labels {
        let loadedModel = loaded(at: modelURL)
        guard let model = loadedModel.model else {
            return Labels(labels: [:], error: loadedModel.error ?? "The digest's classifier is missing from its delivery.")
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
        return Labels(labels: labels, error: nil)
    }

    private static func loaded(at url: URL) -> (model: NLModel?, error: String?) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return (nil, "The digest's classifier is missing from its delivery.")
        }
        do {
            let compiled = try MLModel.compileModel(at: url)
            return (try NLModel(mlModel: MLModel(contentsOf: compiled)), nil)
        } catch {
            return (nil, "The digest's classifier did not load: \(error.localizedDescription)")
        }
    }
}
