import SwiftUI
import AppKit
import CryptoKit
import SQLite3

@main
struct TacketApp: App {
    @StateObject private var model = TacketModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 840, minHeight: 620)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1040, height: 760)
    }
}

@MainActor
final class TacketModel: ObservableObject {
    enum TransferTarget: String, CaseIterable, Identifiable {
        case clipboard = "clipboard"
        case codex = "codex"
        case claudeCode = "claude-code"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .clipboard: "Clipboard"
            case .codex: "Codex"
            case .claudeCode: "Claude Code"
            }
        }
    }

    @Published var captureDirectory: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/Tacket Captures", isDirectory: true)
    @Published var selectedBundle: URL?
    @Published var selectedTarget: TransferTarget = .clipboard
    @Published var extensionId = ""
    @Published var status = "Ready."
    @Published var commandOutput = ""
    @Published var isRunning = false
    @Published var installedHostPath: String?
    @Published var connectorStatus = "Connector status unknown."
    @Published var maxChunkCharacters = "24000"
    @Published var selectedBundleInfo: BundleInfo?
    @Published var librarySearchText = ""
    @Published var libraryItems: [LibraryItem] = []
    @Published var selectedLibraryItem: LibraryItem?
    @Published var libraryStatus = "Index your capture folder to search saved raw transcripts."

    let supportedSources = ["ChatGPT", "Claude", "Gemini"]

    init() {
        captureDirectory = Self.readConfiguredCaptureDirectory() ?? Self.defaultCaptureDirectory()
    }

    private static func defaultCaptureDirectory() -> URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Tacket Captures", isDirectory: true)
    }

    private var repoRoot: URL? {
        var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<5 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("package.json").path),
               FileManager.default.fileExists(atPath: url.appendingPathComponent("apps/cli/bin/tacket.js").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return nil
    }

    private var resourcesRoot: URL {
        Bundle.main.resourceURL ?? repoRoot ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private var extensionManifestURL: URL {
        if let repoRoot {
            return repoRoot.appendingPathComponent("apps/chrome-extension/manifest.json")
        }
        return resourcesRoot.appendingPathComponent("chrome-extension/manifest.json")
    }

    private var extensionDirectoryURL: URL {
        extensionManifestURL.deletingLastPathComponent()
    }

    private var nativeHostURL: URL? {
        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/TacketNativeHost")
        if FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        if let repoRoot {
            let debug = repoRoot.appendingPathComponent("apps/mac/TacketApp/.build/debug/TacketNativeHost")
            if FileManager.default.isExecutableFile(atPath: debug.path) {
                return debug
            }
        }

        return nil
    }

    private var configDirectoryURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Tacket", isDirectory: true)
    }

    private var configURL: URL {
        configDirectoryURL.appendingPathComponent("config.json")
    }

    private var libraryDatabaseURL: URL {
        configDirectoryURL.appendingPathComponent("library.sqlite")
    }

    func revealCaptureDirectory() {
        try? FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([captureDirectory])
    }

    func chooseCaptureDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose capture folder"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = captureDirectory

        if panel.runModal() == .OK, let url = panel.url {
            captureDirectory = url
            persistConfig()
            status = "Capture folder updated."
            commandOutput = "Tacket captures will be written to:\n\(url.path)"
        }
    }

    func resetCaptureDirectory() {
        captureDirectory = Self.defaultCaptureDirectory()
        persistConfig()
        status = "Capture folder reset."
        commandOutput = "Tacket captures will be written to:\n\(captureDirectory.path)"
    }

    func chooseBundle() {
        let panel = NSOpenPanel()
        panel.title = "Choose a .tacket bundle"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = captureDirectory

        if panel.runModal() == .OK {
            selectedBundle = panel.url
            loadSelectedBundleInfo()
            status = "Selected \(panel.url?.lastPathComponent ?? "bundle")."
        }
    }

    func revealSelectedBundle() {
        guard let selectedBundle else {
            status = "Choose a .tacket bundle first."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([selectedBundle])
    }

    func openSelectedTranscript() {
        guard let selectedBundle else {
            status = "Choose a .tacket bundle first."
            return
        }
        NSWorkspace.shared.open(selectedBundle.appendingPathComponent("transcript.md"))
    }

    func copySelectedTranscript() {
        guard let selectedBundle else {
            status = "Choose a .tacket bundle first."
            return
        }
        do {
            let transcript = try String(contentsOf: selectedBundle.appendingPathComponent("transcript.md"), encoding: .utf8)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(transcript, forType: .string)
            status = "Copied raw transcript."
            commandOutput = "Copied unchunked transcript from \(selectedBundle.lastPathComponent)."
        } catch {
            status = "Copy failed."
            commandOutput = error.localizedDescription
        }
    }

    func openExtensionFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([
            extensionManifestURL
        ])
    }

    func copyExtensionFolderPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(extensionDirectoryURL.path, forType: .string)
        status = "Copied extension folder path."
        commandOutput = extensionDirectoryURL.path
    }

    func openChromeExtensions() {
        openInChrome("chrome://extensions")
    }

    func openChatGPT() {
        openInChrome("https://chatgpt.com")
    }

    func openClaude() {
        openInChrome("https://claude.ai")
    }

    func openGemini() {
        openInChrome("https://gemini.google.com")
    }

    func openDocs() {
        if let repoRoot {
            NSWorkspace.shared.open(repoRoot.appendingPathComponent("README.md"))
        } else {
            NSWorkspace.shared.open(resourcesRoot)
        }
    }

    private func openInChrome(_ target: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Google Chrome", target]
        do {
            try process.run()
            status = "Opened Chrome."
        } catch {
            status = "Could not open Chrome."
            commandOutput = error.localizedDescription
        }
    }

    func installConnector() {
        let id = extensionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            status = "Paste the Chrome extension ID first."
            return
        }
        guard Self.isValidChromeExtensionId(id) else {
            status = "Invalid Chrome extension ID."
            commandOutput = "Chrome extension IDs are 32 lowercase letters from a to p. Copy the ID from chrome://extensions."
            return
        }

        do {
            let path = try installNativeMessagingHost(extensionId: id)
            installedHostPath = path.path
            refreshConnectorStatus()
            commandOutput = "Installed Chrome native messaging host:\n\(path.path)"
            status = "Connector installed."
        } catch {
            commandOutput = error.localizedDescription
            status = "Connector install failed."
        }
    }

    func refreshConnectorStatus() {
        let manifestURL = nativeHostManifestURL()
        do {
            let data = try Data(contentsOf: manifestURL)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let hostPath = json["path"] as? String ?? "unknown"
            let origins = (json["allowed_origins"] as? [String] ?? []).joined(separator: ", ")
            installedHostPath = manifestURL.path
            connectorStatus = "Installed: \(hostPath)"
            commandOutput = "Manifest: \(manifestURL.path)\nAllowed origins: \(origins)"
        } catch {
            installedHostPath = nil
            connectorStatus = "Not installed."
            commandOutput = "No connector manifest at \(manifestURL.path)"
        }
    }

    func uninstallConnector() {
        let manifestURL = nativeHostManifestURL()
        do {
            try FileManager.default.removeItem(at: manifestURL)
            installedHostPath = nil
            connectorStatus = "Not installed."
            commandOutput = "Removed connector manifest:\n\(manifestURL.path)"
            status = "Connector removed."
        } catch CocoaError.fileNoSuchFile {
            installedHostPath = nil
            connectorStatus = "Not installed."
            commandOutput = "No connector manifest at \(manifestURL.path)"
            status = "Connector not installed."
        } catch {
            commandOutput = error.localizedDescription
            status = "Connector removal failed."
        }
    }

    func transferSelectedBundle() {
        guard let selectedBundle else {
            status = "Choose a .tacket bundle first."
            return
        }

        do {
            try validateBundleForTransfer(selectedBundle)
        } catch {
            status = "Invalid bundle."
            commandOutput = error.localizedDescription
            return
        }

        let target = selectedTarget
        guard let maxChunkCharacters = Int(maxChunkCharacters.trimmingCharacters(in: .whitespacesAndNewlines)),
              maxChunkCharacters >= 1000 else {
            status = "Invalid chunk size."
            commandOutput = "Max chunk characters must be an integer of at least 1000."
            return
        }

        isRunning = true
        status = "Transferring raw transcript..."
        commandOutput = ""

        Task {
            do {
                let transcript = try String(contentsOf: selectedBundle.appendingPathComponent("transcript.md"), encoding: .utf8)
                let chunks = splitTranscript(transcript, maxCharacters: maxChunkCharacters)
                let transferText = chunks.joined(separator: "\n\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(transferText, forType: .string)

                let output: String
                switch target {
                case .clipboard:
                    output = "Copied \(chunks.count) raw transcript chunk(s) to clipboard."
                case .codex:
                    output = await launchTerminal(command: "codex", title: "Tacket Codex Transfer", chunkCount: chunks.count)
                case .claudeCode:
                    output = await launchTerminal(command: "claude", title: "Tacket Claude Code Transfer", chunkCount: chunks.count)
                }

                commandOutput = output
                status = "Done."
            } catch {
                commandOutput = error.localizedDescription
                status = "Transfer failed."
            }
            isRunning = false
        }
    }

    func refreshLibrary() {
        do {
            try ensureLibraryDatabase()
            libraryItems = try queryLibrary(search: librarySearchText)
            selectedLibraryItem = selectedLibraryItem.flatMap { selected in
                libraryItems.first(where: { $0.id == selected.id })
            } ?? libraryItems.first
            libraryStatus = libraryItems.isEmpty ? "No indexed transcripts yet." : "\(libraryItems.count) indexed transcript(s)."
        } catch {
            libraryStatus = "Library refresh failed."
            commandOutput = error.localizedDescription
        }
    }

    func searchLibrary() {
        refreshLibrary()
    }

    func indexCaptureFolderForLibrary() {
        do {
            let result = try indexLibraryFolder(captureDirectory)
            librarySearchText = ""
            libraryItems = try queryLibrary(search: "")
            selectedLibraryItem = libraryItems.first
            libraryStatus = "Indexed \(result.indexed) of \(result.found) .tacket bundle(s)."
            status = "Library indexed."
            commandOutput = "Library database:\n\(libraryDatabaseURL.path)\n\nIndexed folder:\n\(captureDirectory.path)"
        } catch {
            libraryStatus = "Indexing failed."
            status = "Library indexing failed."
            commandOutput = error.localizedDescription
        }
    }

    func chooseFolderAndIndexLibrary() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder of .tacket bundles"
        panel.prompt = "Index"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = captureDirectory

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let result = try indexLibraryFolder(url)
                librarySearchText = ""
                libraryItems = try queryLibrary(search: "")
                selectedLibraryItem = libraryItems.first
                libraryStatus = "Indexed \(result.indexed) of \(result.found) .tacket bundle(s)."
                status = "Library indexed."
                commandOutput = "Indexed folder:\n\(url.path)"
            } catch {
                libraryStatus = "Indexing failed."
                status = "Library indexing failed."
                commandOutput = error.localizedDescription
            }
        }
    }

    func removeMissingLibraryBundles() {
        do {
            try ensureLibraryDatabase()
            let items = try queryLibrary(search: "")
            var removed = 0
            for item in items where !FileManager.default.fileExists(atPath: item.path) {
                try removeLibraryBundle(id: item.id)
                removed += 1
            }
            refreshLibrary()
            status = "Library cleaned."
            commandOutput = "Removed \(removed) missing indexed bundle(s)."
        } catch {
            status = "Library cleanup failed."
            commandOutput = error.localizedDescription
        }
    }

    func selectLibraryItem(_ item: LibraryItem) {
        selectedLibraryItem = item
        selectedBundle = URL(fileURLWithPath: item.path, isDirectory: true)
        loadSelectedBundleInfo()
    }

    func revealLibraryItem(_ item: LibraryItem) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path, isDirectory: true)])
    }

    func openLibraryTranscript(_ item: LibraryItem) {
        NSWorkspace.shared.open(URL(fileURLWithPath: item.path, isDirectory: true).appendingPathComponent("transcript.md"))
    }

    func copyLibraryTranscript(_ item: LibraryItem) {
        do {
            let transcript = try String(
                contentsOf: URL(fileURLWithPath: item.path, isDirectory: true).appendingPathComponent("transcript.md"),
                encoding: .utf8
            )
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(transcript, forType: .string)
            status = "Copied raw transcript."
            commandOutput = "Copied transcript from \(item.title)."
        } catch {
            status = "Copy failed."
            commandOutput = error.localizedDescription
        }
    }

    func transferLibraryItem(_ item: LibraryItem) {
        selectLibraryItem(item)
        transferSelectedBundle()
    }

    private func loadSelectedBundleInfo() {
        guard let selectedBundle else {
            selectedBundleInfo = nil
            return
        }

        do {
            let manifestURL = selectedBundle.appendingPathComponent("manifest.json")
            let data = try Data(contentsOf: manifestURL)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let source = json["source"] as? [String: Any] ?? [:]
            let warnings = (json["warnings"] as? [[String: Any]] ?? []).map { warning in
                BundleWarning(
                    kind: warning["kind"] as? String ?? "unknown",
                    count: warning["count"] as? Int ?? 0,
                    messageIds: warning["messageIds"] as? [String] ?? []
                )
            }
            selectedBundleInfo = BundleInfo(
                title: json["title"] as? String ?? selectedBundle.lastPathComponent,
                platform: source["platform"] as? String ?? "unknown",
                url: source["url"] as? String ?? "",
                capturedAt: json["capturedAt"] as? String ?? "",
                messageCount: json["messageCount"] as? Int ?? 0,
                warnings: warnings
            )
        } catch {
            selectedBundleInfo = nil
            commandOutput = "Could not read manifest.json: \(error.localizedDescription)"
        }
    }

    private func validateBundleForTransfer(_ bundleURL: URL) throws {
        _ = try Data(contentsOf: bundleURL.appendingPathComponent("manifest.json"))
        _ = try Data(contentsOf: bundleURL.appendingPathComponent("messages.jsonl"))
        let transcript = try String(contentsOf: bundleURL.appendingPathComponent("transcript.md"), encoding: .utf8)
        for target in ["codex.md", "claude-code.md"] {
            let targetText = try String(
                contentsOf: bundleURL.appendingPathComponent("targets").appendingPathComponent(target),
                encoding: .utf8
            )
            if targetText != transcript {
                throw TacketAppError.invalidBundle("targets/\(target) must match transcript.md exactly.")
            }
        }
    }

    private func indexLibraryFolder(_ folder: URL) throws -> (found: Int, indexed: Int) {
        try ensureLibraryDatabase()
        let bundles = try findTacketBundles(in: folder)
        var indexed = 0
        for bundle in bundles {
            if try indexLibraryBundle(bundle) {
                indexed += 1
            }
        }
        return (bundles.count, indexed)
    }

    private func findTacketBundles(in folder: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var bundles: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true, url.pathExtension == "tacket" else { continue }
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("manifest.json").path),
               FileManager.default.fileExists(atPath: url.appendingPathComponent("messages.jsonl").path),
               FileManager.default.fileExists(atPath: url.appendingPathComponent("transcript.md").path) {
                bundles.append(url)
                enumerator.skipDescendants()
            }
        }
        return bundles.sorted { $0.path < $1.path }
    }

    private func indexLibraryBundle(_ bundleURL: URL) throws -> Bool {
        let manifestURL = bundleURL.appendingPathComponent("manifest.json")
        let messagesURL = bundleURL.appendingPathComponent("messages.jsonl")
        let transcriptURL = bundleURL.appendingPathComponent("transcript.md")
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any] ?? [:]
        let source = manifest["source"] as? [String: Any] ?? [:]
        let transcript = try String(contentsOf: transcriptURL, encoding: .utf8)
        let transcriptHash = sha256(transcript)
        let bundleId = manifest["id"] as? String ?? stableLibraryId(bundleURL.path)

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
                    text: Self.messageText(from: json),
                    ordinal: index
                )
            }

        let title = manifest["title"] as? String ?? bundleURL.deletingPathExtension().lastPathComponent
        let platform = source["platform"] as? String ?? "unknown"
        let url = source["url"] as? String ?? ""
        let capturedAt = manifest["capturedAt"] as? String ?? ""
        let messageCount = manifest["messageCount"] as? Int ?? messages.count
        let indexedAt = ISO8601DateFormatter().string(from: Date())

        try withLibraryDatabase { db in
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

    private func ensureLibraryDatabase() throws {
        try FileManager.default.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
        try withLibraryDatabase { db in
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
                CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
                  bundle_id UNINDEXED,
                  message_id UNINDEXED,
                  title,
                  platform,
                  role,
                  text
                );
                """)
        }
    }

    private func queryLibrary(search: String) throws -> [LibraryItem] {
        try ensureLibraryDatabase()
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return try queryLibraryItems("""
                SELECT id, path, title, platform, url, captured_at, message_count, indexed_at, '' AS snippet
                FROM bundles
                ORDER BY captured_at DESC, indexed_at DESC
                LIMIT 100;
                """)
        }
        let query = "\"\(trimmed.replacingOccurrences(of: "\"", with: "\"\""))\""
        return try queryLibraryItems("""
            SELECT b.id, b.path, b.title, b.platform, b.url, b.captured_at, b.message_count, b.indexed_at,
                   snippet(messages_fts, 5, '[', ']', ' ... ', 18) AS snippet
            FROM messages_fts
            JOIN bundles b ON b.id = messages_fts.bundle_id
            WHERE messages_fts MATCH \(sqliteQuote(query))
              AND messages_fts.rowid IN (
                SELECT min(rowid)
                FROM messages_fts
                WHERE messages_fts MATCH \(sqliteQuote(query))
                GROUP BY bundle_id
              )
            ORDER BY rank
            LIMIT 100;
            """)
    }

    private func queryLibraryItems(_ sql: String) throws -> [LibraryItem] {
        try withLibraryDatabase { db in
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw TacketAppError.libraryDatabase(sqliteError(db))
            }
            defer { sqlite3_finalize(statement) }
            var items: [LibraryItem] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                items.append(LibraryItem(
                    id: sqliteColumnText(statement, 0),
                    path: sqliteColumnText(statement, 1),
                    title: sqliteColumnText(statement, 2),
                    platform: sqliteColumnText(statement, 3),
                    url: sqliteColumnText(statement, 4),
                    capturedAt: sqliteColumnText(statement, 5),
                    messageCount: Int(sqlite3_column_int(statement, 6)),
                    indexedAt: sqliteColumnText(statement, 7),
                    snippet: sqliteColumnText(statement, 8)
                ))
            }
            return items
        }
    }

    private func queryLibraryHash(path: String) throws -> String? {
        try withLibraryDatabase { db in
            let sql = "SELECT transcript_hash FROM bundles WHERE path = \(sqliteQuote(path)) LIMIT 1;"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw TacketAppError.libraryDatabase(sqliteError(db))
            }
            defer { sqlite3_finalize(statement) }
            if sqlite3_step(statement) == SQLITE_ROW {
                return sqliteColumnText(statement, 0)
            }
            return nil
        }
    }

    private func removeLibraryBundle(id: String) throws {
        try withLibraryDatabase { db in
            try sqliteExec(db, "DELETE FROM messages_fts WHERE bundle_id = \(sqliteQuote(id));")
            try sqliteExec(db, "DELETE FROM messages WHERE bundle_id = \(sqliteQuote(id));")
            try sqliteExec(db, "DELETE FROM bundles WHERE id = \(sqliteQuote(id));")
        }
    }

    private func withLibraryDatabase<T>(_ body: (OpaquePointer?) throws -> T) throws -> T {
        var db: OpaquePointer?
        guard sqlite3_open(libraryDatabaseURL.path, &db) == SQLITE_OK else {
            defer { sqlite3_close(db) }
            throw TacketAppError.libraryDatabase(sqliteError(db))
        }
        defer { sqlite3_close(db) }
        return try body(db)
    }

    private func sqliteExec(_ db: OpaquePointer?, _ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? sqliteError(db)
            sqlite3_free(error)
            throw TacketAppError.libraryDatabase(message)
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

    private func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func stableLibraryId(_ value: String) -> String {
        String(sha256(value).prefix(16))
    }

    private func sqliteQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private func sqliteError(_ db: OpaquePointer?) -> String {
        guard let message = sqlite3_errmsg(db) else { return "Unknown SQLite error." }
        return String(cString: message)
    }

    private func sqliteColumnText(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let text = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: text)
    }

    private func installNativeMessagingHost(extensionId: String) throws -> URL {
        guard let nativeHostURL else {
            throw TacketAppError.nativeHostMissing
        }

        let manifestDirectory = nativeHostManifestDirectory()
        try FileManager.default.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)

        let manifestURL = nativeHostManifestURL()
        let manifest: [String: Any] = [
            "name": "dev.tacket.host",
            "description": "Tacket local capture host",
            "path": nativeHostURL.path,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(extensionId)/"]
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: manifestURL)
        return manifestURL
    }

    private func nativeHostManifestDirectory() -> URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts", isDirectory: true)
    }

    private func nativeHostManifestURL() -> URL {
        nativeHostManifestDirectory().appendingPathComponent("dev.tacket.host.json")
    }

    private func persistConfig() {
        do {
            try FileManager.default.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
            let config: [String: Any] = ["captureDirectory": captureDirectory.path]
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: configURL)
        } catch {
            commandOutput = "Could not write config: \(error.localizedDescription)"
        }
    }

    private static func readConfiguredCaptureDirectory() -> URL? {
        let configURL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Tacket/config.json")
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = json["captureDirectory"] as? String,
              !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
    }

    private static func isValidChromeExtensionId(_ extensionId: String) -> Bool {
        let pattern = #"^[a-p]{32}$"#
        return extensionId.range(of: pattern, options: .regularExpression) != nil
    }

    private nonisolated func splitTranscript(_ transcript: String, maxCharacters: Int) -> [String] {
        guard transcript.count > maxCharacters else {
            return [transcript]
        }

        var chunks: [String] = []
        var cursor = transcript.startIndex

        while cursor < transcript.endIndex {
            let tentativeEnd = transcript.index(cursor, offsetBy: maxCharacters, limitedBy: transcript.endIndex) ?? transcript.endIndex
            var end = tentativeEnd
            let window = transcript[cursor..<tentativeEnd]
            if let boundaryRange = window.range(of: "\n## ", options: .backwards) {
                let distance = transcript.distance(from: cursor, to: boundaryRange.lowerBound)
                if distance > maxCharacters / 3 {
                    end = boundaryRange.lowerBound
                }
            }

            let chunk = transcript[cursor..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty {
                chunks.append(chunk)
            }
            cursor = end
        }

        return chunks.enumerated().map { index, chunk in
            let number = index + 1
            let footer = number == chunks.count ? "[raw transcript complete]" : "Please acknowledge receipt only."
            return "[raw transcript chunk \(number) of \(chunks.count)]\n\n\(chunk)\n\n\(footer)"
        }
    }

    private nonisolated func launchTerminal(command: String, title: String, chunkCount: Int) async -> String {
        let escapedCommand = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedTitle = title.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
          activate
          do script "printf '\\\\e]0;\(escapedTitle)\\\\a'; \(escapedCommand)"
        end tell
        delay 1.5
        tell application "System Events"
          keystroke "v" using command down
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        do {
            try process.run()
            let completed = await waitForExit(process, timeoutNanoseconds: 10_000_000_000)
            guard completed else {
                process.terminate()
                return "Copied \(chunkCount) raw transcript chunk(s). Terminal automation timed out."
            }
            if process.terminationStatus == 0 {
                return "Copied \(chunkCount) raw transcript chunk(s), launched \(command), and requested paste into Terminal."
            }
            return "Copied \(chunkCount) raw transcript chunk(s). Terminal automation exited with \(process.terminationStatus)."
        } catch {
            return "Copied \(chunkCount) raw transcript chunk(s). Terminal automation failed: \(error.localizedDescription)"
        }
    }

    private nonisolated func waitForExit(_ process: Process, timeoutNanoseconds: UInt64) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                process.waitUntilExit()
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }
}

enum TacketAppError: LocalizedError {
    case nativeHostMissing
    case invalidBundle(String)
    case libraryDatabase(String)

    var errorDescription: String? {
        switch self {
        case .nativeHostMissing:
            return "TacketNativeHost was not found. Build the Mac package or run `swift build` in apps/mac/TacketApp."
        case .invalidBundle(let message):
            return "Invalid .tacket bundle: \(message)"
        case .libraryDatabase(let message):
            return "Library database error: \(message)"
        }
    }
}

struct LibraryItem: Identifiable, Equatable {
    let id: String
    let path: String
    let title: String
    let platform: String
    let url: String
    let capturedAt: String
    let messageCount: Int
    let indexedAt: String
    let snippet: String
}

struct LibraryMessage {
    let id: String
    let role: String
    let text: String
    let ordinal: Int
}

struct BundleInfo {
    let title: String
    let platform: String
    let url: String
    let capturedAt: String
    let messageCount: Int
    let warnings: [BundleWarning]
}

struct BundleWarning: Identifiable {
    let id = UUID()
    let kind: String
    let count: Int
    let messageIds: [String]
}

struct ContentView: View {
    @EnvironmentObject private var model: TacketModel
    @State private var selectedSection: AppSection = .library

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            Divider()
            HStack(alignment: .top, spacing: 0) {
                SidebarView(selectedSection: $selectedSection)
                    .frame(width: 250)
                Divider()
                switch selectedSection {
                case .library:
                    LibraryPanelView()
                case .transfer:
                    MainPanelView()
                case .settings:
                    SettingsPanelView()
                }
            }
        }
        .background(TacketColors.window)
        .tint(TacketColors.accent)
    }
}

enum AppSection {
    case library
    case transfer
    case settings
}

struct HeaderView: View {
    @EnvironmentObject private var model: TacketModel

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            AppMark()
                .frame(width: 46, height: 46)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("Tacket")
                    .font(.tacketTitle)
                Text("Move one raw AI chat thread into the coding tool you want next.")
                    .font(.tacketBody)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            HeaderButton(title: "Captures", action: model.revealCaptureDirectory)
            HeaderButton(title: "Docs", action: model.openDocs)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
}

struct SidebarView: View {
    @EnvironmentObject private var model: TacketModel
    @Binding var selectedSection: AppSection

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SidebarSection(title: "How it works") {
                WorkflowStep(number: "1", title: "Capture", detail: "Open a supported chat and capture the thread.")
                WorkflowStep(number: "2", title: "Review", detail: "Pick the saved .tacket bundle on this Mac.")
                WorkflowStep(number: "3", title: "Transfer", detail: "Copy or paste the raw transcript into a coding session.")
            }

            SidebarSection(title: "Library") {
                SidebarNavRow(title: "Search transcripts", isSelected: selectedSection == .library)
                    .onTapGesture {
                        selectedSection = .library
                    }
            }

            SidebarSection(title: "Sources") {
                SourceButton(title: "ChatGPT", action: model.openChatGPT)
                SourceButton(title: "Claude", action: model.openClaude)
                SourceButton(title: "Gemini", action: model.openGemini)
            }

            SidebarSection(title: "Targets") {
                ForEach(TacketModel.TransferTarget.allCases) { target in
                    TargetRow(target: target, isSelected: model.selectedTarget == target)
                        .onTapGesture {
                            selectedSection = .transfer
                            model.selectedTarget = target
                        }
                }
            }

            SidebarNavRow(title: "Settings", isSelected: selectedSection == .settings)
                .onTapGesture {
                    selectedSection = .settings
                }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(TacketColors.sidebar)
    }
}

struct MainPanelView: View {
    @EnvironmentObject private var model: TacketModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StatusBanner(status: model.status)

                SectionCard(
                    eyebrow: "Captures",
                    title: "Local thread bundles",
                    detail: "Tacket saves captures as folders you can inspect, copy, and transfer without an account or backend."
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        PathField(label: "Capture folder", value: model.captureDirectory.path)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Button("Reveal Folder") {
                                    model.revealCaptureDirectory()
                                }
                                Button("Choose Capture Folder") {
                                    model.chooseCaptureDirectory()
                                }
                            }
                            HStack(spacing: 10) {
                                Button("Reset Folder") {
                                    model.resetCaptureDirectory()
                                }
                                Button("Choose Bundle") {
                                    model.chooseBundle()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }

                        if let bundle = model.selectedBundle {
                            PathField(label: "Selected bundle", value: bundle.path)
                        } else {
                            EmptyStateText("No bundle selected yet.")
                        }

                        if let info = model.selectedBundleInfo {
                            BundleSummary(info: info)
                        }
                    }
                }

                SectionCard(
                    eyebrow: "Transfer",
                    title: "Send the raw transcript",
                    detail: "Choose a destination. Tacket keeps the transcript raw and preserves the full thread content it captured."
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Target", selection: $model.selectedTarget) {
                            ForEach(TacketModel.TransferTarget.allCases) { target in
                                Text(target.label).tag(target)
                            }
                        }
                        .pickerStyle(.segmented)

                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("Chunk size")
                                .font(.tacketBody)
                            TextField("24000", text: $model.maxChunkCharacters)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 120)
                            Text("Used only when a transcript is too long for one paste.")
                                .font(.tacketFootnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Button("Transfer") {
                                    model.transferSelectedBundle()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.isRunning)
                                Button("Copy Transcript") {
                                    model.copySelectedTranscript()
                                }
                            }
                            HStack(spacing: 10) {
                                Button("Open Transcript") {
                                    model.openSelectedTranscript()
                                }
                                Button("Reveal Bundle") {
                                    model.revealSelectedBundle()
                                }
                            }
                        }
                    }
                }

                OutputPanel()
            }
            .padding(24)
            .frame(maxWidth: 850, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(TacketColors.content)
    }
}

struct LibraryPanelView: View {
    @EnvironmentObject private var model: TacketModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StatusBanner(status: model.status)

                SectionCard(
                    eyebrow: "Library",
                    title: "Search raw transcripts",
                    detail: "Index local .tacket bundles and search across saved ChatGPT, Claude, Gemini, Codex, and Claude Code handoffs without sending anything off this Mac."
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        TextField("Search transcripts", text: $model.librarySearchText)
                            .textFieldStyle(.roundedBorder)
                            .font(.tacketBody)
                            .onSubmit {
                                model.searchLibrary()
                            }
                            .onChange(of: model.librarySearchText) { _ in
                                model.searchLibrary()
                            }

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Button("Index Capture Folder") {
                                    model.indexCaptureFolderForLibrary()
                                }
                                .buttonStyle(.borderedProminent)
                                Button("Add Folder") {
                                    model.chooseFolderAndIndexLibrary()
                                }
                            }
                            HStack(spacing: 10) {
                                Button("Refresh") {
                                    model.refreshLibrary()
                                }
                                Button("Remove Missing") {
                                    model.removeMissingLibraryBundles()
                                }
                            }
                        }

                        Text(model.libraryStatus)
                            .font(.tacketFootnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SectionCard(
                    eyebrow: "Results",
                    title: "\(model.libraryItems.count) transcript\(model.libraryItems.count == 1 ? "" : "s")",
                    detail: "Select a saved thread to inspect its raw match, copy it, reveal it, or transfer it into your selected target."
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        if model.libraryItems.isEmpty {
                            EmptyStateText("No indexed transcripts match this search.")
                        } else {
                            ForEach(model.libraryItems) { item in
                                LibraryResultRow(item: item, isSelected: model.selectedLibraryItem?.id == item.id)
                                    .onTapGesture {
                                        model.selectLibraryItem(item)
                                    }
                            }
                        }
                    }
                }

                if let item = model.selectedLibraryItem {
                    SectionCard(
                        eyebrow: "Selected",
                        title: item.title,
                        detail: "\(item.platform) · \(item.messageCount) messages · \(item.capturedAt)"
                    ) {
                        VStack(alignment: .leading, spacing: 14) {
                            if !item.snippet.isEmpty {
                                Text(cleanSnippet(item.snippet))
                                    .font(.tacketBody)
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(TacketColors.recessed)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }

                            PathField(label: "Bundle", value: item.path)

                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    Button("Transfer") {
                                        model.transferLibraryItem(item)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(model.isRunning)
                                    Button("Copy Transcript") {
                                        model.copyLibraryTranscript(item)
                                    }
                                }
                                HStack(spacing: 10) {
                                    Button("Open Transcript") {
                                        model.openLibraryTranscript(item)
                                    }
                                    Button("Reveal Bundle") {
                                        model.revealLibraryItem(item)
                                    }
                                }
                            }
                        }
                    }
                }

                OutputPanel()
            }
            .padding(24)
            .frame(maxWidth: 850, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(TacketColors.content)
        .onAppear {
            model.refreshLibrary()
        }
    }

    private func cleanSnippet(_ value: String) -> String {
        value
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
    }
}

struct SettingsPanelView: View {
    @EnvironmentObject private var model: TacketModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StatusBanner(status: model.status)

                SectionCard(
                    eyebrow: "Settings",
                    title: "Capture location",
                    detail: "Choose where Tacket saves local thread bundles before you transfer them."
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        PathField(label: "Capture folder", value: model.captureDirectory.path)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Button("Reveal Folder") {
                                    model.revealCaptureDirectory()
                                }
                                Button("Choose Capture Folder") {
                                    model.chooseCaptureDirectory()
                                }
                            }
                            Button("Reset Folder") {
                                model.resetCaptureDirectory()
                            }
                        }
                    }
                }

                SectionCard(
                    eyebrow: "Advanced",
                    title: "Chrome connector",
                    detail: "For local development, install or inspect the native messaging connector that lets the Chrome extension save captures on this Mac."
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        ConnectorStatusView()

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Button("Open Chrome Extensions") {
                                    model.openChromeExtensions()
                                }
                                Button("Reveal Extension Folder") {
                                    model.openExtensionFolder()
                                }
                            }
                            HStack(spacing: 10) {
                                Button("Copy Folder Path") {
                                    model.copyExtensionFolderPath()
                                }
                                Button("Check Connector") {
                                    model.refreshConnectorStatus()
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Manual extension IDs are only needed for unpacked development builds. The official Chrome Web Store ID will be built into Tacket later.")
                                .font(.tacketFootnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 10) {
                                TextField("Chrome extension ID", text: $model.extensionId)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                                Button("Install Connector") {
                                    model.installConnector()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.isRunning)
                            }

                            Button("Remove Connector") {
                                model.uninstallConnector()
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(TacketColors.recessed)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                OutputPanel()
            }
            .padding(24)
            .frame(maxWidth: 850, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(TacketColors.content)
    }
}

struct SectionCard<Content: View>: View {
    let eyebrow: String
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow)
                    .font(.tacketLabel)
                    .foregroundStyle(TacketColors.accent)
                Text(title)
                    .font(.tacketSectionTitle)
                Text(detail)
                    .font(.tacketBody)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
        }
        .padding(18)
        .background(TacketColors.card)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(TacketColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct ConnectorStatusView: View {
    @EnvironmentObject private var model: TacketModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.installedHostPath == nil ? TacketColors.warning : TacketColors.success)
                    .frame(width: 8, height: 8)
                Text(model.connectorStatus)
                    .font(.tacketBody)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let installedHostPath = model.installedHostPath {
                Text(installedHostPath)
                    .font(.tacketMono)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TacketColors.recessed)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct BundleSummary: View {
    @EnvironmentObject private var model: TacketModel
    let info: BundleInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(info.title)
                    .font(.tacketSectionTitle)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(info.platform) · \(info.messageCount) messages · \(info.capturedAt)")
                    .font(.tacketFootnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !info.url.isEmpty {
                    Text(info.url)
                        .font(.tacketMono)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if info.warnings.isEmpty {
                Text("No local warnings in this bundle.")
                    .font(.tacketFootnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(info.warnings) { warning in
                        Text("Warning: \(warning.kind) (\(warning.count)) in \(warning.messageIds.joined(separator: ", "))")
                            .font(.tacketFootnote)
                            .foregroundStyle(TacketColors.warning)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TacketColors.recessed)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct OutputPanel: View {
    @EnvironmentObject private var model: TacketModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Activity")
                .font(.tacketLabel)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(model.commandOutput.isEmpty ? "Library activity and action details will appear here." : model.commandOutput)
                    .font(.tacketMono)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: 120, maxHeight: 190)
            .background(TacketColors.recessed)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct StatusBanner: View {
    let status: String

    private var color: Color {
        let lower = status.lowercased()
        if lower.contains("failed") || lower.contains("invalid") || lower.contains("could not") {
            return TacketColors.danger
        }
        if lower.contains("done") || lower.contains("installed") || lower.contains("copied") || lower.contains("opened") {
            return TacketColors.success
        }
        return TacketColors.accent
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(status)
                .font(.tacketBody)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(TacketColors.card)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(TacketColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct SidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.tacketLabel)
                .foregroundStyle(.secondary)
            content
        }
    }
}

struct WorkflowStep: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.tacketLabel)
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(TacketColors.accent)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.tacketBody.weight(.semibold))
                Text(detail)
                    .font(.tacketFootnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SourceButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.tacketBody)
                Spacer()
                Text("Open")
                    .font(.tacketFootnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TacketColors.card)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

struct TargetRow: View {
    let target: TacketModel.TransferTarget
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isSelected ? TacketColors.accent : TacketColors.border)
                .frame(width: 8, height: 8)
            Text(target.label)
                .font(.tacketBody)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? TacketColors.selected : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}

struct LibraryResultRow: View {
    let item: LibraryItem
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(isSelected ? TacketColors.accent : TacketColors.border)
                    .frame(width: 8, height: 8)
                Text(item.title)
                    .font(.tacketBody.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text(item.platform)
                    .font(.tacketFootnote)
                    .foregroundStyle(.secondary)
            }
            Text("\(item.messageCount) messages · \(item.capturedAt)")
                .font(.tacketFootnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if !item.snippet.isEmpty {
                Text(item.snippet.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: ""))
                    .font(.tacketFootnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? TacketColors.selected : TacketColors.recessed)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}

struct SidebarNavRow: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isSelected ? TacketColors.accent : TacketColors.border)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.tacketBody)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? TacketColors.selected : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}

struct PathField: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.tacketLabel)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.tacketMono)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TacketColors.recessed)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct EmptyStateText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.tacketBody)
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TacketColors.recessed)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct HeaderButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.tacketBody)
            .buttonStyle(.bordered)
    }
}

struct AppMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(TacketColors.accent)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white)
                .frame(width: 24, height: 16)
                .offset(x: 3, y: 2)
            VStack(spacing: 3) {
                Capsule().fill(TacketColors.paperLine).frame(width: 13, height: 2)
                Capsule().fill(TacketColors.paperLine).frame(width: 17, height: 2)
                Capsule().fill(TacketColors.paperLine).frame(width: 14, height: 2)
            }
            .offset(x: 5, y: 2)
            Capsule()
                .fill(TacketColors.pin)
                .frame(width: 6, height: 29)
                .rotationEffect(.degrees(-39))
                .offset(x: -2, y: 7)
            Circle()
                .fill(TacketColors.pin)
                .frame(width: 18, height: 18)
                .offset(x: -8, y: -7)
            Circle()
                .fill(Color.white.opacity(0.45))
                .frame(width: 5, height: 5)
                .offset(x: -12, y: -11)
        }
    }
}

enum TacketColors {
    static let accent = Color(red: 0.04, green: 0.36, blue: 0.56)
    static let selected = Color(red: 0.04, green: 0.36, blue: 0.56).opacity(0.12)
    static let pin = Color(red: 0.96, green: 0.74, blue: 0.34)
    static let paperLine = Color(red: 0.78, green: 0.79, blue: 0.78)
    static let success = Color(red: 0.12, green: 0.50, blue: 0.34)
    static let warning = Color(red: 0.78, green: 0.48, blue: 0.12)
    static let danger = Color(red: 0.72, green: 0.18, blue: 0.16)

    static let window = Color(nsColor: .windowBackgroundColor)
    static let content = Color(nsColor: .underPageBackgroundColor)
    static let sidebar = Color(nsColor: .controlBackgroundColor)
    static let card = Color(nsColor: .textBackgroundColor)
    static let recessed = Color(nsColor: .controlBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
}

extension Font {
    static let tacketTitle = Font.system(size: 28, weight: .semibold, design: .rounded)
    static let tacketSectionTitle = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let tacketBody = Font.system(size: 13, weight: .regular, design: .rounded)
    static let tacketFootnote = Font.system(size: 12, weight: .regular, design: .rounded)
    static let tacketLabel = Font.system(size: 11, weight: .semibold, design: .rounded)
    static let tacketMono = Font.system(size: 11, weight: .regular, design: .monospaced)
}
