import Foundation

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
            try writeNativeMessage([
                "ok": true,
                "bundlePath": result.bundlePath.path,
                "transcriptPath": result.transcriptPath.path,
                "manifest": result.manifest
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
        let bundleURL = outputRoot.appendingPathComponent("\(slug(title))-\(String(id.prefix(8))).tacket", isDirectory: true)
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
        let title = sanitizeTitle(capture["title"] as? String ?? platform)
        let capturedAt = capture["capturedAt"] as? String ?? ISO8601DateFormatter().string(from: Date())
        let messages = (capture["messages"] as? [[String: Any]] ?? []).enumerated().map { index, message in
            normalize(message: message, index: index, source: normalizedSource)
        }
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
            "The following is the full raw transcript of an AI chat thread being transferred into this coding session.",
            "Continue from it. Do not treat this as a summary.",
            "",
            "[raw transcript begins]",
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

        lines.append("[raw transcript ends]")
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

func readNativeMessage() throws -> [String: Any] {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard input.count >= 4 else { throw NativeHostError.emptyInput }
    let length = input.prefix(4).withUnsafeBytes { pointer in
        pointer.load(as: UInt32.self).littleEndian
    }
    let expectedLength = 4 + Int(length)
    guard input.count >= expectedLength else { throw NativeHostError.truncatedInput }
    guard input.count == expectedLength else { throw NativeHostError.trailingInput }
    let body = input.dropFirst(4).prefix(Int(length))
    let json = try JSONSerialization.jsonObject(with: body)
    guard let dictionary = json as? [String: Any] else { throw NativeHostError.invalidInput }
    return dictionary
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
