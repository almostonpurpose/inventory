import SwiftUI

struct ItemEditorView: View {
    enum Mode {
        case create(defaultRoom: String?)
        case edit(InventoryItem)
    }

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var category: InventoryCategory
    @State private var room: String
    @State private var area: String
    @State private var container: String
    @State private var quantity: Int
    @State private var status: StockStatus
    @State private var condition: ItemCondition
    @State private var brand: String
    @State private var model: String
    @State private var serialNumber: String
    @State private var barcode: String
    @State private var color: String
    @State private var material: String
    @State private var size: String
    @State private var hasExpiryDate: Bool
    @State private var expiresAt: Date
    @State private var hasRestockThreshold: Bool
    @State private var restockThreshold: Int
    @State private var replacementHint: String
    @State private var needsDetailScan: Bool
    @State private var tagsText: String
    @State private var notes: String

    private let mode: Mode
    private let onSave: (InventoryItemDraft) -> Void

    init(mode: Mode, onSave: @escaping (InventoryItemDraft) -> Void) {
        self.mode = mode
        self.onSave = onSave

        switch mode {
        case .create(let defaultRoom):
            _name = State(initialValue: "")
            _category = State(initialValue: .other)
            _room = State(initialValue: defaultRoom ?? "")
            _area = State(initialValue: "")
            _container = State(initialValue: "")
            _quantity = State(initialValue: 1)
            _status = State(initialValue: .available)
            _condition = State(initialValue: .unknown)
            _brand = State(initialValue: "")
            _model = State(initialValue: "")
            _serialNumber = State(initialValue: "")
            _barcode = State(initialValue: "")
            _color = State(initialValue: "")
            _material = State(initialValue: "")
            _size = State(initialValue: "")
            _hasExpiryDate = State(initialValue: false)
            _expiresAt = State(initialValue: Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date())
            _hasRestockThreshold = State(initialValue: false)
            _restockThreshold = State(initialValue: 1)
            _replacementHint = State(initialValue: "")
            _needsDetailScan = State(initialValue: false)
            _tagsText = State(initialValue: "")
            _notes = State(initialValue: "")
        case .edit(let item):
            _name = State(initialValue: item.name)
            _category = State(initialValue: item.category)
            _room = State(initialValue: item.room)
            _area = State(initialValue: item.area ?? "")
            _container = State(initialValue: item.container ?? "")
            _quantity = State(initialValue: item.quantity)
            _status = State(initialValue: item.status)
            _condition = State(initialValue: item.condition ?? .unknown)
            _brand = State(initialValue: item.brand ?? "")
            _model = State(initialValue: item.model ?? "")
            _serialNumber = State(initialValue: item.serialNumber ?? "")
            _barcode = State(initialValue: item.barcode ?? "")
            _color = State(initialValue: item.color ?? "")
            _material = State(initialValue: item.material ?? "")
            _size = State(initialValue: item.size ?? "")
            _hasExpiryDate = State(initialValue: item.expiresAt != nil)
            _expiresAt = State(initialValue: item.expiresAt ?? Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date())
            _hasRestockThreshold = State(initialValue: item.restockThreshold != nil)
            _restockThreshold = State(initialValue: item.restockThreshold ?? 1)
            _replacementHint = State(initialValue: item.replacementHint ?? "")
            _needsDetailScan = State(initialValue: item.needsDetailScan ?? false)
            _tagsText = State(initialValue: item.tags?.joined(separator: ", ") ?? "")
            _notes = State(initialValue: item.notes)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)

                    Picker("Category", selection: $category) {
                        ForEach(InventoryCategory.allCases) { category in
                            Label(category.rawValue, systemImage: category.symbolName)
                                .tag(category)
                        }
                    }

                    TextField("Room", text: $room)
                        .textInputAutocapitalization(.words)
                    TextField("Shelf, drawer, wall, zone", text: $area)
                        .textInputAutocapitalization(.words)
                    TextField("Box, bin, bag, cabinet", text: $container)
                        .textInputAutocapitalization(.words)
                }

                Section {
                    Stepper(value: $quantity, in: 1...999) {
                        Text("Quantity: \(quantity)")
                    }

                    Picker("Status", selection: $status) {
                        ForEach(StockStatus.allCases) { status in
                            Label(status.rawValue, systemImage: status.symbolName)
                                .tag(status)
                        }
                    }

                    Picker("Condition", selection: $condition) {
                        ForEach(ItemCondition.allCases) { condition in
                            Label(condition.rawValue, systemImage: condition.symbolName)
                                .tag(condition)
                        }
                    }

                    HStack {
                        Toggle("Needs Detail Scan", isOn: $needsDetailScan)
                        InfoHelpButton(
                            title: "Needs Detail Scan",
                            message: "Turn this on when the assistant should treat the item as incomplete until you capture or enter better details."
                        )
                    }
                } header: {
                    InfoSectionHeader(
                        title: "Stock",
                        infoTitle: "Stock Fields",
                        message: "Quantity, status, and condition feed restocking and organising suggestions. Detail Scan marks uncertain records for follow-up."
                    )
                }

                Section {
                    TextField("Brand", text: $brand)
                        .textInputAutocapitalization(.words)
                    TextField("Model", text: $model)
                    TextField("Serial number", text: $serialNumber)
                        .textInputAutocapitalization(.characters)
                    TextField("Barcode", text: $barcode)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Color", text: $color)
                        .textInputAutocapitalization(.words)
                    TextField("Material", text: $material)
                        .textInputAutocapitalization(.words)
                    TextField("Size", text: $size)
                    TextField("Replacement hint", text: $replacementHint)
                    TextField("Tags", text: $tagsText)
                } header: {
                    InfoSectionHeader(
                        title: "Metadata",
                        infoTitle: "Metadata",
                        message: "These optional fields make assistant answers more specific. Barcodes, model numbers, tags, and replacement hints are useful for finding, restocking, and repair advice."
                    )
                }

                Section {
                    Toggle("Has Expiry Date", isOn: $hasExpiryDate)

                    if hasExpiryDate {
                        DatePicker("Expires", selection: $expiresAt, displayedComponents: .date)
                    }

                    Toggle("Track Restock Level", isOn: $hasRestockThreshold)

                    if hasRestockThreshold {
                        Stepper(value: $restockThreshold, in: 1...999) {
                            Text("Restock below \(restockThreshold)")
                        }
                    }
                } header: {
                    InfoSectionHeader(
                        title: "Assistant Signals",
                        infoTitle: "Assistant Signals",
                        message: "Expiry dates and restock levels let the assistant warn about food, toiletries, supplies, or anything else you consume over time."
                    )
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(InventoryItemDraft(
                            name: name,
                            category: category,
                            room: room,
                            area: area,
                            container: container,
                            quantity: quantity,
                            status: status,
                            condition: condition,
                            brand: brand,
                            model: model,
                            serialNumber: serialNumber,
                            barcode: barcode,
                            color: color,
                            material: material,
                            size: size,
                            expiresAt: hasExpiryDate ? expiresAt : nil,
                            restockThreshold: hasRestockThreshold ? restockThreshold : nil,
                            replacementHint: replacementHint,
                            needsDetailScan: needsDetailScan,
                            tags: parsedTags,
                            notes: notes
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmed.isEmpty)
                }
            }
        }
    }

    private var title: String {
        switch mode {
        case .create: "Add Item"
        case .edit: "Edit Item"
        }
    }

    private var parsedTags: [String] {
        tagsText
            .split(separator: ",")
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }
    }
}

struct InventoryItemDraft {
    var name: String
    var category: InventoryCategory
    var room: String
    var area: String
    var container: String
    var quantity: Int
    var status: StockStatus
    var condition: ItemCondition
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
    var tags: [String]
    var notes: String
}
