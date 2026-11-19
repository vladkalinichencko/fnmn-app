import Foundation

public enum PackagePath {
    public static func isSafe(_ path: String) -> Bool {
        guard !path.isEmpty, path != ".", !path.hasPrefix("/") else {
            return false
        }
        return !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }

    public static func resolves(_ path: String, in folder: URL) -> URL? {
        guard isSafe(path) else {
            return nil
        }
        let folder = folder.standardizedFileURL
        let destination = folder.appending(path: path).standardizedFileURL
        guard destination.path == folder.path || destination.path.hasPrefix(folder.path + "/") else {
            return nil
        }
        return destination
    }
}
