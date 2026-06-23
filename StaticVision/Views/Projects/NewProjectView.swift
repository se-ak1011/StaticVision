import SwiftUI
import PhotosUI
import AVKit

struct NewProjectView: View {
    @EnvironmentObject private var viewModel: ProjectViewModel
    @Environment(\.dismiss) private var dismiss

    var onComplete: (Project?) -> Void

    @State private var name        = ""
    @State private var description = ""

    // Photos
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var pickedImages: [UIImage]            = []

    // Video
    @State private var selectedVideo: PhotosPickerItem?
    @State private var videoURL: URL?
    @State private var showVideoPlayer = false

    @State private var showPhotosPicker = false
    @State private var showVideoPicker  = false

    var body: some View {
        NavigationStack {
            Form {
                // Details section
                Section("Project Details") {
                    TextField("Name (e.g. 123 Oak Street)", text: $name)
                    TextField("Notes (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                // Photos section
                Section {
                    if pickedImages.isEmpty {
                        photoPlaceholder
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(pickedImages.indices, id: \.self) { i in
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: pickedImages[i])
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 80, height: 80)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                        Button {
                                            pickedImages.remove(at: i)
                                            if i < selectedPhotos.count {
                                                selectedPhotos.remove(at: i)
                                            }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.white)
                                                .shadow(radius: 2)
                                        }
                                        .offset(x: 4, y: -4)
                                    }
                                }
                                Button { showPhotosPicker = true } label: {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.secondary.opacity(0.15))
                                        .frame(width: 80, height: 80)
                                        .overlay(Image(systemName: "plus").font(.title2))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Photos")
                } footer: {
                    Text("Add up to 10 photos of each room for best AI results.")
                }

                // Video section
                Section {
                    if let videoURL {
                        HStack {
                            Image(systemName: "film.fill")
                                .foregroundColor(.blue)
                            Text("Walk-through video added")
                                .font(.subheadline)
                            Spacer()
                            Button("View") { showVideoPlayer = true }
                                .font(.caption)
                            Button("Remove") {
                                self.videoURL = nil
                                self.selectedVideo = nil
                            }
                            .foregroundColor(.red)
                            .font(.caption)
                        }
                    } else {
                        Button {
                            showVideoPicker = true
                        } label: {
                            Label("Add Walk-Around Video", systemImage: "video.badge.plus")
                        }
                    }
                } header: {
                    Text("Video (optional)")
                } footer: {
                    Text("A walk-around video greatly improves blueprint accuracy.")
                }

                // Upload progress
                if viewModel.isLoading {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Uploading… \(Int(viewModel.uploadProgress * 100))%")
                                .font(.subheadline)
                            ProgressView(value: viewModel.uploadProgress)
                        }
                    }
                }

                // Error
                if let err = viewModel.errorMessage {
                    Section {
                        Text(err)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onComplete(nil) }
                        .disabled(viewModel.isLoading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createProject() }
                        .disabled(viewModel.isLoading || name.isEmpty)
                }
            }
            // Photos picker
            .photosPicker(isPresented: $showPhotosPicker,
                          selection: $selectedPhotos,
                          maxSelectionCount: 10,
                          matching: .images)
            .onChange(of: selectedPhotos) { _, items in
                Task { await loadImages(from: items) }
            }
            // Video picker
            .photosPicker(isPresented: $showVideoPicker,
                          selection: $selectedVideo,
                          matching: .videos)
            .onChange(of: selectedVideo) { _, item in
                Task { await loadVideo(from: item) }
            }
            // Video player
            .sheet(isPresented: $showVideoPlayer) {
                if let url = videoURL {
                    VideoPlayer(player: AVPlayer(url: url))
                        .ignoresSafeArea()
                }
            }
        }
    }

    // MARK: – Subview helpers

    private var photoPlaceholder: some View {
        Button { showPhotosPicker = true } label: {
            HStack {
                Image(systemName: "photo.badge.plus")
                    .font(.title2)
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Photos")
                        .foregroundColor(.primary)
                        .fontWeight(.medium)
                    Text("Select up to 10 photos")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: – Actions

    private func createProject() {
        guard !name.isEmpty else { return }
        Task {
            let project = await viewModel.createProject(
                name: name,
                description: description,
                photos: pickedImages,
                videoURL: videoURL
            )
            await MainActor.run { onComplete(project) }
        }
    }

    private func loadImages(from items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }
        await MainActor.run { pickedImages = images }
    }

    private func loadVideo(from item: PhotosPickerItem?) async {
        guard let item else { return }
        if let url = try? await item.loadTransferable(type: URL.self) {
            await MainActor.run { videoURL = url }
        }
    }
}

#Preview {
    NewProjectView { _ in }
        .environmentObject(ProjectViewModel())
}
