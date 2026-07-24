import SwiftUI

struct InsightsView: View {
    @EnvironmentObject private var store: InventoryStore

    private var totalQuantity: Int {
        store.items.reduce(0) { $0 + $1.quantity }
    }

    private var categoryCounts: [(InventoryCategory, Int)] {
        InventoryCategory.allCases
            .map { category in
                (category, store.items.filter { $0.category == category }.reduce(0) { $0 + $1.quantity })
            }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
    }

    private var roomCounts: [(String, Int)] {
        Dictionary(grouping: store.items, by: \.room)
            .map { room, items in
                (room, items.reduce(0) { $0 + $1.quantity })
            }
            .sorted { $0.1 > $1.1 }
    }

    var body: some View {
        NavigationStack {
            List {
                if store.items.isEmpty {
                    ContentUnavailableView("No inventory yet", systemImage: "chart.bar.xaxis")
                } else {
                    Section("Overview") {
                        LabeledContent("Unique items", value: "\(store.items.count)")
                        LabeledContent("Total quantity", value: "\(totalQuantity)")
                        LabeledContent("Rooms", value: "\(roomCounts.count)")
                        LabeledContent("Needs detail scan", value: "\(store.items.filter { $0.needsDetailScan == true }.count)")
                    }

                    Section("Categories") {
                        ForEach(categoryCounts, id: \.0) { category, count in
                            InsightBarRow(
                                title: category.rawValue,
                                value: count,
                                total: max(totalQuantity, 1),
                                symbol: category.symbolName,
                                tint: category.tint
                            )
                        }
                    }

                    Section("Rooms") {
                        ForEach(roomCounts, id: \.0) { room, count in
                            InsightBarRow(
                                title: room,
                                value: count,
                                total: max(totalQuantity, 1),
                                symbol: "door.left.hand.open",
                                tint: .accentColor
                            )
                        }
                    }

                    Section("Needs Attention") {
                        let lowItems = store.items.filter { $0.status == .low }
                        let detailItems = store.items.filter { $0.needsDetailScan == true }

                        if lowItems.isEmpty && detailItems.isEmpty {
                            Label("No low stock items", systemImage: "checkmark.circle")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(detailItems) { item in
                                NavigationLink {
                                    InventoryDetailView(itemID: item.id)
                                } label: {
                                    Label(item.name, systemImage: "viewfinder")
                                }
                            }

                            ForEach(lowItems) { item in
                                NavigationLink {
                                    InventoryDetailView(itemID: item.id)
                                } label: {
                                    Text(item.name)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Insights")
        }
    }
}

private struct InsightBarRow: View {
    var title: String
    var value: Int
    var total: Int
    var symbol: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: symbol)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(value)")
                    .font(.subheadline.weight(.semibold))
            }

            ProgressView(value: Double(value), total: Double(total))
                .tint(tint)
        }
        .padding(.vertical, 4)
    }
}
