import SwiftUI
import AppKit
import CryptoKit
import SQLite3
import ApplicationServices
import Vision

@main
struct TacketApp: App {
    @StateObject private var model = TacketModel()
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(AppearanceMode(rawValue: appearanceMode).flatMap(\.colorScheme))
                .frame(minWidth: 780, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 940, height: 640)
    }
}

@MainActor
final class TacketModel: ObservableObject {
    enum LibraryViewMode: String, CaseIterable, Identifiable {
        case gallery = "gallery"
        case list = "list"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .gallery: "Gallery"
            case .list: "List"
            }
        }
    }

    enum LibraryMatchMode: String, CaseIterable, Identifiable {
        case phrase = "phrase"
        case allTerms = "all"
        case anyTerm = "any"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .phrase: "Phrase"
            case .allTerms: "All terms"
            case .anyTerm: "Any term"
            }
        }
    }

    enum LibrarySearchScope: String, CaseIterable, Identifiable {
        case everywhere = "everywhere"
        case transcript = "transcript"
        case title = "title"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .everywhere: "Everything"
            case .transcript: "Transcript"
            case .title: "Title"
            }
        }
    }

    enum LibrarySourceFilter: String, CaseIterable, Identifiable {
        case all = "all"
        case chatgpt = "chatgpt"
        case claude = "claude"
        case gemini = "gemini"
        case codex = "codex"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: "All sources"
            case .chatgpt: "ChatGPT"
            case .claude: "Claude"
            case .gemini: "Gemini"
            case .codex: "Codex"
            }
        }
    }

    enum LibraryRoleFilter: String, CaseIterable, Identifiable {
        case all = "all"
        case user = "user"
        case assistant = "assistant"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: "All roles"
            case .user: "User"
            case .assistant: "Assistant"
            }
        }
    }

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

    enum NativeCaptureSource: String, CaseIterable, Identifiable {
        case chatgpt
        case claude
        case codex

        var id: String { rawValue }

        var label: String {
            switch self {
            case .chatgpt: "ChatGPT"
            case .claude: "Claude"
            case .codex: "Codex"
            }
        }

        var appNames: [String] {
            switch self {
            case .chatgpt: ["ChatGPT"]
            case .claude: ["Claude"]
            case .codex: ["Codex"]
            }
        }

        var bundleIdentifiers: [String] {
            switch self {
            case .chatgpt: ["com.openai.chat"]
            case .claude: ["com.anthropic.claudefordesktop", "com.anthropic.claude"]
            case .codex: ["com.openai.codex"]
            }
        }

        var platform: String { rawValue }
        var sourceURL: String { "native://\(rawValue)" }
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
    @Published var libraryMatchMode: LibraryMatchMode = .phrase
    @Published var librarySearchScope: LibrarySearchScope = .everywhere
    @Published var librarySourceFilter: LibrarySourceFilter = .all
    @Published var libraryRoleFilter: LibraryRoleFilter = .all
    @Published var libraryViewMode: LibraryViewMode = .gallery
    @Published var libraryItems: [LibraryItem] = []
    @Published var selectedLibraryItem: LibraryItem?
    @Published var libraryStatus = "Add your saved chats to the Library to search them."

    let supportedSources = ["ChatGPT", "Claude", "Gemini", "Codex"]

    var advancedSearchIsActive: Bool {
        libraryMatchMode != .phrase ||
        librarySearchScope != .everywhere ||
        librarySourceFilter != .all ||
        libraryRoleFilter != .all
    }

    var libraryIsFiltered: Bool {
        !librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || advancedSearchIsActive
    }

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
        Self.appSupportDirectoryURL
    }

    private nonisolated static var appSupportDirectoryURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Tacket", isDirectory: true)
    }

    private var configURL: URL {
        configDirectoryURL.appendingPathComponent("config.json")
    }

    private var libraryDatabaseURL: URL {
        Self.libraryDatabaseFileURL
    }

    private nonisolated static var libraryDatabaseFileURL: URL {
        appSupportDirectoryURL.appendingPathComponent("library.sqlite")
    }

    func revealCaptureDirectory() {
        try? FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([captureDirectory])
    }

    func chooseCaptureDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose save folder"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = captureDirectory

        if panel.runModal() == .OK, let url = panel.url {
            captureDirectory = url
            persistConfig()
            status = "Save folder updated."
            commandOutput = "Tacket will save conversations to:\n\(url.path)"
        }
    }

    func resetCaptureDirectory() {
        captureDirectory = Self.defaultCaptureDirectory()
        persistConfig()
        status = "Save folder reset."
        commandOutput = "Tacket will save conversations to:\n\(captureDirectory.path)"
    }

    func chooseBundle() {
        let panel = NSOpenPanel()
        panel.title = "Choose a saved Tacket chat"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = captureDirectory

        if panel.runModal() == .OK {
            selectedBundle = panel.url
            loadSelectedBundleInfo()
            status = "Selected \(panel.url?.lastPathComponent ?? "saved chat")."
        }
    }

    func revealSelectedBundle() {
        guard let selectedBundle else {
            status = "Choose a saved chat first."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([selectedBundle])
    }

    func openSelectedTranscript() {
        guard let selectedBundle else {
            status = "Choose a saved chat first."
            return
        }
        NSWorkspace.shared.open(selectedBundle.appendingPathComponent("transcript.md"))
    }

    func copySelectedTranscript() {
        guard let selectedBundle else {
            status = "Choose a saved chat first."
            return
        }
        do {
            let transcript = try String(contentsOf: selectedBundle.appendingPathComponent("transcript.md"), encoding: .utf8)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(transcript, forType: .string)
            status = "Copied conversation."
            commandOutput = "Copied the full saved conversation from \(selectedBundle.lastPathComponent)."
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

    func openAccessibilitySettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openScreenRecordingSettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    func captureNativeApp(_ source: NativeCaptureSource) {
        guard !isRunning else { return }
        guard let app = runningNativeCaptureApp(for: source) else {
            status = "\(source.label) app is not open."
            commandOutput = "Open the \(source.label) desktop app, open the chat you want to save, click inside the conversation, then capture it from Tacket."
            return
        }

        let accessibilityReady = Self.accessibilityIsTrusted(prompt: true)
        let screenCaptureReady = Self.screenCaptureIsTrusted(prompt: true)
        guard accessibilityReady || screenCaptureReady else {
            status = "Permission needed."
            commandOutput = "Tacket needs Accessibility permission or Screen Recording permission to read desktop app chats locally. Grant permission in System Settings, reopen Tacket, then try again."
            return
        }

        isRunning = true
        status = "Capturing \(source.label) app..."
        commandOutput = "Tacket will read the \(app.localizedName ?? source.label) window locally with macOS Accessibility and on-device OCR. Nothing is uploaded."

        Task {
            do {
                let rawText = try await readConversationText(from: app, source: source)
                let bundleURL = try Self.writeNativeCaptureBundle(
                    source: source,
                    rawText: rawText,
                    outputRoot: captureDirectory
                )
                _ = try Self.indexLibraryBundle(bundleURL)
                librarySearchText = ""
                libraryItems = try queryLibrary(search: "")
                selectedLibraryItem = libraryItems.first(where: { $0.path == bundleURL.path }) ?? libraryItems.first
                selectedBundle = bundleURL
                loadSelectedBundleInfo()
                libraryStatus = "Saved \(source.label) app chat."
                status = "Saved \(source.label) chat."
                commandOutput = "Saved native app capture:\n\(bundleURL.path)"
            } catch {
                status = "Native capture failed."
                commandOutput = error.localizedDescription
            }

            isRunning = false
        }
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

    private func openSystemSettings(_ target: String) {
        guard let url = URL(string: target) else { return }
        NSWorkspace.shared.open(url)
    }

    private func runningNativeCaptureApp(for source: NativeCaptureSource) -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications
        for bundleIdentifier in source.bundleIdentifiers {
            if let app = apps.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
                return app
            }
        }
        return apps.first { app in
            guard let name = app.localizedName?.lowercased() else { return false }
            return source.appNames.contains { name == $0.lowercased() }
        }
    }

    private func readConversationText(from app: NSRunningApplication, source: NativeCaptureSource) async throws -> String {
        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        try await Task.sleep(nanoseconds: 450_000_000)

        var snapshots: [String] = []
        try await Self.scrollNativeApp(processIdentifier: app.processIdentifier, deltaY: 9, repeats: 8)
        for _ in 0..<10 {
            if let text = try? await Self.nativeWindowText(for: app.processIdentifier),
               Self.nativeCaptureTextIsUsable(text) {
                snapshots.append(text)
            }
            try await Self.scrollNativeApp(processIdentifier: app.processIdentifier, deltaY: -7, repeats: 2)
        }

        let merged = Self.mergeNativeCaptureSnapshots(snapshots)
        if Self.nativeCaptureTextIsUsable(merged) {
            return merged
        }

        throw TacketAppError.nativeCapture("Tacket could not find enough readable chat text in the \(source.label) window. Open the chat, wait for messages to finish loading, then try again.")
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
            status = "Choose a saved chat first."
            return
        }

        do {
            try validateBundleForTransfer(selectedBundle)
        } catch {
            status = "Saved chat is missing required files."
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
        status = "Transferring conversation..."
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
                    output = "Copied \(chunks.count) conversation chunk(s) to clipboard."
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
            try Self.ensureLibraryDatabase()
            libraryItems = try queryLibrary(search: librarySearchText)
            selectedLibraryItem = selectedLibraryItem.flatMap { selected in
                libraryItems.first(where: { $0.id == selected.id })
            } ?? libraryItems.first
            libraryStatus = libraryItems.isEmpty ? "No indexed tackets yet." : "\(libraryItems.count) indexed tacket(s)."
        } catch {
            libraryStatus = "Library refresh failed."
            commandOutput = error.localizedDescription
        }
    }

    func searchLibrary() {
        refreshLibrary()
    }

    func resetAdvancedSearch() {
        libraryMatchMode = .phrase
        librarySearchScope = .everywhere
        librarySourceFilter = .all
        libraryRoleFilter = .all
        refreshLibrary()
    }

    func indexCaptureFolderForLibrary() {
        chooseFolderAndIndexLibrary()
    }

    func chooseFolderAndIndexLibrary() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder of saved Tacket chats"
        panel.prompt = "Add"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = captureDirectory

        if panel.runModal() == .OK, let url = panel.url {
            startIndexingLibraryFolder(url)
        }
    }

    private func startIndexingLibraryFolder(_ url: URL) {
        isRunning = true
        status = "Adding saved chats..."
        libraryStatus = "Scanning \(url.lastPathComponent)..."
        commandOutput = ""

        Task {
            do {
                let result = try await Task.detached {
                    try Self.indexLibraryFolder(url)
                }.value
                librarySearchText = ""
                libraryItems = try queryLibrary(search: "")
                selectedLibraryItem = libraryItems.first
                libraryStatus = "Added \(result.indexed) of \(result.found) saved chat(s)."
                status = "Library updated."
                commandOutput = "Added saved chats from:\n\(url.path)"
            } catch {
                libraryStatus = "Could not add saved chats."
                status = "Library update failed."
                commandOutput = error.localizedDescription
            }
            isRunning = false
        }
    }

    func removeMissingLibraryBundles() {
        do {
            try Self.ensureLibraryDatabase()
            let items = try queryLibrary(search: "")
            var removed = 0
            for item in items where !FileManager.default.fileExists(atPath: item.path) {
                try Self.removeLibraryBundle(id: item.id)
                removed += 1
            }
            refreshLibrary()
            status = "Library cleaned."
            commandOutput = "Removed \(removed) missing saved chat(s)."
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
            status = "Copied conversation."
            commandOutput = "Copied the full saved conversation from \(item.title)."
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

    private nonisolated static func writeNativeCaptureBundle(
        source: NativeCaptureSource,
        rawText: String,
        outputRoot: URL
    ) throws -> URL {
        let transcript = cleanNativeCaptureText(rawText)
        guard nativeCaptureTextIsUsable(transcript) else {
            throw TacketAppError.nativeCapture("The \(source.label) app did not expose enough readable chat text.")
        }

        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
        let capturedAt = ISO8601DateFormatter().string(from: Date())
        let title = nativeCaptureTitle(from: transcript, source: source)
        let id = sha256("\(source.rawValue):\(capturedAt):\(transcript)")
        let bundleURL = try reserveNativeCaptureBundleURL(
            outputRoot: outputRoot,
            capturedAt: Date(),
            source: source,
            title: title
        )
        let targetsURL = bundleURL.appendingPathComponent("targets", isDirectory: true)
        let attachmentsURL = bundleURL.appendingPathComponent("attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: targetsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: attachmentsURL, withIntermediateDirectories: true)

        let message: [String: Any] = [
            "id": "native-transcript",
            "role": "unknown",
            "author": source.label,
            "createdAt": capturedAt,
            "source": [
                "platform": source.platform,
                "url": source.sourceURL
            ],
            "content": [
                [
                    "type": "text",
                    "text": transcript
                ]
            ]
        ]
        let manifest: [String: Any] = [
            "schemaVersion": "0.1.0",
            "id": id,
            "title": title,
            "source": [
                "platform": source.platform,
                "url": source.sourceURL,
                "capture": "native-app"
            ],
            "capturedAt": capturedAt,
            "messageCount": 1,
            "attachments": [
                "captured": 0,
                "referenced": 0,
                "unavailable": 0
            ],
            "warnings": []
        ]

        try writeJSONObject(manifest, to: bundleURL.appendingPathComponent("manifest.json"))
        let messageData = try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
        guard let messageLine = String(data: messageData, encoding: .utf8) else {
            throw TacketAppError.nativeCapture("Could not encode native capture message.")
        }
        try (messageLine + "\n").write(to: bundleURL.appendingPathComponent("messages.jsonl"), atomically: true, encoding: .utf8)
        try transcript.write(to: bundleURL.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)
        try transcript.write(to: targetsURL.appendingPathComponent("codex.md"), atomically: true, encoding: .utf8)
        try transcript.write(to: targetsURL.appendingPathComponent("claude-code.md"), atomically: true, encoding: .utf8)
        try nativeCaptureReadme(title: title, source: source, capturedAt: capturedAt)
            .write(to: bundleURL.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        return bundleURL
    }

    private nonisolated static func cleanNativeCaptureText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func nativeCaptureTextIsUsable(_ value: String) -> Bool {
        cleanNativeCaptureText(value).count >= 20
    }

    private nonisolated static func nativeWindowText(for processIdentifier: pid_t) async throws -> String {
        if accessibilityIsTrusted(prompt: false),
           let text = try? accessibilityText(for: processIdentifier),
           nativeCaptureTextIsUsable(text) {
            return cleanNativeCaptureText(text)
        }
        let ocrText = try await ocrText(for: processIdentifier)
        return cleanNativeCaptureText(ocrText)
    }

    private nonisolated static func scrollNativeApp(processIdentifier: pid_t, deltaY: Int32, repeats: Int) async throws {
        guard repeats > 0 else { return }
        for _ in 0..<repeats {
            if let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 1,
                wheel1: deltaY,
                wheel2: 0,
                wheel3: 0
            ) {
                event.postToPid(processIdentifier)
            }
            try await Task.sleep(nanoseconds: 90_000_000)
        }
        try await Task.sleep(nanoseconds: 220_000_000)
    }

    private nonisolated static func mergeNativeCaptureSnapshots(_ snapshots: [String]) -> String {
        var seen = Set<String>()
        var lines: [String] = []
        for snapshot in snapshots {
            for rawLine in cleanNativeCaptureText(snapshot).split(separator: "\n") {
                let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
                guard line.count > 1 else { continue }
                let key = line.lowercased()
                guard !nativeCaptureChromeNoise.contains(key), !seen.contains(key) else { continue }
                seen.insert(key)
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    private nonisolated static func accessibilityIsTrusted(prompt: Bool) -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private nonisolated static func screenCaptureIsTrusted(prompt: Bool) -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        guard prompt else { return false }
        return CGRequestScreenCaptureAccess()
    }

    private nonisolated static func accessibilityText(for processIdentifier: pid_t) throws -> String {
        let appElement = AXUIElementCreateApplication(processIdentifier)
        var roots: [AXUIElement] = []
        if let focusedWindow = axElementAttribute(appElement, kAXFocusedWindowAttribute) {
            roots.append(focusedWindow)
        }
        roots.append(contentsOf: axElementArrayAttribute(appElement, kAXWindowsAttribute))
        if roots.isEmpty {
            roots.append(appElement)
        }

        var lines: [String] = []
        var seen = Set<String>()
        var visited = 0
        for root in roots {
            collectAccessibilityText(from: root, depth: 0, visited: &visited, lines: &lines, seen: &seen)
        }

        let transcript = lines.joined(separator: "\n")
        guard nativeCaptureTextIsUsable(transcript) else {
            throw TacketAppError.nativeCapture("The frontmost app window did not expose readable Accessibility text.")
        }
        return transcript
    }

    private nonisolated static func collectAccessibilityText(
        from element: AXUIElement,
        depth: Int,
        visited: inout Int,
        lines: inout [String],
        seen: inout Set<String>
    ) {
        guard depth <= 28, visited < 5000 else { return }
        visited += 1

        let role = axStringAttribute(element, kAXRoleAttribute)
        let shouldRead = readableAccessibilityRoles.contains(role)
        if shouldRead {
            for attribute in readableAccessibilityAttributes {
                appendAccessibilityText(axStringAttribute(element, attribute), lines: &lines, seen: &seen)
            }
        }

        for child in axElementArrayAttribute(element, kAXChildrenAttribute) {
            collectAccessibilityText(from: child, depth: depth + 1, visited: &visited, lines: &lines, seen: &seen)
        }
    }

    private nonisolated static var readableAccessibilityRoles: Set<String> {
        [
            kAXStaticTextRole as String,
            kAXTextAreaRole as String,
            kAXTextFieldRole as String,
            "AXWebArea"
        ]
    }

    private nonisolated static var readableAccessibilityAttributes: [String] {
        [
            kAXValueAttribute as String,
            kAXTitleAttribute as String,
            kAXDescriptionAttribute as String
        ]
    }

    private nonisolated static func appendAccessibilityText(_ value: String, lines: inout [String], seen: inout Set<String>) {
        let normalized = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in normalized {
            guard line.count > 1 else { continue }
            guard !nativeCaptureChromeNoise.contains(line.lowercased()) else { continue }
            if !seen.contains(line) {
                seen.insert(line)
                lines.append(line)
            }
        }
    }

    private nonisolated static var nativeCaptureChromeNoise: Set<String> {
        [
            "copy",
            "share",
            "edit",
            "delete",
            "retry",
            "regenerate",
            "new chat",
            "send",
            "stop",
            "search",
            "settings"
        ]
    }

    private nonisolated static func axStringAttribute(_ element: AXUIElement, _ attribute: String) -> String {
        guard let value = axAttribute(element, attribute) else { return "" }
        if let text = value as? String {
            return text
        }
        if CFGetTypeID(value) == AXValueGetTypeID() {
            return ""
        }
        return ""
    }

    private nonisolated static func axElementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = axAttribute(element, attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private nonisolated static func axElementArrayAttribute(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        guard let values = axAttribute(element, attribute) as? [AnyObject] else { return [] }
        return values.compactMap { value in
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (value as! AXUIElement)
        }
    }

    private nonisolated static func axAttribute(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else { return nil }
        return value
    }

    private nonisolated static func ocrText(for processIdentifier: pid_t) async throws -> String {
        guard let image = windowImage(for: processIdentifier) else {
            throw TacketAppError.nativeCapture("Tacket could not capture the app window for local OCR. macOS Screen Recording permission may be required.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations
                    .sorted { lhs, rhs in
                        let yDelta = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
                        if yDelta > 0.015 {
                            return lhs.boundingBox.midY > rhs.boundingBox.midY
                        }
                        return lhs.boundingBox.minX < rhs.boundingBox.minX
                    }
                    .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private nonisolated static func windowImage(for processIdentifier: pid_t) -> CGImage? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let candidates = windows.filter { window in
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == processIdentifier,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? CGFloat,
                  let height = bounds["Height"] as? CGFloat else {
                return false
            }
            return width > 320 && height > 240
        }
        guard let window = candidates.first,
              let windowNumber = window[kCGWindowNumber as String] as? CGWindowID else {
            return nil
        }
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tacket-native-capture-\(processIdentifier)-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-l", String(windowNumber), imageURL.path]
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let image = NSImage(contentsOf: imageURL) else {
                return nil
            }
            var rect = CGRect(origin: .zero, size: image.size)
            return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        } catch {
            return nil
        }
    }

    private nonisolated static func nativeCaptureTitle(from transcript: String, source: NativeCaptureSource) -> String {
        let ignored = Set([
            source.label.lowercased(),
            "new chat",
            "copy",
            "share",
            "regenerate",
            "you said:",
            "assistant said:"
        ])
        let line = transcript
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { candidate in
                candidate.count >= 8 && !ignored.contains(candidate.lowercased())
            } ?? "\(source.label) app chat"
        return sanitizeFileSegment(line, maxLength: 80)
    }

    private nonisolated static func reserveNativeCaptureBundleURL(
        outputRoot: URL,
        capturedAt: Date,
        source: NativeCaptureSource,
        title: String
    ) throws -> URL {
        let baseName = [
            fileDateFormatter.string(from: capturedAt),
            source.label,
            sanitizeFileSegment(title, maxLength: 80)
        ].joined(separator: " - ")
        for index in 1..<1000 {
            let suffix = index == 1 ? "" : " (\(index))"
            let candidate = outputRoot.appendingPathComponent("\(baseName)\(suffix).tacket", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: false)
                return candidate
            } catch CocoaError.fileWriteFileExists {
                continue
            } catch {
                throw error
            }
        }
        throw TacketAppError.nativeCapture("Could not create a unique saved chat folder.")
    }

    private nonisolated static var fileDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return formatter
    }

    private nonisolated static func sanitizeFileSegment(_ value: String, maxLength: Int) -> String {
        let forbidden = CharacterSet(charactersIn: #"<>:"/\|?*"#).union(.controlCharacters)
        let cleaned = value
            .components(separatedBy: forbidden)
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ". ")))
        let limited = String(cleaned.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return limited.isEmpty ? "Untitled Thread" : limited
    }

    private nonisolated static func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        var data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        data.append(Data("\n".utf8))
        try data.write(to: url)
    }

    private nonisolated static func nativeCaptureReadme(title: String, source: NativeCaptureSource, capturedAt: String) -> String {
        """
        # \(title)

        This is a local Tacket saved chat captured from the \(source.label) desktop app.

        - Open `transcript.md` to read the copied conversation text.
        - `targets/` contains ready-to-transfer conversation files for supported tools.
        - `manifest.json` and `messages.jsonl` are used by Tacket to verify and search the saved chat.

        Source: \(source.label) desktop app
        Captured: \(capturedAt)
        """
    }

    private nonisolated static func appleScriptErrorMessage(_ error: NSDictionary) -> String {
        if let message = error["NSAppleScriptErrorMessage"] as? String {
            return message
        }
        return "macOS automation failed. Tacket may need Accessibility permission in System Settings."
    }

    private nonisolated static func indexLibraryFolder(_ folder: URL) throws -> (found: Int, indexed: Int) {
        try Self.ensureLibraryDatabase()
        let bundles = try Self.findTacketBundles(in: folder)
        var indexed = 0
        for bundle in bundles {
            if try Self.indexLibraryBundle(bundle) {
                indexed += 1
            }
        }
        return (bundles.count, indexed)
    }

    private nonisolated static func findTacketBundles(in folder: URL) throws -> [URL] {
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

    private nonisolated static func indexLibraryBundle(_ bundleURL: URL) throws -> Bool {
        let manifestURL = bundleURL.appendingPathComponent("manifest.json")
        let messagesURL = bundleURL.appendingPathComponent("messages.jsonl")
        let transcriptURL = bundleURL.appendingPathComponent("transcript.md")
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any] ?? [:]
        let source = manifest["source"] as? [String: Any] ?? [:]
        let transcript = try String(contentsOf: transcriptURL, encoding: .utf8)
        let transcriptHash = Self.sha256(transcript)
        let bundleId = manifest["id"] as? String ?? Self.stableLibraryId(bundleURL.path)

        if let existing = try Self.queryLibraryHash(path: bundleURL.path), existing == transcriptHash {
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

        try Self.withLibraryDatabase { db in
            try Self.sqliteExec(db, "BEGIN;")
            try Self.sqliteExec(db, "DELETE FROM messages_fts WHERE bundle_id = \(Self.sqliteQuote(bundleId));")
            try Self.sqliteExec(db, "DELETE FROM messages WHERE bundle_id = \(Self.sqliteQuote(bundleId));")
            try Self.sqliteExec(db, "DELETE FROM bundles WHERE path = \(Self.sqliteQuote(bundleURL.path)) OR id = \(Self.sqliteQuote(bundleId));")
            try Self.sqliteExec(db, """
                INSERT INTO bundles (id, path, title, platform, url, captured_at, message_count, indexed_at, transcript_hash)
                VALUES (
                  \(Self.sqliteQuote(bundleId)),
                  \(Self.sqliteQuote(bundleURL.path)),
                  \(Self.sqliteQuote(title)),
                  \(Self.sqliteQuote(platform)),
                  \(Self.sqliteQuote(url)),
                  \(Self.sqliteQuote(capturedAt)),
                  \(messageCount),
                  \(Self.sqliteQuote(indexedAt)),
                  \(Self.sqliteQuote(transcriptHash))
                );
                """)
            for message in messages {
                try Self.sqliteExec(db, """
                    INSERT INTO messages (id, bundle_id, role, text, ordinal)
                    VALUES (
                      \(Self.sqliteQuote(message.id)),
                      \(Self.sqliteQuote(bundleId)),
                      \(Self.sqliteQuote(message.role)),
                      \(Self.sqliteQuote(message.text)),
                      \(message.ordinal)
                    );
                    INSERT INTO messages_fts (bundle_id, message_id, title, platform, role, text)
                    VALUES (
                      \(Self.sqliteQuote(bundleId)),
                      \(Self.sqliteQuote(message.id)),
                      \(Self.sqliteQuote(title)),
                      \(Self.sqliteQuote(platform)),
                      \(Self.sqliteQuote(message.role)),
                      \(Self.sqliteQuote(message.text))
                    );
                    """)
            }
            try Self.sqliteExec(db, "COMMIT;")
        }
        return true
    }

    private nonisolated static func ensureLibraryDatabase() throws {
        try FileManager.default.createDirectory(at: Self.appSupportDirectoryURL, withIntermediateDirectories: true)
        try Self.withLibraryDatabase { db in
            try Self.sqliteExec(db, """
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
            if Self.supportsFTS5(db) {
                try Self.sqliteExec(db, """
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
                try Self.sqliteExec(db, """
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

    private func queryLibrary(search: String) throws -> [LibraryItem] {
        try Self.ensureLibraryDatabase()
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasFilters = librarySourceFilter != .all || libraryRoleFilter != .all || librarySearchScope != .everywhere
        if trimmed.isEmpty && !hasFilters {
            return try Self.queryLibraryItems("""
                SELECT id, path, title, platform, url, captured_at, message_count, indexed_at, '' AS snippet
                FROM bundles
                ORDER BY captured_at DESC, indexed_at DESC
                LIMIT 100;
                """)
        }
        if libraryMatchMode == .phrase,
           librarySearchScope == .everywhere,
           librarySourceFilter == .all,
           libraryRoleFilter == .all,
           !trimmed.isEmpty,
           try Self.libraryUsesFTS5() {
            let query = "\"\(trimmed.replacingOccurrences(of: "\"", with: "\"\""))\""
            return try Self.queryLibraryItems("""
                SELECT b.id, b.path, b.title, b.platform, b.url, b.captured_at, b.message_count, b.indexed_at,
                       snippet(messages_fts, 5, '[', ']', ' ... ', 18) AS snippet
                FROM messages_fts
                JOIN bundles b ON b.id = messages_fts.bundle_id
                WHERE messages_fts MATCH \(Self.sqliteQuote(query))
                  AND messages_fts.rowid IN (
                    SELECT min(rowid)
                    FROM messages_fts
                    WHERE messages_fts MATCH \(Self.sqliteQuote(query))
                    GROUP BY bundle_id
                  )
                ORDER BY rank
                LIMIT 100;
                """)
        }

        let conditions = librarySearchConditions(for: trimmed)
        let whereClause = conditions.isEmpty ? "1 = 1" : conditions.joined(separator: "\n              AND ")
        let snippetExpression = librarySearchScope == .title ? "b.title" : "m.text"
        return try Self.queryLibraryItems("""
            SELECT b.id, b.path, b.title, b.platform, b.url, b.captured_at, b.message_count, b.indexed_at,
                   substr(\(snippetExpression), 1, 240) AS snippet
            FROM messages_fts m
            JOIN bundles b ON b.id = m.bundle_id
            WHERE \(whereClause)
              AND m.rowid IN (
                SELECT min(rowid)
                FROM messages_fts
                WHERE \(whereClause.replacingOccurrences(of: "m.", with: "").replacingOccurrences(of: "b.", with: ""))
                GROUP BY bundle_id
              )
            ORDER BY b.captured_at DESC, b.indexed_at DESC
            LIMIT 100;
            """)
    }

    private func librarySearchConditions(for search: String) -> [String] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var conditions: [String] = []

        if !trimmed.isEmpty {
            let expression = librarySearchExpression()
            switch libraryMatchMode {
            case .phrase:
                conditions.append("\(expression) LIKE \(Self.sqliteQuote(Self.sqliteLikePattern(trimmed))) ESCAPE '\\'")
            case .allTerms:
                for term in librarySearchTerms(trimmed) {
                    conditions.append("\(expression) LIKE \(Self.sqliteQuote(Self.sqliteLikePattern(term))) ESCAPE '\\'")
                }
            case .anyTerm:
                let parts = librarySearchTerms(trimmed).map {
                    "\(expression) LIKE \(Self.sqliteQuote(Self.sqliteLikePattern($0))) ESCAPE '\\'"
                }
                if !parts.isEmpty {
                    conditions.append("(\(parts.joined(separator: " OR ")))")
                }
            }
        }

        if librarySourceFilter != .all {
            conditions.append("lower(b.platform) = \(Self.sqliteQuote(librarySourceFilter.rawValue))")
        }

        if libraryRoleFilter != .all {
            conditions.append("lower(m.role) = \(Self.sqliteQuote(libraryRoleFilter.rawValue))")
        }

        return conditions
    }

    private func librarySearchExpression() -> String {
        switch librarySearchScope {
        case .everywhere:
            "lower(m.text || ' ' || m.title || ' ' || m.platform || ' ' || m.role)"
        case .transcript:
            "lower(m.text)"
        case .title:
            "lower(m.title)"
        }
    }

    private func librarySearchTerms(_ value: String) -> [String] {
        value
            .split { $0.isWhitespace }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private nonisolated static func queryLibraryItems(_ sql: String) throws -> [LibraryItem] {
        try Self.withLibraryDatabase { db in
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw TacketAppError.libraryDatabase(Self.sqliteError(db))
            }
            defer { sqlite3_finalize(statement) }
            var items: [LibraryItem] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                items.append(LibraryItem(
                    id: Self.sqliteColumnText(statement, 0),
                    path: Self.sqliteColumnText(statement, 1),
                    title: Self.sqliteColumnText(statement, 2),
                    platform: Self.sqliteColumnText(statement, 3),
                    url: Self.sqliteColumnText(statement, 4),
                    capturedAt: Self.sqliteColumnText(statement, 5),
                    messageCount: Int(sqlite3_column_int(statement, 6)),
                    indexedAt: Self.sqliteColumnText(statement, 7),
                    snippet: Self.sqliteColumnText(statement, 8)
                ))
            }
            return items
        }
    }

    private nonisolated static func queryLibraryHash(path: String) throws -> String? {
        try Self.withLibraryDatabase { db in
            let sql = "SELECT transcript_hash FROM bundles WHERE path = \(Self.sqliteQuote(path)) LIMIT 1;"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw TacketAppError.libraryDatabase(Self.sqliteError(db))
            }
            defer { sqlite3_finalize(statement) }
            if sqlite3_step(statement) == SQLITE_ROW {
                return Self.sqliteColumnText(statement, 0)
            }
            return nil
        }
    }

    private nonisolated static func removeLibraryBundle(id: String) throws {
        try Self.withLibraryDatabase { db in
            try Self.sqliteExec(db, "DELETE FROM messages_fts WHERE bundle_id = \(Self.sqliteQuote(id));")
            try Self.sqliteExec(db, "DELETE FROM messages WHERE bundle_id = \(Self.sqliteQuote(id));")
            try Self.sqliteExec(db, "DELETE FROM bundles WHERE id = \(Self.sqliteQuote(id));")
        }
    }

    private nonisolated static func withLibraryDatabase<T>(_ body: (OpaquePointer?) throws -> T) throws -> T {
        var db: OpaquePointer?
        guard sqlite3_open(Self.libraryDatabaseFileURL.path, &db) == SQLITE_OK else {
            defer { sqlite3_close(db) }
            throw TacketAppError.libraryDatabase(Self.sqliteError(db))
        }
        defer { sqlite3_close(db) }
        return try body(db)
    }

    private nonisolated static func sqliteExec(_ db: OpaquePointer?, _ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? Self.sqliteError(db)
            sqlite3_free(error)
            throw TacketAppError.libraryDatabase(message)
        }
    }

    private nonisolated static func messageText(from json: [String: Any]) -> String {
        let parts = json["content"] as? [[String: Any]] ?? []
        return parts
            .filter { ($0["type"] as? String) == "text" || ($0["type"] as? String) == "code" }
            .map { $0["text"] as? String ?? "" }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func stableLibraryId(_ value: String) -> String {
        String(Self.sha256(value).prefix(16))
    }

    private nonisolated static func sqliteQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private nonisolated static func sqliteLikePattern(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%\(escaped)%"
    }

    private nonisolated static func supportsFTS5(_ db: OpaquePointer?) -> Bool {
        do {
            try Self.sqliteExec(db, "CREATE VIRTUAL TABLE temp.tacket_fts_probe USING fts5(value);")
            try Self.sqliteExec(db, "DROP TABLE temp.tacket_fts_probe;")
            return true
        } catch {
            return false
        }
    }

    private nonisolated static func libraryUsesFTS5() throws -> Bool {
        try Self.withLibraryDatabase { db in
            let sql = "SELECT sql FROM sqlite_master WHERE name = 'messages_fts' LIMIT 1;"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw TacketAppError.libraryDatabase(Self.sqliteError(db))
            }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { return false }
            return Self.sqliteColumnText(statement, 0).lowercased().contains("using fts5")
        }
    }

    private nonisolated static func sqliteError(_ db: OpaquePointer?) -> String {
        guard let message = sqlite3_errmsg(db) else { return "Unknown SQLite error." }
        return String(cString: message)
    }

    private nonisolated static func sqliteColumnText(_ statement: OpaquePointer?, _ index: Int32) -> String {
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
            try FileManager.default.createDirectory(at: Self.appSupportDirectoryURL, withIntermediateDirectories: true)
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
            let footer = number == chunks.count ? "[conversation complete]" : "Please acknowledge receipt only."
            return "[conversation chunk \(number) of \(chunks.count)]\n\n\(chunk)\n\n\(footer)"
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
                return "Copied \(chunkCount) conversation chunk(s). Terminal automation timed out."
            }
            if process.terminationStatus == 0 {
                return "Copied \(chunkCount) conversation chunk(s), launched \(command), and requested paste into Terminal."
            }
            return "Copied \(chunkCount) conversation chunk(s). Terminal automation exited with \(process.terminationStatus)."
        } catch {
            return "Copied \(chunkCount) conversation chunk(s). Terminal automation failed: \(error.localizedDescription)"
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
    case nativeCapture(String)

    var errorDescription: String? {
        switch self {
        case .nativeHostMissing:
            return "TacketNativeHost was not found. Build the Mac package or run `swift build` in apps/mac/TacketApp."
        case .invalidBundle(let message):
            return "Saved chat is missing required files: \(message)"
        case .libraryDatabase(let message):
            return "Library database error: \(message)"
        case .nativeCapture(let message):
            return "Native app capture error: \(message)"
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

private func friendlyDate(_ value: String) -> String {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]

    guard let date = fractional.date(from: value) ?? plain.date(from: value) else {
        return value
    }

    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: TacketModel
    @State private var selectedSection: AppSection = .library

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            Divider()
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    SidebarView(selectedSection: $selectedSection)
                    Divider()
                    SidebarFooterView(selectedSection: $selectedSection)
                        .frame(height: 44)
                }
                    .frame(width: 220)
                Divider()
                VStack(spacing: 0) {
                    switch selectedSection {
                    case .library:
                        LibraryPanelView()
                    case .settings:
                        SettingsPanelView()
                    }
                    Divider()
                    ContentFooterView()
                        .frame(height: 14)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(TacketColors.window)
        .tint(TacketColors.accent)
    }
}

enum AppSection {
    case library
    case settings
}

struct HeaderView: View {
    @EnvironmentObject private var model: TacketModel

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            AppMark()
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("Tacket")
                    .font(.tacketTitle)
                Text("Save, search, and transfer AI chats locally.")
                    .font(.tacketBody)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            HeaderButton(title: "Captures", action: model.revealCaptureDirectory)
            HeaderButton(title: "Docs", action: model.openDocs)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

struct SidebarView: View {
    @Binding var selectedSection: AppSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SidebarSection(title: "Flow") {
                    WorkflowStep(number: "1", title: "Save", detail: "Save from browser or app.")
                    WorkflowStep(number: "2", title: "Find", detail: "Browse or narrow saved tackets.")
                    WorkflowStep(number: "3", title: "Transfer", detail: "Copy or send the saved chat.")
                }

                SidebarSection(title: "Library") {
                    SidebarNavRow(title: "All Tackets", systemImage: "square.grid.2x2", isSelected: selectedSection == .library)
                        .onTapGesture {
                            selectedSection = .library
                        }
                }
            }
            .padding(16)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(TacketColors.sidebar)
    }
}

struct SidebarFooterView: View {
    @Binding var selectedSection: AppSection

    var body: some View {
        HStack {
            SidebarNavRow(title: "Settings", systemImage: "gearshape", isSelected: selectedSection == .settings)
                .onTapGesture {
                    selectedSection = .settings
                }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TacketColors.sidebar)
    }
}

struct ContentFooterView: View {
    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TacketColors.window)
    }
}

struct MainPanelView: View {
    @EnvironmentObject private var model: TacketModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StatusBanner(status: model.status)

                SectionCard(
                    eyebrow: "Saved chats",
                    title: "Saved chats",
                    detail: "Choose where Tacket stores conversations saved from ChatGPT, Claude, and Gemini."
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        PathField(label: "Save folder", value: model.captureDirectory.path)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Button("Reveal Folder") {
                                    model.revealCaptureDirectory()
                                }
                                Button("Choose Save Folder") {
                                    model.chooseCaptureDirectory()
                                }
                            }
                            HStack(spacing: 10) {
                                Button("Reset Folder") {
                                    model.resetCaptureDirectory()
                                }
                                Button("Choose Saved Chat") {
                                    model.chooseBundle()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }

                        if let bundle = model.selectedBundle {
                            PathField(label: "Selected saved chat", value: bundle.path)
                        } else {
                            EmptyStateText("No saved chat selected yet.")
                        }

                        if let info = model.selectedBundleInfo {
                            BundleSummary(info: info)
                        }
                    }
                }

                SectionCard(
                    eyebrow: "Transfer",
                    title: "Send a saved conversation",
                    detail: "Choose where to send the full conversation. Tacket keeps message order and code blocks intact."
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
                            Text("Used only when a conversation is too long for one paste.")
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
                                Button("Copy Conversation") {
                                    model.copySelectedTranscript()
                                }
                            }
                            HStack(spacing: 10) {
                                Button("Open Conversation File") {
                                    model.openSelectedTranscript()
                                }
                                Button("Reveal in Finder") {
                                    model.revealSelectedBundle()
                                }
                            }
                        }
                    }
                }

                OutputPanel()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: 850, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(TacketColors.content)
    }
}

struct LibraryPanelView: View {
    @EnvironmentObject private var model: TacketModel
    @State private var showAdvancedSearch = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    StatusBanner(status: model.status)

                    SectionCard(
                        eyebrow: "Save",
                        title: "Save chats from browser tabs or desktop apps",
                        detail: "Use the Chrome extension for ChatGPT, Claude, and Gemini in the browser. For desktop apps, open the chat, click inside the conversation, then capture it locally from Tacket."
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                HeaderButton(title: "Open ChatGPT", action: model.openChatGPT)
                                HeaderButton(title: "Open Claude", action: model.openClaude)
                                HeaderButton(title: "Open Gemini", action: model.openGemini)
                            }

                            Divider()

                            HStack(spacing: 10) {
                                ForEach(TacketModel.NativeCaptureSource.allCases) { source in
                                    Button {
                                        model.captureNativeApp(source)
                                    } label: {
                                        Label(source.label, systemImage: "macwindow")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(model.isRunning)
                                    .help("Capture the open \(source.label) desktop app chat")
                                }
                            }

                            Text("Native capture reads the open desktop app locally with macOS Accessibility and on-device OCR, then saves it as a .tacket folder.")
                                .font(.tacketFootnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 10) {
                                Button("Accessibility Settings") {
                                    model.openAccessibilitySettings()
                                }
                                Button("Screen Recording Settings") {
                                    model.openScreenRecordingSettings()
                                }
                            }
                        }
                    }

                    SectionCard(
                        eyebrow: "Library",
                        title: "All Tackets",
                        detail: "Browse every saved chat in your local library. Search and filters narrow the list without sending anything off this Mac."
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                SearchBox(text: $model.librarySearchText)
                                    .onSubmit {
                                        model.searchLibrary()
                                    }
                                    .onChange(of: model.librarySearchText) { _ in
                                        model.searchLibrary()
                                    }

                                Button {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        showAdvancedSearch.toggle()
                                    }
                                } label: {
                                    Label("Advanced", systemImage: "slider.horizontal.3")
                                        .labelStyle(.iconOnly)
                                }
                                .buttonStyle(.bordered)
                                .help("Advanced search")
                                .accessibilityLabel("Advanced search")
                            }

                            Picker("View", selection: $model.libraryViewMode) {
                                ForEach(TacketModel.LibraryViewMode.allCases) { mode in
                                    Text(mode.label).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 240)

                            if showAdvancedSearch {
                                AdvancedSearchPanel()
                                    .transition(.opacity)
                            }

                            HStack(spacing: 10) {
                                Button {
                                    model.indexCaptureFolderForLibrary()
                                } label: {
                                    Label("Add Saved Chats", systemImage: "tray.and.arrow.down")
                                }
                                .buttonStyle(.borderedProminent)

                                Menu {
                                    Button("Add Another Folder") {
                                        model.chooseFolderAndIndexLibrary()
                                    }
                                    Button("Refresh Library") {
                                        model.refreshLibrary()
                                    }
                                    Button("Remove Missing Chats") {
                                        model.removeMissingLibraryBundles()
                                    }
                                } label: {
                                    Label("More", systemImage: "ellipsis.circle")
                                }
                            }

                            HStack(spacing: 8) {
                                MetadataPill(text: "\(model.libraryItems.count) shown")
                                if model.advancedSearchIsActive {
                                    MetadataPill(text: "advanced")
                                }
                                Text(model.libraryStatus)
                                    .font(.tacketFootnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    libraryContent(isWide: geometry.size.width >= 780)

                    OutputPanel()
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(TacketColors.content)
            .onAppear {
                model.refreshLibrary()
            }
        }
    }

    @ViewBuilder
    private func libraryContent(isWide: Bool) -> some View {
        if model.libraryViewMode == .gallery {
            VStack(alignment: .leading, spacing: 14) {
                resultsCard

                if let item = model.selectedLibraryItem {
                    LibraryDetailCard(item: item)
                }
            }
        } else if isWide {
            HStack(alignment: .top, spacing: 14) {
                resultsCard
                    .frame(minWidth: 300, maxWidth: .infinity)

                if let item = model.selectedLibraryItem {
                    LibraryDetailCard(item: item)
                        .frame(minWidth: 280, maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                resultsCard

                if let item = model.selectedLibraryItem {
                    LibraryDetailCard(item: item)
                }
            }
        }
    }

    private var resultsCard: some View {
        SectionCard(
            eyebrow: model.libraryIsFiltered ? "Filtered Tackets" : "All Tackets",
            title: "\(model.libraryItems.count) tacket\(model.libraryItems.count == 1 ? "" : "s")",
            detail: resultsDetail
        ) {
            Group {
                if model.libraryItems.isEmpty {
                    LibraryEmptyState {
                        model.indexCaptureFolderForLibrary()
                    }
                } else if model.libraryViewMode == .gallery {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                        ForEach(model.libraryItems) { item in
                            LibraryGalleryCard(item: item, isSelected: model.selectedLibraryItem?.id == item.id)
                                .onTapGesture {
                                    model.selectLibraryItem(item)
                                }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.libraryItems) { item in
                            LibraryResultRow(item: item, isSelected: model.selectedLibraryItem?.id == item.id)
                                .onTapGesture {
                                    model.selectLibraryItem(item)
                                }
                        }
                    }
                }
            }
        }
    }

    private var resultsDetail: String {
        let trimmed = model.librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && !model.advancedSearchIsActive {
            return "Every saved chat, newest first."
        }
        if trimmed.isEmpty {
            return "Filtered saved chats."
        }
        return "Matches for “\(trimmed)”"
    }
}

struct AdvancedSearchPanel: View {
    @EnvironmentObject private var model: TacketModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Advanced search")
                    .font(.tacketLabel)
                    .foregroundStyle(TacketColors.accent)
                Spacer()
                Button("Reset") {
                    model.resetAdvancedSearch()
                }
                .buttonStyle(.plain)
                .font(.tacketFootnote.weight(.semibold))
                .foregroundStyle(TacketColors.accent)
                .disabled(!model.advancedSearchIsActive)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], alignment: .leading, spacing: 10) {
                AdvancedPicker(
                    title: "Match",
                    selection: $model.libraryMatchMode,
                    options: TacketModel.LibraryMatchMode.allCases
                )
                AdvancedPicker(
                    title: "Search in",
                    selection: $model.librarySearchScope,
                    options: TacketModel.LibrarySearchScope.allCases
                )
                AdvancedPicker(
                    title: "Source",
                    selection: $model.librarySourceFilter,
                    options: TacketModel.LibrarySourceFilter.allCases
                )
                AdvancedPicker(
                    title: "Role",
                    selection: $model.libraryRoleFilter,
                    options: TacketModel.LibraryRoleFilter.allCases
                )
            }
        }
        .padding(12)
        .background(TacketColors.recessed)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(TacketColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onChange(of: model.libraryMatchMode) { _ in model.searchLibrary() }
        .onChange(of: model.librarySearchScope) { _ in model.searchLibrary() }
        .onChange(of: model.librarySourceFilter) { _ in model.searchLibrary() }
        .onChange(of: model.libraryRoleFilter) { _ in model.searchLibrary() }
    }
}

struct AdvancedPicker<Option: Identifiable & Hashable>: View where Option.ID == String {
    let title: String
    @Binding var selection: Option
    let options: [Option]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.tacketLabel)
                .foregroundStyle(.secondary)
            Picker(title, selection: $selection) {
                ForEach(options) { option in
                    Text(optionLabel(option)).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func optionLabel(_ option: Option) -> String {
        switch option {
        case let value as TacketModel.LibraryMatchMode:
            value.label
        case let value as TacketModel.LibrarySearchScope:
            value.label
        case let value as TacketModel.LibrarySourceFilter:
            value.label
        case let value as TacketModel.LibraryRoleFilter:
            value.label
        default:
            option.id
        }
    }
}

struct SearchBox: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search chats, code, decisions, errors...", text: $text)
                .textFieldStyle(.plain)
                .font(.tacketBody)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(TacketColors.recessed)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(TacketColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct LibraryEmptyState: View {
    let indexAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(TacketColors.accent)
                Text("No matching chats yet")
                    .font(.tacketBody.weight(.semibold))
            }
            Text("Add your saved chats to the Library, then search for a title, code snippet, decision, or error message.")
                .font(.tacketFootnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add Saved Chats", action: indexAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TacketColors.recessed)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct LibraryDetailCard: View {
    @EnvironmentObject private var model: TacketModel
    let item: LibraryItem

    var body: some View {
        SectionCard(
            eyebrow: "Selected",
            title: item.title,
            detail: "\(item.platform.capitalized) · \(item.messageCount) messages · Saved \(friendlyDate(item.capturedAt))"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if !item.snippet.isEmpty {
                    Text(cleanLibrarySnippet(item.snippet))
                        .font(.tacketBody)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .lineLimit(7)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(TacketColors.recessed)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                PathField(label: "Saved chat folder", value: item.path)

                HStack(spacing: 8) {
                    Button {
                        model.transferLibraryItem(item)
                    } label: {
                        Label("Transfer", systemImage: "arrow.right.doc.on.clipboard")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isRunning)

                    Button {
                        model.copyLibraryTranscript(item)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        model.openLibraryTranscript(item)
                    } label: {
                        Label("Open", systemImage: "doc.text")
                    }
                    Button {
                        model.revealLibraryItem(item)
                    } label: {
                        Label("Reveal", systemImage: "folder")
                    }
                }
            }
        }
    }

}

struct MetadataPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.tacketFootnote.weight(.semibold))
            .foregroundStyle(TacketColors.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(TacketColors.selected)
            .clipShape(Capsule())
    }
}

struct SettingsPanelView: View {
    @EnvironmentObject private var model: TacketModel
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StatusBanner(status: model.status)

                SectionCard(
                    eyebrow: "Appearance",
                    title: "Theme",
                    detail: "Choose whether Tacket follows macOS or uses a fixed light or dark appearance."
                ) {
                    Picker("Theme", selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)
                }

                SectionCard(
                    eyebrow: "Settings",
                    title: "Save location",
                    detail: "Choose where Tacket saves conversations on this Mac."
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        PathField(label: "Save folder", value: model.captureDirectory.path)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Button("Reveal Folder") {
                                    model.revealCaptureDirectory()
                                }
                                Button("Choose Save Folder") {
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
                    title: "Chrome extension connection",
                    detail: "Connect the Chrome extension to the Tacket app so conversations can be saved locally."
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
                            Text("Manual extension IDs are only needed for development builds. The public Chrome Web Store extension will connect automatically.")
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
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)
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
                Text("No local warnings for this saved chat.")
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
        if !model.commandOutput.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Details")
                    .font(.tacketLabel)
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(model.commandOutput)
                        .font(.tacketMono)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(minHeight: 96, maxHeight: 170)
                .background(TacketColors.recessed)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
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

struct LibraryGalleryCard: View {
    let item: LibraryItem
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? TacketColors.accent : .secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.tacketBody.weight(.semibold))
                        .lineLimit(2)
                    Text(item.platform.capitalized)
                        .font(.tacketFootnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Text("\(item.messageCount) messages")
                .font(.tacketFootnote)
                .foregroundStyle(.secondary)

            Text("Saved \(friendlyDate(item.capturedAt))")
                .font(.tacketFootnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !item.snippet.isEmpty {
                Text(cleanLibrarySnippet(item.snippet))
                    .font(.tacketFootnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(isSelected ? TacketColors.selected : TacketColors.recessed)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? TacketColors.accent.opacity(0.55) : TacketColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct LibraryResultRow: View {
    let item: LibraryItem
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? TacketColors.accent : .secondary)
                    .frame(width: 16)
                Text(item.title)
                    .font(.tacketBody.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text(item.platform)
                    .font(.tacketFootnote)
                    .foregroundStyle(.secondary)
            }
            Text("\(item.messageCount) messages · Saved \(friendlyDate(item.capturedAt))")
                .font(.tacketFootnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if !item.snippet.isEmpty {
                Text(cleanLibrarySnippet(item.snippet))
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

private func cleanLibrarySnippet(_ value: String) -> String {
    value
        .replacingOccurrences(of: "[", with: "")
        .replacingOccurrences(of: "]", with: "")
}

struct SidebarNavRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? TacketColors.accent : .secondary)
                .frame(width: 16)
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

private func cleanLibrarySnippet(_ value: String) -> String {
    value
        .replacingOccurrences(of: "[", with: "")
        .replacingOccurrences(of: "]", with: "")
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
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let scale = side / 512

            ZStack {
                RoundedRectangle(cornerRadius: 108 * scale)
                    .fill(TacketColors.accent)
                    .frame(width: side, height: side)

                Group {
                    Path { path in
                        path.move(to: CGPoint(x: 321 * scale, y: 329 * scale))
                        path.addLine(to: CGPoint(x: 335 * scale, y: 315 * scale))
                        path.addLine(to: CGPoint(x: 411 * scale, y: 405 * scale))
                        path.closeSubpath()
                    }
                    .fill(TacketColors.pin)

                    Path { path in
                        path.move(to: CGPoint(x: 328 * scale, y: 322 * scale))
                        path.addLine(to: CGPoint(x: 335 * scale, y: 315 * scale))
                        path.addLine(to: CGPoint(x: 411 * scale, y: 405 * scale))
                        path.closeSubpath()
                    }
                    .fill(TacketColors.pinDark)

                    RoundedRectangle(cornerRadius: 24 * scale)
                        .fill(Color(red: 0.98, green: 0.98, blue: 0.97))
                        .frame(width: 262 * scale, height: 154 * scale)
                        .offset(x: (273 - 256) * scale, y: (256 - 256) * scale)

                    VStack(spacing: 30 * scale) {
                        Capsule().fill(TacketColors.paperLine).frame(width: 174 * scale, height: 8 * scale)
                        Capsule().fill(TacketColors.paperLine).frame(width: 174 * scale, height: 8 * scale)
                        Capsule().fill(TacketColors.paperLine).frame(width: 174 * scale, height: 8 * scale)
                    }
                    .offset(x: (273 - 256) * scale, y: (279 - 256) * scale)

                    Path { path in
                        path.move(to: CGPoint(x: 213 * scale, y: 223 * scale))
                        path.addLine(to: CGPoint(x: 223 * scale, y: 213 * scale))
                        path.addLine(to: CGPoint(x: 259 * scale, y: 251 * scale))
                        path.addLine(to: CGPoint(x: 249 * scale, y: 261 * scale))
                        path.closeSubpath()
                    }
                    .fill(TacketColors.pin)

                    Path { path in
                        path.move(to: CGPoint(x: 223 * scale, y: 213 * scale))
                        path.addLine(to: CGPoint(x: 259 * scale, y: 251 * scale))
                        path.addLine(to: CGPoint(x: 254 * scale, y: 256 * scale))
                        path.closeSubpath()
                    }
                    .fill(TacketColors.pinDark)

                    Circle()
                        .fill(TacketColors.pin)
                        .frame(width: 136 * scale, height: 136 * scale)
                        .offset(x: (169 - 256) * scale, y: (175 - 256) * scale)

                    Circle()
                        .fill(Color.white.opacity(0.45))
                        .frame(width: 24 * scale, height: 24 * scale)
                        .offset(x: (139 - 256) * scale, y: (145 - 256) * scale)
                }
                .offset(x: -19 * scale, y: -15 * scale)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

enum TacketColors {
    static let accent = Color(red: 0.04, green: 0.36, blue: 0.56)
    static let selected = Color(red: 0.04, green: 0.36, blue: 0.56).opacity(0.12)
    static let pin = Color(red: 0.96, green: 0.74, blue: 0.34)
    static let pinDark = Color(red: 1.00, green: 0.75, blue: 0.28)
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
