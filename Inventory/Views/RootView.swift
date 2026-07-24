import SwiftUI

enum InventoryTab: Hashable {
    case home
    case scan
    case inventory
    case assistant
}

struct RootView: View {
    @State private var selectedTab: InventoryTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeMemoryView {
                selectedTab = .scan
            } onOpenAssistant: {
                selectedTab = .assistant
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }
            .tag(InventoryTab.home)

            ScanVideoView {
                selectedTab = .inventory
            }
            .tabItem {
                Label("Scan", systemImage: "viewfinder")
            }
            .tag(InventoryTab.scan)

            InventoryListView {
                selectedTab = .scan
            }
            .tabItem {
                Label("Inventory", systemImage: "shippingbox")
            }
            .tag(InventoryTab.inventory)

            AssistantMemoryView()
                .tabItem {
                    Label("Assistant", systemImage: "sparkles")
                }
                .tag(InventoryTab.assistant)
        }
    }
}

struct InfoHelpButton: View {
    var title: String
    var message: String

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.subheadline)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(title) information")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: "info.circle")
                    .font(.headline)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(minWidth: 260, idealWidth: 300, maxWidth: 340, alignment: .leading)
            .presentationCompactAdaptation(.popover)
        }
    }
}

struct InfoSectionHeader: View {
    var title: String
    var infoTitle: String
    var message: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            InfoHelpButton(title: infoTitle, message: message)
        }
    }
}
