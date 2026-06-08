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
    @AppStorage("quickCaptureMenuBarEnabled") private var quickCaptureMenuBarEnabled = false
    @AppStorage("quickCaptureOpenPreviewWindow") private var quickCaptureOpenPreviewWindow = true

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(AppearanceMode(rawValue: appearanceMode).flatMap(\.colorScheme))
                .frame(minWidth: 780, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 940, height: 640)

        MenuBarExtra(
            "Tacket",
            systemImage: "pin.fill",
            isInserted: $quickCaptureMenuBarEnabled
        ) {
            QuickCaptureMenuView(openPreviewWindow: quickCaptureOpenPreviewWindow)
                .environmentObject(model)
        }
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

    enum LocalAgentSource: String, CaseIterable, Identifiable {
        case codex
        case claudeApp = "claude-app"
        case claudeCode = "claude-code"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .codex: "Codex App"
            case .claudeApp: "Claude App"
            case .claudeCode: "Claude Code"
            }
        }

        var platform: String {
            switch self {
            case .codex: "codex"
            case .claudeApp: "claude"
            case .claudeCode: "claude"
            }
        }

        var sourceURLPrefix: String {
            switch self {
            case .codex: "codex-session://"
            case .claudeApp: "claude-app-conversation://"
            case .claudeCode: "claude-code-session://"
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
    @Published var libraryMatchMode: LibraryMatchMode = .phrase
    @Published var librarySearchScope: LibrarySearchScope = .everywhere
    @Published var librarySourceFilter: LibrarySourceFilter = .all
    @Published var libraryRoleFilter: LibraryRoleFilter = .all
    @Published var libraryViewMode: LibraryViewMode = .gallery
    @Published var libraryItems: [LibraryItem] = []
    @Published var selectedLibraryItem: LibraryItem?
    @Published var libraryStatus = "Add your saved chats to the Library to search them."
    @Published var pendingNativeCaptureDraft: NativeCaptureDraft?
    @Published var libraryPage = 0

    let libraryPageSize = 12

    let supportedSources = ["ChatGPT", "Claude", "Gemini", "Codex"]
    static let publishedChromeExtensionId = "cbpgfpcajomllnfoigagibafblmnbbdh"
    static let publishedChromeExtensionOrigin = "chrome-extension://cbpgfpcajomllnfoigagibafblmnbbdh/"
    static let chromeWebStoreURL = "https://chromewebstore.google.com/detail/tacket/cbpgfpcajomllnfoigagibafblmnbbdh"

    var advancedSearchIsActive: Bool {
        libraryMatchMode != .phrase ||
        librarySearchScope != .everywhere ||
        librarySourceFilter != .all ||
        libraryRoleFilter != .all
    }

    var libraryIsFiltered: Bool {
        !librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || advancedSearchIsActive
    }

    var libraryPageCount: Int {
        max(1, Int(ceil(Double(libraryItems.count) / Double(libraryPageSize))))
    }

    var pagedLibraryItems: [LibraryItem] {
        guard !libraryItems.isEmpty else { return [] }
        let page = min(max(libraryPage, 0), libraryPageCount - 1)
        let start = page * libraryPageSize
        let end = min(start + libraryPageSize, libraryItems.count)
        guard start < end else { return [] }
        return Array(libraryItems[start..<end])
    }

    var libraryPageRangeText: String {
        guard !libraryItems.isEmpty else { return "0 of 0" }
        let start = libraryPage * libraryPageSize + 1
        let end = min((libraryPage + 1) * libraryPageSize, libraryItems.count)
        return "\(start)-\(end) of \(libraryItems.count)"
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

    func openChromeWebStore() {
        openInChrome(Self.chromeWebStoreURL)
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

    func openDesktopApp(_ source: NativeCaptureSource) {
        for bundleIdentifier in source.bundleIdentifiers {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                let configuration = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
                    DispatchQueue.main.async {
                        if let error {
                            self.status = "Could not open \(source.label)."
                            self.commandOutput = error.localizedDescription
                        } else {
                            self.status = "Opened \(source.label)."
                            self.commandOutput = "Open the chat you want to save in \(source.label), click inside the conversation, then choose Preview Current \(source.label) Chat."
                        }
                    }
                }
                return
            }
        }
        status = "\(source.label) app is not installed."
        commandOutput = "Tacket could not find the \(source.label) desktop app on this Mac. You can still save browser chats with the Chrome extension."
    }

    func showMainWindow() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        if NSApp.windows.isEmpty {
            NSApp.sendAction(Selector(("showMainWindow:")), to: nil, from: nil)
        }
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func openAccessibilitySettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openScreenRecordingSettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    func captureFrontmostNativeApp(openPreviewWindow: Bool) {
        guard !isRunning else { return }
        guard let source = frontmostNativeCaptureSource() else {
            status = "No supported chat app in front."
            commandOutput = "Bring ChatGPT, Claude, or Codex to the front with the chat you want to save, then choose Capture Frontmost Chat App from the Tacket menu bar item."
            if openPreviewWindow {
                showMainWindow()
            }
            return
        }
        captureNativeApp(source, openPreviewWindow: openPreviewWindow)
    }

    func captureNativeApp(_ source: NativeCaptureSource, openPreviewWindow: Bool = false) {
        guard !isRunning else { return }
        guard let app = runningNativeCaptureApp(for: source) else {
            status = "\(source.label) app is not open."
            commandOutput = "Open the \(source.label) desktop app, open the chat you want to save, click inside the conversation, then capture the current chat from Tacket."
            if openPreviewWindow {
                showMainWindow()
            }
            return
        }

        let accessibilityReady = Self.accessibilityIsTrusted(prompt: true)
        let screenCaptureReady = Self.screenCaptureIsTrusted(prompt: true)
        let permissionSummary = Self.nativeCapturePermissionSummary(
            accessibilityReady: accessibilityReady,
            screenCaptureReady: screenCaptureReady
        )
        guard accessibilityReady || screenCaptureReady else {
            status = "Permission needed."
            commandOutput = """
            Tacket needs Accessibility or Screen Recording permission before it can capture the current \(source.label) desktop app chat.

            \(permissionSummary)

            Open Accessibility Settings or Screen Recording Settings below, allow Tacket, quit and reopen Tacket, then try Preview Current \(source.label) Chat again.
            """
            if openPreviewWindow {
                showMainWindow()
            }
            return
        }

        isRunning = true
        status = "Preparing \(source.label) preview..."
        commandOutput = "Tacket will scroll and read the current \(app.localizedName ?? source.label) chat locally with macOS Accessibility and on-device OCR. Review the preview before saving. Nothing is uploaded.\n\n\(permissionSummary)"

        Task {
            do {
                let rawText = try await readConversationText(from: app, source: source)
                let transcript = Self.cleanNativeCaptureText(rawText)
                pendingNativeCaptureDraft = Self.nativeCaptureDraft(source: source, transcript: transcript)
                status = "Review \(source.label) capture."
                commandOutput = "Review the desktop capture preview. Save it if the visible conversation text looks right, or discard it and try again after repositioning the chat window.\n\n\(permissionSummary)"
                if openPreviewWindow {
                    showMainWindow()
                }
            } catch {
                status = "Desktop capture failed."
                commandOutput = "\(error.localizedDescription)\n\n\(permissionSummary)\n\nIf the app is open and contains a visible chat, grant Tacket Accessibility or Screen Recording permission in System Settings, quit and reopen Tacket, then try again."
                if openPreviewWindow {
                    showMainWindow()
                }
            }

            isRunning = false
        }
    }

    func saveNativeCaptureDraft() {
        guard let draft = pendingNativeCaptureDraft, !isRunning else { return }
        isRunning = true
        status = "Saving \(draft.source.label) capture..."
        Task {
            do {
                let bundleURL = try Self.writeNativeCaptureBundle(
                    source: draft.source,
                    rawText: draft.transcript,
                    outputRoot: captureDirectory
                )
                _ = try Self.indexLibraryBundle(bundleURL)
                pendingNativeCaptureDraft = nil
                librarySearchText = ""
                libraryItems = try queryLibrary(search: "")
                selectedLibraryItem = libraryItems.first(where: { $0.path == bundleURL.path }) ?? libraryItems.first
                selectedBundle = bundleURL
                loadSelectedBundleInfo()
                libraryStatus = "Saved \(draft.source.label) desktop capture."
                status = "Saved \(draft.source.label) capture."
                commandOutput = "Saved desktop capture:\n\(bundleURL.path)"
            } catch {
                status = "Save failed."
                commandOutput = error.localizedDescription
            }
            isRunning = false
        }
    }

    func discardNativeCaptureDraft() {
        guard let draft = pendingNativeCaptureDraft else { return }
        pendingNativeCaptureDraft = nil
        status = "Discarded \(draft.source.label) preview."
        commandOutput = "Nothing was saved. Open the chat, adjust the window or scroll position, then run another desktop capture preview."
    }

    func importLocalAgentSessions(_ source: LocalAgentSource) {
        guard !isRunning else { return }
        let outputRoot = captureDirectory
        isRunning = true
        status = "Importing \(source.label) transcripts..."
        commandOutput = "Tacket is reading local \(source.label) session files on this Mac and converting recent transcripts into .tacket folders. Nothing is uploaded."

        Task {
            do {
                let result = try await Task.detached {
                    try Self.importLocalAgentSessions(source, outputRoot: outputRoot)
                }.value
                librarySearchText = ""
                libraryItems = try queryLibrary(search: "")
                selectedLibraryItem = result.lastBundle.flatMap { bundleURL in
                    libraryItems.first(where: { $0.path == bundleURL.path })
                } ?? libraryItems.first
                selectedBundle = selectedLibraryItem.map { URL(fileURLWithPath: $0.path, isDirectory: true) }
                loadSelectedBundleInfo()
                libraryStatus = Self.importLibraryStatus(result, source: source)
                status = "Imported \(source.label) transcripts."
                commandOutput = Self.importCommandOutput(result, source: source)
            } catch {
                status = "Import failed."
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

    private func frontmostNativeCaptureSource() -> NativeCaptureSource? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return nil
        }
        if let bundleIdentifier = app.bundleIdentifier {
            for source in NativeCaptureSource.allCases where source.bundleIdentifiers.contains(bundleIdentifier) {
                return source
            }
        }
        guard let name = app.localizedName?.lowercased() else { return nil }
        return NativeCaptureSource.allCases.first { source in
            source.appNames.contains { name == $0.lowercased() }
        }
    }

    private func readConversationText(from app: NSRunningApplication, source: NativeCaptureSource) async throws -> String {
        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        try await Task.sleep(nanoseconds: 450_000_000)

        var snapshots: [String] = []
        var lastMergedSnapshot = ""
        var stableMergeCount = 0
        try await Self.scrollNativeApp(processIdentifier: app.processIdentifier, deltaY: 9, repeats: 8)
        for _ in 0..<10 {
            if let text = try? await Self.nativeWindowText(for: app.processIdentifier),
               Self.nativeCaptureTextIsUsable(text) {
                snapshots.append(text)
                let merged = Self.mergeNativeCaptureSnapshots(snapshots)
                if merged == lastMergedSnapshot {
                    stableMergeCount += 1
                } else {
                    stableMergeCount = 0
                    lastMergedSnapshot = merged
                }
                if stableMergeCount >= 2, Self.nativeCaptureTextIsUsable(merged) {
                    break
                }
            }
            try await Self.scrollNativeApp(processIdentifier: app.processIdentifier, deltaY: -7, repeats: 2)
        }

        let merged = Self.mergeNativeCaptureSnapshots(snapshots)
        if Self.nativeCaptureTextIsUsable(merged) {
            return merged
        }

        throw TacketAppError.nativeCapture("Tacket could not find enough readable chat text in the \(source.label) window. Open the chat, wait for messages to finish loading, then try again.")
    }

    func installPublishedConnector() {
        extensionId = Self.publishedChromeExtensionId
        installConnector(extensionId: Self.publishedChromeExtensionId)
    }

    func installConnector() {
        installConnector(extensionId: extensionId)
    }

    private func installConnector(extensionId rawExtensionId: String) {
        let id = rawExtensionId.trimmingCharacters(in: .whitespacesAndNewlines)
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
            commandOutput = "Installed Chrome native messaging host for extension \(id):\n\(path.path)"
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
            let originList = json["allowed_origins"] as? [String] ?? []
            let origins = originList.joined(separator: ", ")
            installedHostPath = manifestURL.path
            if originList.contains(Self.publishedChromeExtensionOrigin) {
                connectorStatus = "Installed for the published Tacket extension."
            } else {
                connectorStatus = "Installed: \(hostPath)"
            }
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
            clampLibraryPage()
            selectedLibraryItem = selectedLibraryItem.flatMap { selected in
                pagedLibraryItems.first(where: { $0.id == selected.id })
            } ?? pagedLibraryItems.first ?? libraryItems.first
            libraryStatus = libraryItems.isEmpty ? "No indexed tackets yet." : "\(libraryItems.count) indexed tacket(s)."
        } catch {
            libraryStatus = "Library refresh failed."
            commandOutput = error.localizedDescription
        }
    }

    func searchLibrary() {
        libraryPage = 0
        refreshLibrary()
    }

    func resetAdvancedSearch() {
        libraryMatchMode = .phrase
        librarySearchScope = .everywhere
        librarySourceFilter = .all
        libraryRoleFilter = .all
        libraryPage = 0
        refreshLibrary()
    }

    func nextLibraryPage() {
        guard libraryPage < libraryPageCount - 1 else { return }
        libraryPage += 1
        selectedLibraryItem = pagedLibraryItems.first
    }

    func previousLibraryPage() {
        guard libraryPage > 0 else { return }
        libraryPage -= 1
        selectedLibraryItem = pagedLibraryItems.first
    }

    private func clampLibraryPage() {
        libraryPage = min(max(libraryPage, 0), libraryPageCount - 1)
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
                libraryPage = 0
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

    private struct ImportedAgentMessage {
        let id: String
        let role: String
        let author: String
        let createdAt: String
        let text: String
    }

    private struct ImportedAgentSession {
        let source: LocalAgentSource
        let sessionId: String
        let title: String
        let capturedAt: String
        let sourceURL: String
        let messages: [ImportedAgentMessage]
    }

    private nonisolated static func importLocalAgentSessions(
        _ source: LocalAgentSource,
        outputRoot: URL
    ) throws -> (imported: Int, skipped: Int, lastBundle: URL?) {
        if source == .claudeApp {
            return try importParsedAgentSessions(
                try readRecentClaudeAppSessions(limit: 20),
                outputRoot: outputRoot
            )
        }

        let files: [URL]
        let codexIndex: [String: (title: String, updatedAt: String)]
        switch source {
        case .codex:
            files = try recentCodexSessionFiles(limit: 20)
            let codexRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
            codexIndex = readCodexSessionIndex(codexRoot: codexRoot)
        case .claudeApp:
            files = []
            codexIndex = [:]
        case .claudeCode:
            files = try recentClaudeCodeSessionFiles(limit: 20)
            codexIndex = [:]
        }

        let existingBundles = existingImportedSessionBundles(outputRoot: outputRoot)
        var imported = 0
        var skipped = 0
        var lastBundle: URL?
        for file in files {
            let sourceURL = sourceURLForLocalAgentFile(source, file: file)
            if let existing = existingBundles[sourceURL] {
                skipped += 1
                lastBundle = existing
                continue
            }
            let session: ImportedAgentSession?
            switch source {
            case .codex:
                let sessionId = sessionIdFromCodexPath(file)
                session = try? parseCodexSession(file, indexedTitle: codexIndex[sessionId]?.title)
            case .claudeApp:
                session = nil
            case .claudeCode:
                session = try? parseClaudeCodeSession(file)
            }
            guard let session else { continue }
            guard !session.messages.isEmpty else { continue }
            let bundleURL = try writeAgentSessionBundle(session, outputRoot: outputRoot)
            _ = try indexLibraryBundle(bundleURL)
            imported += 1
            lastBundle = bundleURL
        }
        return (imported, skipped, lastBundle)
    }

    private nonisolated static func importParsedAgentSessions(
        _ sessions: [ImportedAgentSession],
        outputRoot: URL
    ) throws -> (imported: Int, skipped: Int, lastBundle: URL?) {
        let existingBundles = existingImportedSessionBundles(outputRoot: outputRoot)
        var imported = 0
        var skipped = 0
        var lastBundle: URL?
        for session in sessions {
            guard !session.messages.isEmpty else { continue }
            if let existing = existingBundles[session.sourceURL] {
                skipped += 1
                lastBundle = existing
                continue
            }
            let bundleURL = try writeAgentSessionBundle(session, outputRoot: outputRoot)
            _ = try indexLibraryBundle(bundleURL)
            imported += 1
            lastBundle = bundleURL
        }
        return (imported, skipped, lastBundle)
    }

    private nonisolated static func importLibraryStatus(
        _ result: (imported: Int, skipped: Int, lastBundle: URL?),
        source: LocalAgentSource
    ) -> String {
        if result.imported == 0, result.skipped > 0 {
            return "All recent \(source.label) transcripts are already saved."
        }
        if result.skipped > 0 {
            return "Imported \(result.imported) \(source.label) transcript(s); \(result.skipped) already saved."
        }
        return "Imported \(result.imported) \(source.label) transcript(s)."
    }

    private nonisolated static func importCommandOutput(
        _ result: (imported: Int, skipped: Int, lastBundle: URL?),
        source: LocalAgentSource
    ) -> String {
        if result.imported == 0, result.skipped == 0 {
            return "No importable \(source.label) transcripts were found."
        }
        if result.imported == 0 {
            return "No new \(source.label) transcripts were imported. \(result.skipped) recent transcript(s) are already saved in your Tacket library."
        }
        if result.skipped > 0 {
            return "Imported \(result.imported) new \(source.label) transcript(s) from local session files. Skipped \(result.skipped) already-saved transcript(s)."
        }
        return "Imported \(result.imported) \(source.label) transcript(s) from local session files."
    }

    private nonisolated static func readRecentCodexSessions(limit: Int) throws -> [ImportedAgentSession] {
        let codexRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        let index = readCodexSessionIndex(codexRoot: codexRoot)
        let files = try recentCodexSessionFiles(limit: limit)
        return files.prefix(limit).compactMap { file in
            try? parseCodexSession(file, indexedTitle: index[sessionIdFromCodexPath(file)]?.title)
        }.filter { !$0.messages.isEmpty }
    }

    private nonisolated static func readRecentClaudeCodeSessions(limit: Int) throws -> [ImportedAgentSession] {
        let files = try recentClaudeCodeSessionFiles(limit: limit)
        return files.prefix(limit).compactMap { file in
            try? parseClaudeCodeSession(file)
        }.filter { !$0.messages.isEmpty }
    }

    private nonisolated static func recentCodexSessionFiles(limit: Int) throws -> [URL] {
        let codexRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        let sessionsRoot = codexRoot.appendingPathComponent("sessions", isDirectory: true)
        return try recentJSONLFiles(in: sessionsRoot, limit: limit * 2)
    }

    private nonisolated static func recentClaudeCodeSessionFiles(limit: Int) throws -> [URL] {
        let projectsRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        return try recentJSONLFiles(in: projectsRoot, limit: limit * 3)
            .filter { !$0.path.contains("/subagents/") }
    }

    private nonisolated static func sourceURLForLocalAgentFile(_ source: LocalAgentSource, file: URL) -> String {
        switch source {
        case .codex:
            return "codex-session://\(sessionIdFromCodexPath(file))"
        case .claudeApp:
            return ""
        case .claudeCode:
            return "claude-code-session://\(file.deletingPathExtension().lastPathComponent)"
        }
    }

    private nonisolated static func existingImportedSessionBundles(
        outputRoot _: URL
    ) -> [String: URL] {
        (try? existingImportedSessionBundlesFromIndex()) ?? [:]
    }

    private nonisolated static func existingImportedSessionBundlesFromIndex() throws -> [String: URL] {
        try ensureLibraryDatabase()
        var bundles: [String: URL] = [:]
        try withLibraryDatabase { db in
            let sql = """
                SELECT url, path
                FROM bundles
                WHERE url LIKE 'codex-session://%'
                   OR url LIKE 'claude-app-conversation://%'
                   OR url LIKE 'claude-code-session://%';
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw TacketAppError.libraryDatabase(sqliteError(db))
            }
            defer { sqlite3_finalize(statement) }

            while sqlite3_step(statement) == SQLITE_ROW {
                guard let urlCString = sqlite3_column_text(statement, 0),
                      let pathCString = sqlite3_column_text(statement, 1) else {
                    continue
                }
                let sourceURL = String(cString: urlCString)
                let path = String(cString: pathCString)
                bundles[sourceURL] = URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return bundles
    }

    private nonisolated static func recentJSONLFiles(in root: URL, limit: Int) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        var files: [(url: URL, date: Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            files.append((url, values.contentModificationDate ?? .distantPast))
        }
        return files
            .sorted { lhs, rhs in lhs.date > rhs.date }
            .prefix(limit)
            .map(\.url)
    }

    private nonisolated static func readCodexSessionIndex(
        codexRoot: URL
    ) -> [String: (title: String, updatedAt: String)] {
        let indexURL = codexRoot.appendingPathComponent("session_index.jsonl")
        guard let text = try? String(contentsOf: indexURL, encoding: .utf8) else { return [:] }
        var index: [String: (title: String, updatedAt: String)] = [:]
        for line in text.split(separator: "\n") {
            guard let object = try? jsonObject(from: String(line)),
                  let id = object["id"] as? String else {
                continue
            }
            index[id] = (
                title: object["thread_name"] as? String ?? "Codex session",
                updatedAt: object["updated_at"] as? String ?? ""
            )
        }
        return index
    }

    private nonisolated static func sessionIdFromCodexPath(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: #"^rollout-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-"#, with: "", options: .regularExpression)
    }

    private nonisolated static func parseCodexSession(
        _ file: URL,
        indexedTitle: String?
    ) throws -> ImportedAgentSession {
        let text = try String(contentsOf: file, encoding: .utf8)
        let fallbackId = sessionIdFromCodexPath(file)
        var sessionId = fallbackId
        var capturedAt = iso8601String(from: fileModificationDate(file))
        var title = indexedTitle ?? "Codex session"
        var messages: [ImportedAgentMessage] = []

        for rawLine in text.split(separator: "\n") {
            guard let object = try? jsonObject(from: String(rawLine)) else { continue }
            let timestamp = object["timestamp"] as? String ?? capturedAt
            if object["type"] as? String == "session_meta",
               let payload = object["payload"] as? [String: Any] {
                sessionId = payload["id"] as? String ?? sessionId
                capturedAt = payload["timestamp"] as? String ?? capturedAt
                continue
            }
            guard object["type"] as? String == "response_item",
                  let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "message" else {
                continue
            }
            let rawRole = payload["role"] as? String ?? "unknown"
            let role = normalizedTacketRole(rawRole)
            let text = textFromOpenAIContent(payload["content"])
            guard !text.isEmpty else { continue }
            if title == "Codex session", role == "user" {
                title = titleFromText(text, fallback: title)
            }
            messages.append(ImportedAgentMessage(
                id: "codex-\(messages.count + 1)",
                role: role,
                author: roleLabel(role),
                createdAt: timestamp,
                text: text
            ))
        }

        return ImportedAgentSession(
            source: .codex,
            sessionId: sessionId,
            title: sanitizeFileSegment(title, maxLength: 80),
            capturedAt: capturedAt,
            sourceURL: "codex-session://\(sessionId)",
            messages: messages
        )
    }

    private nonisolated static func parseClaudeCodeSession(_ file: URL) throws -> ImportedAgentSession {
        let text = try String(contentsOf: file, encoding: .utf8)
        let sessionId = file.deletingPathExtension().lastPathComponent
        var capturedAt = iso8601String(from: fileModificationDate(file))
        var title = "Claude Code session"
        var messages: [ImportedAgentMessage] = []

        for rawLine in text.split(separator: "\n") {
            guard let object = try? jsonObject(from: String(rawLine)),
                  (object["type"] as? String == "user" || object["type"] as? String == "assistant"),
                  object["isMeta"] as? Bool != true,
                  let message = object["message"] as? [String: Any] else {
                continue
            }
            let timestamp = object["timestamp"] as? String ?? capturedAt
            if messages.isEmpty {
                capturedAt = timestamp
            }
            let role = normalizedTacketRole(message["role"] as? String ?? object["type"] as? String ?? "unknown")
            let text = textFromClaudeContent(message["content"])
            guard !text.isEmpty else { continue }
            if title == "Claude Code session", role == "user" {
                title = titleFromText(text, fallback: title)
            }
            messages.append(ImportedAgentMessage(
                id: "claude-code-\(messages.count + 1)",
                role: role,
                author: roleLabel(role),
                createdAt: timestamp,
                text: text
            ))
        }

        return ImportedAgentSession(
            source: .claudeCode,
            sessionId: sessionId,
            title: sanitizeFileSegment(title, maxLength: 80),
            capturedAt: capturedAt,
            sourceURL: "claude-code-session://\(sessionId)",
            messages: messages
        )
    }

    private nonisolated static func readRecentClaudeAppSessions(limit: Int) throws -> [ImportedAgentSession] {
        let storageRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/Local Storage/leveldb", isDirectory: true)
        guard FileManager.default.fileExists(atPath: storageRoot.path),
              let enumerator = FileManager.default.enumerator(
                at: storageRoot,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        var files: [(url: URL, date: Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "log" || url.pathExtension == "ldb" {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            files.append((url, values.contentModificationDate ?? .distantPast))
        }

        var sessionsByURL: [String: ImportedAgentSession] = [:]
        for file in files.sorted(by: { $0.date > $1.date }).prefix(12).map(\.url) {
            for session in try parseClaudeAppStorageFile(file) {
                sessionsByURL[session.sourceURL] = session
            }
        }

        return sessionsByURL.values
            .sorted { lhs, rhs in lhs.capturedAt > rhs.capturedAt }
            .prefix(limit)
            .map { $0 }
    }

    private nonisolated static func parseClaudeAppStorageFile(_ file: URL) throws -> [ImportedAgentSession] {
        let data = try Data(contentsOf: file)
        let text = utf16LittleEndianStringRuns(from: data, minimumScalars: 5).joined()
        guard text.contains(#""chat_messages""#) else { return [] }

        var sessions: [ImportedAgentSession] = []
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: #"{"uuid":""#, options: [], range: searchRange) {
            defer {
                let nextIndex = text.index(after: range.lowerBound)
                searchRange = nextIndex..<text.endIndex
            }
            guard let objectText = balancedJSONObject(in: text, from: range.lowerBound),
                  objectText.contains(#""chat_messages""#),
                  let data = objectText.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let session = parseClaudeAppConversationObject(object) else {
                continue
            }
            sessions.append(session)
        }
        return sessions
    }

    private nonisolated static func parseClaudeAppConversationObject(_ object: [String: Any]) -> ImportedAgentSession? {
        guard let sessionId = object["uuid"] as? String,
              let rawMessages = object["chat_messages"] as? [[String: Any]] else {
            return nil
        }

        var capturedAt = object["created_at"] as? String
            ?? rawMessages.compactMap { $0["created_at"] as? String }.first
            ?? ISO8601DateFormatter().string(from: Date())
        var title = object["name"] as? String ?? "Claude App conversation"
        var messages: [ImportedAgentMessage] = []

        for rawMessage in rawMessages.sorted(by: { lhs, rhs in
            let lhsIndex = lhs["index"] as? Int ?? Int.max
            let rhsIndex = rhs["index"] as? Int ?? Int.max
            return lhsIndex < rhsIndex
        }) {
            let sender = rawMessage["sender"] as? String ?? "unknown"
            let role = normalizedTacketRole(sender == "human" ? "user" : sender)
            let text = textFromClaudeContent(rawMessage["content"])
            guard !text.isEmpty else { continue }
            let createdAt = rawMessage["created_at"] as? String ?? capturedAt
            if messages.isEmpty {
                capturedAt = createdAt
            }
            if title == "Claude App conversation", role == "user" {
                title = titleFromText(text, fallback: title)
            }
            messages.append(ImportedAgentMessage(
                id: "claude-app-\(messages.count + 1)",
                role: role,
                author: roleLabel(role),
                createdAt: createdAt,
                text: text
            ))
        }

        guard !messages.isEmpty else { return nil }
        return ImportedAgentSession(
            source: .claudeApp,
            sessionId: sessionId,
            title: sanitizeFileSegment(title, maxLength: 80),
            capturedAt: capturedAt,
            sourceURL: "claude-app-conversation://\(sessionId)",
            messages: messages
        )
    }

    private nonisolated static func utf16LittleEndianStringRuns(
        from data: Data,
        minimumScalars: Int
    ) -> [String] {
        let bytes = [UInt8](data)
        var runs: [String] = []
        var index = 0
        while index + 1 < bytes.count {
            let start = index
            var runBytes: [UInt8] = []
            var scalarCount = 0
            while index + 1 < bytes.count {
                let value = UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
                let isAllowed = bytes[index + 1] == 0
                    && (value == 9 || value == 10 || value == 13 || (value >= 32 && value <= 126))
                guard isAllowed else { break }
                runBytes.append(bytes[index])
                runBytes.append(bytes[index + 1])
                scalarCount += 1
                index += 2
            }
            if scalarCount >= minimumScalars,
               let string = String(data: Data(runBytes), encoding: .utf16LittleEndian) {
                runs.append(string)
            }
            index = max(index + 1, start + 1)
        }
        return runs
    }

    private nonisolated static func balancedJSONObject(in text: String, from start: String.Index) -> String? {
        var index = start
        var depth = 0
        var isInString = false
        var isEscaped = false
        while index < text.endIndex {
            let character = text[index]
            if isInString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInString = false
                }
            } else {
                if character == "\"" {
                    isInString = true
                } else if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(text[start...index])
                    }
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private nonisolated static func writeAgentSessionBundle(
        _ session: ImportedAgentSession,
        outputRoot: URL
    ) throws -> URL {
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
        let capturedAt = validISO8601(session.capturedAt) ?? ISO8601DateFormatter().string(from: Date())
        let bundleURL = try reserveAgentBundleURL(
            outputRoot: outputRoot,
            capturedAt: dateFromISO8601(capturedAt) ?? Date(),
            source: session.source,
            title: session.title
        )
        let targetsURL = bundleURL.appendingPathComponent("targets", isDirectory: true)
        let attachmentsURL = bundleURL.appendingPathComponent("attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: targetsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: attachmentsURL, withIntermediateDirectories: true)

        let messages = session.messages.map { message -> [String: Any] in
            [
                "id": message.id,
                "role": message.role,
                "author": message.author,
                "createdAt": message.createdAt,
                "source": [
                    "platform": session.source.platform,
                    "url": session.sourceURL
                ],
                "content": [
                    [
                        "type": "text",
                        "text": message.text
                    ]
                ]
            ]
        }
        let transcript = renderAgentSessionTranscript(session, capturedAt: capturedAt)
        let manifest: [String: Any] = [
            "schemaVersion": "0.1.0",
            "id": sha256("\(session.source.rawValue):\(session.sessionId):\(capturedAt)"),
            "title": session.title,
            "source": [
                "platform": session.source.platform,
                "url": session.sourceURL,
                "capture": "local-agent-session"
            ],
            "capturedAt": capturedAt,
            "messageCount": messages.count,
            "attachments": [
                "captured": 0,
                "referenced": 0,
                "unavailable": 0
            ],
            "warnings": []
        ]

        try writeJSONObject(manifest, to: bundleURL.appendingPathComponent("manifest.json"))
        let jsonl = try messages.map { message -> String in
            let data = try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
            guard let line = String(data: data, encoding: .utf8) else {
                throw TacketAppError.nativeCapture("Could not encode imported message.")
            }
            return line
        }.joined(separator: "\n") + "\n"
        try jsonl.write(to: bundleURL.appendingPathComponent("messages.jsonl"), atomically: true, encoding: .utf8)
        try transcript.write(to: bundleURL.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)
        try transcript.write(to: targetsURL.appendingPathComponent("codex.md"), atomically: true, encoding: .utf8)
        try transcript.write(to: targetsURL.appendingPathComponent("claude-code.md"), atomically: true, encoding: .utf8)
        try agentSessionReadme(session, capturedAt: capturedAt)
            .write(to: bundleURL.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        return bundleURL
    }

    private nonisolated static func reserveAgentBundleURL(
        outputRoot: URL,
        capturedAt: Date,
        source: LocalAgentSource,
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

    private nonisolated static func renderAgentSessionTranscript(
        _ session: ImportedAgentSession,
        capturedAt: String
    ) -> String {
        var lines: [String] = [
            "The following is the full saved AI chat conversation being transferred into this coding session.",
            "Continue from it. Do not treat this as a summary.",
            "",
            "[conversation begins]",
            "",
            "# \(session.title)",
            "",
            "Source: \(session.source.platform)",
            "URL: \(session.sourceURL)",
            "Captured: \(capturedAt)",
            ""
        ]

        for message in session.messages {
            lines.append("## \(roleLabel(message.role))")
            lines.append("")
            lines.append(message.text.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("")
        }
        lines.append("[conversation ends]")
        lines.append("")
        return lines.joined(separator: "\n")
            .replacingOccurrences(of: #"\n{4,}"#, with: "\n\n\n", options: .regularExpression)
    }

    private nonisolated static func agentSessionReadme(
        _ session: ImportedAgentSession,
        capturedAt: String
    ) -> String {
        """
        # \(session.title)

        This is a local Tacket saved chat imported from \(session.source.label) session files on this Mac.

        - Open `transcript.md` to read the full imported conversation.
        - `targets/` contains ready-to-transfer conversation files for supported tools.
        - `manifest.json` and `messages.jsonl` are used by Tacket to verify and search the saved chat.

        Source: \(session.source.label)
        Captured: \(capturedAt)
        """
    }

    private nonisolated static func textFromOpenAIContent(_ value: Any?) -> String {
        guard let parts = value as? [[String: Any]] else { return "" }
        return parts.compactMap { part in
            guard let text = part["text"] as? String else { return nil }
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        }.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func textFromClaudeContent(_ value: Any?) -> String {
        if let text = value as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let parts = value as? [[String: Any]] else { return "" }
        return parts.compactMap { part in
            if let text = part["text"] as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
            if let content = part["content"] as? String,
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return content
            }
            guard part["type"] as? String != "thinking",
                  JSONSerialization.isValidJSONObject(part),
                  let data = try? JSONSerialization.data(withJSONObject: part, options: [.sortedKeys]),
                  let json = String(data: data, encoding: .utf8) else {
                return nil
            }
            return json
        }.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func normalizedTacketRole(_ value: String) -> String {
        switch value.lowercased() {
        case "user": "user"
        case "assistant": "assistant"
        case "system", "developer": "system"
        case "tool", "tool_result", "tool_use": "tool"
        default: "unknown"
        }
    }

    private nonisolated static func roleLabel(_ role: String) -> String {
        switch role {
        case "user": "User"
        case "assistant": "Assistant"
        case "system": "System"
        case "tool": "Tool"
        default: "Unknown"
        }
    }

    private nonisolated static func titleFromText(_ text: String, fallback: String) -> String {
        let line = text
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.count >= 8 } ?? fallback
        return sanitizeFileSegment(line, maxLength: 80)
    }

    private nonisolated static func jsonObject(from line: String) throws -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private nonisolated static func fileModificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
    }

    private nonisolated static func iso8601String(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private nonisolated static func dateFromISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private nonisolated static func validISO8601(_ value: String) -> String? {
        dateFromISO8601(value).map { ISO8601DateFormatter().string(from: $0) }
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
        let cleaned = basicCleanNativeCaptureText(value)
        let collapsed = nativeCaptureCollapseRepeatedBlocks(nativeCaptureLines(fromCleanedText: cleaned))
        guard !collapsed.isEmpty else { return cleaned }
        return collapsed.joined(separator: "\n")
    }

    private nonisolated static func basicCleanNativeCaptureText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func nativeCaptureTextIsUsable(_ value: String) -> Bool {
        cleanNativeCaptureText(value).count >= 20
    }

    private nonisolated static func nativeCaptureDraft(
        source: NativeCaptureSource,
        transcript: String
    ) -> NativeCaptureDraft {
        let lines = nativeCaptureLines(transcript)
        let title = nativeCaptureTitle(from: transcript, source: source)
        let preview = String(transcript.prefix(4_000))
        let quality: NativeCaptureDraft.Quality
        if transcript.count >= 1_500 && lines.count >= 20 {
            quality = .strong
        } else if transcript.count >= 300 && lines.count >= 6 {
            quality = .review
        } else {
            quality = .thin
        }
        return NativeCaptureDraft(
            source: source,
            title: title,
            transcript: transcript,
            preview: preview,
            lineCount: lines.count,
            characterCount: transcript.count,
            quality: quality
        )
    }

    private nonisolated static func nativeWindowText(for processIdentifier: pid_t) async throws -> String {
        if accessibilityIsTrusted(prompt: false),
           let text = try? accessibilityText(for: processIdentifier),
           nativeCaptureTextIsUsable(text) {
            return cleanNativeCaptureText(text)
        }
        guard screenCaptureIsTrusted(prompt: false) else {
            throw TacketAppError.nativeCapture("The app window did not expose enough Accessibility text, and Screen Recording is not granted for local OCR.")
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

    nonisolated static func mergeNativeCaptureSnapshots(_ snapshots: [String]) -> String {
        var lines: [String] = []
        for snapshot in snapshots {
            let snapshotLines = nativeCaptureLines(snapshot)
            guard !snapshotLines.isEmpty else { continue }
            if lines.isEmpty {
                lines.append(contentsOf: snapshotLines)
                continue
            }
            if nativeCaptureContainsSubsequence(snapshotLines, in: lines) {
                continue
            }
            if let overlap = nativeCaptureBestOverlap(existing: lines, next: snapshotLines) {
                let prefix = Array(snapshotLines.prefix(overlap.nextStart))
                let suffixStart = overlap.nextStart + overlap.count
                let suffix = Array(snapshotLines.dropFirst(suffixStart))
                if !prefix.isEmpty,
                   overlap.existingStart == 0,
                   !nativeCaptureContainsSubsequence(prefix, in: lines) {
                    lines.insert(contentsOf: prefix, at: 0)
                }
                if !suffix.isEmpty,
                   !nativeCaptureContainsSubsequence(suffix, in: lines) {
                    lines.append(contentsOf: suffix)
                }
                continue
            }

            let overlap = nativeCaptureOverlap(previous: lines, next: snapshotLines)
            let newLines = Array(snapshotLines.dropFirst(overlap))
            if !newLines.isEmpty,
               !nativeCaptureContainsSubsequence(newLines, in: lines) {
                lines.append(contentsOf: newLines)
            }
        }
        return nativeCaptureCollapseRepeatedBlocks(lines).joined(separator: "\n")
    }

    private nonisolated static func nativeCaptureLines(_ value: String) -> [String] {
        nativeCaptureLines(fromCleanedText: basicCleanNativeCaptureText(value))
    }

    private nonisolated static func nativeCaptureLines(fromCleanedText value: String) -> [String] {
        value
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                line.count > 1 && !nativeCaptureLineIsNoise(line)
            }
    }

    private nonisolated static func nativeCaptureOverlap(previous: [String], next: [String]) -> Int {
        let maxOverlap = min(previous.count, next.count, 120)
        guard maxOverlap > 0 else { return 0 }
        for count in stride(from: maxOverlap, through: 1, by: -1) {
            let previousSuffix = previous.suffix(count).map { $0.lowercased() }
            let nextPrefix = next.prefix(count).map { $0.lowercased() }
            if Array(previousSuffix) == Array(nextPrefix) {
                return count
            }
        }
        return 0
    }

    private nonisolated static func nativeCaptureBestOverlap(existing: [String], next: [String]) -> (existingStart: Int, nextStart: Int, count: Int)? {
        let existingNormalized = nativeCaptureNormalizedLines(existing)
        let nextNormalized = nativeCaptureNormalizedLines(next)
        var best: (existingStart: Int, nextStart: Int, count: Int)?

        for existingStart in existingNormalized.indices {
            for nextStart in nextNormalized.indices where existingNormalized[existingStart] == nextNormalized[nextStart] {
                var count = 0
                while existingStart + count < existingNormalized.count,
                      nextStart + count < nextNormalized.count,
                      existingNormalized[existingStart + count] == nextNormalized[nextStart + count] {
                    count += 1
                }
                if nativeCaptureOverlapIsUseful(lines: next, start: nextStart, count: count),
                   best == nil || count > best!.count {
                    best = (existingStart, nextStart, count)
                }
            }
        }

        return best
    }

    private nonisolated static func nativeCaptureOverlapIsUseful(lines: [String], start: Int, count: Int) -> Bool {
        guard count > 0, start >= 0, start + count <= lines.count else { return false }
        if count >= 2 {
            return true
        }
        return lines[start].count >= 32
    }

    private nonisolated static func nativeCaptureCollapseRepeatedBlocks(_ input: [String]) -> [String] {
        var lines = input
        guard lines.count >= 4 else { return lines }

        var index = 0
        while index < lines.count {
            var collapsedAtIndex = false
            let remaining = lines.count - index
            let maxBlockSize = min(remaining / 2, 180)
            if maxBlockSize > 0 {
                for blockSize in stride(from: maxBlockSize, through: 2, by: -1) {
                    let first = Array(lines[index..<(index + blockSize)])
                    let secondStart = index + blockSize
                    let secondEnd = secondStart + blockSize
                    guard secondEnd <= lines.count else { continue }
                    let second = Array(lines[secondStart..<secondEnd])
                    if nativeCaptureBlocksMatch(first, second) {
                        lines.removeSubrange(secondStart..<secondEnd)
                        collapsedAtIndex = true
                        break
                    }
                }
            }
            if !collapsedAtIndex {
                index += 1
            }
        }

        return lines
    }

    private nonisolated static func nativeCaptureNormalizedLines(_ lines: [String]) -> [String] {
        lines.map { nativeCaptureNormalizedLine($0) }
    }

    private nonisolated static func nativeCaptureNormalizedLine(_ line: String) -> String {
        line
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private nonisolated static func nativeCaptureBlocksMatch(_ first: [String], _ second: [String]) -> Bool {
        guard first.count == second.count, first.count >= 2 else { return false }
        let firstNormalized = nativeCaptureNormalizedLines(first)
        let secondNormalized = nativeCaptureNormalizedLines(second)
        var matching = 0
        for index in firstNormalized.indices where firstNormalized[index] == secondNormalized[index] {
            matching += 1
        }
        if matching == first.count {
            return true
        }
        return first.count >= 4 && Double(matching) / Double(first.count) >= 0.8
    }

    private nonisolated static func nativeCaptureContainsSubsequence(_ needle: [String], in haystack: [String]) -> Bool {
        guard !needle.isEmpty, haystack.count >= needle.count else { return false }
        let normalizedNeedle = nativeCaptureNormalizedLines(needle)
        let normalizedHaystack = nativeCaptureNormalizedLines(haystack)
        for start in 0...(normalizedHaystack.count - normalizedNeedle.count) {
            let end = start + normalizedNeedle.count
            if Array(normalizedHaystack[start..<end]) == normalizedNeedle {
                return true
            }
        }
        return false
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

    private nonisolated static func nativeCapturePermissionSummary(
        accessibilityReady: Bool,
        screenCaptureReady: Bool
    ) -> String {
        """
        Permission check:
        Accessibility: \(accessibilityReady ? "granted" : "not granted yet")
        Screen Recording: \(screenCaptureReady ? "granted" : "not granted yet")
        """
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
        var visited = 0
        for root in roots {
            collectAccessibilityText(from: root, depth: 0, visited: &visited, lines: &lines)
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
        lines: inout [String]
    ) {
        guard depth <= 28, visited < 5000 else { return }
        visited += 1

        let role = axStringAttribute(element, kAXRoleAttribute)
        let shouldRead = readableAccessibilityRoles.contains(role)
        if shouldRead {
            for attribute in readableAccessibilityAttributes {
                appendAccessibilityText(axStringAttribute(element, attribute), lines: &lines)
            }
        }

        for child in axElementArrayAttribute(element, kAXChildrenAttribute) {
            collectAccessibilityText(from: child, depth: depth + 1, visited: &visited, lines: &lines)
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

    private nonisolated static func appendAccessibilityText(_ value: String, lines: inout [String]) {
        let normalized = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in normalized {
            guard line.count > 1 else { continue }
            guard !nativeCaptureChromeNoise.contains(line.lowercased()) else { continue }
            if lines.last != line {
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
            "settings",
            "outputs",
            "no artifacts yet",
            "sources",
            "no sources yet"
        ]
    }

    private nonisolated static func nativeCaptureLineIsNoise(_ line: String) -> Bool {
        let normalizedLine = nativeCaptureNormalizedLine(line)
        if normalizedLine.count <= 1,
           line.contains("<") || line.contains("->") || line.contains("→") || line.contains("←") {
            return true
        }
        let lowercased = line.lowercased()
        if nativeCaptureChromeNoise.contains(lowercased) {
            return true
        }
        if lowercased.hasPrefix("ask for follow-up") {
            return true
        }
        if lowercased.contains("full access") {
            return true
        }
        if lowercased.contains("medium"), lowercased.first?.isNumber == true {
            return true
        }
        return false
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
            let deadline = Date().addingTimeInterval(2)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                process.terminate()
                return nil
            }
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

        This is a local Tacket saved chat captured from the current \(source.label) desktop app conversation.

        - Open `transcript.md` to read the captured conversation text.
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
                ORDER BY captured_at DESC, indexed_at DESC;
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

struct NativeCaptureDraft {
    enum Quality {
        case strong
        case review
        case thin

        var label: String {
            switch self {
            case .strong: "Looks ready"
            case .review: "Review closely"
            case .thin: "Probably incomplete"
            }
        }

        var detail: String {
            switch self {
            case .strong:
                "Tacket found enough local text for a likely complete desktop capture."
            case .review:
                "Tacket found readable text, but the capture may be partial. Check the preview before saving."
            case .thin:
                "Tacket found only a small amount of text. Reopen the chat, widen the window, or grant permissions before saving."
            }
        }

        var color: Color {
            switch self {
            case .strong: TacketColors.success
            case .review: TacketColors.warning
            case .thin: TacketColors.danger
            }
        }
    }

    let source: TacketModel.NativeCaptureSource
    let title: String
    let transcript: String
    let preview: String
    let lineCount: Int
    let characterCount: Int
    let quality: Quality
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

struct QuickCaptureMenuView: View {
    @EnvironmentObject private var model: TacketModel
    let openPreviewWindow: Bool

    var body: some View {
        Button {
            model.captureFrontmostNativeApp(openPreviewWindow: openPreviewWindow)
        } label: {
            Label("Capture Frontmost Chat App", systemImage: "viewfinder")
        }
        .disabled(model.isRunning)

        Divider()

        Button {
            model.captureNativeApp(.chatgpt, openPreviewWindow: openPreviewWindow)
        } label: {
            Label("Capture ChatGPT", systemImage: "macwindow")
        }
        .disabled(model.isRunning)

        Button {
            model.captureNativeApp(.claude, openPreviewWindow: openPreviewWindow)
        } label: {
            Label("Capture Claude", systemImage: "macwindow")
        }
        .disabled(model.isRunning)

        Button {
            model.captureNativeApp(.codex, openPreviewWindow: openPreviewWindow)
        } label: {
            Label("Capture Codex", systemImage: "macwindow")
        }
        .disabled(model.isRunning)

        Divider()

        Button {
            model.showMainWindow()
        } label: {
            Label("Open Tacket", systemImage: "app")
        }

        Button {
            model.revealCaptureDirectory()
        } label: {
            Label("Open Save Folder", systemImage: "folder")
        }

        Menu("Privacy / Permissions") {
            Button("Accessibility Settings") {
                model.openAccessibilitySettings()
            }
            Button("Screen Recording Settings") {
                model.openScreenRecordingSettings()
            }
        }

        Divider()

        Button("Quit Tacket") {
            NSApp.terminate(nil)
        }
    }
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
                        title: "Add chats",
                        detail: "Choose the capture path that matches where the chat lives."
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            AddChatsCommandBar()

                            if let draft = model.pendingNativeCaptureDraft {
                                NativeCaptureReviewCard(draft: draft)
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
                                .fixedSize()

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
                                .fixedSize()
                            }

                            HStack(spacing: 8) {
                                if model.advancedSearchIsActive {
                                    MetadataPill(text: "advanced")
                                }
                                Text(model.libraryStatus)
                                    .font(.tacketFootnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if !model.libraryItems.isEmpty {
                                LibraryPaginationControls()
                            }
                        }
                    }

                    libraryContent(isWide: geometry.size.width >= 780)

                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 20)
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
            VStack(alignment: .leading, spacing: 12) {
                if model.libraryItems.isEmpty {
                    LibraryEmptyState {
                        model.indexCaptureFolderForLibrary()
                    }
                } else if model.libraryViewMode == .gallery {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                        ForEach(model.pagedLibraryItems) { item in
                            LibraryGalleryCard(item: item, isSelected: model.selectedLibraryItem?.id == item.id)
                                .onTapGesture {
                                    model.selectLibraryItem(item)
                                }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.pagedLibraryItems) { item in
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

struct AddChatsCommandBar: View {
    @EnvironmentObject private var model: TacketModel

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Open ChatGPT in Chrome", action: model.openChatGPT)
                Button("Open Claude in Chrome", action: model.openClaude)
                Button("Open Gemini in Chrome", action: model.openGemini)
            } label: {
                Label("Browser", systemImage: "globe")
            }
            .buttonStyle(.borderedProminent)

            Menu {
                ForEach(TacketModel.LocalAgentSource.allCases) { source in
                    Button("Import \(source.label)") {
                        model.importLocalAgentSessions(source)
                    }
                    .disabled(model.isRunning)
                }
            } label: {
                Label("Import", systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)

            Menu {
                Section("Open app") {
                    ForEach(TacketModel.NativeCaptureSource.allCases) { source in
                        Button(source.label) {
                            model.openDesktopApp(source)
                        }
                    }
                }
                Section("Preview current chat") {
                    ForEach(TacketModel.NativeCaptureSource.allCases) { source in
                        Button(source.label) {
                            model.captureNativeApp(source)
                        }
                        .disabled(model.isRunning)
                    }
                }
            } label: {
                Label("Desktop", systemImage: "viewfinder")
            }
            .buttonStyle(.bordered)

            Menu {
                Button("Accessibility Settings") {
                    model.openAccessibilitySettings()
                }
                Button("Screen Recording Settings") {
                    model.openScreenRecordingSettings()
                }
            } label: {
                Label("Permissions", systemImage: "lock")
            }
            .buttonStyle(.bordered)

            Spacer(minLength: 0)
        }
        .controlSize(.regular)
        .padding(12)
        .background(TacketColors.recessed)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(TacketColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ActionPanel<Content: View>: View {
    let title: String
    let systemImage: String
    let detail: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TacketColors.accent)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.tacketBody.weight(.semibold))
                    Text(detail)
                        .font(.tacketFootnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
                .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(TacketColors.recessed)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(TacketColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct FlowButtonRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], alignment: .leading, spacing: 8) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct NativeCaptureReviewCard: View {
    @EnvironmentObject private var model: TacketModel
    let draft: NativeCaptureDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label("Desktop capture preview", systemImage: "doc.text.magnifyingglass")
                    .font(.tacketBody.weight(.semibold))
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Circle()
                        .fill(draft.quality.color)
                        .frame(width: 8, height: 8)
                    Text(draft.quality.label)
                        .font(.tacketFootnote.weight(.semibold))
                        .foregroundStyle(draft.quality.color)
                }
            }

            Text(draft.title)
                .font(.tacketSectionTitle)
                .fixedSize(horizontal: false, vertical: true)

            Text(draft.quality.detail)
                .font(.tacketFootnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                MetadataPill(text: draft.source.label)
                MetadataPill(text: "\(draft.lineCount) lines")
                MetadataPill(text: "\(draft.characterCount) characters")
            }

            ScrollView {
                Text(draft.preview)
                    .font(.tacketMono)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: 120, maxHeight: 210)
            .background(TacketColors.card)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(TacketColors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 10) {
                Button {
                    model.saveNativeCaptureDraft()
                } label: {
                    Label("Save Capture", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isRunning)

                Button {
                    model.discardNativeCaptureDraft()
                } label: {
                    Label("Discard", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .disabled(model.isRunning)

                Text("For exact ChatGPT transcripts, open the thread in Chrome and use the Tacket extension.")
                    .font(.tacketFootnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(TacketColors.recessed)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(draft.quality.color.opacity(0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

struct LibraryPaginationControls: View {
    @EnvironmentObject private var model: TacketModel

    var body: some View {
        HStack(spacing: 10) {
            Button {
                model.previousLibraryPage()
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
            .disabled(model.libraryPage == 0)

            Text("Page \(model.libraryPage + 1) of \(model.libraryPageCount)")
                .font(.tacketFootnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Button {
                model.nextLibraryPage()
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .buttonStyle(.bordered)
            .disabled(model.libraryPage >= model.libraryPageCount - 1)

            Spacer(minLength: 0)

            Text(model.libraryPageRangeText)
                .font(.tacketFootnote)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
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
    @AppStorage("quickCaptureMenuBarEnabled") private var quickCaptureMenuBarEnabled = false
    @AppStorage("quickCaptureOpenPreviewWindow") private var quickCaptureOpenPreviewWindow = true

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
                    eyebrow: "Quick Capture",
                    title: "Menu bar capture",
                    detail: "Add an optional Tacket menu bar item for starting desktop app captures without switching back to the main window first."
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $quickCaptureMenuBarEnabled) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Show Tacket in the menu bar")
                                    .font(.tacketBody.weight(.semibold))
                                Text("The menu appears only when this is on. It captures only after you click a menu item.")
                                    .font(.tacketFootnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .toggleStyle(.switch)

                        Toggle(isOn: $quickCaptureOpenPreviewWindow) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Open Tacket when a preview is ready")
                                    .font(.tacketBody.weight(.semibold))
                                Text("After a menu bar capture, bring Tacket forward so you can review, save, or discard the local preview.")
                                    .font(.tacketFootnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .toggleStyle(.switch)
                        .disabled(!quickCaptureMenuBarEnabled)

                        Text("Quick Capture supports ChatGPT, Claude, and Codex desktop apps. Browser chats still use the Chrome extension for exact transcripts.")
                            .font(.tacketFootnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SectionCard(
                    eyebrow: "Browser",
                    title: "Chrome Web Store extension",
                    detail: "Use the approved Tacket extension to save ChatGPT, Claude, and Gemini browser chats directly to this Mac."
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        ConnectorStatusView()

                        Text("Install the local connector once, then add Tacket from the Chrome Web Store. Browser chat text goes from Chrome to this app through Chrome's local native messaging system. It is not sent to Tacket servers.")
                            .font(.tacketFootnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Button("Install Local Connector") {
                                    model.installPublishedConnector()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.isRunning)

                                Button("Open Chrome Web Store") {
                                    model.openChromeWebStore()
                                }

                                Button("Open Chrome Extensions") {
                                    model.openChromeExtensions()
                                }
                            }

                            HStack(spacing: 10) {
                                Button("Check Connector") {
                                    model.refreshConnectorStatus()
                                }
                                Button("Remove Connector") {
                                    model.uninstallConnector()
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Development only")
                                .font(.tacketBody.weight(.semibold))

                            Text("Use these controls only for an unpacked local extension build. The published Chrome Web Store extension ID is \(TacketModel.publishedChromeExtensionId).")
                                .font(.tacketFootnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 10) {
                                TextField("Chrome extension ID", text: $model.extensionId)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                                Button("Install Development Connector") {
                                    model.installConnector()
                                }
                                .disabled(model.isRunning)
                            }

                            HStack(spacing: 10) {
                                Button("Reveal Bundled Extension") {
                                    model.openExtensionFolder()
                                }
                                Button("Copy Bundled Extension Path") {
                                    model.copyExtensionFolderPath()
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(TacketColors.recessed)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

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
