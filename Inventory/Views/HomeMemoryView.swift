import SwiftUI

struct HomeMemoryView: View {
    @EnvironmentObject private var store: InventoryStore

    var onStartScan: () -> Void
    var onOpenAssistant: () -> Void

    private var places: [String] {
        Set(store.items.map(\.placeDescription).filter { !$0.isEmpty })
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var attentionItems: [InventoryItem] {
        store.items
            .filter { $0.needsDetailScan == true || $0.isLowStock || $0.isExpiringSoon }
            .sorted {
                if $0.isExpiringSoon != $1.isExpiringSoon {
                    return $0.isExpiringSoon
                }
                if $0.isLowStock != $1.isLowStock {
                    return $0.isLowStock
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("House Memory")
                                    .font(.title2.bold())
                                Text("\(store.items.count) items across \(places.count) places")
                                    .foregroundStyle(.secondary)
                                Text(store.currentProfile.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "brain.head.profile")
                                .font(.title2)
                                .foregroundStyle(.tint)
                        }

                        HStack(spacing: 10) {
                            HStack(spacing: 4) {
                                Button(action: onStartScan) {
                                    Label("Scan", systemImage: "viewfinder")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)

                                InfoHelpButton(
                                    title: "Scan",
                                    message: "Capture a photo sweep or walkthrough video so the app can detect objects, crop evidence photos, and prepare inventory cards."
                                )
                            }
                            .frame(maxWidth: .infinity)

                            HStack(spacing: 4) {
                                Button(action: onOpenAssistant) {
                                    Label("Memory", systemImage: "sparkles")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)

                                InfoHelpButton(
                                    title: "Memory",
                                    message: "Open the assistant-facing view for exports, restock signals, expiry signals, and items needing more detail."
                                )
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    SignalGrid(items: store.items)
                } header: {
                    InfoSectionHeader(
                        title: "Signals",
                        infoTitle: "Dashboard Signals",
                        message: "Usable means enough clean context for assistant use. Detail means the item probably needs a closer scan. Low and Expiry come from stock and date metadata."
                    )
                }

                if !attentionItems.isEmpty {
                    Section("Needs Attention") {
                        ForEach(attentionItems.prefix(8)) { item in
                            NavigationLink {
                                InventoryDetailView(itemID: item.id)
                            } label: {
                                AttentionRow(item: item)
                            }
                        }
                    }
                }

                if !places.isEmpty {
                    Section("Places") {
                        ForEach(places.prefix(12), id: \.self) { place in
                            HStack {
                                Label(place, systemImage: "mappin.and.ellipse")
                                Spacer()
                                Text("\(store.items.filter { $0.placeDescription == place }.count)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !store.events.isEmpty {
                    Section("Recent Memory") {
                        ForEach(store.events.prefix(5)) { event in
                            AssistantEventRow(event: event)
                        }
                    }
                }
            }
            .navigationTitle("Home")
        }
    }
}

private struct SignalGrid: View {
    var items: [InventoryItem]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                SignalMetric(value: "\(items.filter { $0.hasUsefulAssistantContext }.count)", label: "Usable", symbol: "checkmark.seal")
                SignalMetric(value: "\(items.filter { $0.needsDetailScan == true }.count)", label: "Detail", symbol: "viewfinder")
            }

            GridRow {
                SignalMetric(value: "\(items.filter(\.isLowStock).count)", label: "Low", symbol: "exclamationmark.triangle")
                SignalMetric(value: "\(items.filter(\.isExpiringSoon).count)", label: "Expiry", symbol: "calendar.badge.exclamationmark")
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SignalMetric: View {
    var value: String
    var label: String
    var symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
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

private struct AttentionRow: View {
    var item: InventoryItem

    var body: some View {
        HStack(spacing: 12) {
            InventoryPhotoView(
                filename: item.photoFilename,
                symbolName: item.category.symbolName,
                tint: item.category.tint,
                cornerRadius: 8
            )
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                Text(item.placeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if item.isExpiringSoon {
                Image(systemName: "calendar.badge.exclamationmark")
                    .foregroundStyle(.red)
            } else if item.isLowStock {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else if item.needsDetailScan == true {
                Image(systemName: "viewfinder")
                    .foregroundStyle(.orange)
            }
        }
    }
}

struct AssistantEventRow: View {
    var event: AssistantEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.kind.symbolName)
                .foregroundStyle(.tint)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.message)
                    .font(.subheadline)
                Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
