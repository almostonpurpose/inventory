import Foundation

/// Single home for scan-pipeline thresholds and the label sets that were
/// previously duplicated across the analyzer and views.
enum ScanTuning {
    // MARK: - CLIP zero-shot scoring
    // Scores are raw cosine similarities against the vocabulary embeddings,
    // deliberately not softmaxed: an absolute threshold keeps an honest
    // "none of these" for out-of-vocabulary crops.

    /// Below this cosine a vocabulary match is discarded entirely.
    static let clipRejectCosine = 0.20

    /// At or above this cosine the CLIP name outranks detector and OCR evidence.
    static let clipAcceptCosine = 0.26

    /// Cosine mapped to the top of the confidence range.
    static let clipSaturationCosine = 0.38

    /// Maps a raw cosine similarity onto the 0...1 confidence scale the rest
    /// of the pipeline was tuned around. Returns nil below the reject floor.
    static func confidence(fromCosine cosine: Double) -> Double? {
        guard cosine > clipRejectCosine else {
            return nil
        }

        let fraction = (cosine - clipRejectCosine) / (clipSaturationCosine - clipRejectCosine)
        return min(0.95, 0.25 + fraction * 0.7)
    }

    // MARK: - Proposal reliability

    /// Proposals below this confidence are flagged for a detail scan and
    /// default to unselected/unreliable in review.
    static let reliableConfidence = 0.42

    // MARK: - Shared label sets

    /// Names that describe a container rather than its contents; demoted
    /// below OCR-derived names when picking an identity.
    static let genericContainerLabels: Set<String> = [
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

    /// Labels too vague to identify an item; treated as weak evidence only.
    static let weakIdentityLabels: Set<String> = [
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

    /// Detector classes never proposed as inventory (people and fixed fixtures).
    static let ignoredDetectorLabels: Set<String> = [
        "Person", "Human", "Face", "Hand", "Chair", "Couch", "Dining Table",
        "Bed", "Toilet", "Sink", "Refrigerator", "Oven"
    ]
}
