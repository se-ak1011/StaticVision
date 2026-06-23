import SwiftUI

/// Project detail screen – entry point for blueprint generation and design.
struct ProjectDetailView: View {
    let project: Project

    @StateObject private var blueprintVM = BlueprintViewModel()
    @State private var tab: Tab = .blueprint

    enum Tab { case blueprint, design }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            Picker("View", selection: $tab) {
                Label("Blueprint", systemImage: "squareshape.split.2x2").tag(Tab.blueprint)
                Label("Design",    systemImage: "paintpalette").tag(Tab.design)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            switch tab {
            case .blueprint:
                BlueprintView(project: project)
                    .environmentObject(blueprintVM)
            case .design:
                InteriorDesignView(project: project)
                    .environmentObject(blueprintVM)
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await blueprintVM.loadBlueprint(for: project) }
    }
}
