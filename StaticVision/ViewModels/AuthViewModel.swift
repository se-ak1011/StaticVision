import Foundation
import Combine

@MainActor
final class AuthViewModel: ObservableObject {

    @Published var isAuthenticated = false
    @Published var isLoading       = false
    @Published var errorMessage: String?

    private let supabase = SupabaseService.shared

    var currentUser: SupabaseUser? { supabase.currentUser }

    // MARK: – Sign Up

    func signUp(email: String, password: String) async {
        await perform {
            _ = try await self.supabase.signUp(email: email, password: password)
            self.isAuthenticated = true
        }
    }

    // MARK: – Sign In

    func signIn(email: String, password: String) async {
        await perform {
            _ = try await self.supabase.signIn(email: email, password: password)
            self.isAuthenticated = true
        }
    }

    // MARK: – Sign Out

    func signOut() async {
        await perform {
            try await self.supabase.signOut()
            self.isAuthenticated = false
        }
    }

    // MARK: – Restore session on launch

    func restoreSession() async {
        await supabase.restoreSession()
        isAuthenticated = supabase.currentUser != nil
    }

    // MARK: – Helper

    private func perform(_ action: @escaping () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        do {
            try await action()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
