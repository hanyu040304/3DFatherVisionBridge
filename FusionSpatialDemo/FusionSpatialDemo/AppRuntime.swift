import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppRuntime {
    let bridge: SpatialBridge
    let shortcutManager: ShortcutManager
    let blenderConnector: BlenderConnectorManager
    let sourceManager: SourceAppManager
    private var monitorTask: Task<Void, Never>?

    init() {
        let bridge = SpatialBridge()
        let shortcutManager = ShortcutManager()
        let blenderConnector = BlenderConnectorManager()
        let sourceManager = SourceAppManager()
        self.bridge = bridge
        self.shortcutManager = shortcutManager
        self.blenderConnector = blenderConnector
        self.sourceManager = sourceManager
        self.monitorTask = nil

        bridge.configure(sourceManager: sourceManager, blenderConnector: blenderConnector)
        shortcutManager.onTrigger = { [weak bridge] in
            guard let bridge else { return }
            Task { await bridge.sendNow() }
        }
        _ = shortcutManager.register()
        monitorTask = Task { await bridge.monitor() }
    }
}

final class FusionSpatialAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
