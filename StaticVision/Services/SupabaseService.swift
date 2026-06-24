import Foundation
import Security

// MARK: - SupabaseService
// A lightweight REST wrapper around the Supabase PostgREST, Auth and
// Storage APIs so the project compiles without the Supabase Swift SDK
// while you set up your credentials.  Replace the manual URLSession calls
// with the official `supabase-swift` package once you add it via SPM.

final class SupabaseService: ObservableObject {

    static let shared = SupabaseService()
    private init() {}

    // MARK: – Session state
    @Published var currentUser: SupabaseUser?
    @Published var session: SupabaseSession?

    // NOTE: the models declare explicit snake_case `CodingKeys` for the columns that
    // need them, so we must NOT also apply `convert*SnakeCase` strategies — doing both
    // double-transforms the keys and breaks decoding. Nested `Room`/`FurnitureItem`
    // live inside a `jsonb` blob and round-trip symmetrically with their default keys.
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = fmt.date(from: s) { return date }
            if let date = ISO8601DateFormatter().date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date: \(s)")
        }
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    /// Auth payloads (Supabase GoTrue) use snake_case keys that are already spelled
    /// out in the models' `CodingKeys`, so this decoder must NOT also apply
    /// `convertFromSnakeCase` (that would double-transform and fail to match).
    private let authDecoder: JSONDecoder = {
        let d = JSONDecoder()
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = fmt.date(from: s) { return date }
            if let date = ISO8601DateFormatter().date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date: \(s)")
        }
        return d
    }()

    private let keychainAccount = "com.static-vision.session"

    // MARK: – Base URLs
    private var authURL: URL { URL(string: "\(AppConfig.supabaseURL)/auth/v1")! }
    private var restURL: URL { URL(string: "\(AppConfig.supabaseURL)/rest/v1")! }
    private var storageURL: URL { URL(string: "\(AppConfig.supabaseURL)/storage/v1")! }

    // MARK: – Auth headers
    private var baseHeaders: [String: String] {
        var h: [String: String] = [
            "apikey": AppConfig.supabaseAnonKey,
            "Content-Type": "application/json",
        ]
        if let token = session?.accessToken {
            h["Authorization"] = "Bearer " + token
        }
        return h
    }

    // MARK: – Auth

    func signUp(email: String, password: String) async throws -> SupabaseUser {
        let body = ["email": email, "password": password]
        let data = try await post(url: authURL.appendingPathComponent("signup"), body: body)
        let response = try authDecoder.decode(AuthResponse.self, from: data)
        await apply(session: response.session, user: response.user)
        return response.user
    }

    func signIn(email: String, password: String) async throws -> SupabaseUser {
        let body = ["email": email, "password": password]
        var url = authURL.appendingPathComponent("token")
        url = url.appending(queryItems: [URLQueryItem(name: "grant_type", value: "password")])
        let data = try await post(url: url, body: body)
        let response = try authDecoder.decode(AuthResponse.self, from: data)
        await apply(session: response.session, user: response.user)
        return response.user
    }

    func signOut() async throws {
        _ = try? await post(url: authURL.appendingPathComponent("logout"), body: [String: String]())
        await MainActor.run {
            self.session = nil
            self.currentUser = nil
        }
        Keychain.delete(account: keychainAccount)
    }

    /// Restores a persisted session from the Keychain and refreshes its tokens so
    /// the user stays signed in across app launches.
    func restoreSession() async {
        guard
            let data = Keychain.load(account: keychainAccount),
            let stored = try? JSONDecoder().decode(StoredSession.self, from: data)
        else { return }

        // Optimistically restore, then refresh in the background.
        await MainActor.run {
            self.session = stored.session
            self.currentUser = stored.user
        }

        guard let refreshToken = stored.session.refreshToken else { return }
        do {
            try await refreshSession(refreshToken: refreshToken)
        } catch {
            // Refresh token expired or revoked → force re-login.
            await MainActor.run {
                self.session = nil
                self.currentUser = nil
            }
            Keychain.delete(account: keychainAccount)
        }
    }

    private func refreshSession(refreshToken: String) async throws {
        var url = authURL.appendingPathComponent("token")
        url = url.appending(queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")])
        let bodyData = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
        let data = try await post(url: url, bodyData: bodyData)
        let response = try authDecoder.decode(AuthResponse.self, from: data)
        await apply(session: response.session, user: response.user)
    }

    /// Updates the published session/user and persists them to the Keychain.
    private func apply(session newSession: SupabaseSession?, user: SupabaseUser) async {
        await MainActor.run {
            self.session = newSession
            self.currentUser = user
        }
        if let newSession {
            let stored = StoredSession(session: newSession, user: user)
            if let data = try? JSONEncoder().encode(stored) {
                Keychain.save(data, account: keychainAccount)
            }
        }
    }

    // MARK: – Database

    func fetchProjects(userId: UUID) async throws -> [Project] {
        let url = restURL
            .appendingPathComponent("projects")
            .appending(queryItems: [URLQueryItem(name: "user_id", value: "eq.\(userId.uuidString)")])
        let data = try await get(url: url)
        return try decoder.decode([Project].self, from: data)
    }

    func createProject(_ project: Project) async throws -> Project {
        let body = try encoder.encode(project)
        let url = restURL.appendingPathComponent("projects")
        var headers = baseHeaders
        headers["Prefer"] = "return=representation"
        let data = try await post(url: url, bodyData: body, extraHeaders: headers)
        let arr = try decoder.decode([Project].self, from: data)
        guard let created = arr.first else { throw AppError.serverError("No project returned") }
        return created
    }

    func updateProject(_ project: Project) async throws {
        let body = try encoder.encode(project)
        let url = restURL
            .appendingPathComponent("projects")
            .appending(queryItems: [URLQueryItem(name: "id", value: "eq.\(project.id.uuidString)")])
        try await patch(url: url, bodyData: body)
    }

    func deleteProject(id: UUID) async throws {
        let url = restURL
            .appendingPathComponent("projects")
            .appending(queryItems: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")])
        try await delete(url: url)
    }

    func fetchBlueprint(projectId: UUID) async throws -> Blueprint? {
        let url = restURL
            .appendingPathComponent("blueprints")
            .appending(queryItems: [
                URLQueryItem(name: "project_id", value: "eq.\(projectId.uuidString)"),
                URLQueryItem(name: "limit", value: "1"),
            ])
        let data = try await get(url: url)
        let arr = try decoder.decode([Blueprint].self, from: data)
        return arr.first
    }

    func upsertBlueprint(_ blueprint: Blueprint) async throws -> Blueprint {
        let body = try encoder.encode(blueprint)
        // Upsert on the project_id unique constraint so re-generating updates the
        // existing row instead of colliding with it (HTTP 409).
        let url = restURL
            .appendingPathComponent("blueprints")
            .appending(queryItems: [URLQueryItem(name: "on_conflict", value: "project_id")])
        var headers = baseHeaders
        headers["Prefer"] = "return=representation,resolution=merge-duplicates"
        let data = try await post(url: url, bodyData: body, extraHeaders: headers)
        let arr = try decoder.decode([Blueprint].self, from: data)
        guard let saved = arr.first else { throw AppError.serverError("No blueprint returned") }
        return saved
    }

    func addMedia(_ media: ProjectMedia) async throws -> ProjectMedia {
        let body = try encoder.encode(media)
        let url = restURL.appendingPathComponent("project_media")
        var headers = baseHeaders
        headers["Prefer"] = "return=representation"
        let data = try await post(url: url, bodyData: body, extraHeaders: headers)
        let arr = try decoder.decode([ProjectMedia].self, from: data)
        guard let saved = arr.first else { throw AppError.serverError("No media returned") }
        return saved
    }

    func fetchMedia(projectId: UUID) async throws -> [ProjectMedia] {
        let url = restURL
            .appendingPathComponent("project_media")
            .appending(queryItems: [URLQueryItem(name: "project_id", value: "eq.\(projectId.uuidString)")])
        let data = try await get(url: url)
        return try decoder.decode([ProjectMedia].self, from: data)
    }

    // MARK: – Storage

    /// Uploads `data` to the given (private) `bucket` at `path`.
    func uploadFile(bucket: String, path: String, data fileData: Data, contentType: String) async throws {
        let url = storageURL
            .appendingPathComponent("object")
            .appendingPathComponent(bucket)
            .appendingPathComponent(path)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = baseHeaders
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = fileData

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AppError.serverError("Upload failed")
        }
    }

    /// Creates a time-limited signed URL for an object in a **private** bucket.
    /// The buckets are private, so plain `/object/public/...` URLs do not work.
    func createSignedURL(bucket: String, path: String, expiresIn seconds: Int = 3600) async throws -> URL {
        let url = storageURL
            .appendingPathComponent("object/sign")
            .appendingPathComponent(bucket)
            .appendingPathComponent(path)
        let bodyData = try JSONSerialization.data(withJSONObject: ["expiresIn": seconds])
        let data = try await post(url: url, bodyData: bodyData)

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let signed = json["signedURL"] as? String ?? json["signedUrl"] as? String
        else {
            throw AppError.parsingError("No signedURL in storage response")
        }
        // `signedURL` is a path relative to the storage endpoint, e.g.
        // "/object/sign/bucket/path?token=...".
        let relative = signed.hasPrefix("/") ? String(signed.dropFirst()) : signed
        guard let full = URL(string: "\(AppConfig.supabaseURL)/storage/v1/\(relative)") else {
            throw AppError.serverError("Invalid signed URL")
        }
        return full
    }

    /// Downloads the bytes of a private media object via a signed URL.
    func downloadMedia(_ media: ProjectMedia) async throws -> Data {
        let signed = try await createSignedURL(bucket: AppConfig.mediaBucket, path: media.storagePath)
        let (data, response) = try await URLSession.shared.data(from: signed)
        try validate(response)
        return data
    }

    // MARK: – Private HTTP helpers

    private func get(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = baseHeaders
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return data
    }

    @discardableResult
    private func post<B: Encodable>(url: URL, body: B) async throws -> Data {
        let bodyData = try encoder.encode(body)
        return try await post(url: url, bodyData: bodyData)
    }

    @discardableResult
    private func post(url: URL, bodyData: Data, extraHeaders: [String: String]? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        var headers = baseHeaders
        if let extra = extraHeaders { headers.merge(extra) { _, new in new } }
        request.allHTTPHeaderFields = headers
        request.httpBody = bodyData
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return data
    }

    private func patch(url: URL, bodyData: Data) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.allHTTPHeaderFields = baseHeaders
        request.httpBody = bodyData
        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response)
    }

    private func delete(url: URL) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.allHTTPHeaderFields = baseHeaders
        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            throw AppError.serverError("HTTP \(http.statusCode)")
        }
    }
}

// MARK: - Auth response models

/// Supabase GoTrue returns the session tokens at the top level of the JSON
/// (alongside `user`), not nested under a `session` key — so we assemble the
/// `SupabaseSession` manually from those fields.
struct AuthResponse: Decodable {
    let user: SupabaseUser
    let session: SupabaseSession?

    private enum CodingKeys: String, CodingKey {
        case user
        case accessToken  = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn    = "expires_in"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.user = try c.decode(SupabaseUser.self, forKey: .user)
        if let accessToken = try c.decodeIfPresent(String.self, forKey: .accessToken) {
            self.session = SupabaseSession(
                accessToken: accessToken,
                refreshToken: try c.decodeIfPresent(String.self, forKey: .refreshToken),
                expiresIn: try c.decodeIfPresent(Int.self, forKey: .expiresIn)
            )
        } else {
            self.session = nil
        }
    }
}

/// Container persisted to the Keychain so the user stays signed in across launches.
struct StoredSession: Codable {
    let session: SupabaseSession
    let user: SupabaseUser
}

struct SupabaseUser: Codable, Identifiable {
    let id: UUID
    let email: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, email
        case createdAt = "created_at"
    }
}

struct SupabaseSession: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn    = "expires_in"
    }
}

// MARK: - AppError

enum AppError: LocalizedError {
    case serverError(String)
    case parsingError(String)
    case authRequired
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .serverError(let msg):  return "Server error: \(msg)"
        case .parsingError(let msg): return "Parsing error: \(msg)"
        case .authRequired:          return "You must be signed in."
        case .unknown(let e):        return e.localizedDescription
        }
    }
}

// MARK: - URL extension helper

private extension URL {
    func appending(queryItems: [URLQueryItem]) -> URL {
        guard var comps = URLComponents(url: self, resolvingAgainstBaseURL: true) else { return self }
        comps.queryItems = (comps.queryItems ?? []) + queryItems
        return comps.url ?? self
    }
}

// MARK: - Keychain

/// Minimal wrapper around the Keychain for storing the session securely.
enum Keychain {
    private static let service = "com.static-vision.app"

    static func save(_ data: Data, account: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        // Update if it already exists, otherwise add.
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    static func load(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
