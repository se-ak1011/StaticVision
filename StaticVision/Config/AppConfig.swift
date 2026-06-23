import Foundation

/// Central configuration for StaticVision.
/// Replace the placeholder values with your own credentials before building.
/// Store sensitive keys in Xcode's scheme environment variables or a local
/// `Config.xcconfig` file that is git-ignored — never commit real API keys.
enum AppConfig {

    // MARK: – Supabase
    /// Your Supabase project URL, e.g. "https://xyzxyz.supabase.co"
    static let supabaseURL: String = {
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
            ?? "https://YOUR_SUPABASE_PROJECT.supabase.co"
    }()

    /// Your Supabase project's public anon key
    static let supabaseAnonKey: String = {
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
            ?? "YOUR_SUPABASE_ANON_KEY"
    }()

    // MARK: – OpenAI
    /// The OpenAI key is **not** stored in the app. Requests are routed through a
    /// Supabase Edge Function (`openai-proxy`) that holds the key server-side as a
    /// Supabase secret, so it can never be extracted from the shipped binary.
    /// The function authenticates callers with their Supabase session JWT.
    static let openAIProxyFunction = "openai-proxy"

    /// Full URL of the OpenAI proxy edge function.
    static var openAIProxyURL: URL {
        URL(string: "\(supabaseURL)/functions/v1/\(openAIProxyFunction)")!
    }

    static let openAIModel = "gpt-4o"

    // MARK: – Storage buckets
    static let mediaBucket     = "project-media"
    static let blueprintBucket = "blueprints"
}
