import SwiftUI
import AppKit
import Foundation
import Observation
import SpatialPreview
import UniformTypeIdentifiers

@main
struct FusionSpatialBridgeApp: App {
    @NSApplicationDelegateAdaptor(FusionSpatialAppDelegate.self) private var appDelegate
    @State private var runtime = AppRuntime()

    var body: some Scene {
        Window("Fusion Spatial", id: "main") {
            ContentView(
                bridge: runtime.bridge,
                shortcutManager: runtime.shortcutManager,
                blenderConnector: runtime.blenderConnector,
                sourceManager: runtime.sourceManager
            )
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)

        MenuBarExtra("Fusion Spatial", systemImage: "cube.transparent") {
            FusionSpatialMenuBar(
                bridge: runtime.bridge,
                blenderConnector: runtime.blenderConnector,
                shortcutManager: runtime.shortcutManager,
                sourceManager: runtime.sourceManager
            )
        }
        .menuBarExtraStyle(.menu)
    }
}

struct ContentView: View {
    @Bindable var bridge: SpatialBridge
    @Bindable var shortcutManager: ShortcutManager
    @Bindable var blenderConnector: BlenderConnectorManager
    @Bindable var sourceManager: SourceAppManager
    @State private var showingShortcutRecorder = false
    @State private var selectedConnector: SourceApp = .fusion360

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            mainContent
        }
        .frame(minWidth: 960, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingShortcutRecorder) {
            ShortcutRecorderSheet(shortcutManager: shortcutManager)
        }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 13) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable().frame(width: 46, height: 46)
                    BilingualText("Fusion Spatial", "将你的设计带入空间\nBring Your Designs Into Spatial", titleSize: 20)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeading("应用连接器", "APP CONNECTORS")
                    ConnectorCard(asset: "Fusion360Icon", fallback: "cube", title: "Fusion 360",
                                  chinese: fusionState.chinese, english: fusionState.english,
                                  color: fusionState.color, selected: selectedConnector == .fusion360) {
                        selectedConnector = .fusion360
                    }
                    ConnectorCard(asset: nil, fallback: "cube.fill", title: "Blender",
                                  chinese: blenderState.chinese, english: blenderState.english,
                                  color: blenderState.color, selected: selectedConnector == .blender) {
                        selectedConnector = .blender
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeading("当前来源", "CURRENT SOURCE")
                    StatusRow(asset: nil, fallback: "cursorarrow.motionlines",
                              title: sourceManager.currentSource.displayName,
                              chinese: "最近使用", english: "Last Active",
                              color: sourceManager.currentSource == .none ? .secondary : .green)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeading("连接器操作", "CONNECTOR ACTIONS")
                    connectorActions
                }
                .disabled(bridge.connecting || bridge.sending)

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeading("空间操作", "SPATIAL ACTIONS")
                    StatusRow(asset: "VisionProIcon", fallback: "visionpro", title: "Apple Vision Pro",
                              chinese: bridge.visionConnected ? "已连接" : "等待设备",
                              english: bridge.visionConnected ? "Connected" : "Waiting",
                              color: bridge.visionConnected ? .green : .secondary)
                    sidebarSendButton
                    shortcutButton
                    if !bridge.visionConnected {
                        SidebarButton("连接 Vision Pro", "Connect Vision Pro", icon: "visionpro") {
                            Task { await bridge.connect() }
                        }
                    }
                }
                .disabled(bridge.connecting || bridge.sending)

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        BilingualText("实时预览（自动更新）", "Live Preview (Auto Update)", titleSize: 13)
                        Text(bridge.liveActive ? "活动中 · Active" : "等待 · Waiting")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $bridge.liveEnabled).labelsHidden()
                }
                .padding(14)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(24)
        }
        .frame(minWidth: 290, idealWidth: 330, maxWidth: 350)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder private var connectorActions: some View {
        switch selectedConnector {
        case .fusion360:
            if bridge.connector.state == .notInstalled {
                SidebarButton("安装 Fusion 连接器", "Install Fusion Connector", icon: "shippingbox") { bridge.installConnector() }
            } else if bridge.connector.state == .updateAvailable {
                SidebarButton("更新 Fusion 连接器", "Update Fusion Connector", icon: "arrow.down.circle") { bridge.installConnector(update: true) }
            } else {
                SidebarButton("修复 Fusion 连接器", "Repair Fusion Connector", icon: "wrench.and.screwdriver") { bridge.installConnector(repair: true) }
            }
            SidebarButton("打开 Fusion 导出文件夹", "Open Fusion Export Folder", icon: "folder") {
                NSWorkspace.shared.open(bridge.connector.bridgeURL)
            }
        case .blender:
            if blenderConnector.installed {
                SidebarButton("修复 Blender 连接器", "Repair Blender Connector", icon: "wrench.and.screwdriver") { blenderConnector.repair() }
            } else {
                SidebarButton("安装 Blender 连接器", "Install Blender Connector", icon: "shippingbox") { blenderConnector.install() }
            }
            SidebarButton("打开 Blender 导出文件夹", "Open Blender Export Folder", icon: "folder") {
                NSWorkspace.shared.open(blenderConnector.bridgeURL)
            }
        case .none:
            EmptyView()
        }
    }

    private var shortcutButton: some View {
        Button { showingShortcutRecorder = true } label: {
            HStack(spacing: 11) {
                Image(systemName: "keyboard").frame(width: 20)
                BilingualText("发送快捷键", "Send Shortcut", titleSize: 13)
                Spacer()
                Text(shortcutManager.shortcut?.displayName ?? "未设置")
                    .font(.system(.callout, design: .rounded).weight(.medium)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 4)
        }
        .buttonStyle(.bordered).controlSize(.large)
    }

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 28) {
                        heroText
                        Spacer(minLength: 12)
                        HeroAssetView().frame(minWidth: 220, idealWidth: 290, maxWidth: 330,
                                              minHeight: 180, idealHeight: 220, maxHeight: 250)
                    }
                    VStack(alignment: .leading, spacing: 22) {
                        heroText
                        HeroAssetView().frame(maxWidth: .infinity, minHeight: 180, idealHeight: 220, maxHeight: 250)
                    }
                }

                VStack(spacing: 16) {
                    Button { Task { await bridge.sendNow() } } label: {
                        HStack(spacing: 12) {
                            if bridge.sending { ProgressView().controlSize(.small).tint(.white) }
                            else { Image(systemName: "paperplane.fill") }
                            VStack(spacing: 1) {
                                Text(bridge.sending ? "正在更新" : "发送当前模型").font(.headline)
                                Text(bridge.sending ? "Updating" : "Send Current Model").font(.caption)
                            }
                        }
                        .frame(minWidth: 220, maxWidth: 280, minHeight: 54)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(bridge.connecting || bridge.sending)
                    .keyboardShortcut(.return, modifiers: [.command])

                    VStack(spacing: 3) {
                        Text(operationState.chinese).font(.callout.weight(.medium))
                        Text(operationState.english).font(.caption).foregroundStyle(.secondary)
                        if operationState.detail != operationState.chinese {
                            Text(operationState.detail).font(.caption).foregroundStyle(operationState.color)
                                .lineLimit(2).multilineTextAlignment(.center)
                        }
                    }
                    .frame(minHeight: 48)
                }
                .frame(maxWidth: .infinity)

                PerformanceStrip(summary: bridge.timingSummary, fileSize: bridge.modelFileSizeText)
            }
            .padding(.horizontal, 40).padding(.vertical, 34)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var heroText: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("当前模型  →  Apple Vision Pro", systemImage: "arrow.right")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text("让设计，突破屏幕的边界")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .lineLimit(2).minimumScaleFactor(0.82)
                Text("Bring Your Designs Into Spatial")
                    .font(.title3).foregroundStyle(.secondary).lineLimit(2)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("将当前 3D 模型发送到 Apple Vision Pro，\n在真实空间中查看与评审设计。")
                    .font(.body).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                Text("Send the current 3D model to Apple Vision Pro\nfor spatial review.")
                    .font(.callout).foregroundStyle(.secondary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minWidth: 300, maxWidth: 540, alignment: .leading)
    }

    private var sidebarSendButton: some View {
        Button { Task { await bridge.sendNow() } } label: {
            HStack(spacing: 11) {
                Image(systemName: "paperplane.fill").frame(width: 20)
                BilingualText("发送当前模型", "Send Current Model", titleSize: 13)
                Spacer()
            }
            .frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent).controlSize(.large)
        .disabled(bridge.connecting || bridge.sending)
    }

    private var fusionState: (chinese: String, english: String, color: Color) {
        if bridge.connector.connected { return ("已连接", "Connected", .green) }
        switch bridge.connector.state {
        case .notInstalled: return ("未安装", "Not Installed", .secondary)
        case .updateAvailable: return ("有可用更新", "Update Available", .orange)
        case .broken: return ("连接器异常", "Needs Repair", .red)
        case .installed: return bridge.connector.restartRequired
            ? ("需要重启 Fusion", "Restart Required", .orange) : ("已安装", "Installed", .secondary)
        }
    }

    private var blenderState: (chinese: String, english: String, color: Color) {
        blenderConnector.connected ? ("已连接", "Connected", .green)
            : (blenderConnector.installed ? ("已安装", "Installed", .secondary) : ("未安装", "Not Installed", .secondary))
    }

    private var operationState: (chinese: String, english: String, detail: String, color: Color) {
        let status = bridge.status
        if bridge.connecting { return ("正在连接", "Connecting", status, .secondary) }
        if bridge.sending && status.contains("导出") { return ("正在导出", "Exporting", status, .secondary) }
        if bridge.sending { return ("正在发送", "Sending", status, .secondary) }
        if status.contains("发送完成") || status.contains("已更新") {
            return ("发送完成", "Sent Successfully", "请在 Vision Pro 中查看模型", .green)
        }
        if status.contains("失败") || status.contains("错误") || status.contains("损坏") {
            return ("操作失败", "Action Failed", status, .red)
        }
        return ("准备就绪", "Ready", status, .secondary)
    }
}

private struct FusionSpatialMenuBar: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var bridge: SpatialBridge
    @Bindable var blenderConnector: BlenderConnectorManager
    @Bindable var shortcutManager: ShortcutManager
    @Bindable var sourceManager: SourceAppManager

    var body: some View {
        Text("Fusion 360 — \(bridge.connector.connected ? "已连接 / Connected" : "未连接 / Not Connected")")
        Text("Blender — \(blenderStatus)")
        Text("Apple Vision Pro — \(bridge.visionConnected ? "已连接 / Connected" : "等待 / Waiting")")
        Text("当前来源 / Current Source — \(sourceManager.currentSource.displayName)")
        Divider()
        Button(sendTitle) { Task { await bridge.sendNow() } }
            .disabled(bridge.sending || bridge.connecting)
        Divider()
        Button("打开 Fusion Spatial / Show Fusion Spatial") {
            NSApplication.shared.activate()
            openWindow(id: "main")
        }
        Button("退出 / Quit") {
            NSApplication.shared.terminate(nil)
        }
    }

    private var blenderStatus: String {
        if blenderConnector.connected { return "已连接 / Connected" }
        if blenderConnector.installed { return "已安装 / Installed" }
        return "未安装 / Not Installed"
    }

    private var sendTitle: String {
        let shortcut = shortcutManager.shortcut.map { "   \($0.displayName)" } ?? ""
        if bridge.sending { return "发送中… / Sending…\(shortcut)" }
        if bridge.status.contains("发送完成") { return "已发送 / Sent\(shortcut)" }
        if bridge.status.contains("失败") || bridge.status.contains("错误") {
            return "发送失败 / Send Failed\(shortcut)"
        }
        return "发送当前模型 / Send Current Model\(shortcut)"
    }
}

private struct BilingualText: View {
    let chinese: String
    let english: String
    let titleSize: CGFloat
    init(_ chinese: String, _ english: String, titleSize: CGFloat) {
        self.chinese = chinese; self.english = english; self.titleSize = titleSize
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(chinese).font(.system(size: titleSize, weight: .medium))
            Text(english).font(.system(size: max(10, titleSize - 3))).foregroundStyle(.secondary)
        }
    }
}

private struct SectionHeading: View {
    let chinese: String; let english: String
    init(_ chinese: String, _ english: String) { self.chinese = chinese; self.english = english }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(chinese).font(.caption.weight(.semibold))
            Text(english).font(.system(size: 9, weight: .medium)).tracking(0.5).foregroundStyle(.tertiary)
        }
    }
}

private struct StatusRow: View {
    let asset: String?; let fallback: String; let title: String
    let chinese: String; let english: String; let color: Color
    var body: some View {
        HStack(spacing: 12) {
            AssetOrSymbol(asset: asset, fallback: fallback).frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.medium))
                HStack(spacing: 6) {
                    Circle().fill(color).frame(width: 7, height: 7)
                    Text(chinese).font(.caption)
                    Text(english).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ConnectorCard: View {
    let asset: String?
    let fallback: String
    let title: String
    let chinese: String
    let english: String
    let color: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                AssetOrSymbol(asset: asset, fallback: fallback).frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.callout.weight(.medium))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Circle().fill(color).frame(width: 7, height: 7)
                        Text(chinese).font(.caption)
                        Text(english).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.caption.weight(.semibold)).foregroundStyle(.tint) }
            }
            .padding(12)
            .contentShape(Rectangle())
            .background(selected ? Color.accentColor.opacity(0.10) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarButton: View {
    let chinese: String; let english: String; let icon: String; let action: () -> Void
    init(_ chinese: String, _ english: String, icon: String, action: @escaping () -> Void) {
        self.chinese = chinese; self.english = english; self.icon = icon; self.action = action
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon).frame(width: 20)
                BilingualText(chinese, english, titleSize: 13)
                Spacer()
            }
            .frame(maxWidth: .infinity).padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}

private struct AssetOrSymbol: View {
    let asset: String?; let fallback: String
    var body: some View {
        if let asset, let image = NSImage(named: asset) {
            Image(nsImage: image).resizable().scaledToFit()
        } else if let image = NSImage(systemSymbolName: fallback, accessibilityDescription: nil) {
            Image(nsImage: image).resizable().scaledToFit().foregroundStyle(.secondary)
        } else {
            Image(systemName: "cube").resizable().scaledToFit().foregroundStyle(.secondary)
        }
    }
}

private struct HeroAssetView: View {
    var body: some View {
        ZStack {
            if let image = NSImage(named: "VisionProHero") {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.thinMaterial)
                    .overlay {
                        VStack(spacing: 10) {
                            AssetOrSymbol(asset: nil, fallback: "visionpro").frame(width: 58, height: 58)
                            Text("VisionProHero").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
            }
        }
        .mask(LinearGradient(colors: [.black, .black, .black.opacity(0.45)],
                             startPoint: .top, endPoint: .bottom))
    }
}

private struct PerformanceStrip: View {
    let summary: String; let fileSize: String
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 18)], alignment: .leading, spacing: 14) {
            metric("导出", "Export", value(for: "导出"))
            metric("传输", "Transfer", value(for: "发送"))
            metric("文件", "File", fileSize)
        }
        .padding(.vertical, 14).padding(.horizontal, 18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .opacity(summary.isEmpty ? 0.62 : 1)
    }

    private func metric(_ chinese: String, _ english: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(chinese).font(.caption.weight(.medium))
            Text(english).font(.caption2).foregroundStyle(.tertiary)
            Text(value).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
        }
        .frame(minWidth: 76, alignment: .leading)
    }

    private func value(for key: String) -> String {
        guard let range = summary.range(of: #"\#(key)\s+([0-9.]+)s"#, options: .regularExpression) else { return "—" }
        return summary[range].split(separator: " ").last.map { String($0).replacingOccurrences(of: "s", with: " s") } ?? "—"
    }
}

@MainActor
@Observable
final class SpatialBridge {
    private(set) var status = "Waiting for Vision Pro"
    private(set) var timingSummary = ""
    private(set) var connecting = false
    private(set) var sending = false
    let connector = FusionConnectorManager()
    var liveEnabled = false
    private var monitoring = false
    private var lastChange: String?
    private var pendingChangeAt: Date?
    private var lastEndpointAvailable = false
    private weak var sourceManager: SourceAppManager?
    private var blenderConnector: BlenderConnectorManager?
    var visionConnected: Bool { observer.isEndpointAvailable && session?.state == .connected }
    var liveActive: Bool { liveEnabled && connector.connected && visionConnected }
    var modelFileSizeText: String {
        let modelURL = activeBridgeDirectory.appendingPathComponent("current.usdz")
        guard let values = try? modelURL.resourceValues(forKeys: [.fileSizeKey]),
              let bytes = values.fileSize else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
    var fusionStatus: String {
        if connector.connected { return "Connected" }
        if connector.state == .notInstalled { return "Connector Not Installed" }
        if connector.state == .broken { return "Connector Broken" }
        if connector.state == .updateAvailable { return "Update Available" }
        if connector.restartRequired { return "Restart Fusion Required" }
        return connector.fusionInstalled ? "Start Fusion" : "Fusion Not Installed"
    }
    private let observer = ConnectedSpatialEndpointObserver()
    private var session: DocumentPreviewSession?
    private var fileURL: URL { connector.bridgeURL.appendingPathComponent("current.usdz") }
    private var activeBridgeDirectory: URL {
        sourceManager?.currentSource == .blender
            ? (blenderConnector?.bridgeURL ?? connector.bridgeURL)
            : connector.bridgeURL
    }

    init() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            status = "Cannot create model directory: \(error.localizedDescription)"
        }
    }

    func configure(sourceManager: SourceAppManager, blenderConnector: BlenderConnectorManager) {
        self.sourceManager = sourceManager
        self.blenderConnector = blenderConnector
    }

    func installConnector(update: Bool = false, repair: Bool = false) {
        do {
            let result = try repair ? connector.repair() : (update ? connector.update() : connector.install())
            status = result.message
        } catch { status = error.localizedDescription }
    }

    func monitor() async {
        guard !monitoring else { return }
        monitoring = true
        defer { monitoring = false }
        while !Task.isCancelled {
            connector.refreshRuntime()
            blenderConnector?.refresh()
            let available = observer.isEndpointAvailable
            if available && !lastEndpointAvailable && !connecting && !sending {
                lastEndpointAvailable = true
                await connect()
            } else if !available { lastEndpointAvailable = false }
            if let data = try? Data(contentsOf: activeBridgeDirectory.appendingPathComponent("model-change.json")),
               let change = try? JSONDecoder().decode(ModelChange.self, from: data), change.id != lastChange {
                lastChange = change.id
                pendingChangeAt = Date()
            }
            if !liveEnabled { pendingChangeAt = nil }
            if liveActive, !sending, !connecting, let pending = pendingChangeAt,
               Date().timeIntervalSince(pending) >= 1.5 {
                pendingChangeAt = nil
                await sendNow()
            }
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
        }
    }

    private struct ModelChange: Decodable { let id: String }

    func connect() async {
        guard !connecting, !sending else { return }
        connecting = true
        status = "Checking Vision Pro connection…"
        print("[Spatial] Connect requested; endpoint available: \(observer.isEndpointAvailable)")
        defer { connecting = false }
        guard observer.isEndpointAvailable else {
            status = "Waiting for Vision Pro"
            return
        }
        do {
            status = "Getting Vision Pro endpoint…"
            let endpoint = try await observer.endpoint
            print("[Spatial] Endpoint obtained")
            if let session { try? await session.close() }
            session = nil
            let newSession = DocumentPreviewSession(name: "Fusion Live Model", contentType: .usdz)
            do {
                status = "Starting Spatial Preview on Vision Pro…"
                print("[Spatial] Starting preview session")
                try await newSession.start(endpoint: endpoint)
            } catch {
                try? await newSession.close()
                throw error
            }
            session = newSession
            status = "Vision Pro Connected"
            print("[Spatial] Vision Pro connected")
            connecting = false
        } catch {
            status = observer.isEndpointAvailable
                ? "Connection failed: \(error.localizedDescription)"
                : "Waiting for Vision Pro"
        }
    }

    private struct ExportRequest: Encodable {
        let id: String
        let requestedAt: Double
        let expiresAt: Double
    }

    private struct ExportResponse: Decodable {
        let id: String
        let status: String
        let message: String
        let timings: [String: Double]?
    }

    private func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }

    func sendNow() async {
        guard !sending, !connecting else { return }
        let source = sourceManager?.currentSource ?? .fusion360
        let directory: URL
        switch source {
        case .fusion360:
            connector.detect()
            guard connector.connected else {
                status = connector.restartRequired ? "Restart Fusion to apply changes" : "请先连接 Fusion Connector 并启动 Fusion"
                return
            }
            directory = connector.bridgeURL
        case .blender:
            blenderConnector?.refresh()
            guard let blenderConnector, blenderConnector.connected else {
                status = "请安装并启用 Blender Connector，然后保持 Blender 运行"
                return
            }
            directory = blenderConnector.bridgeURL
        case .none:
            status = "未检测到受支持的 3D 软件"
            return
        }
        guard observer.isEndpointAvailable, let session, session.state == .connected else {
            status = "请先点击 Connect Vision Pro 连接设备"
            return
        }
        sending = true
        timingSummary = ""
        let started = ContinuousClock.now
        defer { sending = false }
        let modelURL = directory.appendingPathComponent("current.usdz")
        let requestURL = directory.appendingPathComponent("export-request.json")
        let responseURL = directory.appendingPathComponent("export-response.json")
        let id = UUID().uuidString
        do {
            let request = ExportRequest(id: id, requestedAt: Date().timeIntervalSince1970, expiresAt: Date().timeIntervalSince1970 + 120)
            try JSONEncoder().encode(request).write(to: requestURL, options: .atomic)
            print("[Spatial] Requesting Fusion export: \(id)")
            status = "等待 Fusion 响应…请保持 Add-in 运行"
            defer {
                // Stop an unhandled request from exporting after this operation ends.
                try? FileManager.default.removeItem(at: requestURL)
            }
            let deadline = ContinuousClock.now.advanced(by: .seconds(120))
            while ContinuousClock.now < deadline {
                try Task.checkCancellation()
                guard observer.isEndpointAvailable, session.state == .connected else {
                    status = "Vision Pro 已断开，请重新连接"
                    return
                }
                if let data = try? Data(contentsOf: responseURL),
                   let response = try? JSONDecoder().decode(ExportResponse.self, from: data),
                   response.id == id {
                    switch response.status {
                    case "exporting":
                        status = "Fusion 正在导出模型…"
                    case "error":
                        status = "导出失败：\(response.message)"
                        return
                    case "complete":
                        guard observer.isEndpointAvailable, session.state == .connected else {
                            status = "模型已导出，但 Vision Pro 已断开，请重新连接后更新"
                            return
                        }
                        guard FileManager.default.fileExists(atPath: modelURL.path) else {
                            status = "模型文件不存在，请重新发送"
                            return
                        }
                        status = "正在发送到 Vision Pro…"
                        print("[Spatial] Sending update")
                        let sendStarted = ContinuousClock.now
                        try await session.updateContents(url: modelURL)
                        let sendSeconds = seconds(sendStarted.duration(to: .now))
                        let totalSeconds = seconds(started.duration(to: .now))
                        let waitingSeconds = seconds(started.duration(to: sendStarted))
                        var timings = response.timings ?? [:]
                        timings["sendSeconds"] = sendSeconds
                        timings["totalSeconds"] = totalSeconds
                        timings["requestToReadySeconds"] = waitingSeconds
                        if let exportSeconds = timings["exportSeconds"] {
                            timingSummary = String(format: "等待 %.1fs · 导出 %.1fs · 文件 %.3fs\n发送 %.1fs · 总计 %.1fs",
                                timings["queueSeconds", default: 0] + timings["detectionSeconds", default: 0],
                                exportSeconds, timings["fileSeconds", default: 0], sendSeconds, totalSeconds)
                        } else {
                            timingSummary = String(format: "等待及导出 %.1fs · 发送 %.1fs\n请重启 Fusion 加载新版分段计时", waitingSeconds, sendSeconds)
                        }
                        if let timingData = try? JSONEncoder().encode(timings) {
                            try? timingData.write(to: directory.appendingPathComponent("last-update-timing.json"), options: .atomic)
                        }
                        print("[Spatial] Timings: \(timings)")
                        status = "发送完成 · 请在 Vision Pro 查看模型"
                        print("[Spatial] Update complete")
                        return
                    default: break
                    }
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            status = "等待超时：请确认 Fusion Add-in 已启动，完成当前命令后重试"
        } catch {
            status = "更新失败：\(error.localizedDescription)"
            print("[Spatial] Update failed: \(error)")
        }
    }
}
