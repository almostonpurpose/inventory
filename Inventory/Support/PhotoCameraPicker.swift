@preconcurrency import AVFoundation
import CoreMotion
import SwiftUI
import UIKit

struct PhotoCameraPicker: UIViewControllerRepresentable {
    var onCapture: @MainActor @Sendable (ScanImageInput) -> Void
    var onCancel: @MainActor @Sendable () -> Void

    func makeUIViewController(context: Context) -> PhotoCaptureViewController {
        PhotoCaptureViewController(onCapture: onCapture, onCancel: onCancel)
    }

    func updateUIViewController(_ uiViewController: PhotoCaptureViewController, context: Context) {}
}

final class PhotoCaptureViewController: UIViewController {
    private let onCapture: @MainActor @Sendable (ScanImageInput) -> Void
    private let onCancel: @MainActor @Sendable () -> Void
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "HomeInventory.PhotoCapture.session")
    private let photoOutput = AVCapturePhotoOutput()
    private let motionSampler = CaptureMotionSampler()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var photoDelegates: [PhotoCaptureDelegate] = []
    private var shotCount = 0

    init(
        onCapture: @escaping @MainActor @Sendable (ScanImageInput) -> Void,
        onCancel: @escaping @MainActor @Sendable () -> Void
    ) {
        self.onCapture = onCapture
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configurePreview()
        configureControls()
        configureSession()
        motionSampler.start()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        motionSampler.stop()
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func configurePreview() {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    private func configureControls() {
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        closeButton.layer.cornerRadius = 22
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        let shutterButton = UIButton(type: .system)
        shutterButton.setImage(UIImage(systemName: "camera.circle.fill"), for: .normal)
        shutterButton.tintColor = .white
        shutterButton.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        shutterButton.layer.cornerRadius = 36
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        shutterButton.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
        view.addSubview(shutterButton)

        let hintLabel = UILabel()
        hintLabel.text = "Tap shutter, keep moving"
        hintLabel.font = .preferredFont(forTextStyle: .footnote)
        hintLabel.textColor = .white
        hintLabel.textAlignment = .center
        hintLabel.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        hintLabel.layer.cornerRadius = 12
        hintLabel.clipsToBounds = true
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),
            shutterButton.widthAnchor.constraint(equalToConstant: 72),
            shutterButton.heightAnchor.constraint(equalToConstant: 72),

            hintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hintLabel.bottomAnchor.constraint(equalTo: shutterButton.topAnchor, constant: -16),
            hintLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            hintLabel.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    private func configureSession() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else {
                    DispatchQueue.main.async {
                        self?.onCancel()
                        self?.dismiss(animated: true)
                    }
                    return
                }
                self?.setupSession()
            }
        default:
            onCancel()
            dismiss(animated: true)
        }
    }

    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }

            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            guard
                let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: camera),
                self.session.canAddInput(input),
                self.session.canAddOutput(self.photoOutput)
            else {
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.onCancel()
                    self.dismiss(animated: true)
                }
                return
            }

            self.session.addInput(input)
            self.session.addOutput(self.photoOutput)
            self.photoOutput.isHighResolutionCaptureEnabled = true
            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
        onCancel()
    }

    @objc private func shutterTapped() {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        settings.isHighResolutionPhotoEnabled = true

        shotCount += 1
        let shotNumber = shotCount
        let motion = motionSampler.currentSample()
        let delegate = PhotoCaptureDelegate(
            name: "In-app photo \(shotNumber)",
            motion: motion,
            onCapture: { [weak self] input in
                self?.onCapture(input)
            },
            onFinish: { [weak self] delegate in
                self?.photoDelegates.removeAll { $0 === delegate }
            }
        )

        photoDelegates.append(delegate)
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let name: String
    private let motion: CaptureMotionSample?
    private let onCapture: @MainActor @Sendable (ScanImageInput) -> Void
    private let onFinish: (PhotoCaptureDelegate) -> Void

    init(
        name: String,
        motion: CaptureMotionSample?,
        onCapture: @escaping @MainActor @Sendable (ScanImageInput) -> Void,
        onFinish: @escaping (PhotoCaptureDelegate) -> Void
    ) {
        self.name = name
        self.motion = motion
        self.onCapture = onCapture
        self.onFinish = onFinish
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        defer {
            onFinish(self)
        }

        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data),
              let cgImage = image.normalizedCGImage else {
            return
        }

        let input = ScanImageInput(
            image: cgImage,
            name: name,
            capturedAt: Date(),
            motion: motion
        )

        let onCapture = onCapture
        Task { @MainActor in
            onCapture(input)
        }
    }
}

private final class CaptureMotionSampler {
    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable else {
            return
        }

        manager.deviceMotionUpdateInterval = 0.1
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    func currentSample() -> CaptureMotionSample? {
        guard let motion = manager.deviceMotion else {
            return nil
        }

        return CaptureMotionSample(
            attitudeRoll: motion.attitude.roll,
            attitudePitch: motion.attitude.pitch,
            attitudeYaw: motion.attitude.yaw,
            rotationRateX: motion.rotationRate.x,
            rotationRateY: motion.rotationRate.y,
            rotationRateZ: motion.rotationRate.z,
            gravityX: motion.gravity.x,
            gravityY: motion.gravity.y,
            gravityZ: motion.gravity.z,
            userAccelerationX: motion.userAcceleration.x,
            userAccelerationY: motion.userAcceleration.y,
            userAccelerationZ: motion.userAcceleration.z,
            timestamp: motion.timestamp
        )
    }
}
