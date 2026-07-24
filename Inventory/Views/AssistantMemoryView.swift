import SwiftUI

struct AssistantMemoryView: View {
    @EnvironmentObject private var store: InventoryStore
    @State private var exportURL: URL?
    @State private var errorMessage: String?
    @State private var profileNameDraft = ""
    @State private var showingClearProfileConfirmation = false

    private var snapshot: AssistantSnapshot {
        store.assistantSnapshot()
    }

    private var readyCount: Int {
        store.items.filter(\.hasUsefulAssistantContext).count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 4) {
                                    Text("Assistant Memory")
                                        .font(.title2.bold())
                                    InfoHelpButton(
                                        title: "Assistant Memory",
                                        message: "This is the structured inventory stream an assistant can use for cooking, restocking, organising, and finding things."
                                    )
                                }
                                Text("\(readyCount) reliable items, \(snapshot.needsDetailScan.count) need detail")
                                    .foregroundStyle(.secondary)
                                Text(store.currentProfile.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "sparkles")
                                .font(.title2)
                                .foregroundStyle(.tint)
                        }

                        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                            GridRow {
                                HStack(spacing: 4) {
                                    Button {
                                        prepareSnapshot()
                                    } label: {
                                        Label("Snapshot", systemImage: "doc.badge.arrow.up")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)

                                    InfoHelpButton(
                                        title: "Snapshot",
                                        message: "Exports a clean JSON summary for an assistant. It includes confirmed items, places, low-stock signals, expiry signals, and recent inventory events."
                                    )
                                }
                                .frame(maxWidth: .infinity)

                                HStack(spacing: 4) {
                                    Button {
                                        prepareLaptopPackage()
                                    } label: {
                                        Label("Laptop", systemImage: "laptopcomputer.and.arrow.down")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)

                                    InfoHelpButton(
                                        title: "Laptop Review",
                                        message: "Exports low-confidence items and cropped object photos for a stronger laptop-side classifier or AI review pass. It does not include the original source photos or videos."
                                    )
                                }
                                .frame(maxWidth: .infinity)
                            }

                            if let exportURL {
                                GridRow {
                                    HStack(spacing: 4) {
                                        ShareLink(item: exportURL) {
                                            Label("Share", systemImage: "square.and.arrow.up")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.bordered)

                                        InfoHelpButton(
                                            title: "Share Export",
                                            message: "Shares the file you just prepared. Use Snapshot for assistant memory, or Laptop for a review package with cropped object evidence."
                                        )
                                    }
                                    .gridCellColumns(2)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    HStack {
                        Label(store.currentProfile.name, systemImage: "person.crop.circle")
                        Spacer()
                        Menu {
                            ForEach(store.profiles) { profile in
                                Button {
                                    store.selectProfile(profile)
                                    profileNameDraft = profile.name
                                    exportURL = nil
                                } label: {
                                    if profile.id == store.currentProfile.id {
                                        Label(profile.name, systemImage: "checkmark")
                                    } else {
                                        Text(profile.name)
                                    }
                                }
                            }
                        } label: {
                            Label("Switch", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("Profile name", text: $profileNameDraft)
                            .textInputAutocapitalization(.words)

                        Button {
                            store.switchToProfile(named: profileNameDraft)
                            profileNameDraft = store.currentProfile.name
                            exportURL = nil
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(profileNameDraft.trimmed.isEmpty)
                    }

                    Button(role: .destructive) {
                        showingClearProfileConfirmation = true
                    } label: {
                        Label("Clear This Profile", systemImage: "trash")
                    }
                } header: {
                    InfoSectionHeader(
                        title: "Profile",
                        infoTitle: "Local Profile",
                        message: "Profiles keep inventories, assistant events, exports, and cropped object photos separate for different testers, homes, or users on the same device."
                    )
                }

                Section {
                    AssistantUseCaseRow(symbol: "fork.knife", title: "Cooking", detail: "\(store.items.filter { $0.category == .food }.count) food records")
                    AssistantUseCaseRow(symbol: "cart.badge.plus", title: "Restocking", detail: "\(snapshot.lowStock.count) low-stock records")
                    AssistantUseCaseRow(symbol: "archivebox", title: "Organising", detail: "\(snapshot.places.count) known places")
                    AssistantUseCaseRow(symbol: "magnifyingglass", title: "Finding Things", detail: "\(store.items.count) searchable records")
                } header: {
                    InfoSectionHeader(
                        title: "Useful For",
                        infoTitle: "Assistant Uses",
                        message: "These are computed from the current inventory. Better names, places, quantities, expiry dates, and restock thresholds make assistant answers more useful."
                    )
                }

                if !snapshot.lowStock.isEmpty {
                    Section("Restock") {
                        ForEach(snapshot.lowStock.prefix(12), id: \.self) { name in
                            Label(name, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                if !snapshot.expiringSoon.isEmpty {
                    Section("Expiring Soon") {
                        ForEach(snapshot.expiringSoon.prefix(12), id: \.self) { name in
                            Label(name, systemImage: "calendar.badge.exclamationmark")
                                .foregroundStyle(.red)
                        }
                    }
                }

                if !snapshot.needsDetailScan.isEmpty {
                    Section {
                        ForEach(snapshot.needsDetailScan.prefix(12), id: \.self) { name in
                            Label(name, systemImage: "viewfinder")
                                .foregroundStyle(.orange)
                        }
                    } header: {
                        InfoSectionHeader(
                            title: "Needs Detail Scan",
                            infoTitle: "Detail Scan",
                            message: "These items were detected with weak or incomplete evidence. A closer photo can add better identity, brand, condition, barcode, or expiry details."
                        )
                    }
                }

                Section("Recent Events") {
                    if store.events.isEmpty {
                        Label("No memory events yet", systemImage: "clock")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.events.prefix(25)) { event in
                            AssistantEventRow(event: event)
                        }
                    }
                }
            }
            .navigationTitle("Assistant")
            .onAppear {
                profileNameDraft = store.currentProfile.name
            }
            .onChange(of: store.currentProfile) { _, profile in
                profileNameDraft = profile.name
            }
            .confirmationDialog(
                "Clear this profile?",
                isPresented: $showingClearProfileConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear Items, Photos, and Events", role: .destructive) {
                    store.clearCurrentProfileData()
                    exportURL = nil
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the current profile's inventory records, assistant event history, and cropped object photos from this device.")
            }
            .alert("Could not prepare snapshot", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func prepareSnapshot() {
        do {
            exportURL = try store.makeAssistantSnapshotFile()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareLaptopPackage() {
        do {
            exportURL = try store.makeLaptopReviewPackageFile()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AssistantUseCaseRow: View {
    var symbol: String
    var title: String
    var detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
