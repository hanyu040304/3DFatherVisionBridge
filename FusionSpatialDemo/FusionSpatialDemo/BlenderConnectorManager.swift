import AppKit
import Darwin
import Foundation
import Observation

@MainActor
@Observable
final class BlenderConnectorManager {
    private(set) var installed = false
    private(set) var running = false
    private(set) var connected = false
    private(set) var message = ""
    let bridgeURL: URL
    private let home: URL
    private let bundledURL: URL
    private let fm = FileManager.default

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, bundledURL: URL? = nil) {
        self.home = home
        self.bridgeURL = home.appendingPathComponent("Library/Application Support/FusionSpatialBridge/Bridge/Blender", isDirectory: true)
        self.bundledURL = bundledURL ?? (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("BlenderConnector", isDirectory: true)
        refresh()
    }

    func refresh() {
        running = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "org.blenderfoundation.blender" || $0.localizedName == "Blender"
        }
        installed = installationDirectories().contains { fm.fileExists(atPath: $0.appendingPathComponent("__init__.py").path) }
        if let data = try? Data(contentsOf: bridgeURL.appendingPathComponent("connector-status.json")),
           let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let timestamp = value["timestamp"] as? Double,
           let pid = value["pid"] as? Int {
            connected = running && Date().timeIntervalSince1970 - timestamp < 8 && kill(Int32(pid), 0) == 0
        } else { connected = false }
    }

    func install() {
        do {
            guard fm.fileExists(atPath: bundledURL.appendingPathComponent("__init__.py").path) else {
                throw CocoaError(.fileNoSuchFile)
            }
            let destinations = candidateVersionDirectories()
            guard !destinations.isEmpty else { throw NSError(domain: "FusionSpatial", code: 1, userInfo: [NSLocalizedDescriptionKey: "未找到 Blender 用户目录"] ) }
            for destination in destinations {
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                try fm.copyItem(at: bundledURL, to: destination)
            }
            try fm.createDirectory(at: bridgeURL, withIntermediateDirectories: true)
            message = "Blender Connector 已安装，请在 Blender Add-ons 中启用"
        } catch { message = "Blender Connector 安装失败：\(error.localizedDescription)" }
        refresh()
    }

    func repair() { install() }

    private func candidateVersionDirectories() -> [URL] {
        let root = home.appendingPathComponent("Library/Application Support/Blender", isDirectory: true)
        guard let versions = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) else { return [] }
        return versions.filter { Double($0.lastPathComponent) != nil }.map {
            $0.appendingPathComponent("scripts/addons/fusion_spatial_connector", isDirectory: true)
        }
    }

    private func installationDirectories() -> [URL] { candidateVersionDirectories() }
}
