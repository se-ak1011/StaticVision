import SwiftUI

struct AuthView: View {
    @StateObject private var viewModel = AuthViewModel()
    @State private var email           = ""
    @State private var password        = ""
    @State private var isSignUp        = false
    @State private var showPassword    = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color(hex: "#0D0717"), Color(hex: "#1A0B2E"), Color(hex: "#2D1B4E")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 32) {
                    // Logo
                    VStack(spacing: 12) {
                        Image(systemName: "house.and.flag.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(
                                LinearGradient(colors: [.white, Color.brandPurple],
                                               startPoint: .top, endPoint: .bottom)
                            )

                        Text("StaticVision")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text("See your fixer-upper potential")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.top, 40)

                    // Form
                    VStack(spacing: 16) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .textInputAutocapitalization(.never)
                            .authFieldStyle()

                        ZStack(alignment: .trailing) {
                            if showPassword {
                                TextField("Password", text: $password)
                                    .textContentType(isSignUp ? .newPassword : .password)
                                    .authFieldStyle()
                            } else {
                                SecureField("Password", text: $password)
                                    .textContentType(isSignUp ? .newPassword : .password)
                                    .authFieldStyle()
                            }
                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .foregroundColor(.white.opacity(0.6))
                                    .padding(.trailing, 16)
                            }
                        }
                    }
                    .padding(.horizontal, 24)

                    // Error
                    if let err = viewModel.errorMessage {
                        Text(err)
                            .foregroundColor(Color.brandPurple)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    // Primary button
                    Button {
                        Task {
                            if isSignUp {
                                await viewModel.signUp(email: email, password: password)
                            } else {
                                await viewModel.signIn(email: email, password: password)
                            }
                        }
                    } label: {
                        HStack {
                            if viewModel.isLoading {
                                ProgressView().tint(.white)
                            }
                            Text(isSignUp ? "Create Account" : "Sign In")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.brandPurple)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                    }
                    .disabled(viewModel.isLoading || email.isEmpty || password.isEmpty)
                    .padding(.horizontal, 24)

                    // Toggle mode
                    Button {
                        withAnimation { isSignUp.toggle() }
                        viewModel.errorMessage = nil
                    } label: {
                        HStack(spacing: 4) {
                            Text(isSignUp ? "Already have an account?" : "New here?")
                                .foregroundColor(.white.opacity(0.6))
                            Text(isSignUp ? "Sign In" : "Create Account")
                                .foregroundColor(Color.brandPurple)
                                .fontWeight(.semibold)
                        }
                        .font(.subheadline)
                    }

                    Spacer()
                }
            }
        }
    }
}

// MARK: – Field style modifier

private extension View {
    func authFieldStyle() -> some View {
        self
            .padding(14)
            .background(.white.opacity(0.12))
            .cornerRadius(12)
            .foregroundColor(.white)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
    }
}

// MARK: – Color hex init

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }

    // MARK: – Brand palette (dark purple & black)
    static let brandPurple     = Color(hex: "#9D4EDD")
    static let brandPurpleDeep = Color(hex: "#6A2FB5")
    static let brandBackground = Color(hex: "#0D0717")
}

#Preview {
    AuthView()
}
