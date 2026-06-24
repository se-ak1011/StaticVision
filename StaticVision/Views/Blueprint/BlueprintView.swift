import SwiftUI
import UIKit

struct BlueprintView: View {
    let project: Project
    @EnvironmentObject private var viewModel: BlueprintViewModel

    @State private var showEditor = false
    @State private var zoom: CGFloat = 1.0
    @GestureState private var gestureZoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var gestureDrag: CGSize = .zero
    @State private var sourcePhotos: [UIImage] = []

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            if viewModel.isGenerating {
                generatingState
            } else if let blueprint = viewModel.blueprint {
                VStack(spacing: 0) {
                    if !sourcePhotos.isEmpty {
                        SourcePhotoStrip(images: sourcePhotos)
                    }
                    blueprintCanvas(blueprint)
                        .overlay(alignment: .bottom) { bottomToolbar }
                }
            } else {
                emptyState
            }
        }
        .task { await loadSourcePhotos() }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $showEditor) {
            if viewModel.blueprint != nil {
                BlueprintEditorView()
                    .environmentObject(viewModel)
            }
        }
    }

    // MARK: – Source photos

    private func loadSourcePhotos() async {
        guard sourcePhotos.isEmpty else { return }
        let media = (try? await SupabaseService.shared.fetchMedia(projectId: project.id)) ?? []
        var images: [UIImage] = []
        for item in media where item.mediaType == .photo {
            if let data = try? await SupabaseService.shared.downloadMedia(item),
               let img = UIImage(data: data) {
                images.append(img)
            }
        }
        let loaded = images
        await MainActor.run { sourcePhotos = loaded }
    }

    // MARK: – States

    private var generatingState: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text(viewModel.generationStep)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .animation(.default, value: viewModel.generationStep)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            VStack(spacing: 8) {
                Text("No Blueprint Yet")
                    .font(.title2.bold())
                Text("Generate a floor plan from your uploaded photos and video.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 40)
            }
            Button {
                Task { await viewModel.generateBlueprint(for: project) }
            } label: {
                Label("Generate Blueprint", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.brandPurple)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                    .padding(.horizontal, 40)
            }
        }
    }

    // MARK: – Canvas

    private func blueprintCanvas(_ blueprint: Blueprint) -> some View {
        let totalZoom = zoom * gestureZoom
        let currentOffset = CGSize(
            width:  offset.width  + gestureDrag.width,
            height: offset.height + gestureDrag.height
        )

        return GeometryReader { geo in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    // Grid background
                    BlueprintGridView(
                        width:  blueprint.canvasWidth + 80,
                        height: blueprint.canvasHeight + 80
                    )

                    // Rooms
                    ForEach(blueprint.rooms) { room in
                        RoomTileView(room: room, isSelected: viewModel.selectedRoomId == room.id)
                            .frame(width: room.width, height: room.height)
                            .position(
                                x: room.x + room.width / 2,
                                y: room.y + room.height / 2
                            )
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.selectedRoomId =
                                        viewModel.selectedRoomId == room.id ? nil : room.id
                                }
                            }
                    }
                }
                .frame(
                    width:  (blueprint.canvasWidth + 80) * totalZoom,
                    height: (blueprint.canvasHeight + 80) * totalZoom
                )
                .scaleEffect(totalZoom, anchor: .topLeading)
                .offset(currentOffset)
            }
        }
        .gesture(
            MagnificationGesture()
                .updating($gestureZoom) { val, state, _ in state = val }
                .onEnded { zoom = min(max(zoom * $0, 0.4), 4.0) }
        )
    }

    private var bottomToolbar: some View {
        HStack(spacing: 16) {
            // Zoom controls
            HStack(spacing: 0) {
                Button { withAnimation { zoom = max(0.4, zoom - 0.2) } } label: {
                    Image(systemName: "minus").frame(width: 36, height: 36)
                }
                Divider().frame(height: 24)
                Button { withAnimation { zoom = 1.0; offset = .zero } } label: {
                    Text("\(Int(zoom * 100))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 48, height: 36)
                }
                Divider().frame(height: 24)
                Button { withAnimation { zoom = min(4.0, zoom + 0.2) } } label: {
                    Image(systemName: "plus").frame(width: 36, height: 36)
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))

            Spacer()

            // Re-generate
            Button {
                Task { await viewModel.generateBlueprint(for: project) }
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
                    .font(.caption.bold())
            }
            .buttonStyle(.bordered)

            // Edit
            Button {
                showEditor = true
            } label: {
                Label("Edit", systemImage: "pencil")
                    .font(.caption.bold())
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .padding(.top, 8)
        .background(.ultraThinMaterial)
    }
}

// MARK: – Grid background

struct BlueprintGridView: View {
    let width: Double
    let height: Double
    private let gridSize: CGFloat = 20

    var body: some View {
        Canvas { context, size in
            let gridColor = Color(hex: "#9D4EDD").opacity(0.20)
            // Vertical lines
            var x: CGFloat = 0
            while x <= size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(gridColor), lineWidth: 0.5)
                x += gridSize
            }
            // Horizontal lines
            var y: CGFloat = 0
            while y <= size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(gridColor), lineWidth: 0.5)
                y += gridSize
            }
        }
        .background(Color(hex: "#0D0717"))
        .frame(width: width, height: height)
    }
}

// MARK: – Room tile

struct RoomTileView: View {
    let room: Room
    let isSelected: Bool

    var body: some View {
        ZStack {
            // Floor fill
            Rectangle()
                .fill(Color(hex: room.floorColor).opacity(0.35))

            // Wall outline
            Rectangle()
                .stroke(
                    isSelected ? Color.yellow : Color(hex: "#9D4EDD"),
                    lineWidth: isSelected ? 2.5 : 1.5
                )

            // Room label
            VStack(spacing: 2) {
                Text(room.name)
                    .font(.system(size: max(9, min(13, room.width / 10))))
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 1)
                Text("\(Int(room.width / 10))′ × \(Int(room.height / 10))′")
                    .font(.system(size: max(7, min(10, room.width / 14))))
                    .foregroundColor(.white.opacity(0.7))
                    .shadow(color: .black.opacity(0.5), radius: 1)
            }
            .padding(4)

            // Furniture items
            ForEach(room.furniture) { item in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: item.color).opacity(0.7))
                    .frame(width: item.width, height: item.height)
                    .position(
                        x: item.x + item.width / 2,
                        y: item.y + item.height / 2
                    )
                    .rotationEffect(.degrees(item.rotation))
            }
        }
        .clipShape(Rectangle())
    }
}

// MARK: – Source photo strip

struct SourcePhotoStrip: View {
    let images: [UIImage]
    @State private var preview: PreviewImage?

    private struct PreviewImage: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your photos")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 6)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(images.indices, id: \.self) { i in
                        Image(uiImage: images[i])
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .onTapGesture { preview = PreviewImage(image: images[i]) }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .background(.ultraThinMaterial)
        .sheet(item: $preview) { item in
            Image(uiImage: item.image)
                .resizable()
                .scaledToFit()
                .ignoresSafeArea()
                .background(Color.black)
                .onTapGesture { preview = nil }
        }
    }
}

#Preview {
    let vm = BlueprintViewModel()
    return BlueprintView(
        project: Project(
            id: UUID(), name: "Preview", description: "",
            userId: UUID(), status: .ready, mediaCount: 3,
            blueprintId: nil, createdAt: Date(), updatedAt: Date()
        )
    )
    .environmentObject(vm)
}
