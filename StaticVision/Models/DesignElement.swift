import Foundation

// MARK: - OpenAI Blueprint response models (internal parsing)

/// The structured JSON that OpenAI returns when asked to analyse
/// property images and generate a floor plan layout.
struct AIBlueprintResponse: Codable {
    let rooms: [AIRoom]
    let notes: String?
}

struct AIRoom: Codable {
    let name: String
    let widthFt: Double
    let heightFt: Double
    let adjacentRooms: [String]?
    let suggestedFurniture: [String]?

    enum CodingKeys: String, CodingKey {
        case name, notes
        case widthFt         = "width_ft"
        case heightFt        = "height_ft"
        case adjacentRooms   = "adjacent_rooms"
        case suggestedFurniture = "suggested_furniture"
    }
}

// MARK: - Design preset

struct DesignPreset: Identifiable {
    let id: UUID
    let name: String
    let wallColor: String
    let floorColor: String
    let floorMaterial: Room.FloorMaterial
    let accentColor: String

    static let presets: [DesignPreset] = [
        DesignPreset(id: UUID(), name: "Modern White",
                     wallColor: "#FFFFFF", floorColor: "#C8B89A",
                     floorMaterial: .hardwood, accentColor: "#2C2C2C"),
        DesignPreset(id: UUID(), name: "Warm Scandi",
                     wallColor: "#F0E6D8", floorColor: "#B8935A",
                     floorMaterial: .hardwood, accentColor: "#5C8A5A"),
        DesignPreset(id: UUID(), name: "Industrial",
                     wallColor: "#D0CCC8", floorColor: "#808080",
                     floorMaterial: .concrete, accentColor: "#3E3E3E"),
        DesignPreset(id: UUID(), name: "Coastal Blue",
                     wallColor: "#E8F4F8", floorColor: "#DDD5C8",
                     floorMaterial: .tile, accentColor: "#2E7DAF"),
        DesignPreset(id: UUID(), name: "Forest Cabin",
                     wallColor: "#EEE8DC", floorColor: "#8B6F47",
                     floorMaterial: .hardwood, accentColor: "#4A6741"),
        DesignPreset(id: UUID(), name: "Midnight Dark",
                     wallColor: "#2C2C2C", floorColor: "#1A1A1A",
                     floorMaterial: .laminate, accentColor: "#C5A028"),
    ]
}
