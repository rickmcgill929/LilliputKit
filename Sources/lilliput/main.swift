import Foundation
import LilliputKit

// lilliput — command-line control for Lilliput Q-series / RemoteTerminal-protocol monitors.

func names<E: CaseIterable>(_: E.Type) -> String {
    E.allCases.map { "\($0)".lowercased() }.joined(separator: "|")
}

let usage = """
usage:
  lilliput discover [ip …]          (no IP = broadcast on every interface)
  lilliput get   <ip> [options]
  lilliput set   <ip> key=value [key=value …] [options]
  lilliput raw   <ip> <cmd-hex> [payload-hex …] [options]
  lilliput listen [seconds]

options:
  --id N        device ID (default: discovered from the IP, else 255 = all)
  --screen N    screen index, 0-based (default 0)
  --mv          force extended (multiview) frames
  -v            print every packet sent/received

set keys:
  brightness contrast saturation tint sharpness backlight volume   0-255 (UI range unverified)
  colortemp   \(names(ColorTemp.self))
  input       \(names(InputSource.self))
  tally       \(names(Tally.self))
  umd         text (16 ASCII chars)      umdon  on|off      umdcolor \(names(UMDColor.self))
  markercolor \(names(MarkerColor.self))   center on|off
  safety      \(names(SafetyMarker.self))
  aspectmarker \(names(AspectMarker.self))
  thickness 1-7   mat 0-7
  aspect      \(names(Aspect.self))
  scan        \(names(ScanMode.self))   freeze on|off   overscan on|off
  flip        \(names(Flip.self))   checkfield \(names(CheckField.self))
  colorbar    \(names(ColorBar.self))   vector on|off
  hvdelay     \(names(HVDelay.self))   timecode \(names(Timecode.self))
  falsecolor  \(names(FalseColor.self))   exposure on|off   peaking on|off
  histogram   \(names(Histogram.self))   waveform \(names(Waveform.self))
  fullmode    \(names(FullMode.self))   displayscan \(names(DisplayScan.self))
  levelmeter on|off   audiovector on|off   meterch 1|3|…|15   outch 1|3|…|15
"""

struct CLIError: Error, CustomStringConvertible { let description: String }

func parseEnum<E: CaseIterable>(_ s: String, _: E.Type) throws -> E {
    let k = s.lowercased().replacingOccurrences(of: "%", with: "")
    if let e = E.allCases.first(where: { "\($0)".lowercased() == k }) { return e }
    throw CLIError(description: "'\(s)' — expected one of \(names(E.self))")
}
func parseBool(_ s: String) throws -> Bool {
    switch s.lowercased() {
    case "on", "1", "true", "yes": return true
    case "off", "0", "false", "no": return false
    default: throw CLIError(description: "'\(s)' — expected on|off")
    }
}
func parseByte(_ s: String) throws -> UInt8 {
    guard let v = UInt8(s) else { throw CLIError(description: "'\(s)' — expected 0-255") }
    return v
}
func parsePair(_ s: String) throws -> ChannelPair {
    guard let n = Int(s), let p = ChannelPair(first: n) else { throw CLIError(description: "'\(s)' — expected 1,3,5…15") }
    return p
}

typealias Setter = (inout MonitorSettings, String) throws -> Void
let setters: [String: Setter] = [
    "brightness": { $0.brightness = try parseByte($1) },
    "contrast": { $0.contrast = try parseByte($1) },
    "saturation": { $0.saturation = try parseByte($1) },
    "tint": { $0.tint = try parseByte($1) },
    "sharpness": { $0.sharpness = try parseByte($1) },
    "backlight": { $0.backlight = try parseByte($1) },
    "volume": { $0.volume = try parseByte($1) },
    "colortemp": { $0.colorTemp = try parseEnum($1, ColorTemp.self) },
    "input": { $0.input = try parseEnum($1, InputSource.self) },
    "tally": { $0.tally = try parseEnum($1, Tally.self) },
    "umd": { $0.umdText = $1 },
    "umdon": { $0.umdEnabled = try parseBool($1) },
    "umdcolor": { $0.umdColor = try parseEnum($1, UMDColor.self) },
    "markercolor": { $0.markerColor = try parseEnum($1, MarkerColor.self) },
    "center": { $0.centerMarker = try parseBool($1) },
    "safety": { $0.safetyMarker = try parseEnum($1, SafetyMarker.self) },
    "aspectmarker": { $0.aspectMarker = try parseEnum($1, AspectMarker.self) },
    "thickness": { $0.markerThickness = try parseByte($1) },
    "mat": { $0.aspectMat = try parseByte($1) },
    "aspect": { $0.aspect = try parseEnum($1, Aspect.self) },
    "scan": { $0.scan = try parseEnum($1, ScanMode.self) },
    "freeze": { $0.freeze = try parseBool($1) },
    "overscan": { $0.overscan = try parseBool($1) },
    "flip": { $0.flip = try parseEnum($1, Flip.self) },
    "checkfield": { $0.checkField = try parseEnum($1, CheckField.self) },
    "colorbar": { $0.colorBar = try parseEnum($1, ColorBar.self) },
    "vector": { $0.vectorscope = try parseBool($1) },
    "hvdelay": { $0.hvDelay = try parseEnum($1, HVDelay.self) },
    "timecode": { $0.timecode = try parseEnum($1, Timecode.self) },
    "falsecolor": { $0.falseColor = try parseEnum($1, FalseColor.self) },
    "exposure": { $0.exposure = try parseBool($1) },
    "peaking": { $0.peaking = try parseBool($1) },
    "histogram": { $0.histogram = try parseEnum($1, Histogram.self) },
    "waveform": { $0.waveform = try parseEnum($1, Waveform.self) },
    "fullmode": { $0.fullMode = try parseEnum($1, FullMode.self) },
    "displayscan": { $0.displayScan = try parseEnum($1, DisplayScan.self) },
    "levelmeter": { $0.levelMeter = try parseBool($1) },
    "audiovector": { $0.audioVector = try parseBool($1) },
    "meterch": { $0.meterVectorChannels = try parsePair($1) },
    "outch": { $0.audioOutChannels = try parsePair($1) },
]

func show(_ s: MonitorSettings) {
    func e<T>(_ v: T?) -> String { v.map { "\($0)" } ?? "?" }
    print("""
    device      \(s.deviceName.isEmpty ? "?" : s.deviceName)
    picture     brightness \(s.brightness)  contrast \(s.contrast)  saturation \(s.saturation)  tint \(s.tint)  sharpness \(s.sharpness)  backlight \(s.backlight)  colortemp \(e(s.colorTemp))
    input       \(e(s.input))
    marker      color \(e(s.markerColor))  center \(s.centerMarker)  safety \(e(s.safetyMarker))  aspect \(e(s.aspectMarker))  thickness \(s.markerThickness)  mat \(s.aspectMat)
    function    aspect \(e(s.aspect))  scan \(e(s.scan))  freeze \(s.freeze)  flip \(e(s.flip))  checkfield \(e(s.checkField))  colorbar \(e(s.colorBar))
                vector \(s.vectorscope)  hvdelay \(e(s.hvDelay))  timecode \(e(s.timecode))  falsecolor \(e(s.falseColor))  exposure \(s.exposure)  peaking \(s.peaking)
                histogram \(e(s.histogram))  waveform \(e(s.waveform))  fullmode \(e(s.fullMode))  displayscan \(e(s.displayScan))  overscan \(s.overscan)
    audio       volume \(s.volume)  levelmeter \(s.levelMeter)  audiovector \(s.audioVector)  meterch \(s.meterVectorChannels.first)/\(s.meterVectorChannels.first + 1)  outch \(s.audioOutChannels.first)/\(s.audioOutChannels.first + 1)
    signal      \(s.signalStatus.isEmpty ? "?" : s.signalStatus)
    umd         on \(s.umdEnabled)  color \(e(s.umdColor))  tally \(e(s.tally))   (label text isn't readable back)
    raw         pic \(s.picture.hex) | src \(s.source.hex) | mkr \(s.marker.hex) | aud \(s.audio.hex) | fn \(s.function.hex) | umd \(String(format: "%02X", s.umdFlags))
    reply       \(s.rawReply.enumerated().map { String(format: "%d:%02X", $0.offset, $0.element) }.joined(separator: " "))
    """)
}

// MARK: - Argument handling

var args = Array(CommandLine.arguments.dropFirst())
func takeOption(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]; args.removeSubrange(i...(i + 1)); return v
}
func takeFlag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i); return true
}

let verbose = takeFlag("-v")
let forceMV = takeFlag("--mv")
let idOpt = takeOption("--id").flatMap(UInt8.init)
let screen = takeOption("--screen").flatMap(Int.init) ?? 0

guard let cmd = args.first else { print(usage); exit(1) }
args.removeFirst()

do {
    let t = try UDPTransport()
    if verbose { t.log = { print($0) } }

    func monitor(_ ip: String) throws -> Monitor {
        if let id = idOpt { return Monitor(transport: t, ip: ip, deviceID: id, screen: screen, extended: forceMV) }
        if let d = try t.discover(timeout: 1.0, targets: [ip]).first(where: { $0.ip == ip }) {
            return Monitor(transport: t, ip: ip, deviceID: d.deviceID, screen: screen, extended: forceMV || d.extended)
        }
        if verbose { print("(no discovery reply from \(ip); using ID 255)") }
        return Monitor(transport: t, ip: ip, deviceID: Frame.broadcastID, screen: screen, extended: forceMV)
    }

    switch cmd {
    case "discover":
        // `lilliput discover 192.168.0.200 …` probes those IPs directly
        let found = try t.discover(targets: args.isEmpty ? nil : args)
        if found.isEmpty { print("no monitors answered"); exit(2) }
        found.forEach { print($0) }

    case "get":
        guard let ip = args.first else { throw CLIError(description: "get needs an IP") }
        show(try monitor(ip).refresh())

    case "set":
        guard let ip = args.first else { throw CLIError(description: "set needs an IP") }
        let pairs = try args.dropFirst().map { kv -> (Setter, String) in
            let parts = kv.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, let s = setters[parts[0].lowercased()] else {
                throw CLIError(description: "bad setting '\(kv)'")
            }
            return (s, parts[1])
        }
        guard !pairs.isEmpty else { throw CLIError(description: "nothing to set") }
        // validate every value before touching the monitor
        var scratch = MonitorSettings()
        for (setter, v) in pairs { try setter(&scratch, v) }

        let m = try monitor(ip)
        do { try m.refresh() } catch {
            print("warning: couldn't read current settings (\(error)); other fields in the blocks you change will be sent as 0")
        }
        let umdKeys: Set<String> = ["tally", "umd", "umdon", "umdcolor"]
        let keys = args.dropFirst().map { $0.split(separator: "=").first.map { $0.lowercased() } ?? "" }
        if keys.contains(where: umdKeys.contains), !keys.contains("umd") {
            print("note: tally/UMD writes also send the UMD label, and the monitor can't report it back —")
            print("      the label will be blank. Add umd=\"TEXT\" to set it in the same command.")
        }
        try m.update { s in for (setter, v) in pairs { try? setter(&s, v) } }
        print("ok")

    case "raw":
        guard args.count >= 2, let c = UInt8(args[1], radix: 16) else { throw CLIError(description: "raw <ip> <cmd-hex> [bytes…]") }
        let payload = try args.dropFirst(2).map { b -> UInt8 in
            guard let v = UInt8(b, radix: 16) else { throw CLIError(description: "bad hex byte '\(b)'") }
            return v
        }
        let m = try monitor(args[0])
        try m.sendRaw(command: c, payload: payload)
        t.collect(for: 0.5) { f, ip in print("← \(ip)  \(f.encoded().hex)"); return false }

    case "listen":
        let secs = args.first.flatMap(Double.init) ?? 30
        t.log = { print($0) }
        t.collect(for: secs) { _, _ in false }

    default:
        print(usage); exit(1)
    }
} catch {
    FileHandle.standardError.write("error: \(error)\n".data(using: .utf8)!)
    exit(1)
}
