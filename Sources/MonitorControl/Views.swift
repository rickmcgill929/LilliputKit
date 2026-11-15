import SwiftUI
import LilliputKit

// MARK: - Building blocks

struct Panel<Content: View>: View {
    let title: String
    var note: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Theme.accent)
                Spacer()
                if let note {
                    Text(note).font(Theme.monoSmall).foregroundStyle(Theme.warn)
                }
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct Row<Control: View>: View {
    let title: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(Theme.label)
                .foregroundStyle(Theme.dim)
                .frame(width: 104, alignment: .leading)
            control
            Spacer(minLength: 0)
        }
    }
}

struct EnumPicker<E: Labeled>: View {
    @Binding var selection: E
    var segmented = false

    var body: some View {
        let picker = Picker("", selection: $selection) {
            ForEach(Array(E.allCases), id: \.self) { Text($0.label).tag($0) }
        }
        .labelsHidden()
        if segmented {
            picker.pickerStyle(.segmented)
        } else {
            picker.pickerStyle(.menu).frame(maxWidth: 170)
        }
    }
}

/// Slider that only sends when you let go, so dragging doesn't flood the monitor.
struct ValueSlider: View {
    let title: String
    let value: Int
    var range: ClosedRange<Double> = 0...100
    let commit: (Int) -> Void

    @State private var local: Double = 0
    @State private var editing = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(Theme.label)
                .foregroundStyle(Theme.dim)
                .frame(width: 104, alignment: .leading)
            Slider(value: $local, in: range, step: 1, onEditingChanged: { isEditing in
                editing = isEditing
                if !isEditing { commit(Int(local)) }
            })
            .tint(Theme.accent)
            Text("\(Int(editing ? local : Double(value)))")
                .font(Theme.mono)
                .foregroundStyle(Theme.text)
                .frame(width: 34, alignment: .trailing)
        }
        .onAppear { local = Double(value) }
        .onChange(of: value) { newValue in
            if !editing { local = Double(newValue) }
        }
    }
}

struct TallyButton: View {
    let tally: Tally
    let active: Bool
    let action: () -> Void

    private var title: String {
        switch tally {
        case .off: return "OFF"
        case .red: return "PGM"
        case .green: return "PVW"
        case .yellow: return "ISO"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Rectangle()
                    .fill(active ? Theme.tally(tally) : Theme.tally(tally).opacity(tally == .off ? 1 : 0.18))
                    .frame(height: 6)
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(active ? Theme.text : Theme.dim)
                Text(tally == .off ? "—" : (tally == .yellow ? "AMBER" : "\(tally)".uppercased()))
                    .font(Theme.monoSmall)
                    .foregroundStyle(Theme.dim)
            }
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(active ? Theme.well : Theme.panel)
            .overlay(RoundedRectangle(cornerRadius: 3)
                .stroke(active ? Theme.tally(tally == .off ? .off : tally) : Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding(get: { model.selectedID }, set: { model.select($0) })) {
                Section("Monitors") {
                    ForEach(model.monitors) { m in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.ip).font(Theme.mono)
                            Text("ID \(m.deviceID) · type \(String(format: "%02X", m.machineType))\(m.extended ? " · MV" : "")")
                                .font(Theme.monoSmall)
                                .foregroundStyle(Theme.dim)
                        }
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    TextField("IP address", text: $model.manualIP)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.mono)
                        .onSubmit { model.addManual() }
                    Button("Add") { model.addManual() }
                }
                Text(model.status).font(Theme.monoSmall).foregroundStyle(Theme.dim)
            }
            .padding(10)
        }
        .frame(minWidth: 210)
    }
}

// MARK: - Detail

struct MonitorDetail: View {
    @ObservedObject var model: AppModel
    let monitor: DiscoveredMonitor

    private let columns = [GridItem(.adaptive(minimum: 360), spacing: 12, alignment: .top)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.border)
            if model.settings == nil {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.lastError ?? "Reading settings…").font(Theme.mono).foregroundStyle(Theme.dim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        tallyPanel
                        picturePanel
                        inputPanel
                        scopesPanel
                        exposurePanel
                        geometryPanel
                        markersPanel
                        audioPanel
                    }
                    .padding(12)
                }
            }
            if model.showLog { LogView(lines: model.log) }
        }
        .background(Theme.bg)
    }

    // Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Circle()
                .fill(model.online ? Theme.green : Theme.dim.opacity(0.5))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.settings?.deviceName.isEmpty == false ? model.settings!.deviceName : "Monitor")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("\(monitor.ip)  ·  ID \(monitor.deviceID)  ·  TYPE \(String(format: "%02X", monitor.machineType))\(monitor.extended ? " MV" : "")")
                    .font(Theme.monoSmall)
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
            if let err = model.lastError, model.settings != nil {
                Text(err).font(Theme.monoSmall).foregroundStyle(Theme.red).lineLimit(1)
            }
            VStack(alignment: .trailing, spacing: 3) {
                Text("SIGNAL").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.dim)
                Text(model.settings?.signalStatus.isEmpty == false ? model.settings!.signalStatus : "—")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(model.settings?.signalStatus == "No Signal" ? Theme.warn : Theme.text)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.well)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.border))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.panel)
    }

    // Panels

    private var tallyPanel: some View {
        let current = model.settings?.tally ?? .off
        return Panel(title: "Tally & UMD") {
            HStack(spacing: 6) {
                ForEach(Tally.allCases, id: \.self) { t in
                    TallyButton(tally: t, active: current == t) { model.apply { $0.tally = t } }
                }
            }
            Row(title: "Label") {
                TextField("16 characters", text: $model.umdText)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.mono)
                    .frame(maxWidth: 180)
                    .onSubmit { model.sendUMDLabel() }
                Button("Send") { model.sendUMDLabel() }
            }
            Row(title: "UMD") {
                Toggle("Show", isOn: model.bind(\.umdEnabled, false)).toggleStyle(.switch).controlSize(.small)
                EnumPicker(selection: model.bindEnum(\.umdColor, .white))
            }
            Text("The monitor can't report the label back; it's remembered here per monitor. Turning UMD on may switch off scopes.")
                .font(Theme.monoSmall).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var picturePanel: some View {
        Panel(title: "Picture") {
            ValueSlider(title: "Brightness", value: model.byte(\.brightness)) { model.setByte(\.brightness, $0) }
            ValueSlider(title: "Contrast", value: model.byte(\.contrast)) { model.setByte(\.contrast, $0) }
            ValueSlider(title: "Saturation", value: model.byte(\.saturation)) { model.setByte(\.saturation, $0) }
            ValueSlider(title: "Tint", value: model.byte(\.tint)) { model.setByte(\.tint, $0) }
            ValueSlider(title: "Sharpness", value: model.byte(\.sharpness)) { model.setByte(\.sharpness, $0) }
            ValueSlider(title: "Backlight", value: model.byte(\.backlight)) { model.setByte(\.backlight, $0) }
            Row(title: "Color temp") { EnumPicker(selection: model.bindEnum(\.colorTemp, .k6500), segmented: true) }
        }
    }

    private var inputPanel: some View {
        Panel(title: "Input", note: monitor.extended ? "UNTESTED ON MV" : nil) {
            let sel = model.bindEnum(\.input, .sdi1)
            Picker("", selection: sel) {
                ForEach([InputSource.sdi1, .sdi2, .sdi3, .sdi4, .sfp, .hdmi], id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden().pickerStyle(.segmented)
            Picker("", selection: sel) {
                ForEach([InputSource.twoSI, .square, .video], id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden().pickerStyle(.segmented)
            .frame(maxWidth: 240)
        }
    }

    private var scopesPanel: some View {
        Panel(title: "Scopes") {
            Row(title: "Waveform") { EnumPicker(selection: model.bindEnum(\.waveform, .off)) }
            Row(title: "Vectorscope") { Toggle("", isOn: model.bind(\.vectorscope, false)).toggleStyle(.switch).controlSize(.small).labelsHidden() }
            Row(title: "Histogram") { EnumPicker(selection: model.bindEnum(\.histogram, .off), segmented: true) }
            Row(title: "Full screen") { EnumPicker(selection: model.bindEnum(\.fullMode, .off)) }
        }
    }

    private var exposurePanel: some View {
        Panel(title: "Exposure & Focus") {
            Row(title: "Peaking") { Toggle("", isOn: model.bind(\.peaking, false)).toggleStyle(.switch).controlSize(.small).labelsHidden() }
            Row(title: "False color") {
                Toggle("", isOn: model.falseColorOn).toggleStyle(.switch).controlSize(.small).labelsHidden()
                Picker("", selection: model.falseColorModeBinding) {
                    ForEach([FalseColor.default, .spectrum, .arri, .red], id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }
            Row(title: "Exposure") { Toggle("", isOn: model.bind(\.exposure, false)).toggleStyle(.switch).controlSize(.small).labelsHidden() }
            Row(title: "Check field") { EnumPicker(selection: model.bindEnum(\.checkField, .off), segmented: true) }
            Row(title: "Color bars") { EnumPicker(selection: model.bindEnum(\.colorBar, .off), segmented: true) }
            Row(title: "Timecode") { EnumPicker(selection: model.bindEnum(\.timecode, .off), segmented: true) }
        }
    }

    private var geometryPanel: some View {
        Panel(title: "Geometry") {
            Row(title: "Aspect") { EnumPicker(selection: model.bindEnum(\.aspect, .full)) }
            Row(title: "Scan mode") { EnumPicker(selection: model.bindEnum(\.scan, .aspect), segmented: true) }
            Row(title: "Display scan") { EnumPicker(selection: model.bindEnum(\.displayScan, .full), segmented: true) }
            Row(title: "Flip") { EnumPicker(selection: model.bindEnum(\.flip, .off), segmented: true) }
            Row(title: "H/V delay") { EnumPicker(selection: model.bindEnum(\.hvDelay, .off), segmented: true) }
            Row(title: "Freeze") { Toggle("", isOn: model.bind(\.freeze, false)).toggleStyle(.switch).controlSize(.small).labelsHidden() }
        }
    }

    private var markersPanel: some View {
        Panel(title: "Markers") {
            Row(title: "Aspect marker") { EnumPicker(selection: model.bindEnum(\.aspectMarker, .off)) }
            Row(title: "Safety area") { EnumPicker(selection: model.bindEnum(\.safetyMarker, .off)) }
            Row(title: "Center") { Toggle("", isOn: model.bind(\.centerMarker, false)).toggleStyle(.switch).controlSize(.small).labelsHidden() }
            Row(title: "Color") { EnumPicker(selection: model.bindEnum(\.markerColor, .white), segmented: true) }
            Row(title: "Thickness") {
                Stepper(value: Binding(get: { model.byte(\.markerThickness) },
                                       set: { model.setByte(\.markerThickness, min(max($0, 1), 7)) }), in: 1...7) {
                    Text("\(model.byte(\.markerThickness))").font(Theme.mono)
                }
            }
            Row(title: "Aspect mat") {
                Stepper(value: Binding(get: { model.byte(\.aspectMat) },
                                       set: { model.setByte(\.aspectMat, min(max($0, 0), 7)) }), in: 0...7) {
                    Text(model.byte(\.aspectMat) == 0 ? "Off" : "\(model.byte(\.aspectMat))").font(Theme.mono)
                }
            }
        }
    }

    private var audioPanel: some View {
        Panel(title: "Audio") {
            ValueSlider(title: "Volume", value: model.byte(\.volume)) { model.setByte(\.volume, $0) }
            Row(title: "Level meter") { Toggle("", isOn: model.bind(\.levelMeter, false)).toggleStyle(.switch).controlSize(.small).labelsHidden() }
            Row(title: "Audio vector") { Toggle("", isOn: model.bind(\.audioVector, false)).toggleStyle(.switch).controlSize(.small).labelsHidden() }
            Row(title: "Meter pair") { EnumPicker(selection: model.bindPair(\.meterVectorChannels)) }
            Row(title: "Output pair") { EnumPicker(selection: model.bindPair(\.audioOutChannels)) }
        }
    }
}

struct LogView: View {
    let lines: [String]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                        Text(line)
                            .font(Theme.monoSmall)
                            .foregroundStyle(line.contains("→") ? Theme.accent : Theme.dim)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(i)
                    }
                }
                .padding(8)
            }
            .frame(height: 160)
            .background(Theme.well)
            .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
            .onChange(of: lines.count) { n in
                if n > 0 { proxy.scrollTo(n - 1, anchor: .bottom) }
            }
        }
    }
}

// MARK: - Root

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        NavigationSplitView {
            Sidebar(model: model)
        } detail: {
            if let m = model.selected {
                MonitorDetail(model: model, monitor: m)
            } else {
                VStack(spacing: 10) {
                    Text("No monitor selected").font(Theme.mono).foregroundStyle(Theme.dim)
                    Button("Search again") { model.discover() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $model.autoRefresh) { Label("Live", systemImage: "dot.radiowaves.left.and.right") }
                    .help("Poll the monitor every 2 s")
                Button { model.refresh() } label: { Label("Read", systemImage: "arrow.down.circle") }
                    .help("Read settings now")
                Button { model.discover() } label: { Label("Search", systemImage: "magnifyingglass") }
                    .help("Search the network for monitors")
                Button { model.toggleFalseColor() } label: { Label("False Color", systemImage: "thermometer.medium") }
                    .help("Toggle false color (⌘F)")
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(model.settings == nil)
                Toggle(isOn: $model.showLog) { Label("Log", systemImage: "terminal") }
                    .help("Show packet log")
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .frame(minWidth: 900, minHeight: 620)
        .onAppear { model.start() }
    }
}
