import CoreGraphics
import CoreML
import CoreVideo
import CryptoKit
import Foundation

struct CLIPPrediction: Sendable {
    var name: String
    var category: InventoryCategory?
    var cosine: Double
    var confidence: Double
}

/// Zero-shot crop identification with MobileCLIP-S2.
///
/// The image encoder embeds each crop; item names come from a runtime-editable
/// vocabulary whose text embeddings are computed once with the text encoder and
/// cached on disk. Scores are raw cosine similarities thresholded in ScanTuning,
/// so out-of-vocabulary crops can honestly return no match.
final class MobileCLIPClassifier: @unchecked Sendable {
    static let shared = MobileCLIPClassifier()

    private static let embeddingDimension = 512
    private static let imageInputSide = 256
    private static let cacheVersion = 1
    private static let defaultTemplates = [
        "a photo of a {}",
        "a close-up photo of a {}",
        "a photo of a {} in a home"
    ]

    private let queue = DispatchQueue(label: "HomeInventory.MobileCLIPClassifier")
    private var runtime: Runtime?
    private var isLoading = false
    private var waiters: [CheckedContinuation<Runtime, Error>] = []

    private init() {}

    func prepare() async -> Bool {
        do {
            _ = try await loadRuntime()
            return true
        } catch {
            return false
        }
    }

    /// Returns vocabulary matches for a crop, best first, all above the reject
    /// floor. Empty when the crop most resembles a negative (wall, floor, ...)
    /// or nothing in the vocabulary.
    func classify(_ image: CGImage, topK: Int = 3) async -> [CLIPPrediction] {
        guard let runtime = try? await loadRuntime() else {
            return []
        }

        return await Task.detached(priority: .userInitiated) {
            Self.classify(image: image, topK: topK, runtime: runtime)
        }.value
    }

    // MARK: - Runtime

    private struct VocabularyEntry {
        var name: String
        var category: InventoryCategory?
        var isNegative: Bool
    }

    // Immutable after init; MLModel prediction is thread-safe.
    private final class Runtime: @unchecked Sendable {
        let imageModel: MLModel
        let imageInputName: String
        let entries: [VocabularyEntry]
        /// Row-major L2-normalized embeddings, entries.count x embeddingDimension.
        let embeddings: [Float]

        init(imageModel: MLModel, imageInputName: String, entries: [VocabularyEntry], embeddings: [Float]) {
            self.imageModel = imageModel
            self.imageInputName = imageInputName
            self.entries = entries
            self.embeddings = embeddings
        }
    }

    enum ClassifierError: Error {
        case missingModel(String)
        case missingVocabulary
        case badModelOutput
        case badPixelBuffer
    }

    private func loadRuntime() async throws -> Runtime {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let runtime = self.runtime {
                    continuation.resume(returning: runtime)
                    return
                }

                self.waiters.append(continuation)

                guard !self.isLoading else {
                    return
                }

                self.isLoading = true
                Task.detached(priority: .userInitiated) {
                    let result = Result { try Self.buildRuntime() }
                    self.queue.async {
                        self.isLoading = false

                        switch result {
                        case .success(let runtime):
                            self.runtime = runtime
                            let waiters = self.waiters
                            self.waiters = []
                            for waiter in waiters {
                                waiter.resume(returning: runtime)
                            }
                        case .failure(let error):
                            let waiters = self.waiters
                            self.waiters = []
                            for waiter in waiters {
                                waiter.resume(throwing: error)
                            }
                        }
                    }
                }
            }
        }
    }

    private static func buildRuntime() throws -> Runtime {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        guard let imageModelURL = Bundle.main.url(forResource: "mobileclip_s2_image", withExtension: "mlmodelc") else {
            throw ClassifierError.missingModel("mobileclip_s2_image")
        }

        let imageModel = try MLModel(contentsOf: imageModelURL, configuration: configuration)

        guard let imageInputName = imageModel.modelDescription.inputDescriptionsByName.keys.first else {
            throw ClassifierError.badModelOutput
        }

        let vocabulary = try loadVocabulary()

        let table: (entries: [VocabularyEntry], embeddings: [Float])
        if let cached = loadCachedTable(matching: vocabulary.hash) {
            table = cached
        } else {
            table = try buildEmbeddingTable(for: vocabulary, configuration: configuration)
            saveCachedTable(table, hash: vocabulary.hash)
        }

        return Runtime(
            imageModel: imageModel,
            imageInputName: imageInputName,
            entries: table.entries,
            embeddings: table.embeddings
        )
    }

    // MARK: - Vocabulary

    private struct VocabularyFile: Codable {
        struct Item: Codable {
            var name: String
            var prompt: String?
            var category: String?
        }

        var templates: [String]?
        var negatives: [String]?
        var items: [Item]
    }

    private struct Vocabulary {
        var templates: [String]
        var entries: [VocabularyEntry]
        var prompts: [String]
        var hash: String
    }

    private static func loadVocabulary() throws -> Vocabulary {
        var fileURL = Bundle.main.url(forResource: "household-vocabulary", withExtension: "json")

        // A copy dropped into Documents (via the Files app) overrides the bundle.
        let documentOverride = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("household-vocabulary.json")
        if let documentOverride, FileManager.default.fileExists(atPath: documentOverride.path) {
            fileURL = documentOverride
        }

        guard let fileURL, let data = try? Data(contentsOf: fileURL) else {
            throw ClassifierError.missingVocabulary
        }

        let file = try JSONDecoder().decode(VocabularyFile.self, from: data)
        let templates = (file.templates?.isEmpty == false ? file.templates! : defaultTemplates)

        var entries: [VocabularyEntry] = []
        var prompts: [String] = []

        for item in file.items {
            let name = item.name.trimmed
            guard !name.isEmpty else {
                continue
            }
            entries.append(VocabularyEntry(
                name: name.inventoryTitleCased,
                category: item.category.flatMap(InventoryCategory.init(rawValue:)),
                isNegative: false
            ))
            prompts.append((item.prompt ?? name).lowercased())
        }

        for negative in file.negatives ?? [] {
            let prompt = negative.trimmed
            guard !prompt.isEmpty else {
                continue
            }
            entries.append(VocabularyEntry(name: prompt.inventoryTitleCased, category: nil, isNegative: true))
            prompts.append(prompt.lowercased())
        }

        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return Vocabulary(templates: templates, entries: entries, prompts: prompts, hash: hash)
    }

    // MARK: - Text embedding table

    private static func buildEmbeddingTable(
        for vocabulary: Vocabulary,
        configuration: MLModelConfiguration
    ) throws -> (entries: [VocabularyEntry], embeddings: [Float]) {
        guard let textModelURL = Bundle.main.url(forResource: "mobileclip_s2_text", withExtension: "mlmodelc") else {
            throw ClassifierError.missingModel("mobileclip_s2_text")
        }

        // The text encoder is only alive while the table is (re)built.
        let textModel = try MLModel(contentsOf: textModelURL, configuration: configuration)

        guard let textInputName = textModel.modelDescription.inputDescriptionsByName.keys.first else {
            throw ClassifierError.badModelOutput
        }

        let tokenizer = CLIPTokenizer()
        var embeddings = [Float]()
        embeddings.reserveCapacity(vocabulary.entries.count * embeddingDimension)

        for prompt in vocabulary.prompts {
            var mean = [Float](repeating: 0, count: embeddingDimension)

            for template in vocabulary.templates {
                let sentence = template.replacingOccurrences(of: "{}", with: prompt)
                let tokens = tokenizer.encode_full(text: sentence)
                let tokenArray = try MLMultiArray(shape: [1, NSNumber(value: tokenizer.contextLength)], dataType: .int32)
                for (index, token) in tokens.enumerated() {
                    tokenArray[index] = NSNumber(value: token)
                }

                let input = try MLDictionaryFeatureProvider(dictionary: [textInputName: MLFeatureValue(multiArray: tokenArray)])
                let output = try textModel.prediction(from: input)
                let embedding = try normalizedEmbedding(from: output)

                for index in 0..<embeddingDimension {
                    mean[index] += embedding[index]
                }
            }

            embeddings.append(contentsOf: l2Normalized(mean))
        }

        return (vocabulary.entries, embeddings)
    }

    // MARK: - Table cache

    private struct CachedTable: Codable {
        var version: Int
        var vocabularyHash: String
        var names: [String]
        var categories: [String?]
        var negativeFlags: [Bool]
        var embeddings: Data
    }

    private static var cacheURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = base.appendingPathComponent("MobileCLIP", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("vocabulary-embeddings.json")
    }

    private static func loadCachedTable(matching hash: String) -> (entries: [VocabularyEntry], embeddings: [Float])? {
        guard let cacheURL,
              let data = try? Data(contentsOf: cacheURL),
              let cached = try? JSONDecoder().decode(CachedTable.self, from: data),
              cached.version == cacheVersion,
              cached.vocabularyHash == hash,
              cached.names.count == cached.categories.count,
              cached.names.count == cached.negativeFlags.count,
              cached.embeddings.count == cached.names.count * embeddingDimension * MemoryLayout<Float>.size else {
            return nil
        }

        let entries = zip(zip(cached.names, cached.categories), cached.negativeFlags).map { pair, isNegative in
            VocabularyEntry(
                name: pair.0,
                category: pair.1.flatMap(InventoryCategory.init(rawValue:)),
                isNegative: isNegative
            )
        }

        let embeddings = cached.embeddings.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }

        return (entries, embeddings)
    }

    private static func saveCachedTable(_ table: (entries: [VocabularyEntry], embeddings: [Float]), hash: String) {
        guard let cacheURL else {
            return
        }

        let cached = CachedTable(
            version: cacheVersion,
            vocabularyHash: hash,
            names: table.entries.map(\.name),
            categories: table.entries.map { $0.category?.rawValue },
            negativeFlags: table.entries.map(\.isNegative),
            embeddings: table.embeddings.withUnsafeBufferPointer { Data(buffer: $0) }
        )

        if let data = try? JSONEncoder().encode(cached) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    // MARK: - Classification

    private static func classify(image: CGImage, topK: Int, runtime: Runtime) -> [CLIPPrediction] {
        guard !runtime.entries.isEmpty,
              let pixelBuffer = squarePixelBuffer(from: image, side: imageInputSide),
              let input = try? MLDictionaryFeatureProvider(
                  dictionary: [runtime.imageInputName: MLFeatureValue(pixelBuffer: pixelBuffer)]
              ),
              let output = try? runtime.imageModel.prediction(from: input),
              let imageEmbedding = try? normalizedEmbedding(from: output) else {
            return []
        }

        var scored: [(index: Int, cosine: Double)] = []
        scored.reserveCapacity(runtime.entries.count)

        runtime.embeddings.withUnsafeBufferPointer { table in
            for entryIndex in runtime.entries.indices {
                var dot: Float = 0
                let offset = entryIndex * embeddingDimension
                for component in 0..<embeddingDimension {
                    dot += imageEmbedding[component] * table[offset + component]
                }
                scored.append((entryIndex, Double(dot)))
            }
        }

        scored.sort { $0.cosine > $1.cosine }

        // A crop that most resembles a rejection prompt is "none of these".
        guard let best = scored.first, !runtime.entries[best.index].isNegative else {
            return []
        }

        return scored
            .lazy
            .filter { !runtime.entries[$0.index].isNegative }
            .prefix(topK)
            .compactMap { candidate in
                guard let confidence = ScanTuning.confidence(fromCosine: candidate.cosine) else {
                    return nil
                }
                let entry = runtime.entries[candidate.index]
                return CLIPPrediction(
                    name: entry.name,
                    category: entry.category,
                    cosine: candidate.cosine,
                    confidence: confidence
                )
            }
    }

    private static func normalizedEmbedding(from output: MLFeatureProvider) throws -> [Float] {
        let multiArray = output.featureValue(for: "final_emb_1")?.multiArrayValue
            ?? output.featureNames.compactMap { output.featureValue(for: $0)?.multiArrayValue }.first

        guard let multiArray, multiArray.count == embeddingDimension else {
            throw ClassifierError.badModelOutput
        }

        var values = [Float](repeating: 0, count: embeddingDimension)
        for index in 0..<embeddingDimension {
            values[index] = multiArray[index].floatValue
        }

        return l2Normalized(values)
    }

    private static func l2Normalized(_ vector: [Float]) -> [Float] {
        let magnitude = sqrt(vector.reduce(Float(0)) { $0 + $1 * $1 })

        guard magnitude > 0 else {
            return vector
        }

        return vector.map { $0 / magnitude }
    }

    private static func squarePixelBuffer(from image: CGImage, side: Int) -> CVPixelBuffer? {
        let squareSource: CGImage
        if image.width == image.height {
            squareSource = image
        } else {
            let cropSide = min(image.width, image.height)
            let cropRect = CGRect(
                x: (image.width - cropSide) / 2,
                y: (image.height - cropSide) / 2,
                width: cropSide,
                height: cropSide
            )
            guard let cropped = image.cropping(to: cropRect) else {
                return nil
            }
            squareSource = cropped
        }

        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            side,
            side,
            kCVPixelFormatType_32ARGB,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(squareSource, in: CGRect(x: 0, y: 0, width: side, height: side))
        return pixelBuffer
    }
}
