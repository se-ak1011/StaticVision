import Foundation
import UIKit
import Combine

@MainActor
final class ProjectViewModel: ObservableObject {

    @Published var projects: [Project]     = []
    @Published var isLoading               = false
    @Published var errorMessage: String?
    @Published var uploadProgress: Double  = 0

    private let supabase = SupabaseService.shared

    // MARK: – Fetch

    func fetchProjects() async {
        guard let userId = supabase.currentUser?.id else { return }
        await perform {
            self.projects = try await self.supabase.fetchProjects(userId: userId)
        }
    }

    // MARK: – Create

    func createProject(name: String, description: String,
                       photos: [UIImage], videoURL: URL?) async -> Project? {
        guard let userId = supabase.currentUser?.id else {
            errorMessage = "Not signed in"
            return nil
        }

        let now = Date()
        let newProject = Project(
            id: UUID(),
            name: name.isEmpty ? "Untitled Project" : name,
            description: description,
            userId: userId,
            status: .draft,
            mediaCount: 0,
            blueprintId: nil,
            createdAt: now,
            updatedAt: now
        )

        var savedProject: Project?
        await perform {
            savedProject = try await self.supabase.createProject(newProject)
            guard let project = savedProject else { return }

            // Upload photos
            var mediaCount = 0
            let total = Double(photos.count) + (videoURL != nil ? 1 : 0)

            for (index, image) in photos.enumerated() {
                guard let jpeg = image.jpegData(compressionQuality: 0.8) else { continue }
                let path = "\(userId)/\(project.id)/photo_\(index).jpg"
                try await self.supabase.uploadFile(
                    bucket: AppConfig.mediaBucket,
                    path: path,
                    data: jpeg,
                    contentType: "image/jpeg"
                )
                let media = ProjectMedia(
                    id: UUID(),
                    projectId: project.id,
                    mediaType: .photo,
                    storagePath: path,
                    thumbnailPath: nil,
                    createdAt: Date()
                )
                _ = try await self.supabase.addMedia(media)
                mediaCount += 1
                self.uploadProgress = Double(index + 1) / total
            }

            // Upload video
            if let videoURL {
                let videoData = try Data(contentsOf: videoURL)
                let path = "\(userId)/\(project.id)/walkthrough.mp4"
                try await self.supabase.uploadFile(
                    bucket: AppConfig.mediaBucket,
                    path: path,
                    data: videoData,
                    contentType: "video/mp4"
                )
                let media = ProjectMedia(
                    id: UUID(),
                    projectId: project.id,
                    mediaType: .video,
                    storagePath: path,
                    thumbnailPath: nil,
                    createdAt: Date()
                )
                _ = try await self.supabase.addMedia(media)
                mediaCount += 1
                self.uploadProgress = 1.0
            }

            // Update media count
            var updated = project
            updated.mediaCount = mediaCount
            updated.updatedAt = Date()
            try await self.supabase.updateProject(updated)
            savedProject = updated

            if let idx = self.projects.firstIndex(where: { $0.id == project.id }) {
                self.projects[idx] = updated
            } else {
                self.projects.insert(updated, at: 0)
            }
        }
        return savedProject
    }

    // MARK: – Delete

    func deleteProject(_ project: Project) async {
        await perform {
            try await self.supabase.deleteProject(id: project.id)
            self.projects.removeAll { $0.id == project.id }
        }
    }

    // MARK: – Update status

    func updateStatus(_ status: Project.ProjectStatus, for project: Project) async {
        var updated = project
        updated.status = status
        updated.updatedAt = Date()
        await perform {
            try await self.supabase.updateProject(updated)
            if let idx = self.projects.firstIndex(where: { $0.id == project.id }) {
                self.projects[idx] = updated
            }
        }
    }

    // MARK: – Fetch media

    func fetchMedia(for project: Project) async -> [ProjectMedia] {
        do {
            return try await supabase.fetchMedia(projectId: project.id)
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    // MARK: – Helper

    private func perform(_ action: @escaping () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        do {
            try await action()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
