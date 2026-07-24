import SwiftUI

struct InventoryDetailView: View {
    @EnvironmentObject private var store: InventoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditor = false
    @State private var showingDeleteConfirmation = false

    var itemID: UUID

    private var item: InventoryItem? {
        store.items.first { $0.id == itemID }
    }

    var body: some View {
        Group {
            if let item {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 14) {
                            InventoryPhotoView(
                                filename: item.photoFilename,
                                symbolName: item.category.symbolName,
                                tint: item.category.tint,
                                cornerRadius: 8
                            )
                            .frame(maxWidth: .infinity)
                            .aspectRatio(4 / 3, contentMode: .fit)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.title3.bold())
                                Text("\(item.category.rawValue) - \(item.placeDescription)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }

                    Section {
                        LabeledContent("Quantity", value: "\(item.quantity)")
                        LabeledContent("Status") {
                            Label(item.status.rawValue, systemImage: item.status.symbolName)
                        }
                        LabeledContent("Condition") {
                            let condition = item.condition ?? .unknown
                            Label(condition.rawValue, systemImage: condition.symbolName)
                        }
                        LabeledContent("Confidence", value: item.confidence.formatted(.percent.precision(.fractionLength(0))))
                        if let mission = item.scanMission {
                            LabeledContent("Scan Mission") {
                                Label(mission.rawValue, systemImage: mission.symbolName)
                            }
                        }
                        if let lastSeenAt = item.lastSeenAt {
                            LabeledContent("Last Seen", value: lastSeenAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        HStack {
                            Toggle("Needs Detail Scan", isOn: Binding(
                                get: { item.needsDetailScan ?? false },
                                set: { store.markNeedsDetailScan(item, needsDetailScan: $0) }
                            ))
                            InfoHelpButton(
                                title: "Needs Detail Scan",
                                message: "This marks the record as useful but incomplete. It will show up in assistant follow-up lists until you clear it."
                            )
                        }
                    } header: {
                        InfoSectionHeader(
                            title: "Status",
                            infoTitle: "Item Status",
                            message: "Status, condition, confidence, and last-seen data help the assistant decide how reliable this item is and whether it needs follow-up."
                        )
                    }

                    Section("Place") {
                        LabeledContent("Room", value: item.room)
                        if let area = item.area, !area.isEmpty {
                            LabeledContent("Area", value: area)
                        }
                        if let container = item.container, !container.isEmpty {
                            LabeledContent("Container", value: container)
                        }
                    }

                    if item.hasStructuredMetadata {
                        Section("Metadata") {
                            if let brand = item.brand, !brand.isEmpty {
                                LabeledContent("Brand", value: brand)
                            }
                            if let model = item.model, !model.isEmpty {
                                LabeledContent("Model", value: model)
                            }
                            if let serialNumber = item.serialNumber, !serialNumber.isEmpty {
                                LabeledContent("Serial", value: serialNumber)
                            }
                            if let barcode = item.barcode, !barcode.isEmpty {
                                LabeledContent("Barcode", value: barcode)
                            }
                            if let color = item.color, !color.isEmpty {
                                LabeledContent("Color", value: color)
                            }
                            if let material = item.material, !material.isEmpty {
                                LabeledContent("Material", value: material)
                            }
                            if let size = item.size, !size.isEmpty {
                                LabeledContent("Size", value: size)
                            }
                            if let replacementHint = item.replacementHint, !replacementHint.isEmpty {
                                LabeledContent("Replacement", value: replacementHint)
                            }
                            if let tags = item.tags, !tags.isEmpty {
                                LabeledContent("Tags", value: tags.joined(separator: ", "))
                            }
                        }
                    }

                    if item.isConsumable {
                        Section {
                            if let expiresAt = item.expiresAt {
                                LabeledContent("Expires", value: expiresAt.formatted(date: .abbreviated, time: .omitted))
                            }
                            if let restockThreshold = item.restockThreshold {
                                LabeledContent("Restock Below", value: "\(restockThreshold)")
                            }
                            LabeledContent("Low Stock") {
                                Label(item.isLowStock ? "Yes" : "No", systemImage: item.isLowStock ? "exclamationmark.triangle" : "checkmark.circle")
                                    .foregroundStyle(item.isLowStock ? .orange : .secondary)
                            }
                        } header: {
                            InfoSectionHeader(
                                title: "Assistant Signals",
                                infoTitle: "Assistant Signals",
                                message: "These are the fields that power expiry warnings, shopping prompts, and restocking suggestions."
                            )
                        }
                    }

                    if !item.notes.trimmed.isEmpty {
                        Section("Notes") {
                            Text(item.notes)
                        }
                    }

                    if !item.evidence.isEmpty {
                        Section {
                            ForEach(item.evidence.prefix(12)) { evidence in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(evidence.sourceVideoName)
                                        .font(.subheadline.weight(.medium))
                                    Text(evidence.captureSource == .photo ? "Seen in photo sweep" : "Seen at \(evidence.timecode.formatted(.number.precision(.fractionLength(1))))s")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    if let barcode = evidence.barcode, !barcode.isEmpty {
                                        Text("Barcode: \(barcode)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    if !evidence.labels.isEmpty {
                                        Text(evidence.labels.prefix(4).joined(separator: ", "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    if !evidence.recognizedText.isEmpty {
                                        Text(evidence.recognizedText.prefix(3).joined(separator: ", "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                        } header: {
                            InfoSectionHeader(
                                title: "Evidence",
                                infoTitle: "Evidence",
                                message: "Evidence shows why the item exists: source scan, visual labels, OCR text, barcode, crop confidence, and where it appeared."
                            )
                        }
                    }

                    Section {
                        Button("Delete Item", role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                    }
                }
                .navigationTitle(item.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    Button("Edit") {
                        showingEditor = true
                    }
                }
                .sheet(isPresented: $showingEditor) {
                    ItemEditorView(mode: .edit(item)) { draft in
                        var updated = item
                        updated.name = draft.name
                        updated.category = draft.category
                        updated.room = draft.room
                        updated.area = draft.area.nilIfBlank
                        updated.container = draft.container.nilIfBlank
                        updated.quantity = draft.quantity
                        updated.status = draft.status
                        updated.condition = draft.condition
                        updated.brand = draft.brand.nilIfBlank
                        updated.model = draft.model.nilIfBlank
                        updated.serialNumber = draft.serialNumber.nilIfBlank
                        updated.barcode = draft.barcode.nilIfBlank
                        updated.color = draft.color.nilIfBlank
                        updated.material = draft.material.nilIfBlank
                        updated.size = draft.size.nilIfBlank
                        updated.expiresAt = draft.expiresAt
                        updated.restockThreshold = draft.restockThreshold
                        updated.replacementHint = draft.replacementHint.nilIfBlank
                        updated.needsDetailScan = draft.needsDetailScan
                        updated.tags = draft.tags.isEmpty ? nil : draft.tags
                        updated.notes = draft.notes
                        store.update(updated)
                    }
                }
                .confirmationDialog("Delete this item?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        store.delete(item)
                        dismiss()
                    }
                }
            } else {
                ContentUnavailableView("Item not found", systemImage: "questionmark.folder")
            }
        }
    }
}

private extension InventoryItem {
    var hasStructuredMetadata: Bool {
        [brand, model, serialNumber, barcode, color, material, size, replacementHint]
            .contains { ($0 ?? "").trimmed.isEmpty == false }
            || (tags?.isEmpty == false)
    }
}
