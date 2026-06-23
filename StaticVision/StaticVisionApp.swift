import SwiftUI

@main
struct StaticVisionApp: App {
    @StateObject private var authViewModel = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authViewModel)
                .task { await authViewModel.restoreSession() }
        }
    }
}
