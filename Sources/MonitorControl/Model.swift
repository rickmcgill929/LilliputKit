import Foundation
import SwiftUI
import LilliputKit

/// Owns the UDP socket and the selected monitor. Touched only on `queue`.
final class Engine: @unchecked Sendable {
    let queue = DispatchQueue(label: "lilliput.io", qos: .userInitiated)
    var transport: UDPTransport?
    var monitor: Monitor?
}

/// UI state. Mutated on the main thread only; all network work hops to `engine.queue`.
final class AppModel: ObservableObject {
    @Published var monitors: [DiscoveredMonitor] = []
    @Published var selectedID: String?
    @Published var settings: MonitorSettings?
    @Published var status = "Starting…"
    @Published var lastError: String?
    @Published var online = false
    @Published var autoRefresh = true
    @Published var showLog = false
    @Published var log: [String] = []
    @Published var umdText = ""
    @Published var manualIP = ""
    /// Mode used when false color is switched on (remembered across launches).
    @Published var falseColorMode: FalseColor =
        FalseColor(rawValue: UInt8(UserDefaults.standard.integer(forKey: "falseColorMode"))).flatMap { $0 == .off ? nil : $0 } ?? .default

    private let engine = Engine()
    private var pollTimer: Timer?
    private var refreshInFlight = false
    private var writesInFlight = 0

    var selected: DiscoveredMonitor? { monitors.first { $0.id == selectedID } }

    // MARK: Lifecycle

    func start() {
        let engine = self.engine
        engine.queue.async { [weak self] in
            do {
                let t = try UDPTransport()
                t.log = { line in DispatchQueue.main.async { self?.appendLog(line) } }
                engine.transport = t
                DispatchQueue.main.async {
                    self?.status = "Ready"
                    self?.discover()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.status = "Network unavailable"
                    self?.lastError = "\(error)"
                }
            }
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self, self.autoRefresh, self.writesInFlight == 0 else { return }
            self.refresh()
        }
    }

    private func appendLog(_ line: String) {
        let stamp = Self.clock.string(from: Date())
        log.append("\(stamp)  \(line)")
        if log.count > 400 { log.removeFirst(log.count - 400) }
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    // MARK: Discovery / selection

    func discover(ip: String? = nil) {
        status = ip == nil ? "Searching…" : "Probing \(ip!)…"
        let engine = self.engine
        engine.queue.async { [weak self] in
            guard let t = engine.transport else { return }
            let found = (try? t.discover(timeout: 1.2, targets: ip.map { [$0] })) ?? []
            DispatchQueue.main.async {
                guard let self else { return }
                for m in found where !self.monitors.contains(where: { $0.id == m.id }) {
                    self.monitors.append(m)
                }
                self.monitors.sort { $0.ip.compare($1.ip, options: .numeric) == .orderedAscending }
                self.status = found.isEmpty ? "No monitors answered" : "Found \(found.count) monitor\(found.count == 1 ? "" : "s")"
                if self.selectedID == nil, let first = self.monitors.first { self.select(first.id) }
            }
        }
    }

    func addManual() {
        let ip = manualIP.trimmingCharacters(in: .whitespaces)
        guard !ip.isEmpty else { return }
        discover(ip: ip)
        manualIP = ""
    }

    func select(_ id: String?) {
        guard let id, id != selectedID || settings == nil,
              let d = monitors.first(where: { $0.id == id }) else { return }
        selectedID = id
        settings = nil
        online = false
        lastError = nil
        umdText = UserDefaults.standard.string(forKey: "umd.\(d.id)") ?? ""
        let label = umdText
        let engine = self.engine
        engine.queue.async { [weak self] in
            guard let t = engine.transport else { return }
            let m = Monitor(transport: t, discovered: d)
            m.primeUMDText(label)
            engine.monitor = m
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    // MARK: Read / write

    func refresh() {
        guard !refreshInFlight, selectedID != nil else { return }
        refreshInFlight = true
        let engine = self.engine
        engine.queue.async { [weak self] in
            let result = Result { try engine.monitor?.refresh(timeout: 0.8) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshInFlight = false
                switch result {
                case .success(let s?):
                    if self.writesInFlight == 0 { self.settings = s }
                    self.online = true
                    self.lastError = nil
                case .success(nil):
                    break
                case .failure(let e):
                    self.online = false
                    self.lastError = "\(e)"
                }
            }
        }
    }

    /// Read current state, apply `change`, send the blocks that changed, read back.
    func apply(_ change: @escaping (inout MonitorSettings) -> Void) {
        guard settings != nil else { return }
        if var s = settings { change(&s); settings = s }      // optimistic
        writesInFlight += 1
        let engine = self.engine
        engine.queue.async { [weak self] in
            var result: Result<MonitorSettings, Error>
            if let m = engine.monitor {
                do {
                    try m.refresh(timeout: 0.6)
                    try m.update(change)
                    usleep(150_000)
                    result = .success(try m.refresh(timeout: 0.8))
                } catch {
                    result = .failure(error)
                }
            } else {
                result = .failure(TransportError.timeout)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.writesInFlight -= 1
                switch result {
                case .success(let s):
                    self.settings = s
                    self.online = true
                    self.lastError = nil
                case .failure(let e):
                    self.lastError = "\(e)"
                }
            }
        }
    }

    func sendUMDLabel() {
        let text = String(umdText.prefix(16))
        umdText = text
        if let id = selectedID { UserDefaults.standard.set(text, forKey: "umd.\(id)") }
        apply { $0.umdText = text }
    }

    // MARK: False color

    var falseColorOn: Binding<Bool> {
        Binding(get: { [weak self] in (self?.settings?.falseColor ?? .off) != .off },
                set: { [weak self] on in
                    guard let self else { return }
                    let mode = self.falseColorMode
                    self.apply { $0.falseColor = on ? mode : .off }
                })
    }

    var falseColorModeBinding: Binding<FalseColor> {
        Binding(get: { [weak self] in
                    guard let self else { return .default }
                    let live = self.settings?.falseColor ?? .off
                    return live == .off ? self.falseColorMode : live
                },
                set: { [weak self] mode in
                    guard let self, mode != .off else { return }
                    self.falseColorMode = mode
                    UserDefaults.standard.set(Int(mode.rawValue), forKey: "falseColorMode")
                    if (self.settings?.falseColor ?? .off) != .off { self.apply { $0.falseColor = mode } }
                })
    }

    func toggleFalseColor() {
        falseColorOn.wrappedValue = !falseColorOn.wrappedValue
    }

    // MARK: Bindings

    func bind<T>(_ kp: WritableKeyPath<MonitorSettings, T>, _ fallback: T) -> Binding<T> {
        Binding(get: { [weak self] in self?.settings?[keyPath: kp] ?? fallback },
                set: { [weak self] v in self?.apply { $0[keyPath: kp] = v } })
    }

    func bindEnum<T>(_ kp: WritableKeyPath<MonitorSettings, T?>, _ fallback: T) -> Binding<T> {
        Binding(get: { [weak self] in (self?.settings?[keyPath: kp] ?? nil) ?? fallback },
                set: { [weak self] v in self?.apply { $0[keyPath: kp] = v } })
    }

    func bindPair(_ kp: WritableKeyPath<MonitorSettings, ChannelPair>) -> Binding<Pair> {
        Binding(get: { [weak self] in self?.settings.map { Pair($0[keyPath: kp]) } ?? .p1 },
                set: { [weak self] v in self?.apply { $0[keyPath: kp] = v.channelPair } })
    }

    func byte(_ kp: WritableKeyPath<MonitorSettings, UInt8>) -> Int {
        Int(settings?[keyPath: kp] ?? 0)
    }

    func setByte(_ kp: WritableKeyPath<MonitorSettings, UInt8>, _ v: Int) {
        let clamped = UInt8(max(0, min(255, v)))
        apply { $0[keyPath: kp] = clamped }
    }
}
