import SwiftUI

struct BlueprintEditorView: View {
    @EnvironmentObject private var viewModel: BlueprintViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showRoomInspector = false
    @State private var editingRoom: Room?
    @State private var zoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero

    var body: some View {
        NavigationStack {
            ZStack {
                // Canvas
                if let blueprint = viewModel.blueprint {
                    editorCanvas(blueprint)
                }

                // Room inspector panel (slides up from bottom)
                if showRoomInspector, let room = editingRoom ?? viewModel.selectedRoom {
                    VStack {
                        Spacer()
                        RoomInspectorPanel(room: room) { updated in
                            viewModel.updateRoom(updated)
                            editingRoom = updated
                        } onDelete: {
                            viewModel.deleteRoom(id: room.id)
                            showRoomInspector = false
                            editingRoom = nil
                        }
                        .transition(.move(edge: .bottom))
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationTitle("Edit Blueprint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        viewModel.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.addRoom()
                    } label: {
                        Image(systemName: "plus.rectangle.on.rectangle")
                    }
                }
            }
            .onChange(of: viewModel.selectedRoomId) { _, id in
                withAnimation(.spring(response: 0.3)) {
                    showRoomInspector = id != nil
                    if let id, let room = viewModel.blueprint?.rooms.first(where: { $0.id == id }) {
                        editingRoom = room
                    } else if id == nil {
                        editingRoom = nil
                    }
                }
            }
        }
    }

    // MARK: – Editor canvas

    private func editorCanvas(_ blueprint: Blueprint) -> some View {
        ScrollView([.horizontal, .vertical], showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                // Grid
                BlueprintGridView(
                    width:  blueprint.canvasWidth + 80,
                    height: blueprint.canvasHeight + 80
                )

                // Draggable rooms
                ForEach(blueprint.rooms) { room in
                    EditableRoomView(
                        room: room,
                        isSelected: viewModel.selectedRoomId == room.id,
                        onTap: {
                            withAnimation {
                                viewModel.selectedRoomId =
                                    viewModel.selectedRoomId == room.id ? nil : room.id
                            }
                        },
                        onDragEnd: { newPosition in
                            viewModel.moveRoom(id: room.id, to: newPosition)
                        },
                        onResize: { w, h in
                            viewModel.resizeRoom(id: room.id, width: w, height: h)
                        }
                    )
                }
            }
            .frame(
                width:  (blueprint.canvasWidth + 80) * zoom,
                height: (blueprint.canvasHeight + 80) * zoom
            )
        }
        .background(Color(hex: "#0D1B2A"))
    }
}

// MARK: – Editable room

struct EditableRoomView: View {
    let room: Room
    let isSelected: Bool
    var onTap: () -> Void
    var onDragEnd: (CGPoint) -> Void
    var onResize: (Double, Double) -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var resizeOffset: CGSize = .zero

    private var baseX: CGFloat { CGFloat(room.x) }
    private var baseY: CGFloat { CGFloat(room.y) }
    private var roomW: CGFloat { CGFloat(room.width)  + resizeOffset.width }
    private var roomH: CGFloat { CGFloat(room.height) + resizeOffset.height }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Room body
            ZStack {
                Rectangle()
                    .fill(Color(hex: room.floorColor).opacity(0.35))
                Rectangle()
                    .stroke(isSelected ? Color.yellow : Color(hex: "#3B6CD4"),
                            lineWidth: isSelected ? 2.5 : 1.5)
                VStack(spacing: 2) {
                    Text(room.name)
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 1)
                    Text("\(Int(room.width / 10))′ × \(Int(room.height / 10))′")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .frame(width: max(60, roomW), height: max(40, roomH))
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .gesture(
                DragGesture()
                    .onChanged { dragOffset = $0.translation }
                    .onEnded { value in
                        let newX = baseX + value.translation.width
                        let newY = baseY + value.translation.height
                        onDragEnd(CGPoint(x: max(0, newX), y: max(0, newY)))
                        dragOffset = .zero
                    }
            )

            // Resize handle (bottom-right)
            if isSelected {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 10))
                    .foregroundColor(.yellow)
                    .frame(width: 20, height: 20)
                    .background(Color.yellow.opacity(0.3))
                    .clipShape(Circle())
                    .gesture(
                        DragGesture()
                            .onChanged { resizeOffset = $0.translation }
                            .onEnded { value in
                                let newW = Double(room.width)  + Double(value.translation.width)
                                let newH = Double(room.height) + Double(value.translation.height)
                                onResize(newW, newH)
                                resizeOffset = .zero
                            }
                    )
            }
        }
        .position(
            x: baseX + max(60, roomW) / 2 + dragOffset.width,
            y: baseY + max(40, roomH) / 2 + dragOffset.height
        )
    }
}

// MARK: – Room inspector panel

struct RoomInspectorPanel: View {
    @State var room: Room
    var onChange: (Room) -> Void
    var onDelete: () -> Void

    @State private var wallColorHex: String
    @State private var floorColorHex: String

    init(room: Room, onChange: @escaping (Room) -> Void, onDelete: @escaping () -> Void) {
        self._room = State(initialValue: room)
        self.onChange = onChange
        self.onDelete = onDelete
        self._wallColorHex  = State(initialValue: room.wallColor)
        self._floorColorHex = State(initialValue: room.floorColor)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            Form {
                Section("Room Name") {
                    TextField("Name", text: $room.name)
                        .onChange(of: room.name) { _, _ in onChange(room) }
                }

                Section("Dimensions (feet)") {
                    HStack {
                        Label("Width", systemImage: "arrow.left.and.right")
                        Spacer()
                        Stepper("\(Int(room.width / 10))′",
                                value: Binding(
                                    get: { room.width / 10 },
                                    set: { room.width = $0 * 10; onChange(room) }
                                ),
                                in: 6...50, step: 1)
                    }
                    HStack {
                        Label("Depth", systemImage: "arrow.up.and.down")
                        Spacer()
                        Stepper("\(Int(room.height / 10))′",
                                value: Binding(
                                    get: { room.height / 10 },
                                    set: { room.height = $0 * 10; onChange(room) }
                                ),
                                in: 6...50, step: 1)
                    }
                }

                Section("Wall Color") {
                    ColorHexField(hex: $wallColorHex, label: "Wall Color") {
                        room.wallColor = wallColorHex
                        onChange(room)
                    }
                }

                Section("Floor") {
                    ColorHexField(hex: $floorColorHex, label: "Floor Color") {
                        room.floorColor = floorColorHex
                        onChange(room)
                    }
                    Picker("Material", selection: Binding(
                        get: { room.floorMaterial },
                        set: { room.floorMaterial = $0; onChange(room) }
                    )) {
                        ForEach(Room.FloorMaterial.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) { onDelete() } label: {
                        Label("Delete Room", systemImage: "trash")
                    }
                }
            }
            .frame(height: 420)
        }
        .background(.regularMaterial)
        .cornerRadius(20, corners: [.topLeft, .topRight])
    }
}

// MARK: – Helpers

struct ColorHexField: View {
    @Binding var hex: String
    let label: String
    var onCommit: () -> Void

    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: hex))
                .frame(width: 28, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.4)))
            TextField(label, text: $hex)
                .onSubmit { onCommit() }
                .autocapitalization(.allCharacters)
            Text("#")
                .foregroundColor(.secondary)
        }
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview {
    let vm = BlueprintViewModel()
    return BlueprintEditorView().environmentObject(vm)
}
