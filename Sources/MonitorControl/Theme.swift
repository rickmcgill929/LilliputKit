import SwiftUI
import LilliputKit

enum Theme {
    static let bg      = Color(red: 0.071, green: 0.078, blue: 0.090)   // #121417
    static let panel   = Color(red: 0.102, green: 0.114, blue: 0.129)   // #1A1D21
    static let well    = Color(red: 0.082, green: 0.090, blue: 0.102)
    static let border  = Color(red: 0.165, green: 0.184, blue: 0.208)   // #2A2F35
    static let text    = Color(red: 0.843, green: 0.859, blue: 0.875)   // #D7DBDF
    static let dim     = Color(red: 0.541, green: 0.573, blue: 0.600)   // #8A9299
    static let accent  = Color(red: 0.247, green: 0.655, blue: 0.639)   // #3FA7A3 muted teal
    static let red     = Color(red: 0.898, green: 0.196, blue: 0.176)   // tally red
    static let green   = Color(red: 0.169, green: 0.698, blue: 0.298)   // tally green
    static let amber   = Color(red: 0.949, green: 0.663, blue: 0.000)   // tally amber
    static let warn    = Color(red: 0.949, green: 0.663, blue: 0.000)

    static let mono = Font.system(size: 12, design: .monospaced)
    static let monoSmall = Font.system(size: 10, design: .monospaced)
    static let label = Font.system(size: 12)

    static func tally(_ t: Tally) -> Color {
        switch t {
        case .off: return Theme.border
        case .red: return Theme.red
        case .green: return Theme.green
        case .yellow: return Theme.amber
        }
    }
}

// MARK: - Display names

protocol Labeled: CaseIterable, Hashable { var label: String { get } }

extension ColorTemp: Labeled {
    var label: String { ["3200K", "5500K", "6500K", "7500K", "9300K", "User"][Int(rawValue)] }
}
extension InputSource: Labeled {
    var label: String {
        switch self {
        case .sdi1: return "SDI 1"
        case .sdi2: return "SDI 2"
        case .sdi3: return "SDI 3"
        case .sdi4: return "SDI 4"
        case .sfp: return "SFP"
        case .hdmi: return "HDMI"
        case .twoSI: return "2SI"
        case .square: return "Square"
        case .video: return "Quad"
        }
    }
}
extension MarkerColor: Labeled { var label: String { ["Black", "Red", "Green", "Blue", "White"][Int(rawValue)] } }
extension SafetyMarker: Labeled { var label: String { ["Off", "95%", "93%", "90%", "88%", "85%", "80%"][Int(rawValue)] } }
extension AspectMarker: Labeled {
    var label: String { ["Off", "16:9", "1.85:1", "2.35:1", "4:3", "3:2", "2.0×", "2.0× MAG", "Grid", "User"][Int(rawValue)] }
}
extension Aspect: Labeled {
    var label: String { ["Full", "16:9", "1.85:1", "2.35:1", "4:3", "3:2", "2.0×", "2.0× MAG", "1.3×", "1.5×"][Int(rawValue)] }
}
extension ScanMode: Labeled { var label: String { ["Aspect", "Pixel to Pixel", "Zoom"][Int(rawValue)] } }
extension Flip: Labeled { var label: String { ["Off", "H", "V", "H/V"][Int(rawValue)] } }
extension CheckField: Labeled { var label: String { ["Off", "Red", "Green", "Blue", "Mono"][Int(rawValue)] } }
extension ColorBar: Labeled { var label: String { ["Off", "100%", "75%"][Int(rawValue)] } }
extension HVDelay: Labeled { var label: String { ["Off", "H", "V", "H/V"][Int(rawValue)] } }
extension Timecode: Labeled { var label: String { ["Off", "LTC", "VITC"][Int(rawValue)] } }
extension FalseColor: Labeled { var label: String { ["Off", "Default", "Spectrum", "ARRI", "RED"][Int(rawValue)] } }
extension Histogram: Labeled { var label: String { ["Off", "Y", "RGB", "Color"][Int(rawValue)] } }
extension Waveform: Labeled { var label: String { ["Off", "Multi", "Y", "YCbCr", "RGB"][Int(rawValue)] } }
extension FullMode: Labeled {
    var label: String { ["Off", "Y", "YCbCr", "RGB", "Vector", "Histogram", "Audio"][Int(rawValue)] }
}
extension DisplayScan: Labeled { var label: String { ["Full", "Over", "Under"][Int(rawValue)] } }
extension UMDColor: Labeled {
    var label: String { ["White", "Red", "Green", "Blue", "Yellow", "Cyan", "Magenta"][Int(rawValue)] }
}

/// Channel pairs as a pickable type.
enum Pair: Int, CaseIterable, Labeled {
    case p1 = 0, p3, p5, p7, p9, p11, p13, p15
    var label: String { "CH \(rawValue * 2 + 1)/\(rawValue * 2 + 2)" }
    init(_ c: ChannelPair) { self = Pair(rawValue: Int(c.rawValue)) ?? .p1 }
    var channelPair: ChannelPair { ChannelPair(rawValue: UInt8(rawValue)) }
}
