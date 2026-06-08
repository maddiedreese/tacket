import Foundation
import Darwin
import CryptoKit
import SQLite3

struct NativeResponse: Encodable {
    let ok: Bool
    let bundlePath: String?
    let transcriptPath: String?
    let manifest: [String: AnyEncodable]?
    let error: String?
}

@main
struct TacketNativeHost {
    static func main() {
        do {
            let request = try readNativeMessage()
            guard let type = request["type"] as? String, type == "saveCapture" else {
                try writeNativeMessage(["ok": false, "error": "Unsupported native host message."])
                return
            }
            guard let capture = request["capture"] as? [String: Any] else {
                try writeNativeMessage(["ok": false, "error": "Missing capture payload."])
                return
            }

            let writer = BundleWriter()
            let result = try writer.write(capture: capture)
            let indexed = try LibraryIndexer.indexBundle(result.bundlePath)
            try writeNativeMessage([
                "ok": true,
                "bundlePath": result.bundlePath.path,
                "transcriptPath": result.transcriptPath.path,
                "manifest": result.manifest,
                "indexed": indexed
            ])
        } catch {
            try? writeNativeMessage(["ok": false, "error": error.localizedDescription])
        }
    }
}

struct BundleWriteResult {
    let bundlePath: URL
    let transcriptPath: URL
    let manifest: [String: Any]
}

struct BundleWriter {
    let schemaVersion = "0.1.0"
    let outputRoot: URL

    init() {
        if let override = ProcessInfo.processInfo.environment["TACKET_CAPTURE_DIR"], !override.isEmpty {
            outputRoot = URL(fileURLWithPath: NSString(string: override).expandingTildeInPath, isDirectory: true)
        } else {
            outputRoot = BundleWriter.configuredCaptureDirectory() ?? BundleWriter.defaultCaptureDirectory()
        }
    }

    func write(capture rawCapture: [String: Any]) throws -> BundleWriteResult {
        try validate(capture: rawCapture)
        let normalized = normalize(capture: rawCapture)
        let title = normalized.title
        let id = normalized.id
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
        let bundleURL = try reserveBundleURL(
            title: title,
            platform: normalized.source["platform"] as? String,
            capturedAt: normalized.capturedAt
        )
        let attachmentsURL = bundleURL.appendingPathComponent("attachments", isDirectory: true)
        let targetsURL = bundleURL.appendingPathComponent("targets", isDirectory: true)

        try FileManager.default.createDirectory(at: attachmentsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetsURL, withIntermediateDirectories: true)

        let messages = try persistAttachments(in: normalized.messages, attachmentsURL: attachmentsURL, bundleURL: bundleURL)
        let manifest = manifest(
            id: id,
            title: title,
            source: normalized.source,
            capturedAt: normalized.capturedAt,
            messages: messages
        )
        let transcript = renderTranscript(
            title: title,
            source: normalized.source,
            capturedAt: normalized.capturedAt,
            messages: messages
        )

        try jsonData(manifest, pretty: true).write(to: bundleURL.appendingPathComponent("manifest.json"))
        try readme(title: title, source: normalized.source, capturedAt: normalized.capturedAt)
            .write(to: bundleURL.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try messages
            .map { String(data: try jsonData($0, pretty: false), encoding: .utf8) ?? "{}" }
            .joined(separator: "\n")
            .appending("\n")
            .write(to: bundleURL.appendingPathComponent("messages.jsonl"), atomically: true, encoding: .utf8)
        try transcript.write(to: bundleURL.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)
        try transcript.write(to: targetsURL.appendingPathComponent("codex.md"), atomically: true, encoding: .utf8)
        try transcript.write(to: targetsURL.appendingPathComponent("claude-code.md"), atomically: true, encoding: .utf8)

        return BundleWriteResult(
            bundlePath: bundleURL,
            transcriptPath: bundleURL.appendingPathComponent("transcript.md"),
            manifest: manifest
        )
    }

    private func validate(capture: [String: Any]) throws {
        guard let messages = capture["messages"] as? [[String: Any]] else {
            throw NativeHostError.invalidCapture("Capture payload must include a messages array.")
        }
        guard !messages.isEmpty else {
            throw NativeHostError.invalidCapture("Capture payload must include at least one message.")
        }
    }

    private func normalize(capture: [String: Any]) -> (id: String, title: String, source: [String: Any], capturedAt: String, messages: [[String: Any]]) {
        let source = capture["source"] as? [String: Any] ?? [:]
        let url = source["url"] as? String ?? ""
        let platform = source["platform"] as? String ?? detectPlatform(url: url)
        let normalizedSource: [String: Any] = ["platform": platform, "url": url]
        let capturedAt = capture["capturedAt"] as? String ?? ISO8601DateFormatter().string(from: Date())
        let messages = (capture["messages"] as? [[String: Any]] ?? []).enumerated().map { index, message in
            normalize(message: message, index: index, source: normalizedSource)
        }
        let title = captureTitle(capture["title"] as? String, messages: messages, fallback: platform)
        let id = capture["id"] as? String ?? UUID().uuidString.lowercased()
        return (id, title, normalizedSource, capturedAt, messages)
    }

    private func normalize(message: [String: Any], index: Int, source: [String: Any]) -> [String: Any] {
        let role = message["role"] as? String ?? "unknown"
        let content = message["content"] as? [[String: Any]] ?? []
        var normalized: [String: Any] = [
            "id": message["id"] as? String ?? "\(index + 1)",
            "role": ["user", "assistant", "system", "tool"].contains(role) ? role : "unknown",
            "content": content.compactMap(normalize(part:)),
            "source": message["source"] as? [String: Any] ?? source
        ]
        if let author = message["author"] as? String { normalized["author"] = author }
        if let createdAt = message["createdAt"] as? String { normalized["createdAt"] = createdAt }
        return normalized
    }

    private func normalize(part: [String: Any]) -> [String: Any]? {
        let type = part["type"] as? String ?? "text"
        if type == "code" {
            var code: [String: Any] = [
                "type": "code",
                "text": part["text"] as? String ?? ""
            ]
            if let language = part["language"] as? String { code["language"] = language }
            return code
        }
        if type == "attachment" {
            let status = part["status"] as? String ?? "referenced"
            var attachment: [String: Any] = [
                "type": "attachment",
                "status": ["captured", "referenced", "unavailable"].contains(status) ? status : "referenced"
            ]
            for key in ["name", "mimeType", "url", "path", "dataUrl", "alt"] {
                if let value = part[key] as? String { attachment[key] = value }
            }
            return attachment
        }
        let text = part["text"] as? String ?? ""
        return text.isEmpty ? nil : ["type": "text", "text": text]
    }

    private func persistAttachments(in messages: [[String: Any]], attachmentsURL: URL, bundleURL: URL) throws -> [[String: Any]] {
        var index = 0
        return try messages.map { message in
            var mutable = message
            let content = message["content"] as? [[String: Any]] ?? []
            mutable["content"] = try content.map { part in
                guard (part["type"] as? String) == "attachment",
                      (part["status"] as? String) == "captured" else {
                    return part
                }

                if let dataUrl = part["dataUrl"] as? String, let data = dataFrom(dataURL: dataUrl) {
                    index += 1
                    let name = "\(String(format: "%03d", index))-\(slug(part["name"] as? String ?? "attachment"))\(fileExtension(for: part))"
                    let destination = attachmentsURL.appendingPathComponent(name)
                    try data.write(to: destination)
                    var saved = part
                    saved["path"] = destination.path.replacingOccurrences(of: bundleURL.path + "/", with: "")
                    saved.removeValue(forKey: "dataUrl")
                    return saved
                }

                var referenced = part
                referenced["status"] = "referenced"
                referenced.removeValue(forKey: "dataUrl")
                return referenced
            }
            return mutable
        }
    }

    private func manifest(id: String, title: String, source: [String: Any], capturedAt: String, messages: [[String: Any]]) -> [String: Any] {
        var counts = ["captured": 0, "referenced": 0, "unavailable": 0]
        for message in messages {
            for part in message["content"] as? [[String: Any]] ?? [] where (part["type"] as? String) == "attachment" {
                let status = part["status"] as? String ?? "referenced"
                counts[status, default: 0] += 1
            }
        }
        return [
            "schemaVersion": schemaVersion,
            "id": id,
            "title": title,
            "source": source,
            "capturedAt": capturedAt,
            "messageCount": messages.count,
            "attachments": counts,
            "warnings": warnings(from: messages)
        ]
    }

    private func renderTranscript(title: String, source: [String: Any], capturedAt: String, messages: [[String: Any]]) -> String {
        var lines: [String] = [
            "The following is the full saved AI chat conversation being transferred into this coding session.",
            "Continue from it. Do not treat this as a summary.",
            "",
            "[conversation begins]",
            "",
            "# \(title)",
            "",
            "Source: \(source["platform"] as? String ?? "unknown")",
            "URL: \(source["url"] as? String ?? "")",
            "Captured: \(capturedAt)",
            ""
        ]

        for message in messages {
            lines.append("## \(roleTitle(message["role"] as? String ?? "unknown"))")
            lines.append("")
            for part in message["content"] as? [[String: Any]] ?? [] {
                switch part["type"] as? String {
                case "code":
                    let language = part["language"] as? String ?? ""
                    lines.append("```\(language)")
                    lines.append(part["text"] as? String ?? "")
                    lines.append("```")
                    lines.append("")
                case "attachment":
                    let status = part["status"] as? String ?? "referenced"
                    let label = part["name"] as? String ?? part["alt"] as? String ?? "attachment"
                    let target = part["path"] as? String ?? part["url"] as? String ?? "unavailable"
                    lines.append("[attachment:\(status)] \(label) -> \(target)")
                    lines.append("")
                default:
                    lines.append(part["text"] as? String ?? "")
                    lines.append("")
                }
            }
        }

        lines.append("[conversation ends]")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func detectPlatform(url: String) -> String {
        guard let host = URL(string: url)?.host else { return "unknown" }
        if host == "chatgpt.com" || host == "chat.openai.com" { return "chatgpt" }
        if host == "claude.ai" { return "claude" }
        if host == "gemini.google.com" { return "gemini" }
        return "unknown"
    }

    private func roleTitle(_ role: String) -> String {
        if role == "user" { return "User" }
        if role == "assistant" { return "Assistant" }
        return role
    }

    private func sanitizeTitle(_ value: String) -> String {
        let collapsed = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? "Untitled Thread" : String(collapsed.prefix(160))
    }

    private func captureTitle(_ value: String?, messages: [[String: Any]], fallback: String) -> String {
        let title = sanitizeTitle(value ?? fallback)
        if !isGenericTitle(title) { return title }
        return titleFromMessages(messages) ?? title
    }

    private func isGenericTitle(_ title: String) -> Bool {
        let generic = [
            "chatgpt",
            "claude",
            "gemini",
            "new chat",
            "temporary chat",
            "conversation with gemini",
            "untitled thread"
        ]
        return generic.contains(title.lowercased())
    }

    private func titleFromMessages(_ messages: [[String: Any]]) -> String? {
        guard let userMessage = messages.first(where: { ($0["role"] as? String) == "user" }),
              let content = userMessage["content"] as? [[String: Any]],
              let part = content.first(where: { ($0["type"] as? String) == "text" }),
              let text = part["text"] as? String else {
            return nil
        }
        let collapsed = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let pattern = "\\b(please|reply|respond|include|do not)\\b"
        let firstRange = collapsed.range(of: pattern, options: [.regularExpression, .caseInsensitive])
        let prefix = firstRange.map { String(collapsed[..<$0.lowerBound]) } ?? collapsed
        let trimmed = prefix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".:;,!?-"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.isEmpty ? collapsed.trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
        let title = sanitizeTitle(candidate)
        return title.isEmpty ? nil : String(title.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func reserveBundleURL(title: String, platform: String?, capturedAt: String) throws -> URL {
        let baseName = [
            fileDate(capturedAt),
            platformLabel(platform),
            fileSegment(title, maxLength: 80)
        ].joined(separator: " - ")

        for index in 1..<1000 {
            let suffix = index == 1 ? "" : " (\(index))"
            let candidate = outputRoot.appendingPathComponent("\(baseName)\(suffix).tacket", isDirectory: true)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: false)
                return candidate
            }
        }

        throw NativeHostError.invalidCapture("Could not create a unique .tacket bundle folder.")
    }

    private func fileDate(_ value: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        let date = formatter.date(from: value) ?? fallbackFormatter.date(from: value) ?? Date()
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "%04d-%02d-%02d %02d.%02d",
            components.year ?? 0,
            components.month ?? 1,
            components.day ?? 1,
            components.hour ?? 0,
            components.minute ?? 0
        )
    }

    private func platformLabel(_ platform: String?) -> String {
        if platform == "chatgpt" { return "ChatGPT" }
        if platform == "claude" { return "Claude" }
        if platform == "gemini" { return "Gemini" }
        return "AI Chat"
    }

    private func fileSegment(_ value: String, maxLength: Int) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
        let invalid = CharacterSet(charactersIn: #"<>:"/\|?*"#)
            .union(.controlCharacters)
        let pieces = folded
            .components(separatedBy: invalid)
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return pieces.isEmpty ? "Untitled Thread" : String(pieces.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func readme(title: String, source: [String: Any], capturedAt: String) -> String {
        """
        # \(title)

        This is a local Tacket saved chat.

        - Open `transcript.md` to read the full saved conversation.
        - `attachments/` contains any files Tacket was able to save locally.
        - `targets/` contains ready-to-transfer conversation files for supported tools.
        - `manifest.json` and `messages.jsonl` are used by Tacket to verify and search the saved chat.

        Source: \(platformLabel(source["platform"] as? String))
        Captured: \(capturedAt)
        """
    }

    private func slug(_ value: String) -> String {
        let lower = value.lowercased()
        let replaced = lower.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        let trimmed = replaced.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "thread" : String(trimmed.prefix(72))
    }

    private func dataFrom(dataURL: String) -> Data? {
        guard let comma = dataURL.firstIndex(of: ",") else { return nil }
        let metadata = dataURL[..<comma]
        let payload = String(dataURL[dataURL.index(after: comma)...])
        if metadata.contains(";base64") {
            return Data(base64Encoded: payload)
        }
        return payload.removingPercentEncoding?.data(using: .utf8)
    }

    private func fileExtension(for part: [String: Any]) -> String {
        if let name = part["name"] as? String {
            let ext = URL(fileURLWithPath: name).pathExtension
            if !ext.isEmpty { return ".\(ext)" }
        }
        switch part["mimeType"] as? String {
        case "image/png": return ".png"
        case "image/jpeg": return ".jpg"
        case "image/gif": return ".gif"
        case "image/webp": return ".webp"
        case "application/pdf": return ".pdf"
        default: return ".bin"
        }
    }

    private func jsonData(_ value: Any, pretty: Bool) throws -> Data {
        let options: JSONSerialization.WritingOptions = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try JSONSerialization.data(withJSONObject: value, options: options)
    }

    private static func defaultCaptureDirectory() -> URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Tacket Captures", isDirectory: true)
    }

    private static func configuredCaptureDirectory() -> URL? {
        let configURL: URL
        if let override = ProcessInfo.processInfo.environment["TACKET_CONFIG_FILE"], !override.isEmpty {
            configURL = URL(fileURLWithPath: NSString(string: override).expandingTildeInPath)
        } else {
            configURL = FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Tacket/config.json")
        }
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = json["captureDirectory"] as? String,
              !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
    }

    private func warnings(from messages: [[String: Any]]) -> [[String: Any]] {
        let patterns: [(String, String)] = [
            ("openai_api_key", #"sk-(?!ant-)[A-Za-z0-9_-]{20,}"#),
            ("anthropic_api_key", #"sk-ant-[A-Za-z0-9_-]{20,}"#),
            ("aws_access_key_id", #"AKIA[0-9A-Z]{16}"#),
            ("github_token", #"gh[pousr]_[A-Za-z0-9_]{20,}"#),
            ("slack_token", #"xox[baprs]-[A-Za-z0-9-]{20,}"#),
            ("private_key", #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#)
        ]
        var findings: [String: (count: Int, messageIds: [String])] = [:]

        for message in messages {
            let messageId = message["id"] as? String ?? "unknown"
            let text = (message["content"] as? [[String: Any]] ?? [])
                .filter { part in
                    let type = part["type"] as? String
                    return type == "text" || type == "code"
                }
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")

            for (kind, pattern) in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                let matches = regex.numberOfMatches(in: text, range: range)
                guard matches > 0 else { continue }

                var finding = findings[kind] ?? (0, [])
                finding.count += matches
                if !finding.messageIds.contains(messageId) {
                    finding.messageIds.append(messageId)
                }
                findings[kind] = finding
            }
        }

        return findings.keys.sorted().map { kind in
            let finding = findings[kind] ?? (0, [])
            return [
                "type": "possible_secret",
                "kind": kind,
                "count": finding.count,
                "messageIds": finding.messageIds
            ]
        }
    }
}

struct LibraryMessage {
    let id: String
    let role: String
    let text: String
    let ordinal: Int
}

enum LibraryIndexer {
    static var appSupportDirectoryURL: URL {
        homeDirectoryURL
            .appendingPathComponent("Library/Application Support/Tacket", isDirectory: true)
    }

    static var libraryDatabaseURL: URL {
        appSupportDirectoryURL.appendingPathComponent("library.sqlite")
    }

    private static var homeDirectoryURL: URL {
        if let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty {
            return URL(fileURLWithPath: NSString(string: home).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static func indexBundle(_ bundleURL: URL) throws -> Bool {
        let manifestURL = bundleURL.appendingPathComponent("manifest.json")
        let messagesURL = bundleURL.appendingPathComponent("messages.jsonl")
        let transcriptURL = bundleURL.appendingPathComponent("transcript.md")
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any] ?? [:]
        let source = manifest["source"] as? [String: Any] ?? [:]
        let transcript = try String(contentsOf: transcriptURL, encoding: .utf8)
        let transcriptHash = sha256(transcript)
        let bundleId = manifest["id"] as? String ?? stableLibraryId(bundleURL.path)

        try ensureDatabase()
        if let existing = try queryLibraryHash(path: bundleURL.path), existing == transcriptHash {
            return false
        }

        let messagesText = try String(contentsOf: messagesURL, encoding: .utf8)
        let messages = messagesText
            .split(separator: "\n")
            .enumerated()
            .compactMap { index, line -> LibraryMessage? in
                guard let data = String(line).data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return nil
                }
                return LibraryMessage(
                    id: "\(bundleId):\(json["id"] as? String ?? String(index + 1))",
                    role: json["role"] as? String ?? "unknown",
                    text: messageText(from: json),
                    ordinal: index
                )
            }

        let title = manifest["title"] as? String ?? bundleURL.deletingPathExtension().lastPathComponent
        let platform = source["platform"] as? String ?? "unknown"
        let url = source["url"] as? String ?? ""
        let capturedAt = manifest["capturedAt"] as? String ?? ""
        let messageCount = manifest["messageCount"] as? Int ?? messages.count
        let indexedAt = ISO8601DateFormatter().string(from: Date())

        try withDatabase { db in
            try sqliteExec(db, "BEGIN;")
            try sqliteExec(db, "DELETE FROM messages_fts WHERE bundle_id = \(sqliteQuote(bundleId));")
            try sqliteExec(db, "DELETE FROM messages WHERE bundle_id = \(sqliteQuote(bundleId));")
            try sqliteExec(db, "DELETE FROM bundles WHERE path = \(sqliteQuote(bundleURL.path)) OR id = \(sqliteQuote(bundleId));")
            try sqliteExec(db, """
                INSERT INTO bundles (id, path, title, platform, url, captured_at, message_count, indexed_at, transcript_hash)
                VALUES (
                  \(sqliteQuote(bundleId)),
                  \(sqliteQuote(bundleURL.path)),
                  \(sqliteQuote(title)),
                  \(sqliteQuote(platform)),
                  \(sqliteQuote(url)),
                  \(sqliteQuote(capturedAt)),
                  \(messageCount),
                  \(sqliteQuote(indexedAt)),
                  \(sqliteQuote(transcriptHash))
                );
                """)
            for message in messages {
                try sqliteExec(db, """
                    INSERT INTO messages (id, bundle_id, role, text, ordinal)
                    VALUES (
                      \(sqliteQuote(message.id)),
                      \(sqliteQuote(bundleId)),
                      \(sqliteQuote(message.role)),
                      \(sqliteQuote(message.text)),
                      \(message.ordinal)
                    );
                    INSERT INTO messages_fts (bundle_id, message_id, title, platform, role, text)
                    VALUES (
                      \(sqliteQuote(bundleId)),
                      \(sqliteQuote(message.id)),
                      \(sqliteQuote(title)),
                      \(sqliteQuote(platform)),
                      \(sqliteQuote(message.role)),
                      \(sqliteQuote(message.text))
                    );
                    """)
            }
            try sqliteExec(db, "COMMIT;")
        }
        return true
    }

    private static func ensureDatabase() throws {
        try FileManager.default.createDirectory(at: appSupportDirectoryURL, withIntermediateDirectories: true)
        try withDatabase { db in
            try sqliteExec(db, """
                PRAGMA journal_mode = WAL;
                CREATE TABLE IF NOT EXISTS bundles (
                  id TEXT PRIMARY KEY,
                  path TEXT NOT NULL UNIQUE,
                  title TEXT,
                  platform TEXT,
                  url TEXT,
                  captured_at TEXT,
                  message_count INTEGER,
                  indexed_at TEXT,
                  transcript_hash TEXT
                );
                CREATE TABLE IF NOT EXISTS messages (
                  id TEXT PRIMARY KEY,
                  bundle_id TEXT NOT NULL,
                  role TEXT,
                  text TEXT,
                  ordinal INTEGER,
                  FOREIGN KEY(bundle_id) REFERENCES bundles(id) ON DELETE CASCADE
                );
                """)
            if supportsFTS5(db) {
                try sqliteExec(db, """
                    CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
                      bundle_id UNINDEXED,
                      message_id UNINDEXED,
                      title,
                      platform,
                      role,
                      text
                    );
                    """)
            } else {
                try sqliteExec(db, """
                    CREATE TABLE IF NOT EXISTS messages_fts (
                      bundle_id TEXT,
                      message_id TEXT,
                      title TEXT,
                      platform TEXT,
                      role TEXT,
                      text TEXT
                    );
                    CREATE INDEX IF NOT EXISTS messages_fts_bundle_id ON messages_fts(bundle_id);
                    """)
            }
        }
    }

    private static func queryLibraryHash(path: String) throws -> String? {
        try withDatabase { db in
            let sql = "SELECT transcript_hash FROM bundles WHERE path = \(sqliteQuote(path)) LIMIT 1;"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw NativeHostError.invalidCapture(sqliteError(db))
            }
            defer { sqlite3_finalize(statement) }
            if sqlite3_step(statement) == SQLITE_ROW {
                return sqliteColumnText(statement, 0)
            }
            return nil
        }
    }

    private static func withDatabase<T>(_ body: (OpaquePointer?) throws -> T) throws -> T {
        var db: OpaquePointer?
        guard sqlite3_open(libraryDatabaseURL.path, &db) == SQLITE_OK else {
            defer { sqlite3_close(db) }
            throw NativeHostError.invalidCapture(sqliteError(db))
        }
        defer { sqlite3_close(db) }
        return try body(db)
    }

    private static func sqliteExec(_ db: OpaquePointer?, _ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? sqliteError(db)
            sqlite3_free(error)
            throw NativeHostError.invalidCapture(message)
        }
    }

    private static func messageText(from json: [String: Any]) -> String {
        let parts = json["content"] as? [[String: Any]] ?? []
        return parts
            .filter { ($0["type"] as? String) == "text" || ($0["type"] as? String) == "code" }
            .map { $0["text"] as? String ?? "" }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func stableLibraryId(_ value: String) -> String {
        String(sha256(value).prefix(16))
    }

    private static func sqliteQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private static func supportsFTS5(_ db: OpaquePointer?) -> Bool {
        do {
            try sqliteExec(db, "CREATE VIRTUAL TABLE temp.tacket_fts_probe USING fts5(value);")
            try sqliteExec(db, "DROP TABLE temp.tacket_fts_probe;")
            return true
        } catch {
            return false
        }
    }

    private static func sqliteColumnText(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let text = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: text)
    }

    private static func sqliteError(_ db: OpaquePointer?) -> String {
        guard let message = sqlite3_errmsg(db) else { return "Unknown SQLite error." }
        return String(cString: message)
    }
}

func readNativeMessage() throws -> [String: Any] {
    let header = try readExactly(byteCount: 4, emptyError: .emptyInput)
    let bytes = [UInt8](header)
    let length = UInt32(bytes[0])
        | (UInt32(bytes[1]) << 8)
        | (UInt32(bytes[2]) << 16)
        | (UInt32(bytes[3]) << 24)
    let body = try readExactly(byteCount: Int(length), emptyError: .truncatedInput)
    try rejectBufferedTrailingInput()
    let json = try JSONSerialization.jsonObject(with: body)
    guard let dictionary = json as? [String: Any] else { throw NativeHostError.invalidInput }
    return dictionary
}

func readExactly(byteCount: Int, emptyError: NativeHostError) throws -> Data {
    var data = Data()
    data.reserveCapacity(byteCount)
    var buffer = [UInt8](repeating: 0, count: min(max(byteCount, 1), 8192))

    while data.count < byteCount {
        let remaining = byteCount - data.count
        let count = Darwin.read(STDIN_FILENO, &buffer, min(buffer.count, remaining))
        if count > 0 {
            data.append(contentsOf: buffer.prefix(count))
            continue
        }
        if count == 0 {
            throw data.isEmpty ? emptyError : NativeHostError.truncatedInput
        }
        if errno == EINTR {
            continue
        }
        throw NativeHostError.invalidInput
    }

    return data
}

func rejectBufferedTrailingInput() throws {
    let flags = fcntl(STDIN_FILENO, F_GETFL, 0)
    guard flags >= 0 else { return }
    _ = fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK)
    defer { _ = fcntl(STDIN_FILENO, F_SETFL, flags) }

    var byte: UInt8 = 0
    while true {
        let count = Darwin.read(STDIN_FILENO, &byte, 1)
        if count > 0 {
            throw NativeHostError.trailingInput
        }
        if count == 0 {
            return
        }
        if errno == EINTR {
            continue
        }
        if errno == EAGAIN || errno == EWOULDBLOCK {
            return
        }
        throw NativeHostError.invalidInput
    }
}

func writeNativeMessage(_ message: [String: Any]) throws {
    let body = try JSONSerialization.data(withJSONObject: message)
    var length = UInt32(body.count).littleEndian
    var output = Data(bytes: &length, count: 4)
    output.append(body)
    FileHandle.standardOutput.write(output)
}

enum NativeHostError: LocalizedError {
    case emptyInput
    case truncatedInput
    case trailingInput
    case invalidInput
    case invalidCapture(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput: "No native message received."
        case .truncatedInput: "Native message body was shorter than declared length."
        case .trailingInput: "Native host expected exactly one native message."
        case .invalidInput: "Native message was not a JSON object."
        case .invalidCapture(let message): message
        }
    }
}

struct AnyEncodable: Encodable {}
