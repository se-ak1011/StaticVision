import SwiftUI
import PhotosUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        Group {
            if authViewModel.isInitializing {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if authViewModel.isAuthenticated {
                RoomVisualizerView()
            } else {
                // Fallback only if the silent shared-account sign-in fails.
                AuthView()
                    .environmentObject(authViewModel)
            }
        }
        .tint(.brandPurple)
        .preferredColorScheme(.dark)
        .animation(.easeInOut, value: authViewModel.isAuthenticated)
    }
}

// MARK: - Room Visualiser (before → after)

enum VisualStyle: String, CaseIterable, Identifiable {
    case fairyBeachBoho = "Fairy Beach Boho"
    case cosyCabin      = "Cosy Cabin"
    case brightAiry     = "Bright & Airy"
    case modernWarm     = "Modern Warm"
    case scandi         = "Scandi"

    var id: String { rawValue }

    var prompt: String {
        let base = """
        Re-imagine this EXACT room as a finished, lived-in home. Keep the existing \
        architecture, the window and door positions, the ceiling height and the wood \
        log burner if one is present, and keep the same camera viewpoint and perspective. \
        Remove ALL mould, damp stains, dirt, clutter and dead insects — show clean, sound \
        walls, ceiling and floor. Result must be a photorealistic interior photograph with \
        warm, natural lighting.
        """
        switch self {
        case .fairyBeachBoho:
            return base + " Decorate it as a cosy bohemian 'fairy + coastal + hippie' retreat: reclaimed and driftwood timber, steampunk brass and copper accents, lots of warm fairy string lights, macramé wall hangings, layered rugs and floor cushions, trailing houseplants, lanterns and candles, a soft and slightly magical ambience."
        case .cosyCabin:
            return base + " Decorate it as a warm rustic cabin: natural timber, chunky knitted throws, the log burner lit and glowing, amber lighting, snug and inviting."
        case .brightAiry:
            return base + " Decorate it light and airy: pale woods, white and sage-green tones, sheer curtains, lots of plants, fresh and calm."
        case .modernWarm:
            return base + " Decorate it modern and warm: clean lines, warm neutral palette, walnut wood, soft textiles, tasteful and uncluttered."
        case .scandi:
            return base + " Decorate it Scandinavian: light oak, white walls, cosy hygge textiles, simple functional furniture, soft warm light."
        }
    }
}

struct RoomVisualizerView: View {
    @State private var beforeImage: UIImage?
    @State private var afterImage: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var style: VisualStyle = .fairyBeachBoho
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showingAfter = true

    private let openAI = OpenAIService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    imageArea
                        .frame(maxWidth: .infinity)
                        .frame(height: 320)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    if beforeImage == nil {
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("Choose a room photo", systemImage: "photo.on.rectangle.angled")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.brandPurple)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        Text("Pick a photo of the room as it is now — mould, mess and all. We'll show you what it could become.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        stylePicker

                        Button {
                            Task { await visualise() }
                        } label: {
                            Label(afterImage == nil ? "Visualise this room" : "Try this style",
                                  systemImage: "wand.and.stars")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.brandPurple)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(isGenerating)

                        if let afterImage {
                            Button {
                                UIImageWriteToSavedPhotosAlbum(afterImage, nil, nil, nil)
                            } label: {
                                Label("Save to Photos", systemImage: "square.and.arrow.down")
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 46)
                            }
                            .buttonStyle(.bordered)
                        }

                        Button(role: .destructive) {
                            reset()
                        } label: {
                            Label("Start over with a new photo", systemImage: "arrow.counterclockwise")
                                .font(.subheadline)
                        }
                        .padding(.top, 4)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
            }
            .navigationTitle("StaticVision")
            .overlay { if isGenerating { generatingOverlay } }
            .onChange(of: pickerItem) { _, item in
                Task { await loadBefore(item) }
            }
        }
    }

    // MARK: – Pieces

    @ViewBuilder
    private var imageArea: some View {
        if let after = afterImage, showingAfter {
            Image(uiImage: after).resizable().scaledToFit()
        } else if let before = beforeImage {
            Image(uiImage: before).resizable().scaledToFit()
        } else {
            VStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 48))
                    .foregroundColor(.brandPurple)
                Text("Before → After")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var stylePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            if afterImage != nil {
                Picker("View", selection: $showingAfter) {
                    Text("Before").tag(false)
                    Text("After").tag(true)
                }
                .pickerStyle(.segmented)
            }
            Text("Style")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(VisualStyle.allCases) { option in
                        Text(option.rawValue)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(style == option ? Color.brandPurple : Color.white.opacity(0.1))
                            .foregroundColor(style == option ? .white : .primary)
                            .clipShape(Capsule())
                            .onTapGesture { style = option }
                    }
                }
            }
        }
    }

    private var generatingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().tint(.white).scaleEffect(1.4)
                Text("Designing your room…").foregroundColor(.white)
                Text("This can take up to a minute.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(28)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    // MARK: – Actions

    private func loadBefore(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let img = UIImage(data: data) {
            beforeImage = img
            afterImage = nil
            showingAfter = true
            errorMessage = nil
        }
    }

    private func visualise() async {
        guard let before = beforeImage else { return }
        isGenerating = true
        errorMessage = nil
        do {
            let result = try await openAI.visualizeRoom(image: before, prompt: style.prompt)
            afterImage = result
            showingAfter = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isGenerating = false
    }

    private func reset() {
        beforeImage = nil
        afterImage = nil
        pickerItem = nil
        errorMessage = nil
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}
