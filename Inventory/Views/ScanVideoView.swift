@preconcurrency import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
import UltralyticsYOLO

private enum ScanInputKind: String, CaseIterable, Identifiable {
    case live = "Live"
    case photos = "Photos"
    case video = "Video"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .live: "camera.viewfinder"
        case .photos: "photo.on.rectangle.angled"
        case .video: "video.badge.plus"
        }
    }
}

struct ScanVideoView: View {
    @EnvironmentObject private var store: InventoryStore

    @State private var inputKind: ScanInputKind = .live
    @State private var mission: ScanMission = .roomSweep
    @State private var room = ""
    @State private var area = ""
    @State private var container = ""
    @State private var selectedVideoURL: URL?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showingPhotoCamera = false
    @State private var pickerSource: VideoPickerSource?
    @State private var proposals: [DetectedInventoryItem] = []
    @State private var showingReview = false
    @State private var isAnalyzing = false
    @State private var photoCaptureCount = 0
    @State private var photoAnalysisInFlight = 0
    @State private var progress = 0.0
    @State private var statusText = "Ready"
    @State private var errorMessage: String?

    var onSaved: () -> Void

    private var roomName: String {
        room.trimmed.isEmpty ? "Unsorted" : room.trimmed
    }

    private var areaName: String {
        area.trimmed
    }

    private var containerName: String {
        container.trimmed
    }

    var body: some View {
        let photoSelectionTitle = selectedPhotoItems.isEmpty ? "Import Photos" : "\(selectedPhotoItems.count) Imported"

        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Text("Input")
                            InfoHelpButton(
                                title: "Input Type",
                                message: "Photos are best for slower sweeps and close-ups. Video is useful for a room walkthrough, but the app samples frames instead of keeping the whole recording."
                            )
                            Spacer()
                        }

                        Picker("Input", selection: $inputKind) {
                            ForEach(ScanInputKind.allCases) { kind in
                                Label(kind.rawValue, systemImage: kind.symbolName)
                                    .tag(kind)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }

                    Picker("Area Type", selection: $mission) {
                        ForEach(ScanMission.allCases) { mission in
                            Label(mission.rawValue, systemImage: mission.symbolName)
                                .tag(mission)
                        }
                    }

                    Label(mission.guidance, systemImage: mission.symbolName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    InfoSectionHeader(
                        title: "Mission",
                        infoTitle: "Scan Mission",
                        message: "The mission gives the analyzer context. For example, Pantry and Fridge scans bias ambiguous detections toward food and restocking metadata."
                    )
                }

                Section {
                    TextField("Room", text: $room)
                        .textInputAutocapitalization(.words)
                    TextField("Shelf, drawer, wall, zone", text: $area)
                        .textInputAutocapitalization(.words)
                    TextField("Box, bin, bag, cabinet", text: $container)
                        .textInputAutocapitalization(.words)
                } header: {
                    InfoSectionHeader(
                        title: "Place",
                        infoTitle: "Place Fields",
                        message: "These become the location path the assistant can search later, such as Kitchen, Pantry Shelf, Pasta Bin."
                    )
                }

                if inputKind == .live {
                    Section {
                        LiveInventoryCameraPanel(
                            objectCardsReady: proposals.count,
                            isAnalyzing: photoAnalysisInFlight > 0,
                            canAutoCapture: photoAnalysisInFlight < 2 && !showingReview
                        ) { input in
                            guard !showingReview else {
                                return
                            }
                            enqueuePhotoAnalysis([input])
                        }
                        .frame(minHeight: 460)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

                        if photoCaptureCount > 0 || photoAnalysisInFlight > 0 || !proposals.isEmpty {
                            Label(photoStatusSummary, systemImage: "camera.viewfinder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !proposals.isEmpty {
                            Button {
                                showingReview = true
                            } label: {
                                Label("Review \(proposals.count) Objects", systemImage: "rectangle.stack")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } header: {
                        InfoSectionHeader(
                            title: "Live Scan",
                            infoTitle: "Live YOLO Scan",
                            message: "Runs detection directly on the camera stream. Stable detections are sampled into the same crop-and-review pipeline without saving source photos."
                        )
                    }
                } else if inputKind == .photos {
                    Section {
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Button {
                                    showingPhotoCamera = true
                                } label: {
                                    Label("Take Photo", systemImage: "camera")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                                InfoHelpButton(
                                    title: "Take Photo",
                                    message: "Opens a continuous camera. Each shutter tap starts analysis immediately, and the source photo is not saved after object crops are made."
                                )
                            }
                            .frame(maxWidth: .infinity)

                            HStack(spacing: 4) {
                                PhotosPicker(
                                    selection: $selectedPhotoItems,
                                    maxSelectionCount: 24,
                                    matching: .images
                                ) {
                                    Label(
                                        photoSelectionTitle,
                                        systemImage: "photo.on.rectangle.angled"
                                    )
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .disabled(false)

                                InfoHelpButton(
                                    title: "Import Photos",
                                    message: "Selected images begin analysis immediately. The app keeps only cropped object photos after analysis."
                                )
                            }
                            .frame(maxWidth: .infinity)
                        }

                        if photoCaptureCount > 0 || photoAnalysisInFlight > 0 || !proposals.isEmpty {
                            Label(photoStatusSummary, systemImage: "camera.viewfinder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !proposals.isEmpty {
                            Button {
                                showingReview = true
                            } label: {
                                Label("Review \(proposals.count) Objects", systemImage: "rectangle.stack")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    } header: {
                        InfoSectionHeader(
                            title: "Photo Sweep",
                            infoTitle: "Photo Analysis",
                            message: "This mode starts object detection as each shot arrives. Keep taking angled shelf, bin, or surface photos while previous shots analyze in the background."
                        )
                    }
                } else {
                    Section {
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Button {
                                    pickerSource = .camera
                                } label: {
                                    Label("Record", systemImage: "video")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera) || isAnalyzing)

                                InfoHelpButton(
                                    title: "Record Video",
                                    message: "Records a walkthrough and samples frames for object crops. The source recording is deleted from app-managed storage after analysis."
                                )
                            }
                            .frame(maxWidth: .infinity)

                            HStack(spacing: 4) {
                                Button {
                                    pickerSource = .library
                                } label: {
                                    Label("Import", systemImage: "photo.on.rectangle")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .disabled(isAnalyzing)

                                InfoHelpButton(
                                    title: "Import Video",
                                    message: "Uses an existing recording for analysis. The app does not need the full video once cropped object evidence has been made."
                                )
                            }
                            .frame(maxWidth: .infinity)
                        }

                        if let selectedVideoURL {
                            Label(selectedVideoURL.lastPathComponent, systemImage: "film")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Button {
                            analyzeSelectedVideo()
                        } label: {
                            Label(isAnalyzing ? "Analyzing" : "Analyze Video", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedVideoURL == nil || isAnalyzing)
                    } header: {
                        InfoSectionHeader(
                            title: "Walkthrough Video",
                            infoTitle: "Video Analysis",
                            message: "Video is treated as a scan source, not an archive. The analyzer samples useful frames, detects object boxes, saves crops for inventory cards, then drops the source file when possible."
                        )
                    }
                }

                if isAnalyzing || progress > 0 {
                    Section("Progress") {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: progress)
                            Text(statusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Scan")
            .sheet(isPresented: $showingPhotoCamera) {
                PhotoCameraPicker { input in
                    enqueuePhotoAnalysis([input])
                } onCancel: {
                    showingPhotoCamera = false
                }
            }
            .sheet(item: $pickerSource) { source in
                VideoPicker(source: source) { url in
                    selectedVideoURL = url
                    statusText = "Ready"
                    progress = 0
                    pickerSource = nil
                } onCancel: {
                    pickerSource = nil
                }
            }
            .sheet(isPresented: $showingReview) {
                ReviewDetectionsView(proposals: $proposals) { selected in
                    store.addDetected(selected)
                    selectedVideoURL = nil
                    selectedPhotoItems = []
                    photoCaptureCount = 0
                    photoAnalysisInFlight = 0
                    proposals = []
                    progress = 0
                    statusText = "Saved"
                    onSaved()
                }
            }
            .alert("Could not analyze scan", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                analyzeImportedPhotos(newItems)
            }
        }
    }

    private var photoStatusSummary: String {
        let analyzed = proposals.count
        if photoAnalysisInFlight > 0 {
            return "\(photoCaptureCount) photos captured, \(photoAnalysisInFlight) analyzing, \(analyzed) object cards ready"
        }

        if analyzed > 0 {
            return "\(photoCaptureCount) photos analyzed, \(analyzed) object cards ready"
        }

        return "\(photoCaptureCount) photos captured"
    }

    private func analyzeSelectedVideo() {
        guard let selectedVideoURL else {
            return
        }

        let videoURLToAnalyze = selectedVideoURL
        let scanRoom = roomName
        let scanArea = areaName
        let scanContainer = containerName
        let scanMission = mission
        isAnalyzing = true
        statusText = "Starting"
        progress = 0

        Task {
            do {
                let detected = try await VideoInventoryAnalyzer.analyze(
                    videoURL: videoURLToAnalyze,
                    room: scanRoom,
                    area: scanArea,
                    container: scanContainer,
                    mission: scanMission
                ) { value, message in
                    progress = value
                    statusText = message
                }

                await MainActor.run {
                    WalkthroughVideoStore.deleteTemporaryCopyIfOwned(videoURLToAnalyze)
                    proposals = detected.map { proposalWithDefaultSelection($0) }
                    showingReview = true
                    isAnalyzing = false
                    self.selectedVideoURL = nil
                }
            } catch {
                await MainActor.run {
                    WalkthroughVideoStore.deleteTemporaryCopyIfOwned(videoURLToAnalyze)
                    errorMessage = error.localizedDescription
                    isAnalyzing = false
                    self.selectedVideoURL = nil
                }
            }
        }
    }

    private func analyzeImportedPhotos(_ photoItems: [PhotosPickerItem]) {
        guard !photoItems.isEmpty else {
            return
        }

        isAnalyzing = true
        statusText = "Loading selected photos"
        progress = 0.05

        Task {
            let importedImages = await PhotoScanLoader.loadImages(from: photoItems)

            await MainActor.run {
                selectedPhotoItems = []

                guard !importedImages.isEmpty else {
                    isAnalyzing = photoAnalysisInFlight > 0
                    statusText = photoAnalysisInFlight > 0 ? statusText : "No usable photos found"
                    return
                }

                enqueuePhotoAnalysis(importedImages)
            }
        }
    }

    private func enqueuePhotoAnalysis(_ images: [ScanImageInput]) {
        guard !images.isEmpty else {
            return
        }

        let scanRoom = roomName
        let scanArea = areaName
        let scanContainer = containerName
        let scanMission = mission
        let imageCount = images.count
        photoCaptureCount += imageCount
        photoAnalysisInFlight += imageCount
        isAnalyzing = true
        statusText = imageCount == 1 ? "Analyzing latest photo" : "Analyzing \(imageCount) photos"
        progress = max(progress, 0.05)

        Task {
            do {
                let detected = try await VideoInventoryAnalyzer.analyze(
                    images: images,
                    room: scanRoom,
                    area: scanArea,
                    container: scanContainer,
                    mission: scanMission
                ) { value, message in
                    progress = value
                    statusText = message
                }

                await MainActor.run {
                    mergeDetectedProposals(detected)
                    photoAnalysisInFlight = max(0, photoAnalysisInFlight - imageCount)
                    isAnalyzing = photoAnalysisInFlight > 0
                    statusText = proposals.isEmpty ? "No object cards yet" : "\(proposals.count) object cards ready"
                    progress = isAnalyzing ? progress : 1
                }
            } catch {
                await MainActor.run {
                    photoAnalysisInFlight = max(0, photoAnalysisInFlight - imageCount)
                    errorMessage = error.localizedDescription
                    isAnalyzing = photoAnalysisInFlight > 0
                }
            }
        }
    }

    private func mergeDetectedProposals(_ detected: [DetectedInventoryItem]) {
        for incoming in detected.map({ proposalWithDefaultSelection($0) }) {
            if let index = proposals.firstIndex(where: { proposalsLikelyReferToSameObject($0, incoming) }) {
                mergeProposal(at: index, with: incoming)
            } else {
                proposals.append(incoming)
            }
        }

        proposals.sort {
            if $0.needsDetailScan != $1.needsDetailScan {
                return !$0.needsDetailScan
            }

            if abs($0.confidence - $1.confidence) > 0.05 {
                return $0.confidence > $1.confidence
            }

            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func proposalsLikelyReferToSameObject(
        _ first: DetectedInventoryItem,
        _ second: DetectedInventoryItem
    ) -> Bool {
        if !first.barcode.trimmed.isEmpty || !second.barcode.trimmed.isEmpty {
            return first.barcode.normalizedInventoryKey == second.barcode.normalizedInventoryKey
        }

        if proposalNameIsGeneric(first.name) || proposalNameIsGeneric(second.name) {
            guard let firstBox = first.boundingBox?.cgRect, let secondBox = second.boundingBox?.cgRect else {
                return false
            }

            return firstBox.intersectionOverUnion(with: secondBox) >= 0.38
                || firstBox.centerDistance(to: secondBox) < 0.14
        }

        let sameIdentity = first.name.normalizedInventoryKey == second.name.normalizedInventoryKey
            && first.category == second.category
            && first.room.normalizedInventoryKey == second.room.normalizedInventoryKey
            && first.area.normalizedInventoryKey == second.area.normalizedInventoryKey
            && first.container.normalizedInventoryKey == second.container.normalizedInventoryKey

        guard sameIdentity else {
            return false
        }

        guard let firstMotion = first.cameraMotion, let secondMotion = second.cameraMotion else {
            return true
        }

        return firstMotion.isNearby(secondMotion)
    }

    private func proposalNameIsGeneric(_ name: String) -> Bool {
        let normalized = name.normalizedInventoryKey
        return [
            "unidentified item",
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
        ].contains(normalized)
    }

    private func proposalWithDefaultSelection(_ proposal: DetectedInventoryItem) -> DetectedInventoryItem {
        var proposal = proposal
        proposal.isSelected = proposalShouldDefaultSelected(proposal)
        return proposal
    }

    private func proposalShouldDefaultSelected(_ proposal: DetectedInventoryItem) -> Bool {
        if !proposal.barcode.trimmed.isEmpty {
            return true
        }

        return proposal.confidence >= 0.42 && !proposalNameIsGeneric(proposal.name)
    }

    private func mergeProposal(at index: Int, with incoming: DetectedInventoryItem) {
        var existing = proposals[index]
        let previousConfidence = existing.confidence
        existing.quantity = max(existing.quantity, incoming.quantity)
        existing.confidence = max(existing.confidence, incoming.confidence)
        existing.needsDetailScan = existing.needsDetailScan && incoming.needsDetailScan
        existing.tags = Array(Set(existing.tags + incoming.tags)).sorted()
        existing.labels = Array(Set(existing.labels + incoming.labels)).sorted()
        existing.recognizedText = Array(Set(existing.recognizedText + incoming.recognizedText)).sorted()
        existing.timecodes = Array(Set(existing.timecodes + incoming.timecodes)).sorted()

        if incoming.confidence > previousConfidence {
            existing.name = incoming.name
            existing.category = incoming.category
            existing.condition = incoming.condition
            existing.photoFilename = incoming.photoFilename
            existing.boundingBox = incoming.boundingBox
            existing.detectionKind = incoming.detectionKind
        }

        if existing.brand.trimmed.isEmpty {
            existing.brand = incoming.brand
        }
        if existing.model.trimmed.isEmpty {
            existing.model = incoming.model
        }
        if existing.serialNumber.trimmed.isEmpty {
            existing.serialNumber = incoming.serialNumber
        }
        if existing.barcode.trimmed.isEmpty {
            existing.barcode = incoming.barcode
        }
        if existing.color.trimmed.isEmpty {
            existing.color = incoming.color
        }
        if existing.material.trimmed.isEmpty {
            existing.material = incoming.material
        }
        if existing.size.trimmed.isEmpty {
            existing.size = incoming.size
        }
        if existing.expiresAt == nil {
            existing.expiresAt = incoming.expiresAt
        }
        if existing.restockThreshold == nil {
            existing.restockThreshold = incoming.restockThreshold
        }
        if existing.replacementHint.trimmed.isEmpty {
            existing.replacementHint = incoming.replacementHint
        }
        if existing.cameraMotion == nil || existing.cameraMotion?.isNearby(incoming.cameraMotion ?? existing.cameraMotion!) == false {
            existing.cameraMotion = incoming.cameraMotion ?? existing.cameraMotion
        }
        if !existing.isSelected && proposalShouldDefaultSelected(existing) {
            existing.isSelected = true
        }

        proposals[index] = existing
    }
}

private struct LiveInventoryCameraPanel: View {
    var objectCardsReady: Int
    var isAnalyzing: Bool
    var canAutoCapture: Bool
    var onFrameCaptured: @MainActor (ScanImageInput) -> Void

    @StateObject private var modelLoader = LiveYOLOModelLoader()
    @State private var detections: [LiveScanDetection] = []
    @State private var captureRequestID = 0
    @State private var frameCaptureCount = 0
    @State private var lastAutoCapture = Date.distantPast
    @State private var lastCapturedByDetectionID: [String: Date] = [:]
    @State private var pendingCaptureSeeds: [ScanSeedDetection] = []
    @State private var lastCaptureText = "Ready"

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let modelURL = modelLoader.modelURL {
                InventoryYOLOCameraSurface(
                    modelURL: modelURL,
                    captureRequestID: $captureRequestID
                ) { result in
                    handleDetection(result)
                } onFrameCaptured: { image in
                    handleCapturedFrame(image)
                }
                .overlay {
                    LiveScanOverlay(detections: detections)
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView(value: modelLoader.progress > 0 ? modelLoader.progress : nil)
                    Text(modelLoader.statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if let errorMessage = modelLoader.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)

                        Button {
                            modelLoader.load()
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                .background(Color(.secondarySystemBackground))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Label("\(detections.count)", systemImage: "viewfinder")
                    if isAnalyzing {
                        Label("Analyzing", systemImage: "sparkles")
                    }
                    if objectCardsReady > 0 {
                        Label("\(objectCardsReady) ready", systemImage: "rectangle.stack")
                    }
                }
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.black.opacity(0.58), in: Capsule())
                .foregroundStyle(.white)

                if !detections.isEmpty {
                    Text(detections.prefix(3).map(\.displayName).joined(separator: ", "))
                        .font(.caption2)
                        .lineLimit(2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.white)
                }
            }
            .padding(12)

            VStack(spacing: 10) {
                Spacer()

                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(liveGuidance)
                            .font(.caption.weight(.semibold))
                        Text(lastCaptureText)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    .lineLimit(2)
                    .foregroundStyle(.white)

                    Spacer()

                    Button {
                        requestCapture(manual: true)
                    } label: {
                        Image(systemName: "camera.circle.fill")
                            .font(.system(size: 38))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .accessibilityLabel("Capture current objects")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
                .padding(12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task {
            modelLoader.load()
        }
    }

    private var liveGuidance: String {
        if detections.isEmpty {
            return "Move slowly across a shelf or surface"
        }

        if detections.contains(where: { $0.state == .identified }) {
            return "Green objects are ready; shift angle for missed items"
        }

        if detections.contains(where: { $0.state == .isolated }) {
            return "Hold steady, move closer, or tap capture"
        }

        return "Center one object and slow down"
    }

    private func handleDetection(_ result: YOLOResult) {
        let incoming = result.boxes
            .compactMap { LiveScanDetection(box: $0, imageSize: result.orig_shape) }
            .filter(\.isUseful)
            .sorted { $0.confidence > $1.confidence }
            .prefix(18)

        let now = Date()
        detections = incoming.map { detection in
            var updated = detection
            if let previous = detections.first(where: { $0.matches(detection) }) {
                updated.seenCount = previous.seenCount + 1
            }
            updated.lastSeen = now
            updated.updateState()
            return updated
        }

        let shouldCapture = canAutoCapture
            && detections.contains { $0.state != .candidate }
            && now.timeIntervalSince(lastAutoCapture) > 2.5

        if shouldCapture {
            requestCapture(manual: false)
        }
    }

    private func handleCapturedFrame(_ image: UIImage) {
        guard let cgImage = image.normalizedCGImage else {
            return
        }

        frameCaptureCount += 1
        let seeds = pendingCaptureSeeds
        pendingCaptureSeeds = []
        let input = ScanImageInput(
            image: cgImage,
            name: "Live frame \(frameCaptureCount)",
            capturedAt: Date(),
            motion: nil,
            seededDetections: seeds
        )

        lastCaptureText = seeds.isEmpty ? "Analyzing frame" : "Analyzing \(seeds.count) object crops"
        onFrameCaptured(input)
    }

    private func requestCapture(manual: Bool) {
        let now = Date()
        let candidates: [LiveScanDetection]

        if manual {
            candidates = Array(detections
                .filter { $0.state != .candidate }
                .sorted { $0.capturePriority > $1.capturePriority }
                .prefix(8))

            if candidates.isEmpty {
                pendingCaptureSeeds = Array(detections
                    .sorted { $0.confidence > $1.confidence }
                    .prefix(6))
                    .map(\.seedDetection)
            } else {
                pendingCaptureSeeds = candidates.map(\.seedDetection)
            }
        } else {
            candidates = detections
                .filter { detection in
                    detection.state != .candidate
                        && now.timeIntervalSince(lastCapturedByDetectionID[detection.id] ?? .distantPast) > 12
                }
                .sorted { $0.capturePriority > $1.capturePriority }

            guard !candidates.isEmpty else {
                return
            }

            pendingCaptureSeeds = Array(candidates.prefix(8)).map(\.seedDetection)
        }

        for detection in candidates {
            lastCapturedByDetectionID[detection.id] = now
        }

        if pendingCaptureSeeds.isEmpty && detections.isEmpty {
            lastCaptureText = "Analyzing frame"
        } else {
            lastCaptureText = "Capturing \(max(1, pendingCaptureSeeds.count)) object\(pendingCaptureSeeds.count == 1 ? "" : "s")"
        }

        lastAutoCapture = now
        captureRequestID += 1
    }
}

@MainActor
private final class LiveYOLOModelLoader: ObservableObject {
    @Published var modelURL: URL?
    @Published var progress = 0.0
    @Published var statusText = "Preparing detector"
    @Published var errorMessage: String?

    private var downloader: YOLOModelDownloader?
    private var isLoading = false

    func load() {
        guard modelURL == nil, !isLoading else {
            return
        }

        if let localModelURL = YOLOInventoryDetector.preferredLocalModelURL() {
            progress = 1
            statusText = "Detector ready"
            modelURL = localModelURL
            return
        }

        isLoading = true
        errorMessage = nil
        statusText = "Preparing detector"
        let downloader = YOLOModelDownloader()
        self.downloader = downloader

        downloader.download(
            from: YOLOInventoryDetector.defaultModelURL,
            task: .detect
        ) { [weak self] value in
            guard let self else {
                return
            }
            progress = value
            statusText = value < 1 ? "Downloading detector" : "Loading detector"
        } completion: { [weak self] result in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.isLoading = false
                self.downloader = nil

                switch result {
                case .success(let url):
                    self.progress = 1
                    self.statusText = "Detector ready"
                    self.modelURL = url
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.statusText = "Detector unavailable"
                }
            }
        }
    }
}

private struct InventoryYOLOCameraSurface: UIViewRepresentable {
    var modelURL: URL
    @Binding var captureRequestID: Int
    var onDetection: @MainActor (YOLOResult) -> Void
    var onFrameCaptured: @MainActor (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> YOLOView {
        let view = YOLOView(frame: .zero, modelPathOrName: modelURL.path, task: .detect)
        view.showOverlays = false
        view.captureSessionPreset = .hd1280x720
        view.setThresholds(numItems: 48, confidence: 0.16, iou: 0.55)
        view.onDetection = { result in
            onDetection(result)
        }
        return view
    }

    func updateUIView(_ uiView: YOLOView, context: Context) {
        uiView.onDetection = { result in
            onDetection(result)
        }

        guard context.coordinator.lastCaptureRequestID != captureRequestID else {
            return
        }

        context.coordinator.lastCaptureRequestID = captureRequestID
        uiView.capturePhoto { image in
            guard let image else {
                return
            }
            onFrameCaptured(image)
        }
    }

    static func dismantleUIView(_ uiView: YOLOView, coordinator: Coordinator) {
        uiView.stop()
    }

    final class Coordinator {
        var lastCaptureRequestID = 0
    }
}

private struct LiveScanOverlay: View {
    var detections: [LiveScanDetection]

    var body: some View {
        GeometryReader { proxy in
            ForEach(detections) { detection in
                let rect = detection.displayRect(in: proxy.size)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(detection.state.color, lineWidth: detection.state.lineWidth)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(detection.state.color.opacity(0.08))
                        )

                    Text(detection.title)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(detection.state.color, in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(detection.state.textColor)
                        .offset(x: 0, y: -2)
                }
                .frame(width: max(22, rect.width), height: max(22, rect.height))
                .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct LiveScanDetection: Identifiable, Hashable {
    var id: String
    var label: String
    var confidence: Double
    var normalizedBox: CGRect
    var imageSize: CGSize
    var seenCount = 1
    var lastSeen = Date()
    var state: LiveScanDetectionState = .candidate

    init?(box: Box, imageSize: CGSize) {
        let label = box.cls
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmed
            .inventoryTitleCased

        guard !label.isEmpty else {
            return nil
        }

        let rect = box.xywhn.standardized
        let centerX = Int(rect.midX * 10)
        let centerY = Int(rect.midY * 10)

        self.id = "\(label.normalizedInventoryKey)-\(centerX)-\(centerY)"
        self.label = label
        self.confidence = Double(box.conf)
        self.normalizedBox = rect
        self.imageSize = imageSize
    }

    var displayName: String {
        isWeakIdentity ? "Unidentified" : label
    }

    var title: String {
        "\(displayName) \(Int(confidence * 100))%"
    }

    var seedDetection: ScanSeedDetection {
        ScanSeedDetection(
            label: label,
            confidence: confidence,
            normalizedBox: normalizedBox
        )
    }

    var capturePriority: Double {
        let stateBoost: Double
        switch state {
        case .identified: stateBoost = 1.0
        case .isolated: stateBoost = 0.55
        case .candidate: stateBoost = 0
        }

        let area = normalizedBox.width * normalizedBox.height
        let sizeScore = min(1, Double(area / 0.18))
        return confidence + stateBoost + sizeScore * 0.2
    }

    var isUseful: Bool {
        let area = normalizedBox.width * normalizedBox.height
        let ignored = [
            "Person", "Human", "Face", "Hand", "Chair", "Couch", "Dining Table",
            "Bed", "Toilet", "Sink", "Refrigerator", "Oven"
        ]

        return confidence >= 0.16
            && area >= 0.003
            && area <= 0.88
            && normalizedBox.width >= 0.035
            && normalizedBox.height >= 0.035
            && !ignored.contains(label)
    }

    var isWeakIdentity: Bool {
        let weakLabels: Set<String> = [
            "appliance", "artifact", "box", "clothing", "container", "cord",
            "currency", "device", "electronic device", "equipment", "food",
            "furniture", "goods", "home appliance", "instrument", "item",
            "material", "object", "package", "paper", "plastic", "product",
            "textile", "thing", "tool"
        ]

        return weakLabels.contains(label.normalizedInventoryKey)
    }

    mutating func updateState() {
        if !isWeakIdentity, confidence >= 0.34, seenCount >= 2 {
            state = .identified
        } else if seenCount >= 3 || confidence >= 0.28 {
            state = .isolated
        } else {
            state = .candidate
        }
    }

    func matches(_ other: LiveScanDetection) -> Bool {
        if normalizedBox.intersectionOverUnion(with: other.normalizedBox) >= 0.42 {
            return true
        }

        let sameLabel = label.normalizedInventoryKey == other.label.normalizedInventoryKey
        let dx = normalizedBox.midX - other.normalizedBox.midX
        let dy = normalizedBox.midY - other.normalizedBox.midY
        let distance = sqrt(dx * dx + dy * dy)
        return sameLabel && distance < 0.16
    }

    func displayRect(in viewSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, viewSize.width > 0, viewSize.height > 0 else {
            return .zero
        }

        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let scaledImageSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let offset = CGPoint(
            x: (scaledImageSize.width - viewSize.width) / 2,
            y: (scaledImageSize.height - viewSize.height) / 2
        )

        return CGRect(
            x: normalizedBox.minX * imageSize.width * scale - offset.x,
            y: normalizedBox.minY * imageSize.height * scale - offset.y,
            width: normalizedBox.width * imageSize.width * scale,
            height: normalizedBox.height * imageSize.height * scale
        )
    }
}

private enum LiveScanDetectionState: Hashable {
    case candidate
    case isolated
    case identified

    var color: Color {
        switch self {
        case .candidate: .cyan
        case .isolated: .yellow
        case .identified: .green
        }
    }

    var textColor: Color {
        switch self {
        case .candidate, .identified: .black
        case .isolated: .black
        }
    }

    var lineWidth: CGFloat {
        switch self {
        case .candidate: 2
        case .isolated, .identified: 3
        }
    }
}

private extension CGRect {
    func intersectionOverUnion(with other: CGRect) -> CGFloat {
        let intersection = intersection(other)

        guard !intersection.isNull else {
            return 0
        }

        let intersectionArea = intersection.width * intersection.height
        let unionArea = width * height + other.width * other.height - intersectionArea

        guard unionArea > 0 else {
            return 0
        }

        return intersectionArea / unionArea
    }

    func centerDistance(to other: CGRect) -> CGFloat {
        let dx = midX - other.midX
        let dy = midY - other.midY
        return sqrt(dx * dx + dy * dy)
    }
}
