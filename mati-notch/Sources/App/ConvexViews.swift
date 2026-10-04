import SwiftUI

struct ConvexSettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store: ConvexStore
    @State private var token: String
    @State private var teamID: String
    @State private var message: String?

    init(state: AppState) {
        self.state = state
        self.store = state.convex
        _token = State(initialValue: KeychainStore.shared.get("convex-team-token") ?? "")
        _teamID = State(initialValue: state.convexTeamID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: "#F3A744")).frame(width: 8, height: 8)
                Text("Convex").font(.system(size: 12, weight: .semibold))
            }
            SecureField("Team access token", text: $token).textFieldStyle(.roundedBorder)
            TextField("Team ID", text: $teamID).textFieldStyle(.roundedBorder)
            HStack {
                Button("Save & validate") { save() }
                    .disabled(store.projectsLoading)
                if store.projectsLoading { ProgressView().controlSize(.small) }
                Link("Get a team token", destination: URL(string: "https://dashboard.convex.dev")!)
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            if let error = store.projectsError {
                Text(error).font(.caption).foregroundStyle(.red)
            } else if store.projectsRefreshedAt != nil {
                Text("Connected · \(store.projects.count) projects").font(.caption).foregroundStyle(.secondary)
            }
            if !store.projects.isEmpty {
                DisclosureGroup("Projects · \(state.convexProjectFilter.isEmpty ? "All" : "Selected")") {
                    Button("Watch all projects") { state.convexProjectFilter = [] }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(store.projects) { project in
                                Toggle(project.name, isOn: Binding(
                                    get: { state.convexProjectFilter.isEmpty || state.convexProjectFilter.contains(project.id) },
                                    set: { selected in
                                        if state.convexProjectFilter.isEmpty {
                                            state.convexProjectFilter = Set(store.projects.map(\.id))
                                        }
                                        if selected { state.convexProjectFilter.insert(project.id) }
                                        else if state.convexProjectFilter.count > 1 {
                                            state.convexProjectFilter.remove(project.id)
                                        }
                                    }
                                ))
                                .toggleStyle(.checkbox)
                            }
                        }
                    }.frame(maxHeight: 130)
                    Text("Keep at least one selected, or watch all projects.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Usage is best effort through Convex’s internal dashboard API. If unavailable, open the dashboard.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func save() {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTeam = teamID.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanToken.isEmpty {
            KeychainStore.shared.remove("convex-team-token")
            state.convexTeamID = ""
            state.convexProjectFilter = []
            state.syncConvexConnection()
            message = "Convex disconnected."
            return
        }
        guard ConvexConnection(token: cleanToken, teamID: cleanTeam) != nil else {
            message = "Enter a team token and a positive numeric team ID."
            return
        }
        if state.convexTeamID != cleanTeam { state.convexProjectFilter = [] }
        KeychainStore.shared.set("convex-team-token", value: cleanToken)
        state.convexTeamID = cleanTeam
        state.syncConvexConnection()
        store.refreshProjects()
        message = "Saved in Keychain. Enable Convex in Active pills to show it in the notch."
    }
}

struct ConvexCardView: View {
    @ObservedObject var state: AppState
    @ObservedObject var store: ConvexStore
    private let secondary = Color(hex: "#8E939C")

    private var projects: [ConvexProject] {
        store.projects.filter { state.convexProjectFilter.isEmpty || state.convexProjectFilter.contains($0.id) }
    }
    private var selected: ConvexProject? { projects.first { $0.id == store.selectedProjectID } }
    private var configured: Bool {
        ConvexConnection(token: KeychainStore.shared.get("convex-team-token") ?? "", teamID: state.convexTeamID) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                if selected != nil {
                    Button { store.selectedProjectID = nil } label: {
                        Image(systemName: "chevron.left")
                    }.buttonStyle(.plain).help("Back to projects")
                }
                Circle().fill(Color(hex: "#F3A744")).frame(width: 7, height: 7)
                Text(selected?.name ?? "Convex").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                Button { store.refresh() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10))
                }.buttonStyle(.plain).disabled(store.projectsLoading || store.usageLoading || !configured)
                    .help("Refresh Convex")
            }.padding(.trailing, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    if !configured {
                        Text("Connect Convex in Settings → Integrations.")
                    } else if let project = selected {
                        usageDetail
                        Link("Open in Convex ↗", destination: project.usageURL)
                    } else {
                        if let error = store.projectsError {
                            Text(error).foregroundStyle(secondary)
                            if store.projectsRefreshedAt != nil { Text("Showing stale projects").foregroundStyle(secondary) }
                        }
                        if store.projectsLoading { Text("Loading projects…").foregroundStyle(secondary) }
                        if !store.projectsLoading && projects.isEmpty && store.projectsError == nil {
                            Text("No projects found for this selection.").foregroundStyle(secondary)
                        }
                        ForEach(projects) { project in
                            Button { store.selectedProjectID = project.id } label: {
                                HStack {
                                    Text(project.name).lineLimit(1)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.system(size: 9))
                                }.padding(.vertical, 3)
                            }.buttonStyle(.plain)
                        }
                        if let date = store.projectsRefreshedAt { freshness(date, stale: store.projectsError != nil) }
                        Link("Open in Convex ↗", destination: URL(string: "https://dashboard.convex.dev")!)
                    }
                }
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(Color(hex: "#C5C8CD"))
        .padding(.top, 6).padding(.bottom, 6).padding(.leading, 108).padding(.trailing, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            state.syncConvexConnection()
            store.setVisible(true)
        }
        .onDisappear { store.setVisible(false) }
    }

    @ViewBuilder private var usageDetail: some View {
        if let usage = store.usage {
            Text("\(usage.period.start) – \(usage.period.end)").font(.system(size: 9)).foregroundStyle(secondary)
            metric("Function calls", usage.functionCalls, bytes: false)
            metric("Database storage", usage.databaseStorage, bytes: true)
            metric("File storage", usage.fileStorage, bytes: true)
            metric("Data egress", usage.dataEgress, bytes: true)
            freshness(usage.refreshedAt, stale: store.usageError != nil)
        }
        if store.usageLoading { Text("Loading usage…").foregroundStyle(secondary) }
        if let error = store.usageError {
            Text("Usage unavailable · \(error)").foregroundStyle(secondary)
        } else if !store.usageLoading && store.usage == nil {
            Text("Usage unavailable").foregroundStyle(secondary)
        }
    }

    private func metric(_ name: String, _ value: Double?, bytes: Bool) -> some View {
        HStack(spacing: 4) {
            Text(name).foregroundStyle(secondary)
            Spacer(minLength: 0)
            Text(value.map { bytes ? Self.bytes($0) : $0.formatted(.number.precision(.fractionLength(0))) } ?? "Unavailable")
                .monospacedDigit()
        }.font(.system(size: 9))
    }

    private func freshness(_ date: Date, stale: Bool) -> some View {
        HStack(spacing: 3) {
            Text(stale ? "Stale · updated" : "Updated")
            Text(date.formatted(date: .abbreviated, time: .shortened))
        }.font(.system(size: 9)).foregroundStyle(secondary)
    }

    private static func bytes(_ value: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var scaled = value
        var unit = 0
        while scaled >= 1024 && unit < units.count - 1 { scaled /= 1024; unit += 1 }
        return "\(scaled.formatted(.number.precision(.fractionLength(0...1)))) \(units[unit])"
    }
}
