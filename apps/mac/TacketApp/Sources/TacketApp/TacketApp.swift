import SwiftUI
import AppKit

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

    var errorDescription: String? {
        switch self {
        case .nativeHostMissing:
            return "TacketNativeHost was not found. Build the Mac package or run `swift build` in apps/mac/TacketApp."
        case .invalidBundle(let message):
            return "Invalid .tacket bundle: \(message)"
        }
    }
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
    @State private var selectedSection: AppSection = .transfer

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            Divider()
            HStack(alignment: .top, spacing: 0) {
                SidebarView(selectedSection: $selectedSection)
                    .frame(width: 250)
                Divider()
                switch selectedSection {
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
                Text(model.commandOutput.isEmpty ? "Actions and connector details will appear here." : model.commandOutput)
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
