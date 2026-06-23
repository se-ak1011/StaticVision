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
    /// Your OpenAI API key (sk-…)
    static let openAIKey: String = {
        Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String
            ?? "YOUR_OPENAI_API_KEY"
    }()

    static let openAIBaseURL = URL(string: "https://api.openai.com/v1")!
    static let openAIModel  = "gpt-4o"

    // MARK: – Storage buckets
    static let mediaBucket     = "project-media"
    static let blueprintBucket = "blueprints"
}
