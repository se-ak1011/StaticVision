import Foundation

/// Central configuration for StaticVision.
///
/// Values come from `Info.plist` (which CI populates from encrypted env vars),
/// falling back to the baked-in defaults below for plain Xcode builds. The
/// Supabase URL and publishable/anon key are safe to ship — the anon key is a
/// public client key protected by row-level security. The OpenAI key is *not*
/// here; it lives server-side in the `openai-proxy` Edge Function.
enum AppConfig {

    /// Reads a value from Info.plist, ignoring empty or unexpanded `$(VAR)`
    /// placeholders so the baked-in default is used instead.
    private static func infoValue(_ key: String, default fallback: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty, !value.hasPrefix("$(") else {
            return fallback
        }
        return value
    }

    // MARK: – Supabase
    /// Supabase project URL.
    static let supabaseURL = infoValue(
        "SUPABASE_URL",
        default: "https://pldqwyabiimgllyroxug.supabase.co"
    )

    /// Supabase publishable (anon) key — safe for clients, protected by RLS.
    static let supabaseAnonKey = infoValue(
        "SUPABASE_ANON_KEY",
        default: "sb_publishable_SBrulv53KXEuLoIoV2l3Fg_F--e9SuE"
    )

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

    /// Edge Function that turns a room photo into a styled, cleaned-up "after" image.
    static let roomVisualizerFunction = "room-visualizer"
    static var roomVisualizerURL: URL {
        URL(string: "\(supabaseURL)/functions/v1/\(roomVisualizerFunction)")!
    }

    // MARK: – Storage buckets
    static let mediaBucket     = "project-media"
    static let blueprintBucket = "blueprints"

    // MARK: – Shared account (personal app, no per-user login)
    /// Both users share ONE Supabase account, so projects/blueprints are shared and
    /// nobody has to sign in. The app auto-signs-in (and auto-creates the account on
    /// first launch) with these credentials. Requires "Confirm email" turned OFF in
    /// Supabase → Authentication → Providers → Email.
    static let sharedAccountEmail    = "drainedstore@gmail.com"
    static let sharedAccountPassword = "Beanjamin@13246"
}
