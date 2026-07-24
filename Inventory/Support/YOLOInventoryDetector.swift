import CoreGraphics
import Foundation
import UltralyticsYOLO

struct YOLOInventoryDetection: Sendable, Hashable {
    var label: String
    var confidence: Double
    var normalizedBox: CGRect
}

final class YOLOInventoryDetector: @unchecked Sendable {
    static let shared = YOLOInventoryDetector()
    static let defaultModelURL = URL(
        string: "https://github.com/ultralytics/yolo-ios-app/releases/download/v8.3.0/yolo26n.mlpackage.zip"
    )!
    static let preferredLocalModelNames = [
        "inventory-yolo",
        "yoloe-inventory",
        "yoloworld-inventory",
        "home-inventory-yolo"
    ]

    private let queue = DispatchQueue(label: "HomeInventory.YOLOInventoryDetector")
    private var model: YOLO?
    private var isLoading = false
    private var waiters: [CheckedContinuation<YOLO, Error>] = []

    private init() {}

    static func preferredLocalModelURL() -> URL? {
        let fileManager = FileManager.default
        var searchDirectories = [URL]()

        if let resourceURL = Bundle.main.resourceURL {
            searchDirectories.append(resourceURL)
        }

        searchDirectories.append(contentsOf: fileManager.urls(for: .documentDirectory, in: .userDomainMask))
        searchDirectories.append(contentsOf: fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask))

        for directory in searchDirectories {
            for modelName in preferredLocalModelNames {
                for pathExtension in ["mlmodelc", "mlpackage"] {
                    let candidate = directory
                        .appendingPathComponent(modelName)
                        .appendingPathExtension(pathExtension)

                    if fileManager.fileExists(atPath: candidate.path) {
                        return candidate
                    }
                }
            }
        }

        return nil
    }

    func prepare() async -> Bool {
        do {
            _ = try await loadModel()
            return true
        } catch {
            return false
        }
    }

    func detections(in image: CGImage) async throws -> [YOLOInventoryDetection] {
        let model = try await loadModel()

        return await Task.detached(priority: .userInitiated) {
            let result = model(image)
            return result.boxes
                .compactMap { box -> YOLOInventoryDetection? in
                    let label = box.cls
                        .replacingOccurrences(of: "_", with: " ")
                        .replacingOccurrences(of: "-", with: " ")
                        .trimmed
                        .inventoryTitleCased

                    guard !label.isEmpty else {
                        return nil
                    }

                    let normalizedBox = box.xywhn.standardized
                    let area = normalizedBox.width * normalizedBox.height

                    guard area >= 0.004, area <= 0.88 else {
                        return nil
                    }

                    return YOLOInventoryDetection(
                        label: label,
                        confidence: Double(box.conf),
                        normalizedBox: normalizedBox
                    )
                }
        }.value
    }

    private func loadModel() async throws -> YOLO {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let model = self.model, model.isLoaded {
                    continuation.resume(returning: model)
                    return
                }

                self.waiters.append(continuation)

                guard !self.isLoading else {
                    return
                }

                self.isLoading = true
                let handleLoadResult: (Result<YOLO, Error>) -> Void = { result in
                    self.queue.async {
                        self.isLoading = false

                        switch result {
                        case .success(let loadedModel):
                            loadedModel.setThresholds(numItems: 24, confidence: 0.25, iou: 0.65)
                            self.model = loadedModel
                            self.resumeWaiters(returning: loadedModel)
                        case .failure(let error):
                            self.model = nil
                            self.resumeWaiters(throwing: error)
                        }
                    }
                }

                let candidate: YOLO
                if let localModelURL = Self.preferredLocalModelURL() {
                    candidate = YOLO(
                        localModelURL.path,
                        task: .detect,
                        useGpu: true,
                        numItemsThreshold: 24,
                        completion: handleLoadResult
                    )
                } else {
                    candidate = YOLO(
                        url: Self.defaultModelURL,
                        task: .detect,
                        useGpu: true,
                        numItemsThreshold: 24,
                        completion: handleLoadResult
                    )
                }

                self.model = candidate
            }
        }
    }

    private func resumeWaiters(returning model: YOLO) {
        let waiters = self.waiters
        self.waiters = []
        for waiter in waiters {
            waiter.resume(returning: model)
        }
    }

    private func resumeWaiters(throwing error: Error) {
        let waiters = self.waiters
        self.waiters = []
        for waiter in waiters {
            waiter.resume(throwing: error)
        }
    }
}
