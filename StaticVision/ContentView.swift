import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        Group {
            if authViewModel.isAuthenticated {
                ProjectsView()
                    .environmentObject(authViewModel)
            } else {
                AuthView()
                    .environmentObject(authViewModel)
            }
        }
        .animation(.easeInOut, value: authViewModel.isAuthenticated)
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}
