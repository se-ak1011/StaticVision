import SwiftUI

/// Simple, list-based blueprint editor: tap a room to rename, resize or recolour it.
/// Rooms arrange themselves automatically, so there is no fiddly dragging or
/// tiny resize handles.
struct BlueprintEditorView: View {
    @EnvironmentObject private var viewModel: BlueprintViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(viewModel.blueprint?.rooms ?? []) { room in
                        NavigationLink {
                            RoomEditView(
                                room: room,
                                onUpdate: { viewModel.updateRoom($0) },
                                onDelete: { viewModel.deleteRoom(id: room.id) }
                            )
                        } label: {
                            RoomRow(room: room)
                        }
                    }
                    .onDelete(perform: deleteRooms)
                } header: {
                    Text("Rooms")
                } footer: {
                    Text("Tap a room to rename, resize or recolour it. Swipe left to delete. Rooms lay themselves out automatically.")
                }

                Section {
                    Button {
                        viewModel.addRoom()
                    } label: {
                        Label("Add Room", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle("Edit Blueprint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        viewModel.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func deleteRooms(at offsets: IndexSet) {
        guard let rooms = viewModel.blueprint?.rooms else { return }
        for index in offsets {
            viewModel.deleteRoom(id: rooms[index].id)
        }
    }
}

// MARK: – Room row

struct RoomRow: View {
    let room: Room

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: room.floorColor))
                .frame(width: 38, height: 38)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(hex: room.wallColor), lineWidth: 3)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(room.name.isEmpty ? "Untitled Room" : room.name)
                    .font(.headline)
                Text("\(Int(room.width / 10))′ × \(Int(room.height / 10))′ · \(room.floorMaterial.rawValue)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: – Room edit form

struct RoomEditView: View {
    @State var room: Room
    var onUpdate: (Room) -> Void
    var onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let wallPresets  = ["#FFFFFF", "#F5F5F5", "#E8E0D8", "#C8D8E4", "#2C2C2C", "#1A1A2E"]
    private let floorPresets = ["#C8A87A", "#A87A50", "#8B6F47", "#B0B0B0", "#808080", "#5C4033"]

    var body: some View {
        Form {
            Section("Name") {
                TextField("Room name", text: $room.name)
            }

            Section("Size") {
                sizeRow(title: "Width",  feet: room.width  / 10) { room.width  = $0 * 10 }
                sizeRow(title: "Length", feet: room.height / 10) { room.height = $0 * 10 }
            }

            Section("Walls") {
                ColorPickerRow(hex: $room.wallColor, presets: wallPresets)
            }

            Section("Floor") {
                ColorPickerRow(hex: $room.floorColor, presets: floorPresets)
                Picker("Material", selection: $room.floorMaterial) {
                    ForEach(Room.FloorMaterial.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    onDelete()
                    dismiss()
                } label: {
                    Label("Delete Room", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(room.name.isEmpty ? "Room" : room.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: room) { _, updated in onUpdate(updated) }
    }

    private func sizeRow(title: String, feet: Double, set: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(Int(feet))′")
                .foregroundColor(.secondary)
                .monospacedDigit()
            Stepper("", value: Binding(get: { feet }, set: { set($0) }), in: 4...40, step: 1)
                .labelsHidden()
        }
    }
}

#Preview {
    BlueprintEditorView()
        .environmentObject(BlueprintViewModel())
}
