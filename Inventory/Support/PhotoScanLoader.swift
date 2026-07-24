import CoreGraphics
import Foundation
import PhotosUI
import SwiftUI
import UIKit

enum PhotoScanLoader {
    static func loadImages(from items: [PhotosPickerItem]) async -> [ScanImageInput] {
        var inputs: [ScanImageInput] = []

        for (index, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let cgImage = image.normalizedCGImage else {
                continue
            }

            let name = item.itemIdentifier?.components(separatedBy: "/").last ?? "Photo \(index + 1)"
            inputs.append(ScanImageInput(image: cgImage, name: name))
        }

        return inputs
    }
}

extension UIImage {
    var normalizedCGImage: CGImage? {
        if imageOrientation == .up {
            return cgImage
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }
}
