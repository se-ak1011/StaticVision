import Foundation
import Combine

@MainActor
final class AuthViewModel: ObservableObject {

    @Published var isAuthenticated = false
    @Published var isInitializing  = true
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

    /// Restores any saved session, otherwise silently signs in (or creates, on first
    /// launch) the shared account — so no login UI is ever shown.
    func restoreSession() async {
        await supabase.restoreSession()
        if supabase.currentUser == nil {
            await autoSignIn()
        }
        isAuthenticated = supabase.currentUser != nil
        isInitializing = false
    }

    private func autoSignIn() async {
        let email    = AppConfig.sharedAccountEmail
        let password = AppConfig.sharedAccountPassword
        // Don't attempt until real shared-account credentials are set — otherwise we'd
        // create an account with the placeholder password and lock ourselves out.
        guard !password.isEmpty, password != "REPLACE_WITH_A_PASSWORD" else { return }
        do {
            _ = try await supabase.signIn(email: email, password: password)
        } catch {
            // The shared account may not exist yet → create it once.
            // (Requires "Confirm email" disabled so a session is returned immediately.)
            do {
                _ = try await supabase.signUp(email: email, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
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
