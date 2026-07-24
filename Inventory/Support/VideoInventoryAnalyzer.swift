import AVFoundation
import CoreGraphics
import Foundation
import Vision

struct ScanImageInput: @unchecked Sendable {
    var id = UUID()
    var image: CGImage
    var name: String
    var capturedAt = Date()
    var motion: CaptureMotionSample?
    var seededDetections: [ScanSeedDetection] = []
}

struct ScanSeedDetection: Sendable, Hashable {
    var label: String
    var confidence: Double
    var normalizedBox: CGRect
}

struct VideoInventoryAnalyzer {
    enum AnalyzerError: LocalizedError {
        case unreadableVideo
        case noFrames

        var errorDescription: String? {
            switch self {
            case .unreadableVideo:
                "This video could not be read."
            case .noFrames:
                "No usable object frames were found in this video."
            }
        }
    }

    static func analyze(
        videoURL: URL,
        room: String,
        area: String = "",
        container: String = "",
        mission: ScanMission = .roomSweep,
        progress: @escaping @MainActor (Double, String) -> Void
    ) async throws -> [DetectedInventoryItem] {
        await progress(0.02, "Loading video")

        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)

        guard seconds.isFinite, seconds > 0 else {
            throw AnalyzerError.unreadableVideo
        }

        let times = sampleTimes(for: seconds)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.18, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.18, preferredTimescale: 600)

        let scanID = UUID()
        var buckets: [String: CandidateBucket] = [:]
        var usableFrames = 0
        let videoName = videoURL.lastPathComponent.isEmpty ? "Walkthrough video" : videoURL.lastPathComponent
        await progress(0.04, "Preparing YOLO detector")
        let useYOLO = await YOLOInventoryDetector.shared.prepare()

        for (index, time) in times.enumerated() {
            try Task.checkCancellation()

            let frameProgress = Double(index) / Double(max(times.count, 1))
            await progress(0.05 + frameProgress * 0.88, "Finding objects in frame \(index + 1) of \(times.count)")

            do {
                let frame = try generator.copyCGImage(at: time, actualTime: nil)
                let timecode = CMTimeGetSeconds(time)
                let objectCandidates = await objectCandidates(from: frame, useYOLO: useYOLO)
                usableFrames += objectCandidates.isEmpty ? 0 : 1

                for candidate in objectCandidates.prefix(5) {
                    try Task.checkCancellation()

                    guard let finding = try analyze(
                        candidate: candidate,
                        timecode: timecode,
                        room: room,
                        area: area,
                        container: container,
                        mission: mission,
                        captureSource: .video,
                        scanID: scanID,
                        sourceVideoName: videoName,
                        cameraMotion: nil
                    ) else {
                        continue
                    }

                    let key = identityKey(for: finding, timecode: timecode)

                    if buckets[key] == nil {
                        buckets[key] = CandidateBucket(
                            name: finding.name,
                            category: finding.category,
                            room: finding.room,
                            area: finding.area,
                            container: finding.container,
                            mission: finding.scanMission,
                            captureSource: finding.captureSource,
                            scanID: finding.scanID,
                            sourceVideoName: finding.sourceVideoName
                        )
                    }

                    buckets[key]?.add(finding)
                }
            } catch {
                continue
            }
        }

        guard usableFrames > 0 else {
            throw AnalyzerError.noFrames
        }

        await progress(0.95, "Building inventory cards")

        let proposals = buildProposals(from: buckets)

        await progress(1, proposals.isEmpty ? "No object cards found" : "\(proposals.count) object cards ready")
        return proposals
    }

    static func analyze(
        images: [ScanImageInput],
        room: String,
        area: String = "",
        container: String = "",
        mission: ScanMission = .roomSweep,
        progress: @escaping @MainActor (Double, String) -> Void
    ) async throws -> [DetectedInventoryItem] {
        await progress(0.02, "Loading photos")

        guard !images.isEmpty else {
            throw AnalyzerError.noFrames
        }

        let scanID = UUID()
        var buckets: [String: CandidateBucket] = [:]
        var usableFrames = 0
        await progress(0.04, "Preparing YOLO detector")
        let useYOLO = await YOLOInventoryDetector.shared.prepare()

        for (index, input) in images.enumerated() {
            try Task.checkCancellation()

            let frameProgress = Double(index) / Double(max(images.count, 1))
            await progress(0.05 + frameProgress * 0.88, "Finding objects in photo \(index + 1) of \(images.count)")

            let objectCandidates = await objectCandidates(from: input.image, seedDetections: input.seededDetections, useYOLO: useYOLO)
            usableFrames += objectCandidates.isEmpty ? 0 : 1
            let timecode = Double(index)

            for candidate in objectCandidates.prefix(8) {
                try Task.checkCancellation()

                guard let finding = try analyze(
                    candidate: candidate,
                    timecode: timecode,
                    room: room,
                    area: area,
                    container: container,
                        mission: mission,
                        captureSource: .photo,
                        scanID: scanID,
                        sourceVideoName: input.name,
                        cameraMotion: input.motion
                    ) else {
                        continue
                    }

                let key = identityKey(for: finding, timecode: timecode)

                if buckets[key] == nil {
                    buckets[key] = CandidateBucket(
                        name: finding.name,
                        category: finding.category,
                        room: finding.room,
                        area: finding.area,
                        container: finding.container,
                        mission: finding.scanMission,
                        captureSource: finding.captureSource,
                        scanID: finding.scanID,
                        sourceVideoName: finding.sourceVideoName
                    )
                }

                buckets[key]?.add(finding)
            }
        }

        guard usableFrames > 0 else {
            throw AnalyzerError.noFrames
        }

        await progress(0.95, "Building inventory cards")
        let proposals = buildProposals(from: buckets)
        await progress(1, proposals.isEmpty ? "No object cards found" : "\(proposals.count) object cards ready")
        return proposals
    }

    private static func buildProposals(from buckets: [String: CandidateBucket]) -> [DetectedInventoryItem] {
        buckets.values
            .map(\.proposal)
            .filter { !$0.name.trimmed.isEmpty }
            .sorted {
                if $0.needsDetailScan != $1.needsDetailScan {
                    return !$0.needsDetailScan
                }

                if abs($0.confidence - $1.confidence) > 0.05 {
                    return $0.confidence > $1.confidence
                }

                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    private static func sampleTimes(for seconds: Double) -> [CMTime] {
        let frameCount = min(18, max(5, Int(ceil(seconds / 1.8))))
        return (0..<frameCount).map { index in
            let ratio = (Double(index) + 0.5) / Double(frameCount)
            let sampleSecond = min(max(seconds * ratio, 0.05), max(seconds - 0.05, 0.05))
            return CMTime(seconds: sampleSecond, preferredTimescale: 600)
        }
    }

    private static func objectCandidates(from frame: CGImage, seedDetections: [ScanSeedDetection] = [], useYOLO: Bool) async -> [ObjectCandidate] {
        if !seedDetections.isEmpty {
            let seededCandidates = seedDetections
                .filter(isUsefulSeedDetection)
                .sorted { $0.confidence > $1.confidence }
                .reduce(into: [ScanSeedDetection]()) { result, detection in
                    guard result.allSatisfy({ intersectionOverUnion($0.normalizedBox, detection.normalizedBox) < 0.55 }) else {
                        return
                    }
                    result.append(detection)
                }
                .prefix(12)
                .compactMap { detection -> ObjectCandidate? in
                    guard let crop = cropTopLeftNormalized(frame, to: detection.normalizedBox) else {
                        return nil
                    }

                    return ObjectCandidate(
                        image: crop,
                        boundingBox: NormalizedRect(detection.normalizedBox),
                        detectionKind: .yoloObject,
                        detectorLabel: detection.label,
                        detectorConfidence: detection.confidence
                    )
                }

            if !seededCandidates.isEmpty {
                return seededCandidates
            }
        }

        if useYOLO, let yoloCandidates = await yoloObjectCandidates(from: frame), !yoloCandidates.isEmpty {
            return yoloCandidates
        }

        return saliencyObjectCandidates(from: frame)
    }

    private static func yoloObjectCandidates(from frame: CGImage) async -> [ObjectCandidate]? {
        do {
            let detections = try await YOLOInventoryDetector.shared.detections(in: frame)
            let boxes = detections
                .filter(isUsefulYOLODetection)
                .sorted { $0.confidence > $1.confidence }
                .reduce(into: [YOLOInventoryDetection]()) { result, detection in
                    guard result.allSatisfy({ intersectionOverUnion($0.normalizedBox, detection.normalizedBox) < 0.52 }) else {
                        return
                    }
                    result.append(detection)
                }

            let candidates = boxes.prefix(10).compactMap { detection -> ObjectCandidate? in
                guard let crop = cropTopLeftNormalized(frame, to: detection.normalizedBox) else {
                    return nil
                }

                return ObjectCandidate(
                    image: crop,
                    boundingBox: NormalizedRect(detection.normalizedBox),
                    detectionKind: .yoloObject,
                    detectorLabel: detection.label,
                    detectorConfidence: detection.confidence
                )
            }

            return candidates.isEmpty ? nil : candidates
        } catch {
            return nil
        }
    }

    private static func saliencyObjectCandidates(from frame: CGImage) -> [ObjectCandidate] {
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: frame, orientation: .up, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return [ObjectCandidate(image: frame, boundingBox: nil, detectionKind: .frameFallback)]
        }

        let boxes = (request.results ?? [])
            .flatMap { $0.salientObjects ?? [] }
            .map(\.boundingBox)
            .filter(isUsableObjectBox)
            .sorted { ($0.width * $0.height) > ($1.width * $1.height) }

        let distinctBoxes = boxes.reduce(into: [CGRect]()) { result, box in
            guard result.allSatisfy({ intersectionOverUnion($0, box) < 0.55 }) else {
                return
            }
            result.append(box)
        }

        let cropped = distinctBoxes.compactMap { box -> ObjectCandidate? in
            guard let crop = crop(frame, to: box) else {
                return nil
            }

            return ObjectCandidate(image: crop, boundingBox: NormalizedRect(box), detectionKind: .objectCrop)
        }

        if !cropped.isEmpty {
            return cropped
        }

        return [ObjectCandidate(image: frame, boundingBox: nil, detectionKind: .frameFallback)]
    }

    private static func analyze(
        candidate: ObjectCandidate,
        timecode: Double,
        room: String,
        area: String,
        container: String,
        mission: ScanMission,
        captureSource: CaptureSourceKind,
        scanID: UUID,
        sourceVideoName: String,
        cameraMotion: CaptureMotionSample?
    ) throws -> ObjectFinding? {
        let analysis = try analyzeImage(candidate.image, needsClassification: candidate.detectorLabel == nil)

        guard analysis.hasFindings || candidate.detectorLabel != nil else {
            return nil
        }

        guard let name = bestName(
            from: analysis,
            detectorLabel: candidate.detectorLabel,
            detectionKind: candidate.detectionKind
        ) else {
            return nil
        }

        let text = analysis.recognizedText
        let labels = ([candidate.detectorLabel].compactMap { $0 } + analysis.labels.map(\.name))
            .reduce(into: [String]()) { result, label in
                guard !result.contains(label) else {
                    return
                }
                result.append(label)
            }
        let photoFilename = try? InventoryPhotoStore.saveJPEG(candidate.image)
        let confidence = confidenceScore(
            detectorConfidence: candidate.detectorConfidence,
            classifierConfidence: analysis.labels.first?.confidence,
            itemName: name,
            labels: labels,
            recognizedText: text,
            barcodes: analysis.barcodes
        )
        let condition = ItemCondition.suggested(labels: labels, recognizedText: text)
        let detectedCategory = InventoryCategory.suggested(for: "\(name) \(labels.joined(separator: " ")) \(text.joined(separator: " "))")
        let category = mission.suggestedCategory ?? detectedCategory
        let needsDetailScan = confidence < 0.42
            || candidate.detectionKind == .frameFallback
            || isGenericName(name)
            || (candidate.detectionKind == .yoloObject && text.isEmpty && category == .food)

        return ObjectFinding(
            name: name,
            category: category,
            room: room.trimmed.isEmpty ? "Unsorted" : room.trimmed,
            area: area,
            container: container,
            quantity: 1,
            condition: condition,
            confidence: min(1, max(0, confidence)),
            photoFilename: photoFilename,
            brand: plausibleBrand(from: text, itemName: name) ?? "",
            model: "",
            serialNumber: plausibleSerialNumber(from: text) ?? "",
            barcode: analysis.barcodes.first ?? "",
            color: averageColorName(for: candidate.image) ?? "",
            material: "",
            size: "",
            expiresAt: plausibleExpiryDate(from: text),
            restockThreshold: category == .food ? 1 : nil,
            replacementHint: "",
            needsDetailScan: needsDetailScan,
            scanMission: mission,
            tags: Array(Set(labels.prefix(4))).sorted(),
            labels: labels,
            recognizedText: text,
            timecode: timecode,
            boundingBox: candidate.boundingBox,
            detectionKind: candidate.detectionKind,
            captureSource: captureSource,
            scanID: scanID,
            sourceVideoName: sourceVideoName,
            cameraMotion: cameraMotion
        )
    }

    private static func analyzeImage(_ image: CGImage, needsClassification: Bool) throws -> FrameAnalysis {
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.minimumTextHeight = 0.012

        let barcodeRequest = VNDetectBarcodesRequest()
        var requests: [VNRequest] = [textRequest, barcodeRequest]

        let classifyRequest: VNClassifyImageRequest?
        if needsClassification {
            let request = VNClassifyImageRequest()
            classifyRequest = request
            requests.insert(request, at: 0)
        } else {
            classifyRequest = nil
        }

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        try handler.perform(requests)

        let labels = (classifyRequest?.results ?? [])
            .compactMap { observation -> LabeledFinding? in
                guard observation.confidence >= 0.14, let cleanName = cleanVisionLabel(observation.identifier) else {
                    return nil
                }
                return LabeledFinding(name: cleanName, confidence: Double(observation.confidence))
            }

        let texts = (textRequest.results ?? [])
            .compactMap { observation in
                observation.topCandidates(1).first?.string
            }
            .compactMap(cleanTextCandidate)

        let barcodes = (barcodeRequest.results ?? [])
            .compactMap(\.payloadStringValue)
            .map(\.trimmed)
            .filter { !$0.isEmpty }

        return FrameAnalysis(labels: labels, recognizedText: texts, barcodes: barcodes)
    }

    private static func bestName(
        from analysis: FrameAnalysis,
        detectorLabel: String?,
        detectionKind: DetectionKind
    ) -> String? {
        let visualLabels = ([detectorLabel].compactMap { $0 } + analysis.labels.map(\.name))
            .map(\.inventoryTitleCased)
        let usableVisualLabel = visualLabels.first(where: isUsableIdentityName)
        let textSpecificName = specificItemName(from: analysis.recognizedText)

        if let usableVisualLabel, !genericContainerLabels.contains(usableVisualLabel.normalizedInventoryKey) {
            return usableVisualLabel
        }

        if let textSpecificName {
            return textSpecificName
        }

        if let usableVisualLabel {
            return usableVisualLabel
        }

        if let barcode = analysis.barcodes.first {
            return "Barcode \(barcode.suffix(6))"
        }

        guard detectionKind != .frameFallback else {
            return nil
        }

        if visualLabels.contains(where: isWeakIdentityEvidence) {
            return "Unidentified item"
        }

        return nil
    }

    private static func confidenceScore(
        detectorConfidence: Double?,
        classifierConfidence: Double?,
        itemName: String,
        labels: [String],
        recognizedText: [String],
        barcodes: [String]
    ) -> Double {
        var score = max(detectorConfidence ?? 0, classifierConfidence ?? 0)

        if score == 0, !barcodes.isEmpty {
            score = 0.58
        }

        if !barcodes.isEmpty {
            score += 0.1
        }

        if plausibleBrand(from: recognizedText, itemName: itemName) != nil {
            score += 0.06
        }

        if ocrCorroborates(itemName: itemName, labels: labels, recognizedText: recognizedText) {
            score += 0.06
        }

        return min(1, max(0, score))
    }

    private static func ocrCorroborates(itemName: String, labels: [String], recognizedText: [String]) -> Bool {
        let text = recognizedText.joined(separator: " ").normalizedInventoryKey

        guard !text.isEmpty else {
            return false
        }

        let terms = ([itemName] + labels)
            .flatMap { $0.normalizedInventoryKey.split(separator: " ").map(String.init) }
            .filter { $0.count >= 4 }

        return terms.contains { text.contains($0) }
    }

    private static func identityKey(for finding: ObjectFinding, timecode: Double) -> String {
        if !finding.barcode.trimmed.isEmpty {
            return "barcode|\(finding.barcode.normalizedInventoryKey)"
        }

        let timeBucket = finding.cameraMotion?.viewpointKey ?? "\(Int(timecode / 3.0))"
        let spatialBucket: String

        if let rect = finding.boundingBox?.cgRect {
            let centerX = rect.midX
            let centerY = rect.midY
            spatialBucket = "\(Int(centerX * 3))-\(Int(centerY * 3))"
        } else {
            spatialBucket = "wide"
        }

        return "object|\(finding.name.normalizedInventoryKey)|\(timeBucket)|\(spatialBucket)"
    }

    private static func crop(_ image: CGImage, to normalizedBox: CGRect) -> CGImage? {
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let padding: CGFloat = 16

        var rect = CGRect(
            x: normalizedBox.minX * width,
            y: (1 - normalizedBox.maxY) * height,
            width: normalizedBox.width * width,
            height: normalizedBox.height * height
        )
        .insetBy(dx: -padding, dy: -padding)
        .intersection(imageBounds)
        .integral

        rect.size.width = max(1, rect.width)
        rect.size.height = max(1, rect.height)

        return image.cropping(to: rect)
    }

    private static func cropTopLeftNormalized(_ image: CGImage, to normalizedBox: CGRect) -> CGImage? {
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let padding: CGFloat = 16

        var rect = CGRect(
            x: normalizedBox.minX * width,
            y: normalizedBox.minY * height,
            width: normalizedBox.width * width,
            height: normalizedBox.height * height
        )
        .insetBy(dx: -padding, dy: -padding)
        .intersection(imageBounds)
        .integral

        rect.size.width = max(1, rect.width)
        rect.size.height = max(1, rect.height)

        return image.cropping(to: rect)
    }

    private static func isUsableObjectBox(_ box: CGRect) -> Bool {
        let area = box.width * box.height
        return area >= 0.018 && area <= 0.82 && box.width >= 0.06 && box.height >= 0.06
    }

    private static func isUsefulYOLODetection(_ detection: YOLOInventoryDetection) -> Bool {
        let area = detection.normalizedBox.width * detection.normalizedBox.height
        let ignored = [
            "Person", "Human", "Face", "Hand", "Chair", "Couch", "Dining Table",
            "Bed", "Toilet", "Sink", "Refrigerator", "Oven"
        ]

        return detection.confidence >= 0.22
            && area >= 0.004
            && area <= 0.88
            && !ignored.contains(detection.label)
    }

    private static func isUsefulSeedDetection(_ detection: ScanSeedDetection) -> Bool {
        let area = detection.normalizedBox.width * detection.normalizedBox.height
        return detection.confidence >= 0.16
            && area >= 0.003
            && area <= 0.88
            && detection.normalizedBox.width >= 0.035
            && detection.normalizedBox.height >= 0.035
    }

    private static func intersectionOverUnion(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let intersection = first.intersection(second)

        guard !intersection.isNull else {
            return 0
        }

        let intersectionArea = intersection.width * intersection.height
        let unionArea = first.width * first.height + second.width * second.height - intersectionArea

        guard unionArea > 0 else {
            return 0
        }

        return intersectionArea / unionArea
    }

    private static func cleanVisionLabel(_ identifier: String) -> String? {
        let firstLabel = identifier
            .components(separatedBy: ",")
            .first?
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmed
            .lowercased()

        guard let firstLabel, !firstLabel.isEmpty else {
            return nil
        }

        let ignored = [
            "indoor", "outdoor", "room", "wall", "floor", "ceiling", "window",
            "person", "people", "human", "face", "hand", "skin", "scene",
            "structure", "building", "background", "close up", "photograph",
            "pattern", "texture", "display", "screen"
        ]

        guard !ignored.contains(firstLabel), firstLabel.count > 2 else {
            return nil
        }

        return firstLabel.inventoryTitleCased
    }

    private static func isUsableIdentityName(_ name: String) -> Bool {
        let normalized = name.normalizedInventoryKey
        return !normalized.isEmpty && !weakIdentityLabels.contains(normalized)
    }

    private static func isWeakIdentityEvidence(_ name: String) -> Bool {
        weakIdentityLabels.contains(name.normalizedInventoryKey)
    }

    private static let genericContainerLabels: Set<String> = [
        "bag",
        "basket",
        "bottle",
        "box",
        "bucket",
        "can",
        "carton",
        "case",
        "container",
        "jar",
        "package",
        "packet",
        "tin",
        "tube"
    ]

    private static let weakIdentityLabels: Set<String> = [
        "appliance",
        "artifact",
        "box",
        "clothing",
        "container",
        "cord",
        "currency",
        "device",
        "electronic device",
        "equipment",
        "food",
        "furniture",
        "goods",
        "home appliance",
        "instrument",
        "item",
        "material",
        "object",
        "package",
        "paper",
        "plastic",
        "product",
        "textile",
        "thing",
        "tool"
    ]

    private static func specificItemName(from recognizedText: [String]) -> String? {
        let text = recognizedText
            .joined(separator: " ")
            .normalizedInventoryKey

        guard !text.isEmpty else {
            return nil
        }

        let phrases = [
            "spray paint", "paint", "wood stain", "primer", "varnish", "adhesive", "sealant",
            "lubricant", "wd 40", "glue", "tape", "duct tape", "masking tape", "electrical tape",
            "batteries", "battery", "screws", "nails", "bolts", "drill bit", "sandpaper",
            "detergent", "dish soap", "hand soap", "shampoo", "conditioner", "toothpaste",
            "deodorant", "razor", "cleaner", "disinfectant", "bleach", "trash bags",
            "pasta", "rice", "cereal", "coffee", "tea", "flour", "sugar", "salt", "pepper",
            "olive oil", "cooking oil", "sauce", "beans", "tuna", "soup", "milk", "juice",
            "charger", "cable", "adapter", "mouse", "keyboard", "remote", "headphones",
            "notebook", "markers", "pens", "pencils"
        ]

        if let phrase = phrases.first(where: { text.contains($0) }) {
            return phrase.inventoryTitleCased
        }

        return nil
    }

    private static func cleanTextCandidate(_ rawText: String) -> String? {
        let text = rawText
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmed

        guard text.count >= 2, text.count <= 40 else {
            return nil
        }

        let lower = text.lowercased()
        guard !lower.contains("www."), !lower.contains("http"), !lower.contains("@") else {
            return nil
        }

        let words = text.split(separator: " ")
        guard words.count <= 6 else {
            return nil
        }

        let hasLetter = text.rangeOfCharacter(from: .letters) != nil
        let isMostlyPunctuation = text.filter(\.isLetter).count < 2

        guard hasLetter, !isMostlyPunctuation else {
            return nil
        }

        return text.inventoryTitleCased
    }

    private static func isGoodNameText(_ text: String) -> Bool {
        let normalized = text.normalizedInventoryKey

        guard normalized.count >= 3, normalized.count <= 28 else {
            return false
        }

        let ignored = ["made in", "warning", "open", "close", "size", "use by", "best before", "ingredients"]
        return !ignored.contains { normalized.contains($0) } && !looksLikeOCRNoise(normalized)
    }

    private static func looksLikeOCRNoise(_ normalized: String) -> Bool {
        let tokens = normalized.split(separator: " ").map(String.init)

        guard !tokens.isEmpty else {
            return true
        }

        if tokens.count > 1 && tokens.contains(where: { $0.count == 1 }) {
            return true
        }

        if tokens.count > 1 && tokens.allSatisfy({ $0.count <= 3 }) {
            return true
        }

        let compact = tokens.joined()
        let letters = compact.filter(\.isLetter).count
        let digits = compact.filter(\.isNumber).count

        if letters < 3 {
            return true
        }

        if digits > 0 && digits >= max(2, letters / 2) {
            return true
        }

        let mixedShortToken = tokens.contains { token in
            token.count < 6 && token.contains(where: \.isLetter) && token.contains(where: \.isNumber)
        }

        return mixedShortToken
    }

    private static func isGenericName(_ name: String) -> Bool {
        let normalized = name.normalizedInventoryKey
        return normalized == "unidentified item" || weakIdentityLabels.contains(normalized)
    }

    private static func plausibleBrand(from text: [String], itemName: String) -> String? {
        text.first { candidate in
            let normalized = candidate.normalizedInventoryKey
            let wordCount = normalized.split(separator: " ").count
            return wordCount <= 3
                && normalized.count >= 3
                && normalized.count <= 24
                && normalized.rangeOfCharacter(from: .decimalDigits) == nil
                && isGoodNameText(candidate)
                && !itemName.localizedCaseInsensitiveContains(candidate)
                && !normalized.contains("warning")
        }
    }

    private static func plausibleSerialNumber(from text: [String]) -> String? {
        text.first { candidate in
            let normalized = candidate.replacingOccurrences(of: " ", with: "")
            let hasDigit = normalized.contains { $0.isNumber }
            let hasLetter = normalized.contains { $0.isLetter }
            return hasDigit && hasLetter && normalized.count >= 6 && normalized.count <= 20
        }
    }

    private static func plausibleExpiryDate(from text: [String]) -> Date? {
        let joined = text.joined(separator: " ").lowercased()
        let markers = ["use by", "best before", "expires", "expiry", "exp"]

        guard markers.contains(where: joined.contains) else {
            return nil
        }

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(joined.startIndex..<joined.endIndex, in: joined)
        return detector?
            .matches(in: joined, options: [], range: range)
            .compactMap(\.date)
            .first
    }

    private static func averageColorName(for image: CGImage) -> String? {
        var pixel = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        let red = Double(pixel[0]) / 255
        let green = Double(pixel[1]) / 255
        let blue = Double(pixel[2]) / 255
        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        let saturation = maxValue == 0 ? 0 : (maxValue - minValue) / maxValue

        if maxValue < 0.18 {
            return "Black"
        }

        if maxValue > 0.86 && saturation < 0.18 {
            return "White"
        }

        if saturation < 0.16 {
            return "Gray"
        }

        if red > green && red > blue {
            return green > 0.45 && blue < 0.28 ? "Orange" : "Red"
        }

        if green > red && green > blue {
            return blue > 0.45 ? "Teal" : "Green"
        }

        if blue > red && blue > green {
            return red > 0.45 ? "Purple" : "Blue"
        }

        if red > 0.55 && green > 0.45 && blue < 0.25 {
            return "Yellow"
        }

        return nil
    }
}

private struct ObjectCandidate {
    var image: CGImage
    var boundingBox: NormalizedRect?
    var detectionKind: DetectionKind
    var detectorLabel: String? = nil
    var detectorConfidence: Double? = nil
}

private struct ObjectFinding {
    var name: String
    var category: InventoryCategory
    var room: String
    var area: String
    var container: String
    var quantity: Int
    var condition: ItemCondition
    var confidence: Double
    var photoFilename: String?
    var brand: String
    var model: String
    var serialNumber: String
    var barcode: String
    var color: String
    var material: String
    var size: String
    var expiresAt: Date?
    var restockThreshold: Int?
    var replacementHint: String
    var needsDetailScan: Bool
    var scanMission: ScanMission
    var tags: [String]
    var labels: [String]
    var recognizedText: [String]
    var timecode: Double
    var boundingBox: NormalizedRect?
    var detectionKind: DetectionKind
    var captureSource: CaptureSourceKind
    var scanID: UUID
    var sourceVideoName: String
    var cameraMotion: CaptureMotionSample?
}

private struct FrameAnalysis {
    var labels: [LabeledFinding]
    var recognizedText: [String]
    var barcodes: [String]

    var hasFindings: Bool {
        !labels.isEmpty || !recognizedText.isEmpty || !barcodes.isEmpty
    }
}

private struct LabeledFinding {
    var name: String
    var confidence: Double
}

private struct CandidateBucket {
    var name: String
    var category: InventoryCategory
    var room: String
    var area: String
    var container: String
    var mission: ScanMission
    var captureSource: CaptureSourceKind
    var scanID: UUID
    var sourceVideoName: String
    var quantity = 1
    var condition: ItemCondition = .unknown
    var bestConfidence = 0.0
    var photoFilename: String?
    var brand = ""
    var model = ""
    var serialNumber = ""
    var barcode = ""
    var color = ""
    var material = ""
    var size = ""
    var expiresAt: Date?
    var restockThreshold: Int?
    var replacementHint = ""
    var needsDetailScan = true
    var labels: Set<String> = []
    var recognizedText: Set<String> = []
    var timecodes: Set<Double> = []
    var boundingBox: NormalizedRect?
    var detectionKind: DetectionKind = .objectCrop
    var tags: Set<String> = []
    var cameraMotion: CaptureMotionSample?

    mutating func add(_ finding: ObjectFinding) {
        labels.formUnion(finding.labels)
        recognizedText.formUnion(finding.recognizedText)
        timecodes.insert(finding.timecode)
        tags.formUnion(finding.tags)
        needsDetailScan = needsDetailScan && finding.needsDetailScan

        if condition == .unknown {
            condition = finding.condition
        }

        if finding.confidence >= bestConfidence {
            name = finding.name
            category = finding.category
            quantity = finding.quantity
            condition = finding.condition
            bestConfidence = finding.confidence
            photoFilename = finding.photoFilename
            brand = finding.brand
            model = finding.model
            serialNumber = finding.serialNumber
            barcode = finding.barcode
            color = finding.color
            material = finding.material
            size = finding.size
            expiresAt = finding.expiresAt
            restockThreshold = finding.restockThreshold
            replacementHint = finding.replacementHint
            boundingBox = finding.boundingBox
            detectionKind = finding.detectionKind
            cameraMotion = finding.cameraMotion
        }
    }

    var proposal: DetectedInventoryItem {
        var item = DetectedInventoryItem(
            name: name,
            category: category,
            room: room,
            area: area,
            container: container,
            quantity: quantity,
            condition: condition,
            confidence: min(1, max(0, bestConfidence)),
            photoFilename: photoFilename,
            brand: brand,
            model: model,
            serialNumber: serialNumber,
            barcode: barcode,
            color: color,
            material: material,
            size: size,
            expiresAt: expiresAt,
            restockThreshold: restockThreshold,
            replacementHint: replacementHint,
            needsDetailScan: needsDetailScan,
            scanMission: mission,
            tags: Array(tags).sorted(),
            labels: labels.sorted(),
            recognizedText: recognizedText.sorted(),
            timecodes: timecodes.sorted(),
            boundingBox: boundingBox,
            detectionKind: detectionKind,
            captureSource: captureSource,
            scanID: scanID,
            sourceVideoName: sourceVideoName,
            cameraMotion: cameraMotion
        )

        if item.name.normalizedInventoryKey == "unidentified item" {
            item.isSelected = false
        }

        return item
    }
}
