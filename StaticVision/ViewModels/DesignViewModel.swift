import Foundation
import Combine

@MainActor
final class DesignViewModel: ObservableObject {

    @Published var selectedRoomId: UUID?
    @Published var aiSuggestion: String?
    @Published var isLoadingSuggestion = false
    @Published var selectedPreset: DesignPreset?
    @Published var showFurniturePalette = false
    @Published var activeFurnitureCategory: FurnitureCategory = .seating

    private let openAI = OpenAIService.shared

    var furnitureForCategory: [FurnitureType] {
        FurnitureType.allCases.filter { $0.category == activeFurnitureCategory }
    }

    // MARK: – AI design suggestion

    func fetchSuggestion(for room: Room, style: String = "modern") async {
        isLoadingSuggestion = true
        aiSuggestion = nil
        do {
            aiSuggestion = try await openAI.suggestDesign(for: room, style: style)
        } catch {
            aiSuggestion = "Couldn't load suggestions: \(error.localizedDescription)"
        }
        isLoadingSuggestion = false
    }
}
