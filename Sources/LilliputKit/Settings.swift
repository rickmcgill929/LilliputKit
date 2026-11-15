import Foundation

// MARK: - Value enums (raw values are the on-wire field values)

public enum ColorTemp: UInt8, CaseIterable, Sendable { case k3200, k5500, k6500, k7500, k9300, user }

public enum InputSource: UInt8, CaseIterable, Sendable {
    case sdi1 = 0, sdi2 = 1, sdi3 = 2, sdi4 = 3, sfp = 4
    case twoSI = 5       // 2SI (quad-link, two-sample interleave)
    case square = 6      // square-division quad-link
    case hdmi = 7
    case video = 12      // labelled "VIDEO" in RemoteTerminal (multiview / quad mode)
}

public enum MarkerColor: UInt8, CaseIterable, Sendable { case black, red, green, blue, white }
public enum SafetyMarker: UInt8, CaseIterable, Sendable { case off, p95, p93, p90, p88, p85, p80 }
public enum AspectMarker: UInt8, CaseIterable, Sendable {
    case off, r16x9, r185, r235, r4x3, r3x2, x2, x2mag, grid, user
}
public enum Aspect: UInt8, CaseIterable, Sendable {
    case full, r16x9, r185, r235, r4x3, r3x2, x2, x2mag, x1_3, x1_5
}
public enum ScanMode: UInt8, CaseIterable, Sendable { case aspect, pixToPix, zoom }
public enum Flip: UInt8, CaseIterable, Sendable { case off, h, v, hv }
public enum CheckField: UInt8, CaseIterable, Sendable { case off, red, green, blue, mono }
public enum ColorBar: UInt8, CaseIterable, Sendable { case off, p100, p75 }
public enum HVDelay: UInt8, CaseIterable, Sendable { case off, h, v, hv }
public enum Timecode: UInt8, CaseIterable, Sendable { case off, ltc, vitc }
public enum FalseColor: UInt8, CaseIterable, Sendable { case off, `default`, spectrum, arri, red }
public enum Histogram: UInt8, CaseIterable, Sendable { case off, y, rgb, color }
public enum Waveform: UInt8, CaseIterable, Sendable { case off, multi, y, ycbcr, rgb }
public enum FullMode: UInt8, CaseIterable, Sendable { case off, y, ycbcr, rgb, vector, histogram, audio }
public enum DisplayScan: UInt8, CaseIterable, Sendable { case full, over, under }
public enum Tally: UInt8, CaseIterable, Sendable { case off, red, green, yellow }
/// Order assumed from the manual's list (White/Red/Green/Blue/Yellow/Cyan/Magenta); unverified.
public enum UMDColor: UInt8, CaseIterable, Sendable { case white, red, green, blue, yellow, cyan, magenta }

/// Channel pair 1/2 … 15/16, encoded 0…7.
public struct ChannelPair: RawRepresentable, Hashable, Sendable {
    public var rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue & 0x0F }
    /// `first` is the odd channel: 1, 3, 5 … 15
    public init?(first: Int) {
        guard (1...15).contains(first), first % 2 == 1 else { return nil }
        rawValue = UInt8((first - 1) / 2)
    }
    public var first: Int { Int(rawValue) * 2 + 1 }
}

// MARK: - Bitfield helper

@inline(__always) func bits(_ byte: UInt8, _ mask: UInt8) -> UInt8 {
    (byte & mask) >> UInt8(mask.trailingZeroBitCount)
}
@inline(__always) func setBits(_ byte: inout UInt8, _ mask: UInt8, _ value: UInt8) {
    byte = (byte & ~mask) | ((value << UInt8(mask.trailingZeroBitCount)) & mask)
}

// MARK: - Settings

/// Complete per-screen state, laid out exactly as the protocol blocks.
/// Writes are whole blocks, so change fields here and send the block(s) you touched.
public struct MonitorSettings: Equatable, Sendable {
    /// brightness, contrast, saturation, tint, sharpness, backlight, colorTemp
    public var picture = [UInt8](repeating: 0, count: 7)
    /// [0] input; [1],[2] multiview bytes used only by MV-capable models (machine type 2)
    public var source = [UInt8](repeating: 0, count: 3)
    public var marker = [UInt8](repeating: 0, count: 3)
    /// [0] volume, [1] meter/vector flags, [2] audio out channels
    public var audio = [UInt8](repeating: 0, count: 3)
    public var function = [UInt8](repeating: 0, count: 5)
    /// UMD byte 0: screen-1 UMD on (bit3), color (bits0-2), tally (bits4-5)
    public var umdFlags: UInt8 = 0
    /// Extra UMD bytes for MV models (UMD 2–4 on/color)
    public var umdExtra: [UInt8] = [0, 0]
    /// UMD label to send. Not returned by the monitor — the read reply doesn't carry it —
    /// so it keeps whatever you last set (empty after a fresh read).
    public var umdText: String = ""
    /// Input status text from the read reply, e.g. "No Signal" or "1080p59.94".
    public var signalStatus: String = ""
    public var deviceName: String = ""
    /// Raw data bytes of the last read reply (frame bytes 10…), for reverse-engineering.
    public var rawReply: [UInt8] = []

    public init() {}

    // Picture
    public var brightness: UInt8 { get { picture[0] } set { picture[0] = newValue } }
    public var contrast: UInt8 { get { picture[1] } set { picture[1] = newValue } }
    public var saturation: UInt8 { get { picture[2] } set { picture[2] = newValue } }
    public var tint: UInt8 { get { picture[3] } set { picture[3] = newValue } }
    public var sharpness: UInt8 { get { picture[4] } set { picture[4] = newValue } }
    public var backlight: UInt8 { get { picture[5] } set { picture[5] = newValue } }
    public var colorTemp: ColorTemp? {
        get { ColorTemp(rawValue: bits(picture[6], 0x07)) }
        set { setBits(&picture[6], 0x07, (newValue ?? .k6500).rawValue) }
    }

    // Source
    public var input: InputSource? {
        get { InputSource(rawValue: source[0]) }
        set { source[0] = (newValue ?? .sdi1).rawValue }
    }

    // Marker
    public var markerColor: MarkerColor? {
        get { MarkerColor(rawValue: bits(marker[0], 0x07)) }
        set { setBits(&marker[0], 0x07, (newValue ?? .white).rawValue) }
    }
    public var centerMarker: Bool {
        get { marker[0] & 0x08 != 0 } set { setBits(&marker[0], 0x08, newValue ? 1 : 0) }
    }
    public var safetyMarker: SafetyMarker? {
        get { SafetyMarker(rawValue: bits(marker[1], 0x07)) }
        set { setBits(&marker[1], 0x07, (newValue ?? .off).rawValue) }
    }
    public var aspectMarker: AspectMarker? {
        get { AspectMarker(rawValue: bits(marker[1], 0xF0)) }
        set { setBits(&marker[1], 0xF0, (newValue ?? .off).rawValue) }
    }
    /// 1…7
    public var markerThickness: UInt8 {
        get { bits(marker[2], 0x0F) } set { setBits(&marker[2], 0x0F, min(max(newValue, 1), 7)) }
    }
    /// 0 = off, 1…7
    public var aspectMat: UInt8 {
        get { bits(marker[2], 0x70) } set { setBits(&marker[2], 0x70, min(newValue, 7)) }
    }

    // Audio
    public var volume: UInt8 { get { audio[0] } set { audio[0] = newValue } }
    public var meterVectorChannels: ChannelPair {
        get { ChannelPair(rawValue: bits(audio[1], 0x0F)) }
        set { setBits(&audio[1], 0x0F, newValue.rawValue) }
    }
    public var levelMeter: Bool {
        get { audio[1] & 0x10 != 0 } set { setBits(&audio[1], 0x10, newValue ? 1 : 0) }
    }
    public var audioVector: Bool {
        get { audio[1] & 0x20 != 0 } set { setBits(&audio[1], 0x20, newValue ? 1 : 0) }
    }
    /// Headphone/output channel pair (low nibble of audio[2]).
    public var audioOutChannels: ChannelPair {
        get { ChannelPair(rawValue: bits(audio[2], 0x0F)) }
        set { setBits(&audio[2], 0x0F, newValue.rawValue) }
    }

    // Function
    public var aspect: Aspect? {
        get { Aspect(rawValue: bits(function[0], 0x0F)) }
        set { setBits(&function[0], 0x0F, (newValue ?? .full).rawValue) }
    }
    public var scan: ScanMode? {
        get { ScanMode(rawValue: bits(function[0], 0x30)) }
        set { setBits(&function[0], 0x30, (newValue ?? .aspect).rawValue) }
    }
    public var freeze: Bool {
        get { function[0] & 0x80 != 0 } set { setBits(&function[0], 0x80, newValue ? 1 : 0) }
    }
    public var flip: Flip? {
        get { Flip(rawValue: bits(function[1], 0x03)) }
        set { setBits(&function[1], 0x03, (newValue ?? .off).rawValue) }
    }
    public var checkField: CheckField? {
        get { CheckField(rawValue: bits(function[1], 0x1C)) }
        set { setBits(&function[1], 0x1C, (newValue ?? .off).rawValue) }
    }
    public var colorBar: ColorBar? {
        get { ColorBar(rawValue: bits(function[1], 0x60)) }
        set { setBits(&function[1], 0x60, (newValue ?? .off).rawValue) }
    }
    public var vectorscope: Bool {
        get { function[1] & 0x80 != 0 } set { setBits(&function[1], 0x80, newValue ? 1 : 0) }
    }
    public var hvDelay: HVDelay? {
        get { HVDelay(rawValue: bits(function[2], 0x03)) }
        set { setBits(&function[2], 0x03, (newValue ?? .off).rawValue) }
    }
    public var timecode: Timecode? {
        get { Timecode(rawValue: bits(function[2], 0x0C)) }
        set { setBits(&function[2], 0x0C, (newValue ?? .off).rawValue) }
    }
    public var falseColor: FalseColor? {
        get { FalseColor(rawValue: bits(function[2], 0x70)) }
        set { setBits(&function[2], 0x70, (newValue ?? .off).rawValue) }
    }
    public var exposure: Bool {
        get { function[3] & 0x01 != 0 } set { setBits(&function[3], 0x01, newValue ? 1 : 0) }
    }
    public var peaking: Bool {
        get { function[3] & 0x04 != 0 } set { setBits(&function[3], 0x04, newValue ? 1 : 0) }
    }
    public var histogram: Histogram? {
        get { Histogram(rawValue: bits(function[3], 0x18)) }
        set { setBits(&function[3], 0x18, (newValue ?? .off).rawValue) }
    }
    public var waveform: Waveform? {
        get { Waveform(rawValue: bits(function[3], 0xE0)) }
        set { setBits(&function[3], 0xE0, (newValue ?? .off).rawValue) }
    }
    public var fullMode: FullMode? {
        get { FullMode(rawValue: bits(function[4], 0x07)) }
        set { setBits(&function[4], 0x07, (newValue ?? .off).rawValue) }
    }
    public var displayScan: DisplayScan? {
        get { DisplayScan(rawValue: bits(function[4], 0x18)) }
        set { setBits(&function[4], 0x18, (newValue ?? .full).rawValue) }
    }
    public var overscan: Bool {
        get { function[4] & 0x20 != 0 } set { setBits(&function[4], 0x20, newValue ? 1 : 0) }
    }

    // UMD / tally
    public var tally: Tally? {
        get { Tally(rawValue: bits(umdFlags, 0x30)) }
        set { setBits(&umdFlags, 0x30, (newValue ?? .off).rawValue) }
    }
    public var umdEnabled: Bool {
        get { umdFlags & 0x08 != 0 } set { setBits(&umdFlags, 0x08, newValue ? 1 : 0) }
    }
    public var umdColor: UMDColor? {
        get { UMDColor(rawValue: bits(umdFlags, 0x07)) }
        set { setBits(&umdFlags, 0x07, (newValue ?? .white).rawValue) }
    }
}

// MARK: - Block encoding / decoding

public enum Block: CaseIterable, Sendable { case picture, source, marker, audio, function, umd }

extension MonitorSettings {
    /// Payload for one block. `extended` = MV-capable model (machine type 2): source and
    /// UMD frames carry two extra bytes.
    public func payload(for block: Block, extended: Bool = false) -> [UInt8] {
        switch block {
        case .picture: return picture
        case .source: return extended ? source : [source[0]]
        case .marker: return marker
        case .audio: return audio
        case .function: return function
        case .umd:
            var p: [UInt8] = [umdFlags]
            p += MonitorSettings.umdBytes(umdText)
            if extended { p += umdExtra }
            return p
        }
    }

    public static func command(for block: Block) -> Command {
        switch block {
        case .picture: return .picture
        case .source: return .source
        case .marker: return .marker
        case .audio: return .audio
        case .function: return .function
        case .umd: return .umd
        }
    }

    /// 16 ASCII bytes: non-printables become spaces, zero padded (matches RemoteTerminal).
    static func umdBytes(_ s: String) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 16)
        for (i, u) in s.unicodeScalars.prefix(16).enumerated() {
            let v = u.value
            out[i] = (v >= 0x20 && v < 0x7F) ? UInt8(v) : 0x20
        }
        return out
    }

    /// Blocks whose bytes differ between two states.
    public func changedBlocks(from old: MonitorSettings) -> [Block] {
        var b: [Block] = []
        if picture != old.picture { b.append(.picture) }
        if source != old.source { b.append(.source) }
        if marker != old.marker { b.append(.marker) }
        if audio != old.audio { b.append(.audio) }
        if function != old.function { b.append(.function) }
        if umdFlags != old.umdFlags || umdText != old.umdText || umdExtra != old.umdExtra { b.append(.umd) }
        return b
    }

    /// Parse the payload of a 0xFE (read settings) reply.
    /// Layout confirmed on a Q-series monitor (type 0x02) by writing blocks and reading back:
    ///   0-6 picture · 7 input · 8-10 marker · 11-13 audio · 14 unknown (extra byte vs
    ///   RemoteTerminal, which shifts everything after it) · 15-19 function · 20 UMD flags/tally ·
    ///   21-38 input status text · 39-54 device name · 55-56 UMD 2-4 bytes · 57-58 MV source · 59 ?
    public init(readReply frame: Frame, extended: Bool = false) {
        self.init()
        let d = Array(frame.payload.dropFirst())   // payload starts at frame byte 9
        rawReply = d
        func at(_ i: Int) -> UInt8 { i < d.count ? d[i] : 0 }
        picture = (0..<7).map(at)
        source[0] = at(7)
        marker = (8..<11).map(at)
        audio = (11..<14).map(at)
        function = (15..<20).map(at)
        umdFlags = at(20)
        signalStatus = MonitorSettings.ascii((21..<39).map(at))
        deviceName = MonitorSettings.ascii((39..<55).map(at))
        if extended {
            umdExtra = [at(55), at(56)]
            source[1] = at(57)
            source[2] = at(58)
        }
    }

    /// Printable ASCII only, trimmed.
    static func ascii(_ b: [UInt8]) -> String {
        String(decoding: b.filter { $0 >= 0x20 && $0 < 0x7F }, as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)
    }
}
