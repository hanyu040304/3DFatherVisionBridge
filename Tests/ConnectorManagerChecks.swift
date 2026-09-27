import Foundation
import CryptoKit

@main
struct ConnectorManagerChecks {
    @MainActor static func main() throws {
        let fm = FileManager.default
        let temporary = fm.temporaryDirectory.appendingPathComponent("ConnectorChecks-\(UUID().uuidString)")
        try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temporary) }
        let bundle = temporary.appendingPathComponent("Bundle")
        try fm.copyItem(at: URL(fileURLWithPath: CommandLine.arguments[1]), to: bundle)
        let home = temporary.appendingPathComponent("CleanHome")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        let manager = FusionConnectorManager(home: home, bundledURL: bundle, runningProbe: { false })
        precondition(manager.state == .notInstalled)
        try manager.install()
        precondition(manager.detect() == .installed)
        let original = try Data(contentsOf: manager.installURL.appendingPathComponent("FusionSpatialLive.py"))
        try Data("bad receipt".utf8).write(to: manager.installURL.appendingPathComponent("installed.json"))
        precondition(manager.detect() == .broken)
        try manager.repair()

        try Data("broken".utf8).write(to: manager.installURL.appendingPathComponent("FusionSpatialLive.py"))
        precondition(manager.detect() == .broken)
        try manager.repair()
        precondition(manager.detect() == .installed)
        precondition((try? Data(contentsOf: manager.installURL.appendingPathComponent("FusionSpatialLive.py"))) == original)
        let manifestURL = bundle.appendingPathComponent("FusionSpatialLive.manifest")
        var manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
        manifest["version"] = "1.3.0"
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
        var files: [String: String] = [:]
        for name in ["FusionSpatialLive.py", "FusionSpatialLive.manifest"] {
            files[name] = SHA256.hash(data: try Data(contentsOf: bundle.appendingPathComponent(name))).map { String(format: "%02x", $0) }.joined()
        }
        try JSONEncoder().encode(FusionConnectorManager.Inventory(files: files)).write(to: bundle.appendingPathComponent("connector-info.json"))
        precondition(manager.detect() == .updateAvailable)
        try manager.update()
        precondition(manager.installedVersion == "1.3.0")
        let model = home.appendingPathComponent("Documents/FusionSpatialLive/current.usdz")
        try fm.createDirectory(at: model.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("legacy-model".utf8).write(to: model)
        try manager.repair()
        precondition(fm.fileExists(atPath: manager.bridgeURL.appendingPathComponent("current.usdz").path))
        precondition(fm.fileExists(atPath: model.path))
        let legacy = home.appendingPathComponent("Library/Application Support/Autodesk/Autodesk Fusion 360/API/AddIns/FusionSpatialLive")
        try fm.createDirectory(at: legacy, withIntermediateDirectories: true)
        try original.write(to: legacy.appendingPathComponent("FusionSpatialLive.py"))
        try manager.repair()
        precondition(!fm.fileExists(atPath: legacy.path))
        precondition(fm.fileExists(atPath: home.appendingPathComponent("Library/Application Support/FusionSpatialBridge/ConnectorBackups").path))
        let running = FusionConnectorManager(home: home, bundledURL: bundle, runningProbe: { true })
        let result = try running.repair()
        precondition(result.restartRequired && !running.connected)
        do { try running.uninstall(); fatalError("Must not uninstall while running") } catch {}
        let receipt = try JSONDecoder().decode(FusionConnectorManager.Receipt.self, from: Data(contentsOf: manager.installURL.appendingPathComponent("installed.json")))
        let heartbeat: [String: Any] = ["version": "1.3.0", "installationID": receipt.installationID, "pid": ProcessInfo.processInfo.processIdentifier, "timestamp": Date().timeIntervalSince1970]
        let statusURL = manager.bridgeURL.appendingPathComponent("connector-status.json")
        try JSONSerialization.data(withJSONObject: heartbeat).write(to: statusURL)
        running.refreshRuntime()
        precondition(running.connected && !running.restartRequired)
        try fm.removeItem(at: statusURL)
        try manager.uninstall()
        precondition(manager.state == .notInstalled)
        // A corrupt bundle must not destroy a good installed connector.
        try manager.install()
        try Data("damaged bundle".utf8).write(to: bundle.appendingPathComponent("FusionSpatialLive.py"))
        do { try manager.update(); fatalError("Must reject corrupt bundle") } catch {}
        precondition((try? Data(contentsOf: manager.installURL.appendingPathComponent("FusionSpatialLive.py"))) == original)
        print("PASS: clean install, integrity checks, repair, update, model migration, legacy retirement, runtime receipt, restart requirement, uninstall, corrupt-bundle protection")
    }
}
