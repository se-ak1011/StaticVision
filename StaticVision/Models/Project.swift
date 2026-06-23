import Foundation

// MARK: - Project

struct Project: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var description: String
    let userId: UUID
    var status: ProjectStatus
    var mediaCount: Int
    var blueprintId: UUID?
    let createdAt: Date
    var updatedAt: Date

    enum ProjectStatus: String, Codable, CaseIterable {
        case draft      = "draft"
        case processing = "processing"
        case ready      = "ready"
        case failed     = "failed"
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, status
        case userId      = "user_id"
        case mediaCount  = "media_count"
        case blueprintId = "blueprint_id"
        case createdAt   = "created_at"
        case updatedAt   = "updated_at"
    }
}

// MARK: - ProjectMedia

struct ProjectMedia: Identifiable, Codable {
    let id: UUID
    let projectId: UUID
    let mediaType: MediaType
    let storagePath: String
    let thumbnailPath: String?
    let createdAt: Date

    enum MediaType: String, Codable {
        case photo = "photo"
        case video = "video"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case projectId    = "project_id"
        case mediaType    = "media_type"
        case storagePath  = "storage_path"
        case thumbnailPath = "thumbnail_path"
        case createdAt    = "created_at"
    }
}
