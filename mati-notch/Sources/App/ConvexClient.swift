import Foundation
import CoreFoundation

struct ConvexProject: Codable, Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
    let slug: String
    let teamId: Int
    let teamSlug: String

    var usageURL: URL { dashboardURL.appendingPathComponent("usage") }

    var dashboardURL: URL {
        var components = URLComponents(string: "https://dashboard.convex.dev")!
        components.path = "/t/\(teamSlug)/\(slug)"
        return components.url!
    }
}

struct ConvexBillingPeriod: Codable, Equatable, Sendable {
    let start: String
    let end: String
}

struct ConvexUsage: Equatable, Sendable {
    let period: ConvexBillingPeriod
    let functionCalls: Double?
    let databaseStorage: Double?
    let fileStorage: Double?
    let dataEgress: Double?
    let refreshedAt: Date
}

struct ConvexConnection: Equatable, Sendable {
    let token: String
    let teamID: Int

    init?(token: String, teamID: String) {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let team = teamID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !team.isEmpty, team.allSatisfy({ $0.isASCII && $0.isNumber }),
              let id = Int(team), id > 0 else { return nil }
        self.token = token
        self.teamID = id
    }
}

enum ConvexError: LocalizedError, Equatable {
    case http(Int), teamMismatch, invalidResponse

    var errorDescription: String? {
        switch self {
        case .http(401): return "Invalid or expired Convex token."
        case .http(403): return "This token does not have access."
        case .http(429): return "Convex rate limit reached. Try again later."
        case .http(let code): return "Convex returned HTTP \(code)."
        case .teamMismatch: return "Use a team access token matching the team ID."
        case .invalidResponse: return "Convex returned an unsupported response."
        }
    }
}

/// Public project API. Never executes functions or modifies a Convex project.
struct ConvexClient: Sendable {
    let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func get(_ path: String, connection: ConvexConnection,
             query: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(string: "https://api.convex.dev")!
        components.path = path
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.setValue("Bearer \(connection.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw ConvexError.invalidResponse }
        guard http.statusCode == 200 else { throw ConvexError.http(http.statusCode) }
        return data
    }

    func validate(_ connection: ConvexConnection) async throws {
        struct Details: Decodable { let teamId: Int?; let type: String }
        let data = try await get("/v1/token_details", connection: connection)
        guard let details = try? JSONDecoder().decode(Details.self, from: data) else {
            throw ConvexError.invalidResponse
        }
        guard details.type == "teamToken", details.teamId == connection.teamID else {
            throw ConvexError.teamMismatch
        }
    }

    func projects(_ connection: ConvexConnection) async throws -> [ConvexProject] {
        struct Page: Decodable {
            struct Pagination: Decodable { let hasMore: Bool; let nextCursor: String? }
            let items: [ConvexProject]
            let pagination: Pagination
        }
        var result: [ConvexProject] = []
        var cursors = Set<String>()
        var cursor: String?
        repeat {
            try Task.checkCancellation()
            var query = [URLQueryItem(name: "limit", value: "100")]
            if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
            let data = try await get("/v1/teams/\(connection.teamID)/projects", connection: connection, query: query)
            guard let page = try? JSONDecoder().decode(Page.self, from: data),
                  page.items.allSatisfy({ $0.teamId == connection.teamID }) else {
                throw ConvexError.invalidResponse
            }
            result.append(contentsOf: page.items)
            if !page.pagination.hasMore { break }
            guard let next = page.pagination.nextCursor, !next.isEmpty,
                  cursors.insert(next).inserted else { throw ConvexError.invalidResponse }
            cursor = next
        } while true
        var seen = Set<Int>()
        return result.filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Undocumented dashboard interface: keep query IDs and positional decoding here.
/// Source: get-convex/convex-backend, dashboard/src/hooks/usageMetrics.ts.
struct ConvexUsageAdapter: Sendable {
    let client: ConvexClient
    static let summaryQueryID = "b63fe48d-320c-401a-8682-0a0b36b50e2b"

    func usage(_ connection: ConvexConnection, projectID: Int) async throws -> ConvexUsage {
        let base = "/api/dashboard/teams/\(connection.teamID)/usage"
        let data = try await client.get(base + "/current_billing_period", connection: connection)
        guard let period = try? JSONDecoder().decode(ConvexBillingPeriod.self, from: data),
              validDate(period.start), validDate(period.end), period.start < period.end else {
            throw ConvexError.invalidResponse
        }
        // The dashboard omits from/to for the current billing period; explicit ranges
        // select historical aggregation behavior. Match that default exactly.
        let summary = try await client.get(base + "/query", connection: connection, query: [
            URLQueryItem(name: "queryId", value: Self.summaryQueryID),
            URLQueryItem(name: "projectId", value: String(projectID)),
        ])
        return try Self.decodeSummary(summary, period: period)
    }

    private func validDate(_ string: String) -> Bool {
        // Dashboard period boundaries are ISO dates; retain their exact server values.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return string.count == 10 && formatter.date(from: string) != nil
    }

    static func decodeSummary(_ data: Data, period: ConvexBillingPeriod, now: Date = Date()) throws -> ConvexUsage {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[Any]] else {
            throw ConvexError.invalidResponse
        }
        // Summary rows are already aggregated over the period, by deployment class/region.
        // Storage and egress are bytes. Sum classes/regions, never daily storage samples.
        func total(column: Int) -> Double? {
            guard !rows.isEmpty else { return nil }
            var result = 0.0
            for row in rows {
                guard row.count > column else { return nil }
                let value: Double?
                if let string = row[column] as? String {
                    value = string.isEmpty ? nil : Double(string)
                } else if let number = row[column] as? NSNumber,
                          CFGetTypeID(number) != CFBooleanGetTypeID() {
                    value = number.doubleValue
                } else { value = nil }
                guard let value, value.isFinite, value >= 0 else { return nil }
                result += value
                guard result.isFinite else { return nil }
            }
            return result
        }
        return ConvexUsage(period: period, functionCalls: total(column: 5),
                           databaseStorage: total(column: 3), fileStorage: total(column: 9),
                           dataEgress: total(column: 11), refreshedAt: now)
    }
}
