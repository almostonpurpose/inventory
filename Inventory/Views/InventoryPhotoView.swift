import SwiftUI
import UIKit

struct InventoryPhotoView: View {
    var filename: String?
    var symbolName: String
    var tint: Color
    var cornerRadius: CGFloat = 8

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle()
                        .fill(tint.opacity(0.14))
                    Image(systemName: symbolName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(tint)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.separator.opacity(0.6), lineWidth: 0.5)
        }
    }

    private var image: UIImage? {
        guard let url = InventoryPhotoStore.url(for: filename) else {
            return nil
        }

        return UIImage(contentsOfFile: url.path)
    }
}
