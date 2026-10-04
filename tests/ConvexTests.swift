import Foundation

private struct Reply: Sendable {
    var status = 200
    var body: String
    var delay = 0.0
    var offline = false
}

private final class Fixtures: @unchecked Sendable {
    let lock = NSLock()
    private var overrides: [String: Reply] = [:]
    private var recorded: [URLRequest] = []
    static let project = "{\"id\":7,\"name\":\"Example\",\"slug\":\"example\",\"teamId\":41,\"teamSlug\":\"my-team\"}"
    static let summary = "[[41,\"default\",\"us-east-1\",1024,0,12,0,0,0,2048,0,4096]]"
    func reset(_ overrides: [String: Reply] = [:]) {
        lock.withLock { self.overrides = overrides; recorded = [] }
    }
    var requests: [URLRequest] { lock.withLock { recorded } }
    func reply(_ request: URLRequest) -> Reply {
        lock.withLock {
            recorded.append(request)
            let path = request.url!.path
            if let reply = overrides[path] { return reply }
            switch path {
            case "/v1/token_details": return Reply(body: "{\"teamId\":41,\"type\":\"teamToken\"}")
            case "/v1/teams/41/projects":
                let cursor = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "cursor" }?.value
                if cursor != nil {
                    return Reply(body: "{\"items\":[\(Self.project)],\"pagination\":{\"hasMore\":false}}")
                }
                return Reply(body: "{\"items\":[\(Self.project)],\"pagination\":{\"hasMore\":true,\"nextCursor\":\"page 2&cursor\"}}")
            case "/api/dashboard/teams/41/usage/current_billing_period":
                return Reply(body: "{\"start\":\"2026-10-01\",\"end\":\"2026-11-01\"}")
            case "/api/dashboard/teams/41/usage/query": return Reply(body: Self.summary)
            default: return Reply(status: 404, body: "{}")
            }
        }
    }
}

private final class MockProtocol: URLProtocol, @unchecked Sendable {
    static let fixtures = Fixtures()
    private let lock = NSLock()
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let reply = Self.fixtures.reply(request)
        DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay) { [self] in
            lock.withLock {
                guard !stopped else { return }
                if reply.offline {
                    client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                    return
                }
                let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                               httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
                client?.urlProtocolDidFinishLoading(self)
            }
        }
    }
    override func stopLoading() { lock.withLock { stopped = true } }
}

@main @MainActor
struct ConvexTests {
    static var failures = 0
    static func check(_ label: String, _ value: Bool) {
        print("\(value ? "✓" : "✗") \(label)")
        if !value { failures += 1 }
    }
    static func expect(_ label: String, _ expected: ConvexError,
                       action: () async throws -> Void) async {
        do { try await action(); check(label, false) }
        catch { check(label, error as? ConvexError == expected) }
    }
    static func settle(_ condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        check("request settled before deadline", false)
    }
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = ConvexClient(session: session)
        let connection = ConvexConnection(token: "fixture-secret", teamID: "41")!
        let period = ConvexBillingPeriod(start: "2026-10-01", end: "2026-11-01")
        let fixtures = MockProtocol.fixtures
        let usagePath = "/api/dashboard/teams/41/usage/query"
        let periodPath = "/api/dashboard/teams/41/usage/current_billing_period"

        check("reject nonnumeric team", ConvexConnection(token: "x", teamID: "-1") == nil)
        check("reject blank token", ConvexConnection(token: " ", teamID: "41") == nil)
        check("normalize pasted credentials", ConvexConnection(token: " x\n", teamID: " 41 ")?.token == "x")
        fixtures.reset()
        try await client.validate(connection)
        let projects = try await client.projects(connection)
        check("paginate and deduplicate stable IDs", projects.count == 1 && projects[0].id == 7)
        check("dashboard uses team and project slugs", projects[0].dashboardURL.absoluteString == "https://dashboard.convex.dev/t/my-team/example")
        check("usage fallback opens project usage page", projects[0].usageURL.absoluteString == "https://dashboard.convex.dev/t/my-team/example/usage")
        check("pagination cursor correctly encoded", fixtures.requests.last?.url?.absoluteString.contains("page%202%26cursor") == true)
        check("Bearer authorization", fixtures.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-secret" })

        let full = try ConvexUsageAdapter.decodeSummary(Data(Fixtures.summary.utf8), period: period)
        check("decode column mapping and byte units", full.functionCalls == 12 && full.databaseStorage == 1024 && full.fileStorage == 2048 && full.dataEgress == 4096)
        let mixed = "[[41,\"default\",\"us\",\"100\",0,\"0\",0,0,0,\"20\",0,\"30\"],[41,\"business\",\"eu\",200,0,2,0,0,0,40,0,60]]"
        let sum = try ConvexUsageAdapter.decodeSummary(Data(mixed.utf8), period: period)
        check("sum deployment classes and numeric strings", sum.databaseStorage == 300 && sum.functionCalls == 2 && sum.fileStorage == 60 && sum.dataEgress == 90)
        let zero = try ConvexUsageAdapter.decodeSummary(Data("[[41,\"d\",\"us\",0,0,\"0\",0,0,0,0,0,0]]".utf8), period: period)
        check("real zero stays zero", zero.functionCalls == 0 && zero.fileStorage == 0)
        let missing = try ConvexUsageAdapter.decodeSummary(Data("[[41,\"d\",\"us\",null,0,\"bad\",0,0,0,\"\",0,true]]".utf8), period: period)
        check("null malformed empty and boolean unavailable", missing.databaseStorage == nil && missing.functionCalls == nil && missing.fileStorage == nil && missing.dataEgress == nil)
        let empty = try ConvexUsageAdapter.decodeSummary(Data("[]".utf8), period: period)
        check("no rows means unavailable", empty.functionCalls == nil)
        let short = try ConvexUsageAdapter.decodeSummary(Data("[[41,\"d\",\"us\",12]]".utf8), period: period)
        check("short rows do not become zero", short.functionCalls == nil && short.databaseStorage == 12)
        let negative = try ConvexUsageAdapter.decodeSummary(Data("[[41,\"d\",\"us\",-1,0,\"NaN\",0,0,0,1,0,1]]".utf8), period: period)
        check("negative and nonfinite unavailable", negative.databaseStorage == nil && negative.functionCalls == nil)
        do {
            _ = try ConvexUsageAdapter.decodeSummary(Data("{}".utf8), period: period)
            check("reject incompatible summary shape", false)
        } catch { check("reject incompatible summary shape", true) }

        fixtures.reset(["/v1/token_details": Reply(status: 401, body: "{}")])
        await expect("invalid token", .http(401)) { try await client.validate(connection) }
        fixtures.reset(["/v1/token_details": Reply(body: "{\"type\":\"teamToken\",\"teamId\":42}")])
        await expect("team mismatch", .teamMismatch) { try await client.validate(connection) }
        fixtures.reset(["/v1/token_details": Reply(body: "{\"type\":\"projectToken\",\"projectId\":7}")])
        await expect("reject project token", .teamMismatch) { try await client.validate(connection) }
        fixtures.reset(["/v1/teams/41/projects": Reply(status: 429, body: "{}")])
        await expect("rate limit", .http(429)) { _ = try await client.projects(connection) }
        fixtures.reset(["/v1/teams/41/projects": Reply(body: "{\"items\":[],\"pagination\":{\"hasMore\":true,\"nextCursor\":\"loop\"}}")])
        await expect("reject repeating pagination cursor", .invalidResponse) { _ = try await client.projects(connection) }
        fixtures.reset([periodPath: Reply(body: "{\"start\":\"nonsense\",\"end\":\"2026-11-01\"}")])
        await expect("reject invalid billing dates", .invalidResponse) { _ = try await ConvexUsageAdapter(client: client).usage(connection, projectID: 7) }

        fixtures.reset()
        let store = ConvexStore(client: client)
        store.configure(connection)
        store.setEnabled(true)
        check("hidden store makes no requests", fixtures.requests.isEmpty)
        store.setVisible(true)
        await settle { store.projectsRefreshedAt != nil && !store.projectsLoading }
        store.selectedProjectID = 7
        await settle { store.usage != nil && !store.usageLoading }
        let cached = store.usage
        check("project selection loads usage", cached?.functionCalls == 12)
        let query = URLComponents(url: fixtures.requests.first { $0.url?.path == usagePath }!.url!, resolvingAgainstBaseURL: false)!.queryItems!
        check("usage query scoped to project and billing period", query.contains(URLQueryItem(name: "projectId", value: "7")) && !query.contains { $0.name == "from" || $0.name == "to" })
        fixtures.reset([periodPath: Reply(status: 403, body: "{}")])
        store.refresh()
        await settle { !store.projectsLoading && !store.usageLoading }
        check("usage denial retains projects and stale usage", store.projects.count == 1 && store.projectsError == nil && store.usageError != nil && store.usage == cached)
        fixtures.reset([periodPath: Reply(body: "", offline: true)])
        store.refresh()
        await settle { !store.projectsLoading && !store.usageLoading }
        check("offline preserves usage", store.usage == cached && store.usageError != nil)
        fixtures.reset()
        store.refresh()
        await settle { !store.projectsLoading && !store.usageLoading }
        check("recovery clears stale error", store.usageError == nil && store.usage != nil)
        fixtures.reset([usagePath: Reply(body: Fixtures.summary, delay: 0.3)])
        store.selectedProjectID = nil
        store.selectedProjectID = 7
        await settle { fixtures.requests.contains { $0.url?.path == usagePath } }
        store.setVisible(false)
        try? await Task.sleep(for: .milliseconds(400))
        check("closing cancels usage and clears loading", store.usage == nil && !store.usageLoading)
        fixtures.reset()
        store.refresh()
        check("manual refresh while hidden makes no requests", fixtures.requests.isEmpty)
        store.setVisible(true)
        store.setEnabled(false)
        try? await Task.sleep(for: .milliseconds(50))
        let count = fixtures.requests.count
        store.refresh()
        try? await Task.sleep(for: .milliseconds(50))
        check("disabled integration stays stopped", !store.projectsLoading && !store.usageLoading && fixtures.requests.count == count)
        fixtures.reset([usagePath: Reply(body: Fixtures.summary, delay: 0.3)])
        store.setEnabled(true)
        store.selectedProjectID = 7
        await settle { fixtures.requests.contains { $0.url?.path == usagePath } }
        store.configure(ConvexConnection(token: "new-fixture-secret", teamID: "42"))
        try? await Task.sleep(for: .milliseconds(400))
        check("team change discards obsolete responses", store.projects.isEmpty && store.usage == nil && store.selectedProjectID == nil)
        store.setVisible(false)
        store.configure(connection)
        fixtures.reset()
        store.refreshProjects()
        await settle { !store.projectsLoading }
        check("Settings can validate while hidden", store.projects.count == 1 && store.projectsError == nil)
        store.configure(nil)
        check("disconnect clears cached data", store.projects.isEmpty && store.usage == nil && store.projectsRefreshedAt == nil)
        print("\(failures) failures")
        if failures != 0 { exit(1) }
    }
}
