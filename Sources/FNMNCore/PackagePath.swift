import Foundation

/// The one rule a delivery's file name follows: a relative path inside the package's folder, and nothing that
/// climbs out of it.
public enum PackagePath {
    /// No leading slash, no empty name, no `.` or `..` part.
    public static func isSafe(_ path: String) -> Bool {
        guard !path.isEmpty, path != ".", !path.hasPrefix("/") else {
            return false
        }
        return !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }

    /// The file the path names under the folder, or nil when it could leave it.
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
