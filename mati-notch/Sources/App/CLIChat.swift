import Foundation
import Darwin

enum CLIChatProvider: String, Sendable {
    case claude, codex

    var name: String { self == .claude ? "Claude Code" : "Codex" }
    var loginCommand: String { self == .claude ? "claude auth login" : "codex login" }
}

enum CLIChatError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// CLI credentials stay with the CLI. Prompts travel through stdin, never a shell command.
enum CLIChat {
    static func executable(for provider: CLIChatProvider, override: String = "") -> URL? {
        let custom = override.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            let path = (custom as NSString).expandingTildeInPath
            return path.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: path)
                ? URL(fileURLWithPath: path) : nil
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":")
        for directory in paths where directory.hasPrefix("/") {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(provider.rawValue)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // These providers explicitly use subscription sign-in, never inherited API credentials.
        for key in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "OPENAI_API_KEY", "CODEX_API_KEY",
                    "OPENAI_BASE_URL", "ANTHROPIC_BASE_URL", "CLAUDECODE", "CODEX_THREAD_ID"] {
            env.removeValue(forKey: key)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        return env
    }

    static func validateSubscription(provider: CLIChatProvider, status: String) throws {
        if provider == .claude,
           let data = status.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["loggedIn"] as? Bool == true,
           json["authMethod"] as? String == "claude.ai" { return }
        if provider == .codex, status.contains("Logged in using ChatGPT") { return }
        throw CLIChatError.message("Sign into \(provider.name) with your subscription first: \(provider.loginCommand). API-key sign-in is available through the separate API providers.")
    }

    static func arguments(for provider: CLIChatProvider, model: String) -> [String] {
        var args: [String]
        switch provider {
        case .claude:
            args = ["--print", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
                    "--no-session-persistence", "--tools", "", "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}",
                    "--settings", "{\"disableAllHooks\":true}", "--permission-mode", "dontAsk"]
        case .codex:
            args = ["exec", "--json", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only",
                    "--ignore-user-config", "--disable", "shell_tool", "--disable", "hooks",
                    "-c", "approval_policy=\"never\"", "-c", "model_provider=\"openai\""]
        }
        if !model.isEmpty && model != "default" { args += ["--model", model] }
        if provider == .codex { args.append("-") }
        return args
    }

    @MainActor
    static func stream(provider: CLIChatProvider, path: String, model: String, prompt: String,
                       timeout: TimeInterval = 180,
                       onText: @escaping @MainActor @Sendable (String) -> Void) async throws -> String {
        #if APPSTORE
        throw CLIChatError.message("CLI chat is available in the direct-download build of mati-notch.")
        #else
        guard prompt.utf8.count <= 512_000 else { throw CLIChatError.message("This conversation is too large for CLI chat. Start a shorter conversation.") }
        guard let exe = executable(for: provider, override: path) else {
            throw CLIChatError.message("\(provider.name) CLI not found. Install it or set its executable path in Settings → Chat, then run \(provider.loginCommand).")
        }
        let authArgs = provider == .claude ? ["auth", "status", "--json"] : ["login", "status"]
        let auth = try await run(executable: exe, arguments: authArgs, input: "", timeout: 15)
        try validateSubscription(provider: provider, status: auth)
        var parser = CLIChatParser(provider: provider)
        _ = try await run(executable: exe, arguments: arguments(for: provider, model: model),
                          input: prompt, timeout: timeout) { line in
            if let text = try parser.consume(line) { onText(text) }
        }
        let reply = parser.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard parser.completed, !reply.isEmpty else {
            throw CLIChatError.message("\(provider.name) returned no completed reply. Check the CLI login and try again.")
        }
        return reply
        #endif
    }

    /// Drains both pipes concurrently; process launch, reading and waiting never block the UI.
    static func run(executable: URL, arguments: [String], input: String, timeout: TimeInterval,
                    onLine: (@MainActor @Sendable (String) async throws -> Void)? = nil) async throws -> String {
        let control = CLIProcessControl()
        let events = AsyncThrowingStream<String, Error> { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mati-notch-chat-\(UUID())")
                defer { try? FileManager.default.removeItem(at: directory) }
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    process.executableURL = executable
                    process.arguments = arguments
                    process.environment = environment()
                    process.currentDirectoryURL = directory
                    _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
                    process.standardInput = stdin
                    process.standardOutput = stdout
                    process.standardError = stderr
                    try control.start(process)
                    let deadline = DispatchWorkItem { control.stop(timedOut: true) }
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
                    defer { deadline.cancel() }
                    let errors = CLIBuffer()
                    let group = DispatchGroup()
                    group.enter()
                    DispatchQueue.global().async {
                        defer { group.leave() }
                        while let chunk = try? stderr.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty {
                            errors.append(chunk)
                        }
                    }
                    // A large prompt can fill stdin while the CLI emits startup output.
                    group.enter()
                    DispatchQueue.global().async {
                        defer { try? stdin.fileHandleForWriting.close(); group.leave() }
                        try? stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8))
                    }
                    var pending = Data()
                    var total = 0
                    while let chunk = try stdout.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty {
                        total += chunk.count
                        guard total <= 8_000_000 else { throw CLIChatError.message("CLI output exceeded the chat limit.") }
                        pending.append(chunk)
                        while let newline = pending.firstIndex(of: 10) {
                            continuation.yield(String(decoding: pending[..<newline], as: UTF8.self))
                            pending.removeSubrange(...newline)
                        }
                    }
                    if !pending.isEmpty { continuation.yield(String(decoding: pending, as: UTF8.self)) }
                    process.waitUntilExit()
                    group.wait()
                    if control.timedOut { throw CLIChatError.message("CLI request timed out. Try again.") }
                    if control.cancelled { throw CancellationError() }
                    let diagnostic = errors.text
                    guard process.terminationStatus == 0 else {
                        throw CLIChatError.message(diagnostic.isEmpty ? "CLI exited with status \(process.terminationStatus). Check your CLI login." : String(diagnostic.suffix(2000)))
                    }
                    // Codex login status is printed to stderr.
                    if onLine == nil && !diagnostic.isEmpty { continuation.yield(diagnostic) }
                    continuation.finish()
                } catch {
                    control.stop()
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in control.stop() }
        }
        return try await withTaskCancellationHandler {
            var output = ""
            for try await line in events {
                try Task.checkCancellation()
                if let onLine { try await onLine(line) }
                else { output += line + "\n" }
            }
            try Task.checkCancellation()
            return output
        } onCancel: { control.stop() }
    }
}

struct CLIChatParser {
    let provider: CLIChatProvider
    private(set) var text = ""
    private(set) var completed = false
    private var messages: [String: String] = [:]
    private var order: [String] = []

    init(provider: CLIChatProvider) { self.provider = provider }

    mutating func consume(_ line: String) throws -> String? {
        guard let data = line.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return nil }
        if provider == .claude {
            if type == "stream_event", let stream = event["event"] as? [String: Any],
               let delta = stream["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
               let fragment = delta["text"] as? String { text += fragment; return text }
            if type == "result" {
                if event["is_error"] as? Bool == true {
                    let errors = event["errors"] as? [String] ?? []
                    let message = event["result"] as? String ?? errors.joined(separator: "\n")
                    if message.lowercased().contains("oauth") || message.contains("401") {
                        throw CLIChatError.message("Claude Code sign-in expired. Run claude auth login in Terminal, then retry.")
                    }
                    throw CLIChatError.message(message.isEmpty ? "Claude Code request failed." : message)
                }
                if let result = event["result"] as? String { text = result }
                completed = true
                return text
            }
        } else {
            if type == "error" || type == "turn.failed" {
                let error = event["error"] as? [String: Any]
                throw CLIChatError.message(error?["message"] as? String ?? event["message"] as? String ?? "Codex request failed.")
            }
            if type == "turn.completed" { completed = true }
            if ["item.updated", "item.completed"].contains(type),
               let item = event["item"] as? [String: Any], item["type"] as? String == "agent_message",
               let message = item["text"] as? String, let id = item["id"] as? String {
                if messages[id] == nil { order.append(id) }
                messages[id] = message
                text = order.compactMap { messages[$0] }.joined(separator: "\n\n")
                return text
            }
        }
        return nil
    }
}

private final class CLIBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ chunk: Data) { lock.withLock { data.append(chunk); if data.count > 8192 { data = data.suffix(8192) } } }
    var text: String { lock.withLock { String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) } }
}

private final class CLIProcessControl: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stopped = false
    private var timeout = false
    var cancelled: Bool { lock.withLock { stopped } }
    var timedOut: Bool { lock.withLock { timeout } }
    func start(_ process: Process) throws {
        try lock.withLock {
            guard !stopped else { throw CancellationError() }
            self.process = process
            try process.run()
        }
    }
    func stop(timedOut: Bool = false) {
        lock.withLock {
            timeout = timeout || timedOut
            stopped = true
            guard let process, process.isRunning else { return }
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
    }
}
