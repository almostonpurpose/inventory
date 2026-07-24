import SwiftUI

struct ReviewDetectionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var proposals: [DetectedInventoryItem]

    var onSave: ([DetectedInventoryItem]) -> Void

    private var selectedCount: Int {
        proposals.filter(\.isSelected).count
    }

    private var needsDetailCount: Int {
        proposals.filter { $0.isSelected && $0.needsDetailScan }.count
    }

    private var reviewOnlyCount: Int {
        proposals.count - selectedCount
    }

    var body: some View {
        NavigationStack {
            List {
                if proposals.isEmpty {
                    ContentUnavailableView("No object cards", systemImage: "sparkles.rectangle.stack")
                } else {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(isOn: Binding(
                                get: { selectedCount == proposals.count },
                                set: { newValue in
                                    for index in proposals.indices {
                                        proposals[index].isSelected = newValue
                                    }
                                }
                            )) {
                                Text("\(selectedCount) of \(proposals.count) selected")
                            }

                            if needsDetailCount > 0 {
                                Label("\(needsDetailCount) marked for close-up scan", systemImage: "viewfinder")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }

                            if reviewOnlyCount > 0 {
                                Label("\(reviewOnlyCount) weak cards left unselected", systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Label("Saved cards become assistant memory events", systemImage: "brain.head.profile")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                Button {
                                    selectReliableOnly()
                                } label: {
                                    Label("Reliable Only", systemImage: "checkmark.seal")
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    for index in proposals.indices {
                                        proposals[index].isSelected = true
                                    }
                                } label: {
                                    Label("Select All", systemImage: "checklist")
                                }
                                .buttonStyle(.bordered)
                            }
                            .font(.caption)
                        }
                    } header: {
                        InfoSectionHeader(
                            title: "Review",
                            infoTitle: "Review Before Saving",
                            message: "Each detected object becomes a card you can accept, rename, move, or mark for a better close-up scan before it enters assistant memory."
                        )
                    }

                    Section {
                        ForEach($proposals) { $proposal in
                            DetectionCard(proposal: $proposal)
                        }
                    } header: {
                        InfoSectionHeader(
                            title: "Object Cards",
                            infoTitle: "Object Cards",
                            message: "Cards are built from object crops. The image model proposes the item, while text, barcode, color, place, and mission context can add supporting metadata."
                        )
                    }
                }
            }
            .navigationTitle("Review Objects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(proposals.filter(\.isSelected))
                        dismiss()
                    }
                    .disabled(selectedCount == 0)
                }
            }
        }
    }

    private func selectReliableOnly() {
        for index in proposals.indices {
            proposals[index].isSelected = proposalIsReliable(proposals[index])
        }
    }

    private func proposalIsReliable(_ proposal: DetectedInventoryItem) -> Bool {
        if !proposal.barcode.trimmed.isEmpty {
            return true
        }

        let genericNames: Set<String> = [
            "unidentified item", "bag", "basket", "bottle", "box", "bucket",
            "can", "carton", "case", "container", "jar", "package", "packet",
            "tin", "tube"
        ]

        return proposal.confidence >= 0.42
            && !genericNames.contains(proposal.name.normalizedInventoryKey)
    }
}

private struct DetectionCard: View {
    @Binding var proposal: DetectedInventoryItem
    @State private var isExpanded = false

    var body: some View {
        let expiresBinding = Binding<Date>(
            get: {
                proposal.expiresAt ?? Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
            },
            set: { proposal.expiresAt = $0 }
        )
        let hasExpiryBinding = Binding<Bool>(
            get: { proposal.expiresAt != nil },
            set: { proposal.expiresAt = $0 ? Date() : nil }
        )
        let restockBinding = Binding<Int>(
            get: { proposal.restockThreshold ?? 1 },
            set: { proposal.restockThreshold = max(1, $0) }
        )
        let hasRestockBinding = Binding<Bool>(
            get: { proposal.restockThreshold != nil },
            set: { proposal.restockThreshold = $0 ? max(1, proposal.quantity) : nil }
        )

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                InventoryPhotoView(
                    filename: proposal.photoFilename,
                    symbolName: proposal.category.symbolName,
                    tint: proposal.category.tint,
                    cornerRadius: 8
                )
                .frame(width: 104, height: 104)
                .overlay(alignment: .topLeading) {
                    Toggle("", isOn: $proposal.isSelected)
                        .labelsHidden()
                        .padding(6)
                }

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Item name", text: $proposal.name)
                        .font(.headline)
                        .textInputAutocapitalization(.words)

                    HStack(spacing: 8) {
                        Label(proposal.confidence.formatted(.percent.precision(.fractionLength(0))), systemImage: "waveform.path.ecg")
                        InfoHelpButton(
                            title: "Confidence",
                            message: "Confidence is an evidence score. Visual detection carries the most weight; barcode or matching text can increase it when they support the same object."
                        )

                        if proposal.needsDetailScan {
                            Label("Detail", systemImage: "viewfinder")
                                .foregroundStyle(.orange)
                        }

                        Label(proposal.captureSource.rawValue, systemImage: proposal.captureSource == .photo ? "photo" : "video")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text(proposal.evidenceSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Picker("Category", selection: $proposal.category) {
                ForEach(InventoryCategory.allCases) { category in
                    Label(category.rawValue, systemImage: category.symbolName)
                        .tag(category)
                }
            }

            Picker("Condition", selection: $proposal.condition) {
                ForEach(ItemCondition.allCases) { condition in
                    Label(condition.rawValue, systemImage: condition.symbolName)
                        .tag(condition)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("Room", text: $proposal.room)
                    .textInputAutocapitalization(.words)
                TextField("Shelf, drawer, wall, zone", text: $proposal.area)
                    .textInputAutocapitalization(.words)
                TextField("Box, bin, bag, cabinet", text: $proposal.container)
                    .textInputAutocapitalization(.words)
            }

            HStack {
                Stepper("x\(proposal.quantity)", value: $proposal.quantity, in: 1...999)
                    .fixedSize()
                Spacer()
                Label(proposal.scanMission.rawValue, systemImage: proposal.scanMission.symbolName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Toggle("Needs close-up scan", isOn: $proposal.needsDetailScan)
                InfoHelpButton(
                    title: "Needs Close-up Scan",
                    message: "Keep this on when the card is probably real but lacks enough detail for reliable assistant use, such as brand, condition, exact identity, barcode, or expiry."
                )
            }

            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Brand", text: $proposal.brand)
                        .textInputAutocapitalization(.words)
                    TextField("Model", text: $proposal.model)
                    TextField("Serial number", text: $proposal.serialNumber)
                        .textInputAutocapitalization(.characters)
                    TextField("Barcode", text: $proposal.barcode)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Color", text: $proposal.color)
                        .textInputAutocapitalization(.words)
                    TextField("Material", text: $proposal.material)
                        .textInputAutocapitalization(.words)
                    TextField("Size", text: $proposal.size)
                    TextField("Replacement hint", text: $proposal.replacementHint)

                    Toggle("Has expiry date", isOn: hasExpiryBinding)

                    if proposal.expiresAt != nil {
                        DatePicker("Expires", selection: expiresBinding, displayedComponents: .date)
                    }

                    Toggle("Track restock level", isOn: hasRestockBinding)

                    if proposal.restockThreshold != nil {
                        Stepper("Restock below \(restockBinding.wrappedValue)", value: restockBinding, in: 1...999)
                    }

                    if !proposal.recognizedText.isEmpty {
                        LabeledContent("Visible Text", value: proposal.recognizedText.prefix(4).joined(separator: ", "))
                            .font(.caption)
                    }

                    if !proposal.labels.isEmpty {
                        LabeledContent("Vision Labels", value: proposal.labels.prefix(4).joined(separator: ", "))
                            .font(.caption)
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack(spacing: 4) {
                    Text("Metadata")
                    InfoHelpButton(
                        title: "Metadata",
                        message: "These fields make the inventory more useful to an assistant. They can come from visual detection, barcode, OCR, or your edits."
                    )
                }
            }
        }
        .opacity(proposal.isSelected ? 1 : 0.55)
        .padding(.vertical, 8)
    }
}
