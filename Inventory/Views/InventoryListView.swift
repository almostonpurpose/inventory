import SwiftUI

struct InventoryListView: View {
    @EnvironmentObject private var store: InventoryStore
    @State private var searchText = ""
    @State private var selectedCategory: InventoryCategory?
    @State private var showingManualAdd = false

    var onStartScan: () -> Void

    private var filteredItems: [InventoryItem] {
        store.items.filter { item in
            let matchesSearch = searchText.trimmed.isEmpty
                || item.name.localizedCaseInsensitiveContains(searchText)
                || item.room.localizedCaseInsensitiveContains(searchText)
                || (item.area ?? "").localizedCaseInsensitiveContains(searchText)
                || (item.container ?? "").localizedCaseInsensitiveContains(searchText)
                || (item.brand ?? "").localizedCaseInsensitiveContains(searchText)
                || (item.model ?? "").localizedCaseInsensitiveContains(searchText)
                || (item.barcode ?? "").localizedCaseInsensitiveContains(searchText)
                || (item.replacementHint ?? "").localizedCaseInsensitiveContains(searchText)
                || (item.tags ?? []).joined(separator: " ").localizedCaseInsensitiveContains(searchText)
                || item.notes.localizedCaseInsensitiveContains(searchText)

            let matchesCategory = selectedCategory == nil || item.category == selectedCategory
            return matchesSearch && matchesCategory
        }
    }

    private var roomSections: [RoomSection] {
        Dictionary(grouping: filteredItems, by: \.room)
            .map { RoomSection(room: $0.key, items: $0.value.sorted(using: inventoryNameSort)) }
            .sorted { $0.room.localizedStandardCompare($1.room) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                if store.items.isEmpty {
                    EmptyInventorySection(onStartScan: onStartScan) {
                        showingManualAdd = true
                    }
                } else {
                    Section {
                        InventorySummaryStrip(items: filteredItems)
                    } header: {
                        InfoSectionHeader(
                            title: "Summary",
                            infoTitle: "Inventory Summary",
                            message: "These counts reflect the current search and category filter, so they change as you narrow the list."
                        )
                    }

                    if filteredItems.isEmpty {
                        ContentUnavailableView("No matches", systemImage: "magnifyingglass")
                    } else {
                        ForEach(roomSections) { section in
                            Section(section.room) {
                                ForEach(section.items) { item in
                                    NavigationLink {
                                        InventoryDetailView(itemID: item.id)
                                    } label: {
                                        InventoryRow(item: item)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Inventory")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    InfoHelpButton(
                        title: "Inventory Controls",
                        message: "Use the filter icon to show one category at a time. Use plus to add an item manually when scanning is not worth it."
                    )

                    Menu {
                        Button("All Categories") {
                            selectedCategory = nil
                        }

                        Divider()

                        ForEach(InventoryCategory.allCases) { category in
                            Button {
                                selectedCategory = category
                            } label: {
                                Label(category.rawValue, systemImage: category.symbolName)
                            }
                        }
                    } label: {
                        Image(systemName: selectedCategory == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Filter inventory")

                    Button {
                        showingManualAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add item")
                }
            }
            .sheet(isPresented: $showingManualAdd) {
                ItemEditorView(mode: .create(defaultRoom: nil)) { draft in
                    store.addManual(draft)
                }
            }
            .alert("Storage Error", isPresented: Binding(
                get: { store.lastError != nil },
                set: { if !$0 { store.lastError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.lastError ?? "")
            }
        }
    }
}

private struct EmptyInventorySection: View {
    var onStartScan: () -> Void
    var onManualAdd: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "video.viewfinder")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 6) {
                    Text("No items yet")
                        .font(.title2.bold())
                }

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Button(action: onStartScan) {
                            Label("Scan Area", systemImage: "viewfinder")
                        }
                        .buttonStyle(.borderedProminent)

                        InfoHelpButton(
                            title: "Scan Area",
                            message: "Start with a shelf, drawer, bin, or room sweep so the app can create object cards from detected crops."
                        )
                    }

                    HStack(spacing: 4) {
                        Button(action: onManualAdd) {
                            Label("Add Item", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)

                        InfoHelpButton(
                            title: "Add Item",
                            message: "Use manual entry for things the camera missed, private items you do not want to scan, or quick corrections."
                        )
                    }
                }
            }
            .padding(.vertical, 12)
        }
    }
}

private struct InventorySummaryStrip: View {
    var items: [InventoryItem]

    private var roomCount: Int {
        Set(items.map(\.room)).count
    }

    private var totalQuantity: Int {
        items.reduce(0) { $0 + $1.quantity }
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            GridRow {
                SummaryMetric(value: "\(items.count)", label: "Items", symbol: "shippingbox")
                SummaryMetric(value: "\(totalQuantity)", label: "Total Qty", symbol: "number")
            }

            GridRow {
                SummaryMetric(value: "\(roomCount)", label: "Rooms", symbol: "door.left.hand.open")
                SummaryMetric(value: "\(items.filter(\.isLowStock).count)", label: "Low", symbol: "exclamationmark.triangle")
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SummaryMetric: View {
    var value: String
    var label: String
    var symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct InventoryRow: View {
    var item: InventoryItem

    var body: some View {
        HStack(spacing: 12) {
            InventoryPhotoView(
                filename: item.photoFilename,
                symbolName: item.category.symbolName,
                tint: item.category.tint,
                cornerRadius: 8
            )
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("\(item.category.rawValue) - \(item.placeDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if item.isLowStock {
                        Label("Low", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }

                    if item.isExpiringSoon {
                        Label("Expiry", systemImage: "calendar.badge.exclamationmark")
                            .foregroundStyle(.red)
                    }

                    if item.needsDetailScan == true {
                        Label("Detail", systemImage: "viewfinder")
                            .foregroundStyle(.orange)
                    }

                    if let condition = item.condition, condition != .unknown {
                        Label(condition.rawValue, systemImage: condition.symbolName)
                    }
                }
                .font(.caption2)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text("x\(item.quantity)")
                    .font(.subheadline.weight(.semibold))
                Label(item.status.rawValue, systemImage: item.status.symbolName)
                    .font(.caption2)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(item.status == .low ? .orange : .secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct RoomSection: Identifiable {
    var id: String { room }
    var room: String
    var items: [InventoryItem]
}

private let inventoryNameSort = SortDescriptor<InventoryItem>(\.name, comparator: .localizedStandard)
