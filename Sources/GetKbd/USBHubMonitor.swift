import Foundation
@preconcurrency import IOKit

@MainActor
final class USBHubMonitor {
    var configuredHubIdentifier: String? {
        didSet {
            updateConfiguredPresence(notify: true)
        }
    }

    var onChange: ((Bool) -> Void)?
    var onDevicesChanged: (() -> Void)?
    private(set) var isPresent = false

    var availableHubs: [USBHubDescriptor] {
        connectedHubs.values.sorted {
            $0.menuTitle.localizedCaseInsensitiveCompare($1.menuTitle) == .orderedAscending
        }
    }

    private struct DeviceEvent: Sendable {
        let registryID: UInt64
        let descriptor: USBHubDescriptor?
        let isRemoval: Bool
    }

    private var connectedHubs: [UInt64: USBHubDescriptor] = [:]
    private var notificationPort: IONotificationPortRef?
    private var notificationSource: CFRunLoopSource?
    private var matchingIterator: io_iterator_t = 0
    private var terminatedIterator: io_iterator_t = 0
    private var isStarted = false

    init(configuredHubIdentifier: String?) {
        self.configuredHubIdentifier = configuredHubIdentifier
    }

    func start() {
        guard !isStarted else { return }
        guard let notificationPort = IONotificationPortCreate(kIOMainPortDefault) else {
            GetKbdLog.error("usb.hub.monitor.failed", "Unable to create an IOKit notification port")
            return
        }

        guard let notificationSource = IONotificationPortGetRunLoopSource(notificationPort)?.takeUnretainedValue() else {
            IONotificationPortDestroy(notificationPort)
            GetKbdLog.error("usb.hub.monitor.failed", "Unable to create an IOKit run-loop source")
            return
        }

        self.notificationPort = notificationPort
        self.notificationSource = notificationSource
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            notificationSource,
            CFRunLoopMode.defaultMode
        )

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let matchingResult = IOServiceAddMatchingNotification(
            notificationPort,
            kIOFirstMatchNotification,
            IOServiceMatching("IOUSBHostDevice"),
            Self.deviceMatched,
            context,
            &matchingIterator
        )
        guard matchingResult == kIOReturnSuccess else {
            stop()
            GetKbdLog.error("usb.hub.monitor.failed", "Unable to register USB arrival notification")
            return
        }

        consume(matchingIterator, isRemoval: false, notify: false)

        let terminatedResult = IOServiceAddMatchingNotification(
            notificationPort,
            kIOTerminatedNotification,
            IOServiceMatching("IOUSBHostDevice"),
            Self.deviceRemoved,
            context,
            &terminatedIterator
        )
        guard terminatedResult == kIOReturnSuccess else {
            stop()
            GetKbdLog.error("usb.hub.monitor.failed", "Unable to register USB removal notification")
            return
        }

        consume(terminatedIterator, isRemoval: true, notify: false)
        isStarted = true
        updateConfiguredPresence(notify: false)
        GetKbdLog.event("usb.hub.monitor.started", "hubs=\(connectedHubs.count)")
    }

    func stop() {
        guard isStarted || notificationPort != nil else { return }

        if matchingIterator != 0 {
            IOObjectRelease(matchingIterator)
            matchingIterator = 0
        }
        if terminatedIterator != 0 {
            IOObjectRelease(terminatedIterator)
            terminatedIterator = 0
        }
        if let notificationSource,
           let notificationPort {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                notificationSource,
                CFRunLoopMode.defaultMode
            )
            IONotificationPortDestroy(notificationPort)
        }

        self.notificationSource = nil
        self.notificationPort = nil
        connectedHubs.removeAll()
        isPresent = false
        isStarted = false
    }

    private func consume(_ iterator: io_iterator_t, isRemoval: Bool, notify: Bool) {
        while let service = Self.nextService(iterator) {
            if let event = Self.event(for: service, isRemoval: isRemoval) {
                handle(event, notify: notify)
            }
            IOObjectRelease(service)
        }
    }

    private func handle(_ event: DeviceEvent, notify: Bool) {
        if event.isRemoval {
            connectedHubs.removeValue(forKey: event.registryID)
        } else if let descriptor = event.descriptor {
            connectedHubs[event.registryID] = descriptor
        }

        guard notify else { return }
        onDevicesChanged?()
        updateConfiguredPresence(notify: true)
    }

    private func updateConfiguredPresence(notify: Bool) {
        let newValue = configuredHubIdentifier.map { identifier in
            connectedHubs.values.contains { $0.identifier == identifier }
        } ?? false

        guard newValue != isPresent else { return }
        isPresent = newValue
        guard notify else { return }

        GetKbdLog.event(
            newValue ? "usb.hub.connected" : "usb.hub.disconnected",
            configuredHubIdentifier ?? "none"
        )
        onChange?(newValue)
    }

    private static let deviceMatched: IOServiceMatchingCallback = { context, iterator in
        guard let context else { return }
        let monitor = Unmanaged<USBHubMonitor>
            .fromOpaque(context)
            .takeUnretainedValue()
        let events = events(from: iterator, isRemoval: false)
        Task { @MainActor [weak monitor] in
            guard let monitor else { return }
            events.forEach { monitor.handle($0, notify: true) }
        }
    }

    private static let deviceRemoved: IOServiceMatchingCallback = { context, iterator in
        guard let context else { return }
        let monitor = Unmanaged<USBHubMonitor>
            .fromOpaque(context)
            .takeUnretainedValue()
        let events = events(from: iterator, isRemoval: true)
        Task { @MainActor [weak monitor] in
            guard let monitor else { return }
            events.forEach { monitor.handle($0, notify: true) }
        }
    }

    private static func events(from iterator: io_iterator_t, isRemoval: Bool) -> [DeviceEvent] {
        var events: [DeviceEvent] = []

        while let service = nextService(iterator) {
            if let event = event(for: service, isRemoval: isRemoval) {
                events.append(event)
            }
            IOObjectRelease(service)
        }

        return events
    }

    private static func event(for service: io_service_t, isRemoval: Bool) -> DeviceEvent? {
        var registryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &registryID) == kIOReturnSuccess else {
            return nil
        }

        if isRemoval {
            return DeviceEvent(registryID: registryID, descriptor: nil, isRemoval: true)
        }

        guard let descriptor = descriptor(for: service) else { return nil }
        return DeviceEvent(registryID: registryID, descriptor: descriptor, isRemoval: false)
    }

    private static func descriptor(for service: io_service_t) -> USBHubDescriptor? {
        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            service,
            &unmanagedProperties,
            kCFAllocatorDefault,
            0
        ) == kIOReturnSuccess,
              let unmanagedProperties else {
            return nil
        }

        let properties = unmanagedProperties.takeRetainedValue() as NSDictionary
        guard let deviceClass = number(in: properties, keys: ["bDeviceClass"]),
              deviceClass.intValue == 9,
              let vendorID = number(in: properties, keys: ["idVendor"]),
              let productID = number(in: properties, keys: ["idProduct"]) else {
            return nil
        }

        let name = string(in: properties, keys: ["kUSBProductString", "USB Product Name"]) ?? "USB hub"
        let manufacturer = string(in: properties, keys: ["kUSBVendorString", "USB Vendor Name"]) ?? ""
        let serial = string(in: properties, keys: ["kUSBSerialNumberString", "USB Serial Number"]) ?? ""
        let identifier = serial.isEmpty
            ? "usb-hub-\(vendorID.intValue)-\(productID.intValue)-\(normalized(name))-\(normalized(manufacturer))"
            : "usb-hub-\(vendorID.intValue)-\(productID.intValue)-serial-\(normalized(serial))"

        return USBHubDescriptor(
            identifier: identifier,
            name: name,
            manufacturer: manufacturer,
            vendorID: vendorID.intValue,
            productID: productID.intValue
        )
    }

    private static func number(in properties: NSDictionary, keys: [String]) -> NSNumber? {
        keys.lazy.compactMap { properties[$0] as? NSNumber }.first
    }

    private static func string(in properties: NSDictionary, keys: [String]) -> String? {
        keys.lazy.compactMap { properties[$0] as? String }.first
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func nextService(_ iterator: io_iterator_t) -> io_service_t? {
        let service = IOIteratorNext(iterator)
        return service == 0 ? nil : service
    }
}
