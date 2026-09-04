import AppKit
import CrabAppSupport
import SwiftUI

@MainActor
final class DesktopPresenceController: ObservableObject {
    @Published private(set) var state = DesktopPresenceState()

    func mainWindowWillClose() {
        guard state.closeMainWindow() else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.state.phase == .menuBarOnly else { return }
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }

    func prepareToShowMainWindow() {
        _ = state.restoreMainWindow()
        NSApplication.shared.setActivationPolicy(.regular)
    }
}

struct MainWindowCloseObserver: NSViewRepresentable {
    let onClose: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onClose: onClose)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.observe(view.window)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.observe(view.window)
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    @MainActor
    final class Coordinator {
        private let onClose: @MainActor () -> Void
        private weak var window: NSWindow?
        private var closeObserver: NSObjectProtocol?

        init(onClose: @escaping @MainActor () -> Void) {
            self.onClose = onClose
        }

        func observe(_ window: NSWindow?) {
            guard let window, self.window !== window else { return }
            stopObserving()
            self.window = window
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.onClose()
                }
            }
        }

        func stopObserving() {
            if let closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
            }
            closeObserver = nil
            window = nil
        }
    }
}
