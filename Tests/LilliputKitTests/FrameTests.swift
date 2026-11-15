import XCTest
@testable import LilliputKit

/// Expected values come from RemoteTerminal's frame builders: each one adds a constant
/// to the variable bytes for its checksum, e.g. picture = port+screen+id+Σpayload+0x6C.
final class FrameTests: XCTestCase {

    func testDiscoveryLAN() {
        XCTAssertEqual(Frame.discover().encoded().hex, "5A 0B 00 20 00 FF 00 FF FF 82 DD")
    }

    func testReadSettings() {
        XCTAssertEqual(Frame.readSettings(deviceID: 1, screen: 0).encoded().hex,
                       "5A 0B 00 20 01 FF 00 01 FE 84 DD")
    }

    func testChecksumConstantsMatchApp() {
        // (command, payload length, app's checksum constant, total length)
        let cases: [(Command, Int, UInt8, Int)] = [
            (.picture, 7, 0x6C, 0x12),
            (.marker, 3, 0x69, 0x0E),
            (.audio, 3, 0x6A, 0x0E),
            (.function, 5, 0x6D, 0x10),
        ]
        for (cmd, n, k, len) in cases {
            let payload = (0..<n).map { UInt8(17 &* ($0 + 3)) }
            let f = Frame(link: .lan, screenMask: 0x02, deviceID: 7, command: cmd, payload: payload)
            let b = f.encoded()
            XCTAssertEqual(b.count, len, "\(cmd) length")
            XCTAssertEqual(Int(b[1]), len)
            let expected = UInt8(0x20) &+ 0x02 &+ 7 &+ payload.reduce(0, &+) &+ k
            XCTAssertEqual(b[b.count - 2], expected, "\(cmd) checksum")
            XCTAssertEqual(b.last, 0xDD)
        }
    }

    func testSourceAndUMDLengths() {
        var s = MonitorSettings()
        s.input = .hdmi
        XCTAssertEqual(s.payload(for: .source).count + Frame.overhead, 12)
        XCTAssertEqual(s.payload(for: .source, extended: true).count + Frame.overhead, 14)
        s.umdText = "CAM 1"
        XCTAssertEqual(s.payload(for: .umd).count + Frame.overhead, 28)
        XCTAssertEqual(s.payload(for: .umd, extended: true).count + Frame.overhead, 30)
    }

    func testRoundTrip() throws {
        let f = Frame(link: .lan, screenMask: 1, deviceID: 3, command: .picture, payload: [50, 50, 50, 50, 10, 80, 2])
        let d = try Frame.decode(f.encoded())
        XCTAssertEqual(d.payload, f.payload)
        XCTAssertEqual(d.deviceID, 3)
        XCTAssertEqual(d.command, Command.picture.rawValue)
    }

    func testBadChecksumRejected() {
        var b = Frame.discover().encoded()
        b[b.count - 2] ^= 0xFF
        XCTAssertThrowsError(try Frame.decode(b))
        XCTAssertNoThrow(try Frame.decode(b, strict: false))
    }

    func testBitfields() {
        var s = MonitorSettings()
        s.aspectMarker = .grid           // marker[1] high nibble = 8
        s.safetyMarker = .p90            // marker[1] low bits = 3
        XCTAssertEqual(s.marker[1], 0x83)
        s.waveform = .rgb                // function[3] bits 5-7 = 4
        s.peaking = true                 // bit 2
        s.histogram = .y                 // bits 3-4 = 1
        XCTAssertEqual(s.function[3], 0x8C)
        s.tally = .green                 // UMD flags bits 4-5 = 2
        s.umdEnabled = true              // bit 3
        XCTAssertEqual(s.umdFlags, 0x28)
        s.overscan = true                // function[4] bit 5
        s.fullMode = .vector             // bits 0-2 = 4
        XCTAssertEqual(s.function[4], 0x24)
    }

    func testUMDTextSanitised() {
        XCTAssertEqual(MonitorSettings.umdBytes("AB\u{7F}é"), [0x41, 0x42, 0x20, 0x20] + Array(repeating: 0, count: 12))
    }

    func testChangedBlocks() {
        let a = MonitorSettings()
        var b = a
        b.brightness = 60
        b.tally = .red
        XCTAssertEqual(b.changedBlocks(from: a), [.picture, .umd])
    }

    func testReadReplyParse() throws {
        var data = [UInt8](repeating: 0, count: 60)
        data[0] = 55          // brightness
        data[7] = 7           // HDMI
        data[9] = 0x11        // aspect marker 16:9, safety 95%
        data[18] = 0x04       // function[3]: peaking on
        data[20] = 0x18       // tally red, UMD on
        for (i, c) in "No Signal".utf8.enumerated() { data[21 + i] = c }
        for (i, c) in "Monitor".utf8.enumerated() { data[39 + i] = c }
        let reply = Frame(link: .lan, screenMask: 1, deviceID: 1, command: .readSettings, payload: [0x00] + data)
        let s = MonitorSettings(readReply: try Frame.decode(reply.encoded()))
        XCTAssertEqual(s.brightness, 55)
        XCTAssertEqual(s.input, .hdmi)
        XCTAssertEqual(s.aspectMarker, .r16x9)
        XCTAssertEqual(s.safetyMarker, .p95)
        XCTAssertTrue(s.peaking)
        XCTAssertEqual(s.tally, .red)
        XCTAssertTrue(s.umdEnabled)
        XCTAssertEqual(s.signalStatus, "No Signal")
        XCTAssertEqual(s.deviceName, "Monitor")
        XCTAssertEqual(s.umdText, "")
    }
}

final class HardwareReplyTests: XCTestCase {
    /// Captured from a Q-series monitor (type 0x02) at 192.168.10.88, 2026-11-13.
    func testRealReply() throws {
        let hex = "5A480020010200FFFE0032323232006402000400063220100140800088000" +
                  "24E6F205369676E616C2020202020202020204D6F6E69746F72202020202020202020220210320171DD"
        var b: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            b.append(UInt8(hex[i..<j], radix: 16)!); i = j
        }
        let f = try Frame.decode(b)
        XCTAssertEqual(f.byte5, 0x02)
        let s = MonitorSettings(readReply: f, extended: true)
        XCTAssertEqual(s.picture, [50, 50, 50, 50, 0, 100, 2])
        XCTAssertEqual(s.colorTemp, .k6500)
        XCTAssertEqual(s.input, .sdi1)
        XCTAssertEqual(s.markerColor, .white)
        XCTAssertEqual(s.markerThickness, 6)
        XCTAssertTrue(s.audioVector)
        XCTAssertEqual(s.function, [0x40, 0x80, 0x00, 0x88, 0x00])
        XCTAssertEqual(s.aspect, .full)
        XCTAssertTrue(s.vectorscope)
        XCTAssertEqual(s.waveform, .rgb)
        XCTAssertEqual(s.histogram, .y)
        XCTAssertEqual(s.umdFlags, 0x02)
        XCTAssertEqual(s.signalStatus, "No Signal")
        XCTAssertEqual(s.deviceName, "Monitor")
        XCTAssertEqual(s.umdText, "")
        XCTAssertEqual(s.umdExtra, [0x22, 0x02])
        XCTAssertEqual(s.source, [0x00, 0x10, 0x32])
    }
}
