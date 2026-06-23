import Foundation

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

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = fmt.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date: \(s)")
        }
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()

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
        let response = try decoder.decode(AuthResponse.self, from: data)
        await MainActor.run {
            self.session = response.session
            self.currentUser = response.user
        }
        return response.user
    }

    func signIn(email: String, password: String) async throws -> SupabaseUser {
        let body = ["email": email, "password": password]
        var url = authURL.appendingPathComponent("token")
        url = url.appending(queryItems: [URLQueryItem(name: "grant_type", value: "password")])
        let data = try await post(url: url, body: body)
        let response = try decoder.decode(AuthResponse.self, from: data)
        await MainActor.run {
            self.session = response.session
            self.currentUser = response.user
        }
        return response.user
    }

    func signOut() async throws {
        _ = try? await post(url: authURL.appendingPathComponent("logout"), body: [String: String]())
        await MainActor.run {
            self.session = nil
            self.currentUser = nil
        }
    }

    func restoreSession() async {
        // In production use Keychain; for now session is in-memory only.
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
        let url = restURL.appendingPathComponent("blueprints")
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

    /// Uploads `data` to the given `bucket` at `path` and returns the public URL.
    func uploadFile(bucket: String, path: String, data fileData: Data, contentType: String) async throws -> URL {
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
        return storageURL
            .appendingPathComponent("object/public")
            .appendingPathComponent(bucket)
            .appendingPathComponent(path)
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

struct AuthResponse: Codable {
    let user: SupabaseUser
    let session: SupabaseSession?
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
