import AppKit
import Foundation
import Observation
import CryptoKit
import Darwin

@MainActor
@Observable
final class FusionConnectorManager {
    enum State: String { case notInstalled = "Not Installed", installed = "Installed", updateAvailable = "Update Available", broken = "Broken" }
    struct Manifest: Decodable { let version: String; let runOnStartup: Bool }
    struct Inventory: Codable { let files: [String: String] }
    struct Receipt: Codable { let installationID: String; let version: String }
    struct Heartbeat: Decodable {
        let version: String
        let installationID: String
        let timestamp: Double
        let pid: Int32
    }
    struct Result { let message: String; let restartRequired: Bool }
    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
    }

    private(set) var state: State = .notInstalled
    private(set) var message = ""
    private(set) var bundledVersion = ""
    private(set) var installedVersion = ""
    private(set) var connected = false
    private(set) var fusionRunning = false
    private(set) var fusionInstalled = false
    private(set) var restartRequired = false
    let home: URL
    let bundledURL: URL
    let installURL: URL
    let bridgeURL: URL
    private let fm = FileManager.default
    private let runningProbe: () -> Bool
    private var heartbeat: Heartbeat?

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, bundledURL: URL? = nil, runningProbe: (() -> Bool)? = nil) {
        self.runningProbe = runningProbe ?? {
            NSWorkspace.shared.runningApplications.contains { app in
                ["com.autodesk.fusion360", "com.autodesk.mas.fusion360"].contains(app.bundleIdentifier ?? "")
                    || app.localizedName == "Autodesk Fusion" || app.localizedName == "Autodesk Fusion 360"
            }
        }
        self.home = home
        self.bundledURL = bundledURL ?? (Bundle.main.resourceURL ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources")).appendingPathComponent("FusionConnector", isDirectory: true)
        installURL = home.appendingPathComponent("Library/Application Support/Autodesk/FusionAddins/FusionSpatialLive", isDirectory: true)
        bridgeURL = home.appendingPathComponent("Library/Application Support/FusionSpatialBridge/Bridge", isDirectory: true)
        detect()
    }

    @discardableResult
    func detect() -> State {
        do {
            let bundled = try validate(bundledURL)
            bundledVersion = bundled.version
            if fm.fileExists(atPath: installURL.path) {
                let installed = try validate(installURL)
                installedVersion = installed.version
                let receipt = try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: installURL.appendingPathComponent("installed.json")))
                guard receipt.version == installed.version, UUID(uuidString: receipt.installationID) != nil else {
                    throw Failure.message("Connector 安装记录损坏，请修复")
                }
                let comparison = bundled.version.compare(installed.version, options: .numeric)
                state = comparison == .orderedDescending ? .updateAvailable : .installed
                if comparison == .orderedSame {
                    let expected = try Data(contentsOf: bundledURL.appendingPathComponent("connector-info.json"))
                    guard expected == (try Data(contentsOf: installURL.appendingPathComponent("connector-info.json"))) else {
                        throw Failure.message("Connector 文件不匹配，请点击 Repair Connector")
                    }
                }
            } else { state = .notInstalled; installedVersion = "" }
        } catch {
            state = .broken
            message = error.localizedDescription
        }
        refreshRuntime()
        return state
    }

    func refreshRuntime() {
        let wasConnected = connected
        fusionRunning = runningProbe()
        fusionInstalled = fusionRunning || NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.autodesk.fusion360") != nil
            || NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.autodesk.mas.fusion360") != nil
            || hasDeployedFusion()
        heartbeat = (try? Data(contentsOf: bridgeURL.appendingPathComponent("connector-status.json")))
            .flatMap { try? JSONDecoder().decode(Heartbeat.self, from: $0) }
        let receipt = (try? Data(contentsOf: installURL.appendingPathComponent("installed.json")))
            .flatMap { try? JSONDecoder().decode(Receipt.self, from: $0) }
        connected = false
        if let heartbeat, let receipt,
           heartbeat.installationID == receipt.installationID,
           heartbeat.version == installedVersion,
           Date().timeIntervalSince1970 - heartbeat.timestamp < 8,
           Date().timeIntervalSince1970 >= heartbeat.timestamp - 2,
           heartbeat.pid > 0, kill(heartbeat.pid, 0) == 0, state == .installed || state == .updateAvailable {
            connected = true
            fusionRunning = true
        }
        restartRequired = fm.fileExists(atPath: installURL.path) && fusionRunning && !connected
        if connected && !wasConnected {
            message = "Fusion Connector Connected ✓"
            print("[Connector] connection: ready")
        } else if wasConnected && !connected {
            message = "Fusion 已停止或 Connector 暂时无响应"
            print("[Connector] warning: connector disconnected")
        }
    }

    private func hasDeployedFusion() -> Bool {
        let production = home.appendingPathComponent("Library/Application Support/Autodesk/webdeploy/production")
        guard let versions = try? fm.contentsOfDirectory(at: production, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { return false }
        return versions.contains { version in
            ["Autodesk Fusion.app", "Autodesk Fusion 360.app"].contains { name in
                fm.fileExists(atPath: version.appendingPathComponent(name).appendingPathComponent("Contents/Info.plist").path)
            }
        }
    }

    private func validate(_ directory: URL) throws -> Manifest {
        guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw Failure.message("Connector 目录异常，请修复")
        }
        let inventory = try JSONDecoder().decode(Inventory.self, from: Data(contentsOf: directory.appendingPathComponent("connector-info.json")))
        guard inventory.files["FusionSpatialLive.py"] != nil, inventory.files["FusionSpatialLive.manifest"] != nil else {
            throw Failure.message("Connector 缺少必要文件")
        }
        for (name, expected) in inventory.files {
            guard !name.contains("/"), !name.hasPrefix(".") else { throw Failure.message("Connector 文件清单异常") }
            let url = directory.appendingPathComponent(name)
            guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw Failure.message("Connector 文件不能是链接")
            }
            let digest = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
            guard digest == expected else { throw Failure.message("Connector 文件损坏，请点击 Repair Connector") }
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: directory.appendingPathComponent("FusionSpatialLive.manifest")))
        guard manifest.runOnStartup, manifest.version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil else {
            throw Failure.message("Connector 版本或自动启动设置无效")
        }
        return manifest
    }

    @discardableResult func install() throws -> Result { try deploy() }
    @discardableResult func update() throws -> Result { try deploy() }
    @discardableResult func repair() throws -> Result { try deploy() }

    private func deploy() throws -> Result {
        do {
            let manifest = try validate(bundledURL)
            let parent = installURL.deletingLastPathComponent()
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            try fm.createDirectory(at: bridgeURL, withIntermediateDirectories: true)
            let staging = parent.appendingPathComponent(".FusionSpatialLive-\(UUID().uuidString)")
            try fm.copyItem(at: bundledURL, to: staging)
            defer { try? fm.removeItem(at: staging) }
            _ = try validate(staging)
            let receipt = Receipt(installationID: UUID().uuidString, version: manifest.version)
            try JSONEncoder().encode(receipt).write(to: staging.appendingPathComponent("installed.json"), options: .atomic)
            // Keep legacy model data, but never migrate pending requests or stale responses.
            let legacyModel = home.appendingPathComponent("Documents/FusionSpatialLive/current.usdz")
            let model = bridgeURL.appendingPathComponent("current.usdz")
            if !fm.fileExists(atPath: model.path), fm.fileExists(atPath: legacyModel.path) {
                try fm.copyItem(at: legacyModel, to: model)
            }
            // Move only this product's old connector out of Fusion's discovery paths.
            // Existing loaded Python stays in memory; files remain intact in backups.
            let retired = try retireLegacyInstallations()
            var committed = false
            defer {
                if !committed {
                    for (original, backup) in retired.reversed() { try? fm.moveItem(at: backup, to: original) }
                }
            }
            if fm.fileExists(atPath: installURL.path) {
                guard try installURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                    throw Failure.message("安装目录是链接，请先移除该链接")
                }
                let result = staging.path.withCString { source in
                    installURL.path.withCString { destination in renameatx_np(AT_FDCWD, source, AT_FDCWD, destination, UInt32(RENAME_SWAP)) }
                }
                guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                try? fm.moveItem(at: staging, to: backupURL())
            } else {
                try fm.moveItem(at: staging, to: installURL)
            }
            guard try validate(installURL).version == manifest.version else { throw Failure.message("安装后版本验证失败") }
            committed = true
            detect()
            message = fusionRunning ? "Restart Fusion to finish setup" : "Fusion Connector Installed ✓ — 启动 Fusion"
            if !fusionInstalled { message = "Fusion Connector Installed ✓ — 请先安装 Autodesk Fusion" }
            print("[Connector] install: \(manifest.version)")
            return Result(message: message, restartRequired: restartRequired)
        } catch {
            message = "安装失败：\(error.localizedDescription)"
            print("[Connector] error: \(message)")
            throw error
        }
    }

    private func backupURL() throws -> URL {
        let directory = home.appendingPathComponent("Library/Application Support/FusionSpatialBridge/ConnectorBackups")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("FusionSpatialLive-\(UUID().uuidString)")
    }

    private func retireLegacyInstallations() throws -> [(URL, URL)] {
        var retired: [(URL, URL)] = []
        var succeeded = false
        defer {
            if !succeeded {
                for (original, backup) in retired.reversed() { try? fm.moveItem(at: backup, to: original) }
            }
        }
        for product in ["Autodesk Fusion 360", "Autodesk Fusion"] {
            let old = home.appendingPathComponent("Library/Application Support/Autodesk/\(product)/API/AddIns/FusionSpatialLive")
            guard fm.fileExists(atPath: old.path) else { continue }
            let code = try String(contentsOf: old.appendingPathComponent("FusionSpatialLive.py"), encoding: .utf8)
            guard code.contains("[FusionSpatial]"), code.contains("export-request.json") else {
                throw Failure.message("发现同名的其他插件，未覆盖")
            }
            let backup = try backupURL()
            try fm.moveItem(at: old, to: backup)
            retired.append((old, backup))
            print("[Connector] update: archived legacy connector")
        }
        succeeded = true
        return retired
    }

    @discardableResult
    func uninstall() throws -> Result {
        // Defer uninstall while Python may still be running, rather than removing it.
        refreshRuntime()
        guard !fusionRunning else { throw Failure.message("请先退出 Fusion，再卸载 Connector") }
        if fm.fileExists(atPath: installURL.path) { try fm.moveItem(at: installURL, to: backupURL()) }
        detect()
        message = "Fusion Connector uninstalled"
        print("[Connector] uninstall")
        return Result(message: message, restartRequired: false)
    }
}
