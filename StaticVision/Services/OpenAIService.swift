import Foundation
import UIKit

// MARK: - OpenAIService

/// Wraps the OpenAI Chat Completions API (GPT-4o with vision).
final class OpenAIService {

    static let shared = OpenAIService()
    private init() {}

    // MARK: – Blueprint Generation

    /// Analyses up to `maxImages` photos from a project and returns a
    /// `Blueprint` populated with AI-estimated rooms.
    func generateBlueprint(projectId: UUID, images: [UIImage]) async throws -> Blueprint {
        let aiResponse = try await analyseImages(images)
        return buildBlueprint(projectId: projectId, from: aiResponse)
    }

    // MARK: – Interior Design Suggestions

    /// Returns a natural-language description of design suggestions for a room.
    func suggestDesign(for room: Room, style: String = "modern") async throws -> String {
        let prompt = """
        You are an expert interior designer. Suggest a design scheme for a \
        \(room.name) measuring approximately \
        \(Int(room.width / 10)) × \(Int(room.height / 10)) feet. \
        The desired style is \(style). \
        Current wall color: \(room.wallColor), floor: \(room.floorMaterial.rawValue). \
        Provide 3 concise, actionable suggestions (furniture placement, colour palette, \
        lighting). Keep each suggestion to one sentence.
        """
        return try await chatCompletion(prompt: prompt)
    }

    // MARK: – Private helpers

    private func analyseImages(_ images: [UIImage]) async throws -> AIBlueprintResponse {
        let maxImages = min(images.count, 10)
        let selected = Array(images.prefix(maxImages))

        var contentParts: [[String: Any]] = [
            [
                "type": "text",
                "text": """
                You are an expert architectural surveyor. ALL of the following images are of \
                the SAME property. Reconstruct an accurate floor plan from what is actually visible.

                Return ONLY valid JSON (no markdown, no extra text) with exactly this structure:
                {
                  "rooms": [
                    {
                      "name": "Room Name",
                      "width_ft": <number>,
                      "height_ft": <number>,
                      "adjacent_rooms": ["Room Name", ...],
                      "suggested_furniture": ["Sofa", "Coffee Table", ...]
                    }
                  ],
                  "notes": "Brief notes about anything uncertain"
                }

                STRICT rules:
                - Only include rooms you can SEE clear evidence of. Do NOT invent or assume \
                  rooms (e.g. don't add a hallway, utility room or garage unless it is visible).
                - If the same room appears across multiple photos, count it ONCE.
                - Estimate dimensions from visible reference objects: interior door ≈ 32 in wide, \
                  ceiling ≈ 8 ft, kitchen counter ≈ 36 in tall, double bed ≈ 4.5 × 6.5 ft, \
                  sofa ≈ 6–7 ft wide.
                - Use specific realistic names (Living Room, Kitchen, Master Bedroom, Bathroom…).
                - width_ft/height_ft are the floor footprint in feet (typically 6–25).
                - Only list adjacent_rooms where a connecting doorway/opening is actually visible.
                - It is better to return FEWER, accurate rooms than many guessed ones.
                """,
            ]
        ]

        for image in selected {
            guard let jpeg = image.jpegData(compressionQuality: 0.85) else { continue }
            let base64 = jpeg.base64EncodedString()
            contentParts.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:image/jpeg;base64,\(base64)",
                    "detail": "high",
                ],
            ])
        }

        let messages: [[String: Any]] = [
            ["role": "user", "content": contentParts]
        ]

        let body: [String: Any] = [
            "model": AppConfig.openAIModel,
            "messages": messages,
            "max_tokens": 2500,
            "temperature": 0.2,
            "response_format": ["type": "json_object"],
        ]

        let responseText = try await chatRequest(body: body)
        return try parseAIResponse(responseText)
    }

    private func chatCompletion(prompt: String) async throws -> String {
        let body: [String: Any] = [
            "model": AppConfig.openAIModel,
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 400,
            "temperature": 0.7,
        ]
        return try await chatRequest(body: body)
    }

    private func chatRequest(body: [String: Any]) async throws -> String {
        // Calls go to the Supabase Edge Function proxy, which injects the OpenAI
        // key server-side. We authenticate with the user's Supabase session JWT.
        var request = URLRequest(url: AppConfig.openAIProxyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        if let token = SupabaseService.shared.session?.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            throw AppError.authRequired
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AppError.serverError("No response")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AppError.serverError("OpenAI proxy HTTP \(http.statusCode): \(body)")
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw AppError.parsingError("Unexpected OpenAI response shape")
        }
        return content
    }

    private func parseAIResponse(_ text: String) throws -> AIBlueprintResponse {
        // The model sometimes wraps JSON in ```json ... ``` fences
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw AppError.parsingError("Cannot encode AI response as UTF-8")
        }
        do {
            return try JSONDecoder().decode(AIBlueprintResponse.self, from: data)
        } catch {
            throw AppError.parsingError("Cannot decode AI blueprint: \(error.localizedDescription)")
        }
    }

    // MARK: – Blueprint assembly

    private func buildBlueprint(projectId: UUID, from response: AIBlueprintResponse) -> Blueprint {
        let scale: Double = 10.0   // 10 canvas-points per foot
        let padding: Double = 20
        let colWidth: Double = 200
        let rowHeight: Double = 160
        let cols = 3

        var rooms: [Room] = []

        for (index, aiRoom) in response.rooms.enumerated() {
            let col = index % cols
            let row = index / cols
            let x = padding + Double(col) * (colWidth + padding)
            let y = padding + Double(row) * (rowHeight + padding)

            var room = Room(
                id: UUID(),
                name: aiRoom.name,
                x: x,
                y: y,
                width: max(80, aiRoom.widthFt * scale),
                height: max(60, aiRoom.heightFt * scale),
                wallColor: "#F5F5F5",
                floorColor: "#D2A679",
                floorMaterial: defaultFloorMaterial(for: aiRoom.name),
                furniture: []
            )

            // Pre-populate with suggested furniture
            if let suggested = aiRoom.suggestedFurniture {
                room.furniture = suggestedFurnitureItems(
                    from: suggested,
                    roomWidth: room.width,
                    roomHeight: room.height
                )
            }

            rooms.append(room)
        }

        let totalCols = min(response.rooms.count, cols)
        let totalRows = (response.rooms.count + cols - 1) / cols
        let canvasWidth  = padding + Double(totalCols) * (colWidth + padding)
        let canvasHeight = padding + Double(totalRows) * (rowHeight + padding)

        let now = Date()
        return Blueprint(
            id: UUID(),
            projectId: projectId,
            rooms: rooms,
            scale: scale,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            generatedAt: now,
            updatedAt: now
        )
    }

    private func defaultFloorMaterial(for roomName: String) -> Room.FloorMaterial {
        let lower = roomName.lowercased()
        if lower.contains("bath") || lower.contains("toilet") || lower.contains("shower") {
            return .tile
        } else if lower.contains("kitchen") {
            return .tile
        } else if lower.contains("bedroom") || lower.contains("living") {
            return .hardwood
        }
        return .hardwood
    }

    private func suggestedFurnitureItems(from names: [String],
                                         roomWidth: Double,
                                         roomHeight: Double) -> [FurnitureItem] {
        var items: [FurnitureItem] = []
        var offsetX = 8.0
        var offsetY = 8.0

        for name in names.prefix(4) {
            guard let type = FurnitureType.allCases.first(where: {
                $0.rawValue.lowercased().contains(name.lowercased()) ||
                name.lowercased().contains($0.rawValue.lowercased())
            }) else { continue }

            var item = FurnitureItem(type: type, x: offsetX, y: offsetY)

            // Keep item within room bounds
            if offsetX + item.width > roomWidth - 8 {
                offsetX = 8
                offsetY += item.height + 8
            }
            if offsetY + item.height > roomHeight - 8 { break }

            item.x = offsetX
            item.y = offsetY
            items.append(item)
            offsetX += item.width + 8
        }
        return items
    }
}
