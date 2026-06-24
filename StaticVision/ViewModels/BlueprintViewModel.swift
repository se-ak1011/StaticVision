import Foundation
import UIKit
import Combine
import AVFoundation

@MainActor
final class BlueprintViewModel: ObservableObject {

    @Published var blueprint: Blueprint?
    @Published var isGenerating  = false
    @Published var isLoading     = false
    @Published var errorMessage: String?
    @Published var selectedRoomId: UUID?
    @Published var generationStep = ""

    private let supabase = SupabaseService.shared
    private let openAI   = OpenAIService.shared

    var selectedRoom: Room? {
        guard let id = selectedRoomId else { return nil }
        return blueprint?.rooms.first { $0.id == id }
    }

    // MARK: – Load existing

    func loadBlueprint(for project: Project) async {
        isLoading = true
        defer { isLoading = false }
        do {
            blueprint = try await supabase.fetchBlueprint(projectId: project.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: – Generate from AI

    func generateBlueprint(for project: Project) async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        do {
            generationStep = "Fetching media…"
            let mediaItems = try await supabase.fetchMedia(projectId: project.id)
            let photoItems = mediaItems.filter { $0.mediaType == .photo }
            let videoItems = mediaItems.filter { $0.mediaType == .video }

            generationStep = "Loading photos…"
            var images: [UIImage] = []
            for media in photoItems.prefix(4) {
                if let data = try? await supabase.downloadMedia(media),
                   let image = UIImage(data: data) {
                    images.append(image)
                }
            }

            // Pull frames from the walk-around video — far more spatial context
            // than stills alone, which is the whole point of the app.
            if let video = videoItems.first {
                generationStep = "Analysing walk-through video…"
                if let data = try? await supabase.downloadMedia(video) {
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent("bp-\(UUID().uuidString).mp4")
                    if (try? data.write(to: tmp)) != nil {
                        let frames = await extractVideoFrames(from: tmp, maxFrames: 8)
                        images.append(contentsOf: frames)
                        try? FileManager.default.removeItem(at: tmp)
                    }
                }
            }

            if images.isEmpty {
                // No photos uploaded yet – generate a placeholder blueprint
                generationStep = "Creating placeholder blueprint…"
                let placeholder = createPlaceholderBlueprint(projectId: project.id)
                blueprint = try await supabase.upsertBlueprint(placeholder)
            } else {
                generationStep = "Analysing images with AI…"
                let generated = try await openAI.generateBlueprint(
                    projectId: project.id,
                    images: images
                )
                generationStep = "Saving blueprint…"
                blueprint = try await supabase.upsertBlueprint(generated)
            }
            generationStep = "Done!"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: – Room editing

    func addRoom() {
        guard blueprint != nil else { return }
        let offset = Double((blueprint!.rooms.count % 5)) * 20
        let room = Room.defaultRoom(
            name: "Room \(blueprint!.rooms.count + 1)",
            at: CGPoint(x: 20 + offset, y: 20 + offset)
        )
        blueprint!.rooms.append(room)
        save()
    }

    func deleteRoom(id: UUID) {
        blueprint?.rooms.removeAll { $0.id == id }
        if selectedRoomId == id { selectedRoomId = nil }
        save()
    }

    func updateRoom(_ room: Room) {
        guard let idx = blueprint?.rooms.firstIndex(where: { $0.id == room.id }) else { return }
        blueprint?.rooms[idx] = room
    }

    func moveRoom(id: UUID, to position: CGPoint) {
        guard let idx = blueprint?.rooms.firstIndex(where: { $0.id == id }) else { return }
        blueprint?.rooms[idx].x = Double(position.x)
        blueprint?.rooms[idx].y = Double(position.y)
    }

    func resizeRoom(id: UUID, width: Double, height: Double) {
        guard let idx = blueprint?.rooms.firstIndex(where: { $0.id == id }) else { return }
        blueprint?.rooms[idx].width  = max(60, width)
        blueprint?.rooms[idx].height = max(40, height)
    }

    // MARK: – Furniture

    func addFurniture(_ type: FurnitureType, to roomId: UUID) {
        guard let idx = blueprint?.rooms.firstIndex(where: { $0.id == roomId }) else { return }
        let item = FurnitureItem(type: type)
        blueprint?.rooms[idx].furniture.append(item)
    }

    func moveFurniture(id: UUID, in roomId: UUID, to position: CGPoint) {
        guard let roomIdx = blueprint?.rooms.firstIndex(where: { $0.id == roomId }),
              let itemIdx = blueprint?.rooms[roomIdx].furniture.firstIndex(where: { $0.id == id })
        else { return }
        blueprint?.rooms[roomIdx].furniture[itemIdx].x = Double(position.x)
        blueprint?.rooms[roomIdx].furniture[itemIdx].y = Double(position.y)
    }

    func deleteFurniture(id: UUID, from roomId: UUID) {
        guard let roomIdx = blueprint?.rooms.firstIndex(where: { $0.id == roomId }) else { return }
        blueprint?.rooms[roomIdx].furniture.removeAll { $0.id == id }
    }

    // MARK: – Room design

    func setWallColor(_ hex: String, for roomId: UUID) {
        guard let idx = blueprint?.rooms.firstIndex(where: { $0.id == roomId }) else { return }
        blueprint?.rooms[idx].wallColor = hex
    }

    func setFloorColor(_ hex: String, for roomId: UUID) {
        guard let idx = blueprint?.rooms.firstIndex(where: { $0.id == roomId }) else { return }
        blueprint?.rooms[idx].floorColor = hex
    }

    func setFloorMaterial(_ material: Room.FloorMaterial, for roomId: UUID) {
        guard let idx = blueprint?.rooms.firstIndex(where: { $0.id == roomId }) else { return }
        blueprint?.rooms[idx].floorMaterial = material
    }

    func applyPreset(_ preset: DesignPreset, to roomId: UUID) {
        guard let idx = blueprint?.rooms.firstIndex(where: { $0.id == roomId }) else { return }
        blueprint?.rooms[idx].wallColor     = preset.wallColor
        blueprint?.rooms[idx].floorColor    = preset.floorColor
        blueprint?.rooms[idx].floorMaterial = preset.floorMaterial
    }

    // MARK: – Persist

    func save() {
        guard blueprint != nil else { return }
        relayout()
        guard let bp = blueprint else { return }
        Task {
            do {
                var saving = bp
                saving.updatedAt = Date()
                blueprint = try await supabase.upsertBlueprint(saving)
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    // MARK: – Auto layout

    /// Arranges rooms into tidy wrapping rows so they never overlap — no manual
    /// dragging required.
    func relayout() {
        guard blueprint != nil else { return }
        let padding: Double = 16
        let maxRowWidth: Double = 360
        var x = padding
        var y = padding
        var rowHeight: Double = 0

        for index in blueprint!.rooms.indices {
            let w = blueprint!.rooms[index].width
            let h = blueprint!.rooms[index].height
            if x > padding, x + w > maxRowWidth {
                x = padding
                y += rowHeight + padding
                rowHeight = 0
            }
            blueprint!.rooms[index].x = x
            blueprint!.rooms[index].y = y
            x += w + padding
            rowHeight = max(rowHeight, h)
        }

        let maxX = blueprint!.rooms.map { $0.x + $0.width }.max() ?? maxRowWidth
        let maxY = blueprint!.rooms.map { $0.y + $0.height }.max() ?? 300
        blueprint!.canvasWidth = maxX + padding
        blueprint!.canvasHeight = maxY + padding
    }

    // MARK: – Video frames

    private func extractVideoFrames(from url: URL, maxFrames: Int = 8) async -> [UIImage] {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return [] }
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else { return [] }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 1280, height: 1280)

        var frames: [UIImage] = []
        for i in 0..<maxFrames {
            let fraction = maxFrames <= 1 ? 0.5 : Double(i) / Double(maxFrames - 1)
            let time = CMTime(seconds: seconds * fraction, preferredTimescale: 600)
            if let cgImage = try? await generator.image(at: time).image {
                frames.append(UIImage(cgImage: cgImage))
            }
        }
        return frames
    }

    // MARK: – Placeholder when no media exists

    private func createPlaceholderBlueprint(projectId: UUID) -> Blueprint {
        let now = Date()
        let rooms: [Room] = [
            Room(id: UUID(), name: "Living Room",  x: 20,  y: 20,  width: 180, height: 140,
                 wallColor: "#F5F5F5", floorColor: "#C8A87A", floorMaterial: .hardwood, furniture: []),
            Room(id: UUID(), name: "Kitchen",      x: 220, y: 20,  width: 130, height: 120,
                 wallColor: "#F5F5F5", floorColor: "#B0B0B0", floorMaterial: .tile,     furniture: []),
            Room(id: UUID(), name: "Master Bed",   x: 20,  y: 180, width: 150, height: 130,
                 wallColor: "#F5F5F5", floorColor: "#C8A87A", floorMaterial: .carpet,   furniture: []),
            Room(id: UUID(), name: "Bedroom 2",    x: 190, y: 180, width: 130, height: 120,
                 wallColor: "#F5F5F5", floorColor: "#C8A87A", floorMaterial: .carpet,   furniture: []),
            Room(id: UUID(), name: "Bathroom",     x: 340, y: 20,  width: 80,  height: 80,
                 wallColor: "#E8F4F8", floorColor: "#B0C4C8", floorMaterial: .tile,     furniture: []),
        ]
        return Blueprint(
            id: UUID(), projectId: projectId,
            rooms: rooms, scale: 10,
            canvasWidth: 460, canvasHeight: 340,
            generatedAt: now, updatedAt: now
        )
    }
}
