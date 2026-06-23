import SwiftUI

struct ProjectsView: View {
    @StateObject private var viewModel  = ProjectViewModel()
    @EnvironmentObject private var auth : AuthViewModel
    @State private var showNewProject   = false
    @State private var projectToDelete: Project?
    @State private var showDeleteAlert  = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.projects.isEmpty {
                    ProgressView("Loading projects…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.projects.isEmpty {
                    emptyState
                } else {
                    projectList
                }
            }
            .navigationTitle("My Projects")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Sign Out") {
                        Task { await auth.signOut() }
                    }
                    .foregroundColor(.red)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showNewProject = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showNewProject) {
                NewProjectView { project in
                    showNewProject = false
                    if let project {
                        viewModel.projects.insert(project, at: 0)
                    }
                }
                .environmentObject(viewModel)
            }
            .alert("Delete project?", isPresented: $showDeleteAlert, presenting: projectToDelete) { p in
                Button("Delete", role: .destructive) {
                    Task { await viewModel.deleteProject(p) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { p in
                Text(""\(p.name)" and all its media will be deleted.")
            }
            .task { await viewModel.fetchProjects() }
            .refreshable { await viewModel.fetchProjects() }
        }
    }

    // MARK: – Subviews

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "house.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No projects yet")
                .font(.title2.bold())
            Text("Tap + to create your first project.\nUpload photos or a video walk-around and let AI reconstruct the floor plan.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            Button("New Project") { showNewProject = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var projectList: some View {
        List {
            ForEach(viewModel.projects) { project in
                NavigationLink(destination: ProjectDetailView(project: project)) {
                    ProjectRowView(project: project)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        projectToDelete = project
                        showDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: – Row

struct ProjectRowView: View {
    let project: Project

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10)
                .fill(statusColor.opacity(0.15))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: statusIcon)
                        .foregroundColor(statusColor)
                        .font(.title3)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.headline)
                HStack(spacing: 8) {
                    StatusBadge(status: project.status)
                    if project.mediaCount > 0 {
                        Label("\(project.mediaCount)", systemImage: "photo.on.rectangle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch project.status {
        case .draft:      return .orange
        case .processing: return .blue
        case .ready:      return .green
        case .failed:     return .red
        }
    }

    private var statusIcon: String {
        switch project.status {
        case .draft:      return "pencil.circle"
        case .processing: return "arrow.trianglehead.clockwise.rotate.90.circle"
        case .ready:      return "checkmark.circle.fill"
        case .failed:     return "exclamationmark.circle.fill"
        }
    }
}

struct StatusBadge: View {
    let status: Project.ProjectStatus

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case .draft:      return .orange
        case .processing: return .blue
        case .ready:      return .green
        case .failed:     return .red
        }
    }
}

#Preview {
    ProjectsView()
        .environmentObject(AuthViewModel())
}
