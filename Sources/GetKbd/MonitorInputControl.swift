import CoreGraphics
import Foundation
@preconcurrency import IOKit

/// Reads and changes the selected monitor's input source over DDC/CI.
protocol MonitorInputControl: Sendable {
    func readInput(displayIdentifier: String) async -> Int?
    func setInput(_ value: Int, displayIdentifier: String) async -> Bool
}

enum DDCInputReply {
    static let inputSourceCode: UInt8 = 0x60

    /// Parses a Get VCP Feature reply for the input source, returning the current value.
    static func currentValue(from reply: [UInt8]) -> Int? {
        // Layout: 6E 88 02 <result> <vcp> <type> <maxHi> <maxLo> <curHi> <curLo> <checksum>
        guard reply.count >= 11,
              reply[0] == 0x6E,
              reply[2] == 0x02,
              reply[3] == 0x00,
              reply[4] == inputSourceCode else {
            return nil
        }
        return Int(reply[8]) << 8 | Int(reply[9])
    }
}

typealias IOAVServiceRef = CFTypeRef

@_silgen_name("IOAVServiceCreateWithService")
private func IOAVServiceCreateWithService(
    _ allocator: CFAllocator?,
    _ service: io_service_t
) -> Unmanaged<IOAVServiceRef>?

@_silgen_name("IOAVServiceReadI2C")
private func IOAVServiceReadI2C(
    _ service: IOAVServiceRef,
    _ chipAddress: UInt32,
    _ offset: UInt32,
    _ buffer: UnsafeMutableRawPointer,
    _ size: UInt32
) -> IOReturn

@_silgen_name("IOAVServiceWriteI2C")
private func IOAVServiceWriteI2C(
    _ service: IOAVServiceRef,
    _ chipAddress: UInt32,
    _ dataAddress: UInt32,
    _ buffer: UnsafeMutableRawPointer,
    _ size: UInt32
) -> IOReturn

// Apple Silicon exposes external-display DDC/CI through undocumented IOAVService functions.
// They are kept in this adapter so that a failure only hides the monitor menu actions.
final class IOAVMonitorInputControl: MonitorInputControl {
    private static let chipAddress: UInt32 = 0x37
    private static let dataAddress: UInt32 = 0x51
    private static let replyDelay: useconds_t = 50_000
    private static let readAttempts = 5

    private let queue = DispatchQueue(label: "com.getkbd.ddc", qos: .utility)

    func readInput(displayIdentifier: String) async -> Int? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Self.read(displayIdentifier: displayIdentifier))
            }
        }
    }

    func setInput(_ value: Int, displayIdentifier: String) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Self.write(value, displayIdentifier: displayIdentifier))
            }
        }
    }

    private static func read(displayIdentifier: String) -> Int? {
        guard let service = service(for: displayIdentifier) else { return nil }

        var request: [UInt8] = [0x82, 0x01, DDCInputReply.inputSourceCode, 0]
        request[3] = checksum(request[0..<3])

        for _ in 0..<readAttempts {
            let written = request.withUnsafeMutableBytes {
                IOAVServiceWriteI2C(service, chipAddress, dataAddress, $0.baseAddress!, UInt32($0.count))
            }
            usleep(replyDelay)
            guard written == kIOReturnSuccess else { continue }

            var reply = [UInt8](repeating: 0, count: 12)
            let read = reply.withUnsafeMutableBytes {
                IOAVServiceReadI2C(service, chipAddress, dataAddress, $0.baseAddress!, UInt32($0.count))
            }
            if read == kIOReturnSuccess, let value = DDCInputReply.currentValue(from: reply) {
                return value
            }
            usleep(replyDelay)
        }
        return nil
    }

    private static func write(_ value: Int, displayIdentifier: String) -> Bool {
        guard let service = service(for: displayIdentifier),
              (0...0xFFFF).contains(value) else {
            return false
        }

        var packet: [UInt8] = [0x84, 0x03, DDCInputReply.inputSourceCode, UInt8(value >> 8), UInt8(value & 0xFF), 0]
        packet[5] = checksum(packet[0..<5])

        // Monitors occasionally drop a single write, so the command is sent twice.
        var succeeded = false
        for _ in 0..<2 {
            let result = packet.withUnsafeMutableBytes {
                IOAVServiceWriteI2C(service, chipAddress, dataAddress, $0.baseAddress!, UInt32($0.count))
            }
            succeeded = succeeded || result == kIOReturnSuccess
            usleep(replyDelay)
        }
        return succeeded
    }

    private static func checksum(_ bytes: ArraySlice<UInt8>) -> UInt8 {
        bytes.reduce(0x6E ^ UInt8(dataAddress)) { $0 ^ $1 }
    }

    // MARK: - Control channel lookup

    struct ProductNumbers: Equatable {
        let vendor: UInt32
        let model: UInt32
        let serial: UInt32
    }

    /// Finds the external DCPAVServiceProxy whose display matches the identifier.
    private static func service(for displayIdentifier: String) -> IOAVServiceRef? {
        guard let target = productNumbers(forDisplayIdentifier: displayIdentifier) else { return nil }
        let channels = externalChannels()

        if let match = channels.first(where: { $0.product == target }) {
            return match.service
        }
        // The display is online but its registry attributes did not match; with a single
        // external channel there is no ambiguity.
        return channels.count == 1 ? channels[0].service : nil
    }

    static func productNumbers(forDisplayIdentifier identifier: String) -> ProductNumbers? {
        guard let displayID = DisplayMonitor.currentOnlineDisplayIDs()
            .first(where: { DisplayMonitor.identifier(for: $0) == identifier }) else {
            return nil
        }
        return ProductNumbers(
            vendor: CGDisplayVendorNumber(displayID),
            model: CGDisplayModelNumber(displayID),
            serial: CGDisplaySerialNumber(displayID)
        )
    }

    static func externalChannels() -> [(product: ProductNumbers?, service: IOAVServiceRef)] {
        var iterator = io_iterator_t()
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard IORegistryEntryCreateIterator(
            root,
            kIOServicePlane,
            IOOptionBits(kIORegistryIterateRecursively),
            &iterator
        ) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        // The framebuffer for a display precedes its AV service proxy in registry order.
        var channels: [(product: ProductNumbers?, service: IOAVServiceRef)] = []
        var lastFramebufferProduct: ProductNumbers?
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }

            if IOObjectConformsTo(entry, "IOMobileFramebufferShim") != 0 {
                lastFramebufferProduct = productNumbers(forFramebuffer: entry)
                continue
            }

            guard IOObjectConformsTo(entry, "DCPAVServiceProxy") != 0,
                  (property(entry, "Location") as? String) == "External",
                  let service = IOAVServiceCreateWithService(kCFAllocatorDefault, entry)?.takeRetainedValue() else {
                continue
            }
            channels.append((lastFramebufferProduct, service))
            lastFramebufferProduct = nil
        }
        return channels
    }

    private static func productNumbers(forFramebuffer entry: io_registry_entry_t) -> ProductNumbers? {
        guard let attributes = property(entry, "DisplayAttributes") as? [String: Any],
              let product = attributes["ProductAttributes"] as? [String: Any],
              let vendor = (product["LegacyManufacturerID"] as? NSNumber)?.uint32Value,
              let model = (product["ProductID"] as? NSNumber)?.uint32Value else {
            return nil
        }
        let serial = (product["SerialNumber"] as? NSNumber)?.uint32Value ?? 0
        return ProductNumbers(vendor: vendor, model: model, serial: serial)
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
