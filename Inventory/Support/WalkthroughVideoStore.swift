import Foundation

enum WalkthroughVideoStore {
    private static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HomeInventory", isDirectory: true)
            .appendingPathComponent("WalkthroughVideos", isDirectory: true)
    }

    static func saveCopy(of sourceURL: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let destination = directoryURL
            .appendingPathComponent("walkthrough-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }

    static func existingURL(path: String) -> URL? {
        guard !path.trimmed.isEmpty, FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        return URL(fileURLWithPath: path)
    }

    static func deleteTemporaryCopyIfOwned(_ url: URL?) {
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        let standardizedPath = url.standardizedFileURL.path
        let ownedRoots = [
            FileManager.default.temporaryDirectory.standardizedFileURL.path,
            directoryURL.standardizedFileURL.path,
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].standardizedFileURL.path
        ]

        guard ownedRoots.contains(where: { standardizedPath.hasPrefix($0) }) else {
            return
        }

        try? FileManager.default.removeItem(at: url)
    }

    static func deleteAllManagedCopies() {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return
        }

        try? FileManager.default.removeItem(at: directoryURL)
    }
}
