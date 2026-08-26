import SwiftUI

@main
struct HomeInventoryApp: App {
    @StateObject private var store = InventoryStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .task {
                    WalkthroughVideoStore.deleteAllManagedCopies()
                    store.load()
                    #if DEBUG
                    if ScanSelfTest.isRequested {
                        await ScanSelfTest.run()
                    }
                    #endif
                }
        }
    }
}
