import CoreGraphics
import Foundation
import UIKit

enum InventoryPhotoStore {
    private static let activeProfileDefaultsKey = "HomeInventory.activePhotoProfileID"

    static func useProfile(_ profileID: String) {
        UserDefaults.standard.set(sanitizedProfileID(profileID), forKey: activeProfileDefaultsKey)
    }

    private static var activeProfileID: String {
        UserDefaults.standard.string(forKey: activeProfileDefaultsKey) ?? "default"
    }

    private static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HomeInventory", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(activeProfileID, isDirectory: true)
            .appendingPathComponent("ObjectPhotos", isDirectory: true)
    }

    static func url(for filename: String?) -> URL? {
        guard let filename, !filename.trimmed.isEmpty else {
            return nil
        }

        return directoryURL.appendingPathComponent(filename)
    }

    static func saveJPEG(_ image: CGImage, maxDimension: CGFloat = 900, compressionQuality: CGFloat = 0.82) throws -> String {
        try ensureDirectory()

        let filename = "\(UUID().uuidString).jpg"
        let url = directoryURL.appendingPathComponent(filename)
        let rendered = resizedImage(from: image, maxDimension: maxDimension)

        guard let data = rendered.jpegData(compressionQuality: compressionQuality) else {
            throw CocoaError(.fileWriteUnknown)
        }

        try data.write(to: url, options: [.atomic])
        return filename
    }

    private static func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    static func deleteAllPhotos(for profileID: String) throws {
        let directoryURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HomeInventory", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(sanitizedProfileID(profileID), isDirectory: true)
            .appendingPathComponent("ObjectPhotos", isDirectory: true)

        if FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.removeItem(at: directoryURL)
        }
    }

    private static func sanitizedProfileID(_ profileID: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = profileID.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let cleaned = String(scalars).trimmed
        return cleaned.isEmpty ? "default" : cleaned
    }

    private static func resizedImage(from image: CGImage, maxDimension: CGFloat) -> UIImage {
        let sourceSize = CGSize(width: image.width, height: image.height)
        let longestSide = max(sourceSize.width, sourceSize.height)

        guard longestSide > maxDimension else {
            return UIImage(cgImage: image)
        }

        let scale = maxDimension / longestSide
        let targetSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)

        return renderer.image { _ in
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
