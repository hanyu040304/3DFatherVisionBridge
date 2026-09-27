import AppKit
import SwiftUI

struct ShortcutRecorderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var shortcutManager: ShortcutManager
    @State private var draft: SendShortcut?
    @State private var message: String?
    @State private var finished = false

    init(shortcutManager: ShortcutManager) {
        self.shortcutManager = shortcutManager
        _draft = State(initialValue: shortcutManager.shortcut)
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 5) {
                Text("设置发送快捷键").font(.title2.weight(.semibold))
                Text("Set Send Shortcut").foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Text("请按下新的快捷键").font(.headline)
                Text("Press a new shortcut").font(.callout).foregroundStyle(.secondary)
                Text(draft?.displayName ?? "未设置 · Not Set")
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                    .frame(minWidth: 250, minHeight: 72)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                if let message {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
            }

            HStack {
                Button("清除 / Clear") { draft = nil; message = nil }
                Button("恢复默认 / Restore Default") {
                    draft = ShortcutManager.defaultShortcut
                    message = nil
                }
                Spacer()
                Button("取消 / Cancel") { dismiss() }
                Button("完成 / Done") {
                    if shortcutManager.updateShortcut(draft) {
                        finished = true
                        dismiss()
                    } else {
                        message = shortcutManager.registrationError
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 430)
        .background {
            ShortcutCaptureView { event in
                switch shortcutManager.shortcut(from: event) {
                case .success(let shortcut): draft = shortcut; message = nil
                case .failure(let error): message = error.localizedDescription
                }
            }
        }
        .onAppear { shortcutManager.unregister() }
        .onDisappear {
            if !finished { _ = shortcutManager.register() }
        }
        .interactiveDismissDisabled()
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onKeyDown = onKeyDown
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onKeyDown = onKeyDown
        DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
    }
}

private final class KeyCaptureNSView: NSView {
    var onKeyDown: ((NSEvent) -> Void)?
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }
}
