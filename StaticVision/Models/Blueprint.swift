import Foundation
import SwiftUI

// MARK: - Blueprint

struct Blueprint: Identifiable, Codable {
    let id: UUID
    let projectId: UUID
    var rooms: [Room]
    var scale: Double        // pixels-per-foot
    var canvasWidth: Double
    var canvasHeight: Double
    let generatedAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, rooms, scale
        case projectId   = "project_id"
        case canvasWidth = "canvas_width"
        case canvasHeight = "canvas_height"
        case generatedAt = "generated_at"
        case updatedAt   = "updated_at"
    }

    // Convenience: all furniture across all rooms
    var allFurniture: [FurnitureItem] {
        rooms.flatMap(\.furniture)
    }
}

// MARK: - Room

struct Room: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String

    // Position & size on blueprint canvas (in points)
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    // Design properties
    var wallColor: String    // hex, e.g. "#FFFFFF"
    var floorColor: String   // hex
    var floorMaterial: FloorMaterial
    var furniture: [FurnitureItem]

    enum FloorMaterial: String, Codable, CaseIterable {
        case hardwood   = "Hardwood"
        case carpet     = "Carpet"
        case tile       = "Tile"
        case laminate   = "Laminate"
        case concrete   = "Concrete"
        case vinyl      = "Vinyl"
    }

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    static func defaultRoom(name: String = "Room", at position: CGPoint = .zero) -> Room {
        Room(
            id: UUID(),
            name: name,
            x: Double(position.x),
            y: Double(position.y),
            width: 120,
            height: 100,
            wallColor: "#F5F5F5",
            floorColor: "#D2A679",
            floorMaterial: .hardwood,
            furniture: []
        )
    }
}

// MARK: - FurnitureItem

struct FurnitureItem: Identifiable, Codable, Hashable {
    var id: UUID
    var type: FurnitureType
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var rotation: Double    // degrees
    var color: String       // hex tint

    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    init(type: FurnitureType, x: Double = 0, y: Double = 0,
         color: String = "#8B7355") {
        self.id = UUID()
        self.type = type
        self.x = x
        self.y = y
        self.width = type.defaultSize.width
        self.height = type.defaultSize.height
        self.rotation = 0
        self.color = color
    }
}

// MARK: - FurnitureType

enum FurnitureType: String, Codable, CaseIterable {
    // Seating
    case sofa       = "Sofa"
    case armchair   = "Armchair"

    // Tables
    case diningTable = "Dining Table"
    case coffeeTable = "Coffee Table"
    case desk        = "Desk"

    // Beds
    case kingBed   = "King Bed"
    case queenBed  = "Queen Bed"
    case singleBed = "Single Bed"

    // Storage
    case wardrobe  = "Wardrobe"
    case bookshelf = "Bookshelf"

    // Kitchen
    case fridge   = "Fridge"
    case stove    = "Stove"
    case sink     = "Sink"
    case island   = "Kitchen Island"

    // Bathroom
    case toilet  = "Toilet"
    case bathtub = "Bathtub"
    case shower  = "Shower"

    // Other
    case tvUnit  = "TV Unit"
    case plant   = "Plant"

    var category: FurnitureCategory {
        switch self {
        case .sofa, .armchair:                          return .seating
        case .diningTable, .coffeeTable, .desk:         return .tables
        case .kingBed, .queenBed, .singleBed:           return .beds
        case .wardrobe, .bookshelf:                     return .storage
        case .fridge, .stove, .sink, .island:           return .kitchen
        case .toilet, .bathtub, .shower:                return .bathroom
        case .tvUnit, .plant:                           return .other
        }
    }

    var defaultSize: CGSize {
        switch self {
        case .sofa:        return CGSize(width: 72, height: 30)
        case .armchair:    return CGSize(width: 32, height: 32)
        case .diningTable: return CGSize(width: 60, height: 40)
        case .coffeeTable: return CGSize(width: 40, height: 24)
        case .desk:        return CGSize(width: 48, height: 24)
        case .kingBed:     return CGSize(width: 64, height: 80)
        case .queenBed:    return CGSize(width: 56, height: 75)
        case .singleBed:   return CGSize(width: 38, height: 75)
        case .wardrobe:    return CGSize(width: 60, height: 24)
        case .bookshelf:   return CGSize(width: 36, height: 12)
        case .fridge:      return CGSize(width: 28, height: 28)
        case .stove:       return CGSize(width: 30, height: 26)
        case .sink:        return CGSize(width: 24, height: 20)
        case .island:      return CGSize(width: 48, height: 30)
        case .toilet:      return CGSize(width: 18, height: 28)
        case .bathtub:     return CGSize(width: 28, height: 60)
        case .shower:      return CGSize(width: 32, height: 32)
        case .tvUnit:      return CGSize(width: 56, height: 16)
        case .plant:       return CGSize(width: 16, height: 16)
        }
    }

    var systemIcon: String {
        switch self {
        case .sofa:        return "sofa"
        case .armchair:    return "chair.lounge"
        case .diningTable, .coffeeTable, .desk: return "tablecells"
        case .kingBed, .queenBed, .singleBed:  return "bed.double"
        case .wardrobe:    return "cabinet"
        case .bookshelf:   return "books.vertical"
        case .fridge:      return "refrigerator"
        case .stove:       return "flame"
        case .sink:        return "drop"
        case .island:      return "square.grid.2x2"
        case .toilet:      return "toilet"
        case .bathtub:     return "bathtub"
        case .shower:      return "shower"
        case .tvUnit:      return "tv"
        case .plant:       return "leaf"
        }
    }
}

enum FurnitureCategory: String, CaseIterable {
    case seating  = "Seating"
    case tables   = "Tables"
    case beds     = "Beds"
    case storage  = "Storage"
    case kitchen  = "Kitchen"
    case bathroom = "Bathroom"
    case other    = "Other"

    var icon: String {
        switch self {
        case .seating:  return "sofa"
        case .tables:   return "tablecells"
        case .beds:     return "bed.double"
        case .storage:  return "cabinet"
        case .kitchen:  return "fork.knife"
        case .bathroom: return "shower"
        case .other:    return "ellipsis.circle"
        }
    }
}
