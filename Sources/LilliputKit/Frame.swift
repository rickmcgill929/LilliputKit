import Foundation

// Lilliput "RemoteTerminal" wire protocol (Q-series 12G / 8K monitors and siblings).
// Recovered from RemoteTerminal 1.2.x (macOS build); not vendor-documented.
//
//   5A  LEN  00  PORT  SCREEN  FF  00  ID  CMD  [payload…]  CHK  DD
//
//   LEN     total frame length, 5A through DD inclusive
//   PORT    0x20 = LAN, 0x00 = RS-422
//   SCREEN  bitmask of target screen(s), bit0 = screen 1
//   ID      device ID (0xFF = all devices)
//   CHK     low byte of the sum of every preceding byte
//
// Replies reuse the layout: byte 5 carries the machine type and byte 7 the device ID.

public enum LinkType: UInt8, Sendable {
    case lan = 0x20
    case rs422 = 0x00
}

public enum Command: UInt8, Sendable {
    case source = 0x00
    case picture = 0x01
    case marker = 0x02
    case audio = 0x03
    case function = 0x04
    case umd = 0x05
    case readSettings = 0xFE
    case discover = 0xFF
}

public enum FrameError: Error, CustomStringConvertible {
    case tooShort(Int)
    case badStart(UInt8)
    case badEnd(UInt8)
    case lengthMismatch(declared: Int, actual: Int)
    case badChecksum(expected: UInt8, got: UInt8)

    public var description: String {
        switch self {
        case .tooShort(let n): return "frame too short (\(n) bytes)"
        case .badStart(let b): return String(format: "bad start byte 0x%02X", b)
        case .badEnd(let b): return String(format: "bad end byte 0x%02X", b)
        case .lengthMismatch(let d, let a): return "length byte says \(d), got \(a)"
        case .badChecksum(let e, let g): return String(format: "checksum 0x%02X, expected 0x%02X", g, e)
        }
    }
}

public struct Frame: Equatable, Sendable {
    public static let start: UInt8 = 0x5A
    public static let end: UInt8 = 0xDD
    public static let broadcastID: UInt8 = 0xFF
    static let headerLength = 9          // 5A..CMD
    static let overhead = headerLength + 2

    public var link: LinkType
    public var screenMask: UInt8
    public var deviceID: UInt8
    public var command: UInt8
    public var payload: [UInt8]
    /// Byte 5. 0xFF in requests; machine type in replies.
    public var byte5: UInt8 = 0xFF

    public init(link: LinkType = .lan, screenMask: UInt8 = 0x01, deviceID: UInt8 = Frame.broadcastID,
                command: Command, payload: [UInt8] = []) {
        self.link = link
        self.screenMask = screenMask
        self.deviceID = deviceID
        self.command = command.rawValue
        self.payload = payload
    }

    public static func checksum<C: Collection>(_ bytes: C) -> UInt8 where C.Element == UInt8 {
        bytes.reduce(UInt8(0)) { $0 &+ $1 }
    }

    public func encoded() -> [UInt8] {
        var b: [UInt8] = [Frame.start, UInt8(payload.count + Frame.overhead), 0x00,
                          link.rawValue, screenMask, byte5, 0x00, deviceID, command]
        b += payload
        b.append(Frame.checksum(b))
        b.append(Frame.end)
        return b
    }

    public var data: Data { Data(encoded()) }

    /// Parse a received frame. `strict: false` accepts a bad checksum or length byte
    /// (useful while reverse-engineering replies).
    public static func decode(_ raw: [UInt8], strict: Bool = true) throws -> Frame {
        guard raw.count >= overhead else { throw FrameError.tooShort(raw.count) }
        guard raw[0] == start else { throw FrameError.badStart(raw[0]) }
        guard raw[raw.count - 1] == end else { throw FrameError.badEnd(raw[raw.count - 1]) }
        if strict {
            if Int(raw[1]) != raw.count { throw FrameError.lengthMismatch(declared: Int(raw[1]), actual: raw.count) }
            let exp = checksum(raw[0..<(raw.count - 2)])
            if exp != raw[raw.count - 2] { throw FrameError.badChecksum(expected: exp, got: raw[raw.count - 2]) }
        }
        var f = Frame(link: LinkType(rawValue: raw[3]) ?? .lan, screenMask: raw[4], deviceID: raw[7],
                      command: .discover, payload: Array(raw[headerLength..<(raw.count - 2)]))
        f.command = raw[8]
        f.byte5 = raw[5]
        return f
    }

    // MARK: Request builders

    /// Discovery probe. Over LAN the app uses ID 0xFF; over RS-422 it polls IDs 0…125 one at a time.
    public static func discover(link: LinkType = .lan, probeID: UInt8 = broadcastID) -> Frame {
        Frame(link: link, screenMask: 0x00, deviceID: probeID, command: .discover)
    }

    public static func readSettings(link: LinkType = .lan, deviceID: UInt8, screen: Int = 0) -> Frame {
        Frame(link: link, screenMask: UInt8(1 << screen), deviceID: deviceID, command: .readSettings)
    }
}

public extension Array where Element == UInt8 {
    var hex: String { map { String(format: "%02X", $0) }.joined(separator: " ") }
}
