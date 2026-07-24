import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum VideoPickerSource: Identifiable {
    case camera
    case library

    var id: String {
        switch self {
        case .camera: "camera"
        case .library: "library"
        }
    }

    var sourceType: UIImagePickerController.SourceType {
        switch self {
        case .camera: .camera
        case .library: .photoLibrary
        }
    }
}

struct VideoPicker: UIViewControllerRepresentable {
    var source: VideoPickerSource
    var onPick: (URL) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = source.sourceType
        picker.mediaTypes = [UTType.movie.identifier]
        picker.videoQuality = .typeHigh
        picker.allowsEditing = false
        picker.delegate = context.coordinator

        if source == .camera {
            picker.cameraCaptureMode = .video
            picker.cameraDevice = .rear
        }

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var onPick: (URL) -> Void
        var onCancel: () -> Void

        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            defer {
                picker.dismiss(animated: true)
            }

            guard let url = info[.mediaURL] as? URL else {
                onCancel()
                return
            }

            onPick(url)
        }
    }
}
