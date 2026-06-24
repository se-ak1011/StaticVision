import SwiftUI

struct InteriorDesignView: View {
    let project: Project
    @EnvironmentObject private var blueprintVM: BlueprintViewModel
    @StateObject private var designVM = DesignViewModel()

    @State private var selectedRoom: Room?
    @State private var showColorSheet = false
    @State private var showFurnitureSheet = false
    @State private var showPresets = false
    @State private var showAISuggestion = false
    @State private var designStyle = "modern"

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

            if let blueprint = blueprintVM.blueprint {
                VStack(spacing: 0) {
                    // Room selector
                    roomSelectorBar(blueprint.rooms)

                    // Design canvas
                    if let room = selectedRoom {
                        DesignCanvasView(room: room)
                            .environmentObject(blueprintVM)
                            .environmentObject(designVM)
                    } else {
                        selectRoomPlaceholder
                    }

                    if selectedRoom != nil {
                        designToolbar
                    }
                }
            } else {
                noBlueprintState
            }
        }
        // Furniture palette
        .sheet(isPresented: $showFurnitureSheet) {
            if let room = selectedRoom {
                FurniturePaletteView(room: room)
                    .environmentObject(blueprintVM)
                    .environmentObject(designVM)
            }
        }
        // Colour & material sheet
        .sheet(isPresented: $showColorSheet) {
            if let room = selectedRoom {
                ColorMaterialSheet(room: room) { updated in
                    blueprintVM.updateRoom(updated)
                    selectedRoom = updated
                }
            }
        }
        // Design presets
        .sheet(isPresented: $showPresets) {
            PresetsSheet { preset in
                if let room = selectedRoom {
                    blueprintVM.applyPreset(preset, to: room.id)
                    if let updated = blueprintVM.blueprint?.rooms.first(where: { $0.id == room.id }) {
                        selectedRoom = updated
                    }
                }
                showPresets = false
            }
        }
        // AI suggestions
        .sheet(isPresented: $showAISuggestion) {
            if let room = selectedRoom {
                AISuggestionSheet(room: room, style: designStyle)
                    .environmentObject(designVM)
            }
        }
        // Keep selectedRoom in sync with blueprint changes
        .onChange(of: blueprintVM.blueprint) { _, blueprint in
            if let id = selectedRoom?.id {
                selectedRoom = blueprint?.rooms.first { $0.id == id }
            }
        }
    }

    // MARK: – Subviews

    private func roomSelectorBar(_ rooms: [Room]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(rooms) { room in
                    Button {
                        withAnimation { selectedRoom = room }
                    } label: {
                        Text(room.name)
                            .font(.subheadline.bold())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selectedRoom?.id == room.id
                                        ? Color.brandPurple : Color.secondary.opacity(0.15))
                            .foregroundColor(selectedRoom?.id == room.id ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var selectRoomPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "paintpalette")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Select a room above to start designing")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noBlueprintState: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text("Generate a blueprint first")
                .font(.headline)
            Text("Go to the Blueprint tab to generate your floor plan.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var designToolbar: some View {
        HStack(spacing: 12) {
            ToolbarActionButton(icon: "chair.lounge", label: "Furniture") {
                showFurnitureSheet = true
            }
            ToolbarActionButton(icon: "paintpalette", label: "Colours") {
                showColorSheet = true
            }
            ToolbarActionButton(icon: "square.grid.2x2", label: "Presets") {
                showPresets = true
            }
            ToolbarActionButton(icon: "sparkles", label: "AI Ideas") {
                showAISuggestion = true
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

// MARK: – Toolbar button

struct ToolbarActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.12))
            .cornerRadius(10)
        }
        .foregroundColor(.primary)
    }
}

// MARK: – Design canvas

struct DesignCanvasView: View {
    let room: Room
    @EnvironmentObject private var blueprintVM: BlueprintViewModel
    @EnvironmentObject private var designVM: DesignViewModel

    @State private var selectedFurnitureId: UUID?

    var body: some View {
        GeometryReader { geo in
            let scale = min(
                geo.size.width  / CGFloat(room.width  + 40),
                geo.size.height / CGFloat(room.height + 40)
            )
            let scaledW = CGFloat(room.width)  * scale
            let scaledH = CGFloat(room.height) * scale
            let originX = (geo.size.width  - scaledW) / 2
            let originY = (geo.size.height - scaledH) / 2

            ZStack(alignment: .topLeading) {
                // Room background
                Color(hex: room.floorColor)
                    .overlay(floorPattern)
                    .frame(width: scaledW, height: scaledH)
                    .border(Color(hex: room.wallColor).isDark ? Color.white : Color.black, width: 3)
                    .overlay(
                        Rectangle()
                            .inset(by: 6)
                            .stroke(Color(hex: room.wallColor), lineWidth: 12)
                    )
                    .position(x: originX + scaledW / 2, y: originY + scaledH / 2)

                // Furniture
                ForEach(room.furniture) { item in
                    DraggableFurnitureView(
                        item: item,
                        scale: scale,
                        originX: originX,
                        originY: originY,
                        isSelected: selectedFurnitureId == item.id,
                        onTap: { selectedFurnitureId = item.id == selectedFurnitureId ? nil : item.id },
                        onDragEnd: { pos in
                            let scaledPos = CGPoint(
                                x: Double((pos.x - originX) / scale),
                                y: Double((pos.y - originY) / scale)
                            )
                            blueprintVM.moveFurniture(id: item.id, in: room.id, to: scaledPos)
                        },
                        onDelete: { blueprintVM.deleteFurniture(id: item.id, from: room.id) }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(uiColor: .systemBackground))
    }

    @ViewBuilder
    private var floorPattern: some View {
        switch room.floorMaterial {
        case .hardwood:
            HardwoodPattern()
        case .tile:
            TilePattern()
        default:
            EmptyView()
        }
    }
}

// MARK: – Floor patterns

struct HardwoodPattern: View {
    var body: some View {
        Canvas { ctx, size in
            let plankH: CGFloat = 20
            let color = Color.black.opacity(0.08)
            var y: CGFloat = 0
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(path, with: .color(color), lineWidth: 1)
                y += plankH
            }
        }
    }
}

struct TilePattern: View {
    var body: some View {
        Canvas { ctx, size in
            let tileSize: CGFloat = 30
            let color = Color.black.opacity(0.1)
            var x: CGFloat = 0
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(path, with: .color(color), lineWidth: 0.8)
                x += tileSize
            }
            var y: CGFloat = 0
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(path, with: .color(color), lineWidth: 0.8)
                y += tileSize
            }
        }
    }
}

// MARK: – Draggable furniture

struct DraggableFurnitureView: View {
    let item: FurnitureItem
    let scale: CGFloat
    let originX: CGFloat
    let originY: CGFloat
    let isSelected: Bool
    var onTap: () -> Void
    var onDragEnd: (CGPoint) -> Void
    var onDelete: () -> Void

    @State private var dragOffset: CGSize = .zero

    private var scaledW: CGFloat { CGFloat(item.width)  * scale }
    private var scaledH: CGFloat { CGFloat(item.height) * scale }
    private var baseX: CGFloat   { originX + CGFloat(item.x) * scale + scaledW / 2 }
    private var baseY: CGFloat   { originY + CGFloat(item.y) * scale + scaledH / 2 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: max(3, 4 * scale))
                .fill(Color(hex: item.color).opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: max(3, 4 * scale))
                        .stroke(isSelected ? Color.yellow : Color.clear, lineWidth: 2)
                )
            Text(item.type.rawValue)
                .font(.system(size: max(6, 9 * scale)))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(2)
        }
        .frame(width: scaledW, height: scaledH)
        .rotationEffect(.degrees(item.rotation))
        .position(x: baseX + dragOffset.width, y: baseY + dragOffset.height)
        .gesture(
            DragGesture()
                .onChanged { dragOffset = $0.translation }
                .onEnded { value in
                    let finalX = baseX + value.translation.width
                    let finalY = baseY + value.translation.height
                    onDragEnd(CGPoint(x: finalX, y: finalY))
                    dragOffset = .zero
                }
        )
        .onTapGesture { onTap() }
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 18))
                }
                .offset(x: 8, y: -8)
            }
        }
    }
}

// MARK: – Color & material sheet

struct ColorMaterialSheet: View {
    @State var room: Room
    var onApply: (Room) -> Void
    @Environment(\.dismiss) private var dismiss

    private let wallPresets = [
        "#FFFFFF", "#F5F5F5", "#E8E0D8", "#D4C9BC", "#C8D8E4",
        "#E4C8C8", "#C8E4C8", "#2C2C2C", "#1A1A2E", "#0F3460"
    ]
    private let floorPresets = [
        "#C8A87A", "#A87A50", "#8B6F47", "#DDD5C8", "#B0B0B0",
        "#808080", "#5C4033", "#E8D5B0", "#C0A060", "#404040"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Wall Color") {
                    ColorPickerRow(hex: $room.wallColor, presets: wallPresets)
                }
                Section("Floor Color") {
                    ColorPickerRow(hex: $room.floorColor, presets: floorPresets)
                }
                Section("Floor Material") {
                    Picker("Material", selection: $room.floorMaterial) {
                        ForEach(Room.FloorMaterial.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.inline)
                }
                Section("Preview") {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: room.floorColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .inset(by: 8)
                                .stroke(Color(hex: room.wallColor), lineWidth: 16)
                        )
                        .frame(height: 120)
                }
            }
            .navigationTitle("Colors & Materials")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(room)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct ColorPickerRow: View {
    @Binding var hex: String
    let presets: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: hex))
                    .frame(width: 36, height: 36)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                TextField("Hex color", text: $hex)
                    .autocapitalization(.allCharacters)
                    .font(.system(.body, design: .monospaced))
                ColorPicker("", selection: Binding(
                    get: { Color(hex: hex) },
                    set: { hex = $0.toHex() ?? hex }
                ), supportsOpacity: false)
                .labelsHidden()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { preset in
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(hex: preset))
                            .frame(width: 28, height: 28)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(preset == hex ? Color.primary : Color.clear, lineWidth: 2)
                            )
                            .onTapGesture { hex = preset }
                    }
                }
            }
        }
    }
}

// MARK: – Design presets sheet

struct PresetsSheet: View {
    var onSelect: (DesignPreset) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(DesignPreset.presets) { preset in
                Button {
                    onSelect(preset)
                } label: {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: preset.floorColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .inset(by: 6)
                                    .stroke(Color(hex: preset.wallColor), lineWidth: 12)
                            )
                            .frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preset.name).font(.headline)
                            HStack(spacing: 6) {
                                Circle().fill(Color(hex: preset.wallColor))
                                    .frame(width: 12, height: 12)
                                    .overlay(Circle().stroke(Color.secondary.opacity(0.3)))
                                Text("Wall").font(.caption).foregroundColor(.secondary)
                                Circle().fill(Color(hex: preset.floorColor))
                                    .frame(width: 12, height: 12)
                                Text("Floor").font(.caption).foregroundColor(.secondary)
                                Text(preset.floorMaterial.rawValue)
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
                .foregroundColor(.primary)
            }
            .navigationTitle("Style Presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: – AI suggestion sheet

struct AISuggestionSheet: View {
    let room: Room
    @State var style: String
    @EnvironmentObject private var designVM: DesignViewModel
    @Environment(\.dismiss) private var dismiss

    private let styles = ["modern", "contemporary", "scandinavian", "industrial", "coastal", "farmhouse", "minimalist", "bohemian"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Picker("Style", selection: $style) {
                    ForEach(styles, id: \.self) { Text($0.capitalized).tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)

                Button {
                    Task { await designVM.fetchSuggestion(for: room, style: style) }
                } label: {
                    Label("Get AI Suggestions", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.brandPurple)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .padding(.horizontal)
                }
                .disabled(designVM.isLoadingSuggestion)

                if designVM.isLoadingSuggestion {
                    ProgressView("Thinking…")
                } else if let suggestion = designVM.aiSuggestion {
                    ScrollView {
                        Text(suggestion)
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(12)
                            .padding(.horizontal)
                    }
                }
                Spacer()
            }
            .padding(.top, 16)
            .navigationTitle("AI Design Ideas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: – Colour helpers

extension Color {
    var isDark: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: nil)
        return (0.299 * r + 0.587 * g + 0.114 * b) < 0.5
    }

    func toHex() -> String? {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "#%02X%02X%02X",
                      Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

#Preview {
    let vm = BlueprintViewModel()
    return InteriorDesignView(
        project: Project(
            id: UUID(), name: "Preview", description: "",
            userId: UUID(), status: .ready, mediaCount: 2,
            blueprintId: nil, createdAt: Date(), updatedAt: Date()
        )
    )
    .environmentObject(vm)
}
