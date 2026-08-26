#if DEBUG
import CoreGraphics
import Foundation
import ImageIO

/// Headless verification of the scan pipeline, for simulator runs where the
/// camera and photo picker can't be driven. Launch the app with
/// `--scan-self-test` after copying test images into the app container at
/// `Documents/SelfTest/`; results go to the console.
@MainActor
enum ScanSelfTest {
    static nonisolated var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--scan-self-test")
    }

    private static var transcript: [String] = []

    /// Console capture from the simulator is unreliable, so results also land
    /// in Documents/SelfTest/results.txt inside the app container.
    private static func emit(_ line: String) {
        print(line)
        transcript.append(line)
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SelfTest/results.txt")
        try? transcript.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    static func run() async {
        let directory = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SelfTest", isDirectory: true)

        let imageURLs = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !imageURLs.isEmpty else {
            emit("SCAN-SELF-TEST: no images in \(directory.path)")
            return
        }

        emit("SCAN-SELF-TEST: \(imageURLs.count) image(s), preparing classifier")
        let started = Date()
        let ready = await MobileCLIPClassifier.shared.prepare()
        emit("SCAN-SELF-TEST: classifier ready=\(ready) in \(String(format: "%.1f", Date().timeIntervalSince(started)))s")

        var inputs: [ScanImageInput] = []
        for url in imageURLs {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                emit("SCAN-SELF-TEST: could not read \(url.lastPathComponent)")
                continue
            }

            // Per-image raw classification of the full frame, for calibration.
            let predictions = await MobileCLIPClassifier.shared.classify(image, topK: 3)
            let summary = predictions
                .map { String(format: "%@ cos=%.3f conf=%.2f", $0.name, $0.cosine, $0.confidence) }
                .joined(separator: " | ")
            emit("SCAN-SELF-TEST: \(url.lastPathComponent) full-frame -> \(summary.isEmpty ? "no match" : summary)")

            inputs.append(ScanImageInput(image: image, name: url.lastPathComponent))
        }

        do {
            let proposals = try await VideoInventoryAnalyzer.analyze(
                images: inputs,
                room: "Self Test",
                progress: { progress, message in
                    emit(String(format: "SCAN-SELF-TEST: %3.0f%% %@", progress * 100, message))
                }
            )

            emit("SCAN-SELF-TEST: \(proposals.count) proposal(s)")
            for proposal in proposals {
                emit(String(
                    format: "SCAN-SELF-TEST: PROPOSAL %@ [%@] conf=%.2f detail=%@ kind=%@ labels=%@",
                    proposal.name,
                    proposal.category.rawValue,
                    proposal.confidence,
                    proposal.needsDetailScan ? "yes" : "no",
                    proposal.detectionKind.rawValue,
                    proposal.labels.prefix(4).joined(separator: ", ")
                ))
            }
        } catch {
            emit("SCAN-SELF-TEST: pipeline failed: \(error)")
        }

        emit("SCAN-SELF-TEST: done")
    }
}
#endif
