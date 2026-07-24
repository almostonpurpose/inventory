import Foundation

struct InventoryUserProfile: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var createdAt: Date
    var updatedAt: Date

    static let defaultProfile = InventoryUserProfile(
        id: "default",
        name: "My Home",
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}

@MainActor
final class InventoryStore: ObservableObject {
    @Published private(set) var items: [InventoryItem] = []
    @Published private(set) var events: [AssistantEvent] = []
    @Published private(set) var profiles: [InventoryUserProfile] = []
    @Published private(set) var currentProfile: InventoryUserProfile = .defaultProfile
    @Published var lastError: String?

    private let currentProfileDefaultsKey = "HomeInventory.currentProfileID"

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private var appDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HomeInventory", isDirectory: true)
    }

    private var profilesDirectory: URL {
        appDirectory.appendingPathComponent("Profiles", isDirectory: true)
    }

    private var profilesFileURL: URL {
        appDirectory.appendingPathComponent("profiles.json")
    }

    private var currentProfileDirectory: URL {
        profilesDirectory.appendingPathComponent(currentProfile.id, isDirectory: true)
    }

    private var fileURL: URL {
        currentProfileDirectory.appendingPathComponent("inventory-items.json")
    }

    private var eventsFileURL: URL {
        currentProfileDirectory.appendingPathComponent("assistant-events.json")
    }

    func load() {
        do {
            try ensureBaseDirectory()
            try loadProfiles()
            clearLegacyGlobalData()
            InventoryPhotoStore.useProfile(currentProfile.id)
            try ensureStorageDirectory()
            try loadCurrentProfileData()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func selectProfile(_ profile: InventoryUserProfile) {
        guard profiles.contains(where: { $0.id == profile.id }) else {
            return
        }

        currentProfile = profile
        UserDefaults.standard.set(profile.id, forKey: currentProfileDefaultsKey)
        InventoryPhotoStore.useProfile(profile.id)

        do {
            try ensureStorageDirectory()
            try loadCurrentProfileData()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func switchToProfile(named rawName: String) {
        let name = rawName.trimmed.isEmpty ? "My Home" : rawName.trimmed

        if let existing = profiles.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            selectProfile(existing)
            return
        }

        let now = Date()
        let profile = InventoryUserProfile(
            id: "profile-\(UUID().uuidString)",
            name: name,
            createdAt: now,
            updatedAt: now
        )

        profiles.append(profile)
        profiles.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        currentProfile = profile
        UserDefaults.standard.set(profile.id, forKey: currentProfileDefaultsKey)
        InventoryPhotoStore.useProfile(profile.id)

        do {
            try persistProfiles()
            try ensureStorageDirectory()
            items = []
            events = []
            persist()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearCurrentProfileData() {
        let profileID = currentProfile.id
        items = []
        events = []

        do {
            try InventoryPhotoStore.deleteAllPhotos(for: profileID)

            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }

            if FileManager.default.fileExists(atPath: eventsFileURL.path) {
                try FileManager.default.removeItem(at: eventsFileURL)
            }

            try ensureStorageDirectory()
            persist()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func addDetected(_ proposals: [DetectedInventoryItem]) {
        for proposal in proposals where proposal.isSelected {
            let item = proposal.makeInventoryItem()
            items.append(item)
            recordEvent(
                .confirmed,
                item: item,
                message: "\(item.name) confirmed from \(proposal.captureSource.rawValue.lowercased()) scan."
            )

            if item.needsDetailScan == true {
                recordEvent(
                    .needsDetailScan,
                    item: item,
                    message: "\(item.name) needs a close-up scan for better assistant context."
                )
            }
        }

        items.sort(using: inventorySort)
        persist()
    }

    func addManual(_ draft: InventoryItemDraft) {
        let now = Date()
        let item = InventoryItem(
            name: draft.name.trimmed,
            category: draft.category,
            room: draft.room.trimmed.isEmpty ? "Unsorted" : draft.room.trimmed,
            area: draft.area.nilIfBlank,
            container: draft.container.nilIfBlank,
            quantity: max(1, draft.quantity),
            status: draft.status,
            condition: draft.condition,
            confidence: 1,
            photoFilename: nil,
            brand: draft.brand.nilIfBlank,
            model: draft.model.nilIfBlank,
            serialNumber: draft.serialNumber.nilIfBlank,
            barcode: draft.barcode.nilIfBlank,
            color: draft.color.nilIfBlank,
            material: draft.material.nilIfBlank,
            size: draft.size.nilIfBlank,
            expiresAt: draft.expiresAt,
            restockThreshold: draft.restockThreshold,
            replacementHint: draft.replacementHint.nilIfBlank,
            needsDetailScan: draft.needsDetailScan,
            lastSeenAt: now,
            scanMission: nil,
            tags: draft.tags,
            notes: draft.notes.trimmed,
            createdAt: now,
            updatedAt: now,
            evidence: []
        )

        items.append(item)
        recordEvent(.confirmed, item: item, message: "\(item.name) was added manually.")
        items.sort(using: inventorySort)
        persist()
    }

    func update(_ item: InventoryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        let previous = items[index]
        var updated = item
        updated.name = updated.name.trimmed
        updated.room = updated.room.trimmed.isEmpty ? "Unsorted" : updated.room.trimmed
        updated.area = updated.area?.nilIfBlank
        updated.container = updated.container?.nilIfBlank
        updated.quantity = max(1, updated.quantity)
        updated.updatedAt = Date()
        items[index] = updated

        if previous.placeDescription != updated.placeDescription {
            recordEvent(.moved, item: updated, message: "\(updated.name) is now in \(updated.placeDescription).")
        } else if previous.quantity != updated.quantity {
            recordEvent(.quantityChanged, item: updated, message: "\(updated.name) quantity changed to \(updated.quantity).")
        } else {
            recordEvent(.edited, item: updated, message: "\(updated.name) was updated.")
        }

        if updated.isLowStock {
            recordEvent(.lowStock, item: updated, message: "\(updated.name) is at or below its restock threshold.")
        }

        items.sort(using: inventorySort)
        persist()
    }

    func delete(_ item: InventoryItem) {
        items.removeAll { $0.id == item.id }
        recordEvent(.deleted, item: item, message: "\(item.name) was removed from inventory.")
        persist()
    }

    func items(in room: String) -> [InventoryItem] {
        items.filter { $0.room == room }.sorted(using: inventorySort)
    }

    func markNeedsDetailScan(_ item: InventoryItem, needsDetailScan: Bool) {
        var updated = item
        updated.needsDetailScan = needsDetailScan
        update(updated)
    }

    func assistantSnapshot() -> AssistantSnapshot {
        let places = Set(items.map(\.placeDescription).filter { !$0.isEmpty })
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        return AssistantSnapshot(
            generatedAt: Date(),
            itemCount: items.count,
            totalQuantity: items.reduce(0) { $0 + $1.quantity },
            places: places,
            lowStock: items.filter(\.isLowStock).map(\.assistantTitle),
            expiringSoon: items.filter(\.isExpiringSoon).map(\.assistantTitle),
            needsDetailScan: items.filter { $0.needsDetailScan == true }.map(\.assistantTitle),
            items: items.map(\.assistantSnapshotItem),
            recentEvents: Array(events.prefix(80))
        )
    }

    func makeAssistantSnapshotFile() throws -> URL {
        try ensureStorageDirectory()
        let data = try encoder.encode(assistantSnapshot())
        let url = fileURL.deletingLastPathComponent().appendingPathComponent("assistant-snapshot.json")
        try data.write(to: url, options: [.atomic])
        return url
    }

    func makeLaptopReviewPackageFile() throws -> URL {
        try ensureStorageDirectory()

        let reviewItems = items
            .filter { $0.needsDetailScan == true || $0.confidence < 0.7 }
            .prefix(120)
            .map { item in
                let photoData = InventoryPhotoStore.url(for: item.photoFilename)
                    .flatMap { try? Data(contentsOf: $0) }

                return LaptopReviewItem(
                    id: item.id,
                    name: item.name,
                    category: item.category.rawValue,
                    place: item.placeDescription,
                    quantity: item.quantity,
                    confidence: item.confidence,
                    needsDetailScan: item.needsDetailScan ?? false,
                    photoFilename: item.photoFilename,
                    photoJPEGBase64: photoData?.base64EncodedString(),
                    labels: Array(Set(item.evidence.flatMap(\.labels))).sorted(),
                    recognizedText: Array(Set(item.evidence.flatMap(\.recognizedText))).sorted(),
                    barcode: item.barcode,
                    notes: item.notes
                )
            }

        let package = LaptopReviewPackage(
            generatedAt: Date(),
            itemCount: reviewItems.count,
            items: Array(reviewItems)
        )
        let data = try encoder.encode(package)
        let url = fileURL.deletingLastPathComponent().appendingPathComponent("laptop-review-package.json")
        try data.write(to: url, options: [.atomic])
        return url
    }

    private func mergeOrAppend(_ incoming: InventoryItem) {
        if let index = items.firstIndex(where: { $0.normalizedKey == incoming.normalizedKey }) {
            var existing = items[index]
            existing.quantity += incoming.quantity
            existing.confidence = max(existing.confidence, incoming.confidence)
            existing.evidence.append(contentsOf: incoming.evidence)
            existing.status = incoming.status == .consumable ? .consumable : existing.status
            existing.updatedAt = Date()
            items[index] = existing
        } else {
            items.append(incoming)
        }
    }

    private func persist() {
        do {
            try ensureStorageDirectory()
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: [.atomic])
            let eventData = try encoder.encode(Array(events.prefix(500)))
            try eventData.write(to: eventsFileURL, options: [.atomic])
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func ensureStorageDirectory() throws {
        try FileManager.default.createDirectory(at: currentProfileDirectory, withIntermediateDirectories: true)
    }

    private func ensureBaseDirectory() throws {
        try FileManager.default.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)
    }

    private func loadProfiles() throws {
        if FileManager.default.fileExists(atPath: profilesFileURL.path) {
            let data = try Data(contentsOf: profilesFileURL)
            profiles = try decoder.decode([InventoryUserProfile].self, from: data)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }

        if profiles.isEmpty {
            profiles = [.defaultProfile]
            try persistProfiles()
        }

        let storedProfileID = UserDefaults.standard.string(forKey: currentProfileDefaultsKey)
        currentProfile = profiles.first { $0.id == storedProfileID }
            ?? profiles.first { $0.id == InventoryUserProfile.defaultProfile.id }
            ?? profiles[0]
        UserDefaults.standard.set(currentProfile.id, forKey: currentProfileDefaultsKey)
    }

    private func persistProfiles() throws {
        try ensureBaseDirectory()
        let data = try encoder.encode(profiles)
        try data.write(to: profilesFileURL, options: [.atomic])
    }

    private func loadCurrentProfileData() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            items = try decoder.decode([InventoryItem].self, from: data)
                .sorted(using: inventorySort)
        } else {
            items = []
        }

        if FileManager.default.fileExists(atPath: eventsFileURL.path) {
            let eventData = try Data(contentsOf: eventsFileURL)
            events = try decoder.decode([AssistantEvent].self, from: eventData)
                .sorted { $0.createdAt > $1.createdAt }
        } else {
            events = []
        }
    }

    private func clearLegacyGlobalData() {
        let legacyURLs = [
            appDirectory.appendingPathComponent("inventory-items.json"),
            appDirectory.appendingPathComponent("assistant-events.json"),
            appDirectory.appendingPathComponent("assistant-snapshot.json"),
            appDirectory.appendingPathComponent("laptop-review-package.json"),
            appDirectory.appendingPathComponent("ObjectPhotos", isDirectory: true)
        ]

        for url in legacyURLs where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func recordEvent(_ kind: AssistantEventKind, item: InventoryItem, message: String) {
        events.insert(
            AssistantEvent(
                kind: kind,
                itemID: item.id,
                itemName: item.name,
                category: item.category,
                place: item.placeDescription,
                quantity: item.quantity,
                confidence: item.confidence,
                message: message,
                createdAt: Date()
            ),
            at: 0
        )

        if events.count > 500 {
            events = Array(events.prefix(500))
        }
    }
}

private let inventorySort = SortDescriptor<InventoryItem>(\.name, comparator: .localizedStandard)
