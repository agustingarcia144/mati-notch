import Foundation

@main
struct CLIChatTests {
    @MainActor
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mati-notch-cli-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = directory.appendingPathComponent("fake-cli")
        try #"""
        #!/usr/bin/env python3
        import sys, json, time, os
        args = sys.argv[1:]
        if args[:2] == ['auth', 'status']:
            print(json.dumps({'loggedIn': True, 'authMethod': 'claude.ai'})); sys.exit(0)
        if args[:2] == ['login', 'status']:
            print('Logged in using ChatGPT', file=sys.stderr); sys.exit(0)
        prompt = sys.stdin.read()
        assert 'ANTHROPIC_API_KEY' not in os.environ
        assert 'OPENAI_API_KEY' not in os.environ
        if prompt == 'timeout': time.sleep(10)
        if prompt == 'failure':
            print('Login expired; please sign in.', file=sys.stderr); sys.exit(1)
        if prompt == 'incomplete':
            print('{"type":"turn.started"}'); sys.exit(0)
        # Enough stderr to fill an undrained pipe.
        sys.stderr.write('x' * 200000); sys.stderr.flush()
        if '--print' in args:
            assert '--no-session-persistence' in args and '--tools' in args
            for text in ['Hello ', '👋']:
                line = json.dumps({'type': 'stream_event', 'event': {'delta': {'type':'text_delta', 'text':text}}}) + chr(10)
                for byte in line.encode():
                    sys.stdout.buffer.write(bytes([byte])); sys.stdout.buffer.flush()
            print(json.dumps({'type': 'result', 'is_error': False, 'result': 'Hello 👋: ' + prompt}))
        else:
            assert 'read-only' in args and '--ephemeral' in args
            print(json.dumps({'type': 'item.completed', 'item': {'id': 'answer', 'type': 'agent_message', 'text': 'Hello 👋: ' + prompt}}))
            print('{"type":"turn.completed"}')
        """#.write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fake.path)
        var parser = CLIChatParser(provider: .codex)
        _ = try parser.consume(#"{"type":"item.completed","item":{"id":"r","type":"reasoning","text":"private reasoning"}}"#)
        precondition(parser.text.isEmpty)
        _ = try parser.consume(#"{"type":"item.updated","item":{"id":"a","type":"agent_message","text":"Hel"}}"#)
        _ = try parser.consume(#"{"type":"item.completed","item":{"id":"a","type":"agent_message","text":"Hello"}}"#)
        precondition(parser.text == "Hello")
        var claudeParser = CLIChatParser(provider: .claude)
        do {
            _ = try claudeParser.consume(#"{"type":"result","is_error":true,"result":"401 OAuth access token is invalid"}"#)
            fatalError("Expired login accepted")
        } catch { precondition(error.localizedDescription.contains("claude auth login")) }
        precondition(CLIChat.executable(for: .claude, override: "/definitely-missing-cli") == nil)
        let special = "literal `touch /tmp/nope` $(echo nope) ' \" and\nUnicode: café"
        for provider in [CLIChatProvider.claude, .codex] {
            var updates = [String]()
            let result = try await CLIChat.stream(provider: provider, path: fake.path, model: "default", prompt: special) {
                updates.append($0)
            }
            precondition(result == "Hello 👋: " + special)
            precondition(updates.last == result)
            print("\(provider.name): stdin, fragmented JSON/Unicode, streaming, and concurrent stderr passed")
        }
        for provider in [CLIChatProvider.claude, .codex] {
            do { try CLIChat.validateSubscription(provider: provider, status: "Logged in using an API key"); fatalError("API sign-in accepted") }
            catch is CLIChatError {}
        }
        for prompt in ["failure", "incomplete"] {
            do { _ = try await CLIChat.stream(provider: .codex, path: fake.path, model: "default", prompt: prompt) { _ in }; fatalError("Failure accepted") }
            catch is CLIChatError {}
        }
        do {
            _ = try await CLIChat.stream(provider: .codex, path: fake.path, model: "default", prompt: "timeout", timeout: 0.2) { _ in }
            fatalError("Timeout accepted")
        } catch is CLIChatError {}
        let task = Task { try await CLIChat.stream(provider: .claude, path: fake.path, model: "default", prompt: "timeout") { _ in } }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        do { _ = try await task.value; fatalError("Cancellation ignored") } catch is CancellationError {}
        print("API-auth rejection, failed/incomplete replies, timeout, and cancellation passed")
        if CommandLine.arguments.contains("--live") || CommandLine.arguments.contains("--live-codex") {
            for provider in CommandLine.arguments.contains("--live-codex") ? [CLIChatProvider.codex] : [.claude, .codex] {
                let result = try await CLIChat.stream(provider: provider, path: "", model: "default", prompt: "Reply with exactly: mati-notch CLI OK") { _ in }
                precondition(result.contains("mati-notch CLI OK"))
                print("\(provider.name): live subscription chat passed")
            }
        }
    }
}
