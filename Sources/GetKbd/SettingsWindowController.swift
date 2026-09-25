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
        onChange: @escaping (AppSettings) -> Void
    ) {
        viewModel = SettingsViewModel(
            settingsStore: settingsStore,
            keyboard: keyboard,
            usbHub: usbHub,
            display: display,
            ownership: ownership,
            onChange: onChange
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "getkbd"
        window.center()
        window.setFrameAutosaveName("getkbd.settings.v2")
        window.isReleasedWhenClosed = false
        let hostingController = NSHostingController(rootView: SettingsView(viewModel: viewModel))
        hostingController.sizingOptions = [.preferredContentSize]
        window.contentViewController = hostingController

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
