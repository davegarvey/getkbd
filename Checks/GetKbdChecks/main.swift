import Foundation

@main
struct GetKbdChecks {
    static func main() {
        check(
            normalizedBluetoothIdentifier("AA-BB:CC") == "aabbcc",
            "Bluetooth identifier normalization"
        )

        check(AppSettings.initial.needsOnboarding, "initial settings require setup")

        let configured = KeyboardDescriptor(identifier: "keyboard-1", name: "Shared Keyboard")
        var settings = AppSettings.initial
        settings.selectedKeyboard = configured
        settings.selectedDisplay = DisplayDescriptor(
            identifier: "display-1",
            name: "Shared Display",
            isBuiltIn: false
        )
        settings.selectedUSBHub = USBHubDescriptor(
            identifier: "hub-1",
            name: "Switch Hub",
            manufacturer: "Switch Co",
            vendorID: 1,
            productID: 2
        )
        check(!settings.needsOnboarding, "complete local settings are ready")

        print("GetKbd checks passed.")
    }

    private static func check(_ condition: Bool, _ name: String) {
        precondition(condition, "Check failed: \(name)")
    }
}
