import AppKit
import Foundation
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: SettingsViewModel

    init(
        settingsStore: SettingsStore,
        keyboard: KeyboardControlling,
        usbHub: USBHubMonitor,
        display: DisplayMonitor,
        ownership: OwnershipController,
        peer: PeerVerificationController,
        onChange: @escaping (AppSettings) -> Void
    ) {
        viewModel = SettingsViewModel(
            settingsStore: settingsStore,
            keyboard: keyboard,
            usbHub: usbHub,
            display: display,
            ownership: ownership,
            peer: peer,
            onChange: onChange
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "getkbd"
        window.center()
        window.setFrameAutosaveName("getkbd.settings")
        window.minSize = NSSize(width: 820, height: 580)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: SettingsView(viewModel: viewModel)
        )

        super.init(window: window)
        window.delegate = self
        viewModel.reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showAndFocus() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func reload() {
        viewModel.reload()
    }

    func update(snapshot: OwnershipSnapshot) {
        viewModel.update(snapshot: snapshot)
    }

    func refreshPeerState() {
        viewModel.refreshPeerState()
    }

    func showMessage(_ message: String) {
        viewModel.showMessage(message)
    }

    func usbHubListChanged() {
        viewModel.usbHubListChanged()
    }

    func windowWillClose(_ notification: Notification) {
        viewModel.windowWillClose()
    }
}
