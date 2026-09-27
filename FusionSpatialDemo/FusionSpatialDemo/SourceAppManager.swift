import AppKit
import Observation

enum SourceApp: String {
    case fusion360
    case blender
    case none

    var displayName: String {
        switch self { case .fusion360: "Fusion 360"; case .blender: "Blender"; case .none: "未检测到 / None" }
    }
}

@MainActor
@Observable
final class SourceAppManager: NSObject {
    private(set) var currentSource: SourceApp = .none

    override init() {
        super.init()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(applicationActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
        if let frontmost = NSWorkspace.shared.frontmostApplication { update(from: frontmost) }
        if currentSource == .none { chooseRunningFallback() }
    }

    @objc private func applicationActivated(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        update(from: application)
    }

    private func update(from application: NSRunningApplication) {
        let identifier = application.bundleIdentifier ?? ""
        if ["com.autodesk.fusion360", "com.autodesk.mas.fusion360"].contains(identifier)
            || ["Autodesk Fusion", "Autodesk Fusion 360"].contains(application.localizedName ?? "") {
            currentSource = .fusion360
        } else if identifier == "org.blenderfoundation.blender" || application.localizedName == "Blender" {
            currentSource = .blender
        }
    }

    private func chooseRunningFallback() {
        for application in NSWorkspace.shared.runningApplications.reversed() {
            update(from: application)
            if currentSource != .none { return }
        }
    }
}
