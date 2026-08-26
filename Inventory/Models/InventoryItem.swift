import CoreGraphics
import Foundation
import SwiftUI

enum ScanMission: String, CaseIterable, Codable, Identifiable {
    case roomSweep = "Room Sweep"
    case pantry = "Pantry"
    case fridge = "Fridge"
    case wardrobe = "Wardrobe"
    case drawer = "Drawer"
    case toolbox = "Toolbox"
    case toys = "Toys"
    case closeUp = "Close-up"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .roomSweep: "viewfinder"
        case .pantry: "cabinet"
        case .fridge: "refrigerator"
        case .wardrobe: "tshirt"
        case .drawer: "rectangle.split.3x1"
        case .toolbox: "hammer"
        case .toys: "gamecontroller"
        case .closeUp: "camera.macro"
        }
    }

    var suggestedCategory: InventoryCategory? {
        switch self {
        case .pantry, .fridge: .food
        case .wardrobe: .clothing
        case .toolbox: .tools
        case .toys: .toys
        case .roomSweep, .drawer, .closeUp: nil
        }
    }

    var guidance: String {
        switch self {
        case .roomSweep:
            "Capture each wall, then shelves and surfaces."
        case .pantry:
            "Capture shelf faces, labels, and any grouped supplies."
        case .fridge:
            "Open drawers and doors; expiry text helps later."
        case .wardrobe:
            "Capture rails, drawers, shoes, and bags by section."
        case .drawer:
            "Pull it open and capture from straight above."
        case .toolbox:
            "Capture labels, cases, tool faces, and serial plates."
        case .toys:
            "Capture bins, shelves, boxes, and loose groups."
        case .closeUp:
            "Use this for items marked as needing detail."
        }
    }
}

enum CaptureSourceKind: String, Codable, Hashable {
    case video = "Video"
    case photo = "Photo"
    case manual = "Manual"
}

enum InventoryCategory: String, CaseIterable, Codable, Identifiable {
    case clothing = "Clothing"
    case toys = "Toys"
    case food = "Food"
    case tools = "Tools"
    case electronics = "Electronics"
    case furniture = "Furniture"
    case books = "Books"
    case kitchen = "Kitchen"
    case bathroom = "Bathroom"
    case household = "Household"
    case sports = "Sports"
    case other = "Other"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .clothing: "tshirt"
        case .toys: "gamecontroller"
        case .food: "carrot"
        case .tools: "hammer"
        case .electronics: "cable.connector"
        case .furniture: "chair"
        case .books: "books.vertical"
        case .kitchen: "fork.knife"
        case .bathroom: "shower"
        case .household: "house"
        case .sports: "figure.run"
        case .other: "shippingbox"
        }
    }

    var tint: Color {
        switch self {
        case .clothing: .indigo
        case .toys: .purple
        case .food: .green
        case .tools: .orange
        case .electronics: .blue
        case .furniture: .brown
        case .books: .mint
        case .kitchen: .teal
        case .bathroom: .cyan
        case .household: .yellow
        case .sports: .red
        case .other: .gray
        }
    }

    static func suggested(for text: String) -> InventoryCategory {
        let value = text.lowercased()
        let rules: [(InventoryCategory, [String])] = [
            (.clothing, ["shirt", "jean", "jacket", "shoe", "dress", "coat", "sock", "sneaker", "trouser", "hat", "belt", "scarf", "glove", "bag", "backpack", "clothing", "wardrobe"]),
            (.toys, ["toy", "lego", "doll", "game", "puzzle", "plush", "teddy", "balloon", "blocks", "figurine", "play"]),
            (.food, ["food", "fruit", "vegetable", "snack", "cereal", "rice", "pasta", "coffee", "tea", "milk", "bread", "sauce", "beans", "tuna", "soup", "flour", "sugar", "salt", "pepper", "olive oil", "cooking oil", "juice"]),
            (.tools, ["tool", "hammer", "drill", "screwdriver", "wrench", "plier", "saw", "bolt", "nail", "screw", "ladder", "tape measure", "spray paint", "paint", "primer", "varnish", "aerosol", "adhesive", "glue", "sealant", "lubricant", "sandpaper", "duct tape", "masking tape"]),
            (.electronics, ["phone", "laptop", "computer", "charger", "cable", "adapter", "camera", "speaker", "headphone", "earbud", "keyboard", "mouse", "screen", "monitor", "tablet", "remote", "battery", "batteries"]),
            (.furniture, ["chair", "table", "desk", "sofa", "couch", "bed", "cabinet", "drawer", "shelf", "stool", "lamp"]),
            (.books, ["book", "magazine", "notebook", "binder", "paperback", "novel", "journal"]),
            (.kitchen, ["plate", "cup", "mug", "glass", "pan", "pot", "knife", "spoon", "fork", "bowl", "kettle", "toaster", "bottle opener", "spatula", "cutting board"]),
            (.bathroom, ["soap", "hand soap", "towel", "toothbrush", "toothpaste", "shampoo", "conditioner", "razor", "deodorant", "shower"]),
            (.sports, ["bike", "bicycle", "helmet", "tennis", "football", "basketball", "yoga", "skate", "golf"]),
            (.household, ["basket", "box", "bin", "vacuum", "broom", "cleaner", "detergent", "dish soap", "disinfectant", "bleach", "trash bags", "blanket", "pillow", "clock", "marker", "pen", "pencil"])
        ]

        for (category, keywords) in rules where keywords.contains(where: value.contains) {
            return category
        }

        return .other
    }
}

enum StockStatus: String, CaseIterable, Codable, Identifiable {
    case available = "Available"
    case low = "Low"
    case consumable = "Consumable"
    case archived = "Archived"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .available: "checkmark.circle"
        case .low: "exclamationmark.triangle"
        case .consumable: "arrow.down.circle"
        case .archived: "archivebox"
        }
    }
}

enum ItemCondition: String, CaseIterable, Codable, Identifiable {
    case unknown = "Unknown"
    case newLike = "New / Like New"
    case good = "Good"
    case worn = "Worn"
    case damaged = "Damaged"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .unknown: "questionmark.circle"
        case .newLike: "sparkles"
        case .good: "checkmark.seal"
        case .worn: "wrench.and.screwdriver"
        case .damaged: "exclamationmark.triangle"
        }
    }

    static func suggested(labels: [String], recognizedText: [String]) -> ItemCondition {
        let text = (labels + recognizedText).joined(separator: " ").lowercased()

        if ["broken", "cracked", "damaged", "torn", "stained", "rust", "missing"].contains(where: text.contains) {
            return .damaged
        }

        if ["worn", "used", "scratched", "scuffed", "old"].contains(where: text.contains) {
            return .worn
        }

        if ["new", "sealed", "unopened", "unused"].contains(where: text.contains) {
            return .newLike
        }

        return .unknown
    }
}

enum DetectionKind: String, Codable, Hashable {
    case yoloObject = "YOLO Object"
    case objectCrop = "Object Crop"
    case subjectLift = "Subject"
    case frameFallback = "Wide Frame"
    case manual = "Manual"
}

enum AssistantEventKind: String, CaseIterable, Codable, Identifiable {
    case detected = "Detected"
    case confirmed = "Confirmed"
    case edited = "Edited"
    case moved = "Moved"
    case quantityChanged = "Quantity Changed"
    case lowStock = "Low Stock"
    case needsDetailScan = "Needs Detail Scan"
    case deleted = "Deleted"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .detected: "sparkles.rectangle.stack"
        case .confirmed: "checkmark.circle"
        case .edited: "pencil"
        case .moved: "arrow.triangle.swap"
        case .quantityChanged: "number"
        case .lowStock: "exclamationmark.triangle"
        case .needsDetailScan: "viewfinder"
        case .deleted: "trash"
        }
    }
}

struct NormalizedRect: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.width
        height = rect.height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct InventoryEvidence: Identifiable, Codable, Hashable {
    var id = UUID()
    var sourceVideoName: String
    var timecode: Double
    var labels: [String]
    var recognizedText: [String]
    var barcode: String?
    var confidence: Double
    var photoFilename: String?
    var boundingBox: NormalizedRect?
    var detectionKind: DetectionKind?
    var captureSource: CaptureSourceKind?
    var scanMission: ScanMission?
    var scanID: UUID?
    var cameraMotion: CaptureMotionSample?
}

struct CaptureMotionSample: Codable, Hashable {
    var attitudeRoll: Double
    var attitudePitch: Double
    var attitudeYaw: Double
    var rotationRateX: Double
    var rotationRateY: Double
    var rotationRateZ: Double
    var gravityX: Double
    var gravityY: Double
    var gravityZ: Double
    var userAccelerationX: Double
    var userAccelerationY: Double
    var userAccelerationZ: Double
    var timestamp: Double

    var viewpointKey: String {
        let yawBucket = Int((attitudeYaw * 4).rounded())
        let pitchBucket = Int((attitudePitch * 4).rounded())
        let rollBucket = Int((attitudeRoll * 3).rounded())
        return "\(yawBucket):\(pitchBucket):\(rollBucket)"
    }

    func isNearby(_ other: CaptureMotionSample) -> Bool {
        abs(attitudeYaw - other.attitudeYaw) < 0.35
            && abs(attitudePitch - other.attitudePitch) < 0.28
            && abs(attitudeRoll - other.attitudeRoll) < 0.28
    }
}

struct InventoryItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var category: InventoryCategory
    var room: String
    var area: String?
    var container: String?
    var quantity: Int
    var status: StockStatus
    var condition: ItemCondition?
    var confidence: Double
    var photoFilename: String?
    var brand: String?
    var model: String?
    var serialNumber: String?
    var barcode: String?
    var color: String?
    var material: String?
    var size: String?
    var expiresAt: Date?
    var restockThreshold: Int?
    var replacementHint: String?
    var needsDetailScan: Bool?
    var lastSeenAt: Date?
    var scanMission: ScanMission?
    var tags: [String]?
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var evidence: [InventoryEvidence]

    var normalizedKey: String {
        "\(name.normalizedInventoryKey)|\(room.normalizedInventoryKey)|\(category.rawValue)"
    }
}

struct DetectedInventoryItem: Identifiable, Hashable {
    var id = UUID()
    var isSelected = true
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
    var timecodes: [Double]
    var boundingBox: NormalizedRect?
    var detectionKind: DetectionKind
    var captureSource: CaptureSourceKind
    var scanID: UUID
    var sourceVideoName: String
    var cameraMotion: CaptureMotionSample?

    var evidenceSummary: String {
        let labelText = labels.prefix(3).joined(separator: ", ")
        let textParts = ([barcode].filter { !$0.isEmpty } + Array(recognizedText.prefix(2)))
        let text = textParts.joined(separator: ", ")

        if !labelText.isEmpty && !text.isEmpty {
            return "\(labelText) - \(text)"
        } else if !labelText.isEmpty {
            return labelText
        } else if !text.isEmpty {
            return text
        } else {
            return "Video evidence"
        }
    }

    func makeInventoryItem() -> InventoryItem {
        let now = Date()
        let itemEvidence = timecodes.map { timecode in
            InventoryEvidence(
                sourceVideoName: sourceVideoName,
                timecode: timecode,
                labels: labels,
                recognizedText: recognizedText,
                barcode: barcode.trimmed.isEmpty ? nil : barcode.trimmed,
                confidence: confidence,
                photoFilename: photoFilename,
                boundingBox: boundingBox,
                detectionKind: detectionKind,
                captureSource: captureSource,
                scanMission: scanMission,
                scanID: scanID,
                cameraMotion: cameraMotion
            )
        }

        return InventoryItem(
            name: name.trimmed,
            category: category,
            room: room.trimmed.isEmpty ? "Unsorted" : room.trimmed,
            area: area.nilIfBlank,
            container: container.nilIfBlank,
            quantity: max(1, quantity),
            status: category == .food ? .consumable : .available,
            condition: condition,
            confidence: confidence,
            photoFilename: photoFilename,
            brand: brand.nilIfBlank,
            model: model.nilIfBlank,
            serialNumber: serialNumber.nilIfBlank,
            barcode: barcode.nilIfBlank,
            color: color.nilIfBlank,
            material: material.nilIfBlank,
            size: size.nilIfBlank,
            expiresAt: expiresAt,
            restockThreshold: restockThreshold,
            replacementHint: replacementHint.nilIfBlank,
            needsDetailScan: needsDetailScan,
            lastSeenAt: now,
            scanMission: scanMission,
            tags: tags.isEmpty ? nil : tags,
            notes: "",
            createdAt: now,
            updatedAt: now,
            evidence: itemEvidence
        )
    }
}

struct AssistantEvent: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: AssistantEventKind
    var itemID: UUID?
    var itemName: String
    var category: InventoryCategory?
    var place: String
    var quantity: Int?
    var confidence: Double?
    var message: String
    var createdAt: Date
}

struct AssistantSnapshot: Codable {
    var generatedAt: Date
    var itemCount: Int
    var totalQuantity: Int
    var places: [String]
    var lowStock: [String]
    var expiringSoon: [String]
    var needsDetailScan: [String]
    var items: [AssistantSnapshotItem]
    var recentEvents: [AssistantEvent]
}

struct AssistantSnapshotItem: Codable, Identifiable {
    var id: UUID
    var name: String
    var category: String
    var place: String
    var quantity: Int
    var status: String
    var condition: String?
    var brand: String?
    var model: String?
    var barcode: String?
    var expiresAt: Date?
    var restockThreshold: Int?
    var needsDetailScan: Bool
    var tags: [String]
    var notes: String
}

struct LaptopReviewPackage: Codable {
    var generatedAt: Date
    var itemCount: Int
    var items: [LaptopReviewItem]
}

struct LaptopReviewItem: Codable, Identifiable {
    var id: UUID
    var name: String
    var category: String
    var place: String
    var quantity: Int
    var confidence: Double
    var needsDetailScan: Bool
    var photoFilename: String?
    var photoJPEGBase64: String?
    var labels: [String]
    var recognizedText: [String]
    var barcode: String?
    var notes: String
}

extension InventoryItem {
    var placeDescription: String {
        [room, area, container]
            .compactMap { $0?.trimmed }
            .filter { !$0.isEmpty }
            .joined(separator: " > ")
    }

    var assistantTitle: String {
        var parts = [name]

        if let brand, !brand.trimmed.isEmpty {
            parts.append(brand)
        }

        if let model, !model.trimmed.isEmpty {
            parts.append(model)
        }

        return parts.joined(separator: " - ")
    }

    var isConsumable: Bool {
        status == .consumable || category == .food || restockThreshold != nil || expiresAt != nil
    }

    var isLowStock: Bool {
        status == .low || restockThreshold.map { quantity <= $0 } == true
    }

    var isExpiringSoon: Bool {
        guard let expiresAt else {
            return false
        }

        let now = Date()
        let soon = Calendar.current.date(byAdding: .day, value: 10, to: now) ?? now
        return expiresAt >= now && expiresAt <= soon
    }

    var hasUsefulAssistantContext: Bool {
        confidence >= 0.55 && needsDetailScan != true
    }

    var assistantSnapshotItem: AssistantSnapshotItem {
        AssistantSnapshotItem(
            id: id,
            name: name,
            category: category.rawValue,
            place: placeDescription,
            quantity: quantity,
            status: status.rawValue,
            condition: condition?.rawValue,
            brand: brand,
            model: model,
            barcode: barcode,
            expiresAt: expiresAt,
            restockThreshold: restockThreshold,
            needsDetailScan: needsDetailScan ?? false,
            tags: tags ?? [],
            notes: notes
        )
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedInventoryKey: String {
        let allowed = lowercased().unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }

        return String(allowed)
            .split(separator: " ")
            .map(String.init)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var inventoryTitleCased: String {
        split(separator: " ")
            .map { word in
                let lower = word.lowercased()
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }

    var nilIfBlank: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }
}
