import SwiftUI

struct FurniturePaletteView: View {
    let room: Room
    @EnvironmentObject private var blueprintVM: BlueprintViewModel
    @EnvironmentObject private var designVM: DesignViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(FurnitureCategory.allCases, id: \.self) { cat in
                            Button {
                                designVM.activeFurnitureCategory = cat
                            } label: {
                                Label(cat.rawValue, systemImage: cat.icon)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        designVM.activeFurnitureCategory == cat
                                        ? Color.blue : Color.secondary.opacity(0.12)
                                    )
                                    .foregroundColor(
                                        designVM.activeFurnitureCategory == cat ? .white : .primary
                                    )
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                Divider()

                // Furniture grid
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                    ], spacing: 12) {
                        ForEach(designVM.furnitureForCategory, id: \.self) { type in
                            FurnitureItemCard(type: type) {
                                blueprintVM.addFurniture(type, to: room.id)
                                dismiss()
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Add Furniture")
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

// MARK: – Card

struct FurnitureItemCard: View {
    let type: FurnitureType
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            VStack(spacing: 8) {
                // Furniture silhouette
                FurnitureSilhouette(type: type)
                    .frame(width: 60, height: 60)

                Text(type.rawValue)
                    .font(.caption.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundColor(.primary)

                Text("\(Int(type.defaultSize.width / 10))′×\(Int(type.defaultSize.height / 10))′")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(12)
        }
    }
}

// MARK: – Silhouette renderer

struct FurnitureSilhouette: View {
    let type: FurnitureType

    var body: some View {
        let size = type.defaultSize
        let aspectRatio = size.width / size.height
        let color = Color(hex: silhouetteColor)

        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let itemW: CGFloat = aspectRatio > 1 ? w : h * aspectRatio
            let itemH: CGFloat = aspectRatio > 1 ? w / aspectRatio : h

            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(0.25))
                    .frame(width: itemW, height: itemH)
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color, lineWidth: 1.5)
                    .frame(width: itemW, height: itemH)
                Image(systemName: type.systemIcon)
                    .foregroundColor(color)
                    .font(.system(size: min(itemW, itemH) * 0.4))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var silhouetteColor: String {
        switch type.category {
        case .seating:  return "#5C6BC0"
        case .tables:   return "#8D6E63"
        case .beds:     return "#66BB6A"
        case .storage:  return "#FFA726"
        case .kitchen:  return "#EF5350"
        case .bathroom: return "#26C6DA"
        case .other:    return "#AB47BC"
        }
    }
}

#Preview {
    let vm = BlueprintViewModel()
    let dvm = DesignViewModel()
    let room = Room.defaultRoom(name: "Living Room")
    return FurniturePaletteView(room: room)
        .environmentObject(vm)
        .environmentObject(dvm)
}
