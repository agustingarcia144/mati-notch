import Foundation
import Combine

/// Visibility-scoped requests; credentials never enter published state or logs.
@MainActor
final class ConvexStore: ObservableObject {
    @Published private(set) var projects: [ConvexProject] = []
    @Published private(set) var projectsLoading = false
    @Published private(set) var projectsError: String?
    @Published private(set) var projectsRefreshedAt: Date?
    @Published private(set) var usage: ConvexUsage?
    @Published private(set) var usageLoading = false
    @Published private(set) var usageError: String?
    @Published var selectedProjectID: Int? {
        didSet {
            guard oldValue != selectedProjectID else { return }
            usage = nil
            usageError = nil
            if visible && enabled { refreshUsage() }
        }
    }

    private let client: ConvexClient
    private var connection: ConvexConnection?
    private var enabled = false
    private var visible = false
    private var generation = 0
    private var projectTask: Task<Void, Never>?
    private var usageTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    init(client: ConvexClient = ConvexClient()) { self.client = client }

    func configure(_ newConnection: ConvexConnection?) {
        guard connection != newConnection else { return }
        stop()
        connection = newConnection
        projects = []
        projectsError = nil
        projectsRefreshedAt = nil
        selectedProjectID = nil
        usage = nil
        usageError = nil
        if visible && enabled { start() }
    }

    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        if enabled && visible { start() } else { stop() }
    }

    func setVisible(_ value: Bool) {
        guard visible != value else { return }
        visible = value
        if visible && enabled { start() } else { stop() }
    }

    private func start() {
        guard connection != nil else { return }
        refresh()
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(600)) } catch { return }
                guard let self, self.visible, self.enabled else { return }
                self.refresh()
            }
        }
    }

    private func stop() {
        generation += 1
        projectTask?.cancel()
        usageTask?.cancel()
        refreshTask?.cancel()
        projectTask = nil
        usageTask = nil
        refreshTask = nil
        projectsLoading = false
        usageLoading = false
    }

    /// Explicit Settings validation may fetch projects even when the pill is disabled.
    func refreshProjects() {
        guard let connection else { return }
        projectTask?.cancel()
        let generation = generation
        projectsLoading = true
        projectTask = Task { [weak self, client] in
            do {
                try await client.validate(connection)
                let projects = try await client.projects(connection)
                guard let self, !Task.isCancelled, self.generation == generation else { return }
                self.projects = projects
                self.projectsError = nil
                self.projectsRefreshedAt = Date()
                self.projectsLoading = false
                if !projects.contains(where: { $0.id == self.selectedProjectID }) {
                    self.selectedProjectID = nil
                }
            } catch {
                guard let self, !Task.isCancelled, self.generation == generation else { return }
                self.projectsError = Self.message(error)
                self.projectsLoading = false
            }
        }
    }

    func refresh() {
        guard visible && enabled else { return }
        refreshProjects()
        refreshUsage()
    }

    private func refreshUsage() {
        usageTask?.cancel()
        usageLoading = false
        guard visible && enabled, let connection, let id = selectedProjectID else { return }
        let generation = generation
        usageLoading = true
        usageTask = Task { [weak self, client] in
            do {
                let usage = try await ConvexUsageAdapter(client: client).usage(connection, projectID: id)
                guard let self, !Task.isCancelled, self.generation == generation,
                      self.selectedProjectID == id else { return }
                self.usage = usage
                self.usageError = nil
                self.usageLoading = false
            } catch {
                guard let self, !Task.isCancelled, self.generation == generation,
                      self.selectedProjectID == id else { return }
                self.usageError = Self.message(error)
                self.usageLoading = false
            }
        }
    }

    private static func message(_ error: Error) -> String {
        // Never surface raw server bodies or request URLs that might contain secrets.
        if let error = error as? ConvexError { return error.localizedDescription }
        return "Could not connect to Convex. Try again later."
    }
}
