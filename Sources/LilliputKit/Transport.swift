import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum TransportError: Error, CustomStringConvertible {
    case socket(String)
    case timeout
    case notFound(UInt8)

    public var description: String {
        switch self {
        case .socket(let s): return "socket error: \(s)"
        case .timeout: return "timed out waiting for reply"
        case .notFound(let id): return "no monitor with ID \(id) answered"
        }
    }
}

public struct DiscoveredMonitor: Hashable, Sendable, CustomStringConvertible, Identifiable {
    public var id: String { "\(ip)#\(deviceID)" }
    public let ip: String
    public let deviceID: UInt8
    public let machineType: UInt8
    /// Machine type 2 uses the longer source/UMD frames.
    public var extended: Bool { machineType == 2 }
    public var description: String {
        String(format: "%@  id=%d  type=0x%02X%@", ip, deviceID, machineType, extended ? " (MV)" : "")
    }
}

/// UDP transport matching RemoteTerminal: bind 19522 locally, send to 19523.
/// Replies arrive on the bound port. One instance per process (the port is fixed).
public final class UDPTransport: @unchecked Sendable {
    public static let localPort: UInt16 = 19522
    public static let devicePort: UInt16 = 19523

    private let fd: Int32
    public var log: ((String) -> Void)?

    public init(bindPort: UInt16 = UDPTransport.localPort) throws {
        #if canImport(Darwin)
        let s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        #else
        let s = socket(AF_INET, Int32(SOCK_DGRAM.rawValue), Int32(IPPROTO_UDP))
        #endif
        guard s >= 0 else { throw TransportError.socket(String(cString: strerror(errno))) }
        var on: Int32 = 1
        let size = socklen_t(MemoryLayout<Int32>.size)
        setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &on, size)
        #if canImport(Darwin)
        setsockopt(s, SOL_SOCKET, SO_REUSEPORT, &on, size)
        #endif
        setsockopt(s, SOL_SOCKET, SO_BROADCAST, &on, size)

        var addr = sockaddr_in()
        #if canImport(Darwin)
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = bindPort.bigEndian
        addr.sin_addr.s_addr = in_addr_t(0)   // INADDR_ANY
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard rc == 0 else {
            let msg = String(cString: strerror(errno))
            close(s)
            throw TransportError.socket("bind :\(bindPort) failed (\(msg)) — is RemoteTerminal running?")
        }
        fd = s
    }

    deinit { close(fd) }

    public func send(_ bytes: [UInt8], to ip: String, port: UInt16 = UDPTransport.devicePort) throws {
        var addr = sockaddr_in()
        #if canImport(Darwin)
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, ip, &addr.sin_addr) == 1 else { throw TransportError.socket("bad IP \(ip)") }
        let n = bytes.withUnsafeBytes { buf in
            withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, buf.baseAddress, buf.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard n == bytes.count else { throw TransportError.socket(String(cString: strerror(errno))) }
        log?("→ \(ip)  \(bytes.hex)")
    }

    /// Wait up to `timeout` seconds for one datagram. Returns nil on timeout.
    public func receive(timeout: TimeInterval) -> (bytes: [UInt8], ip: String)? {
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let ms = Int32(max(0, timeout * 1000))
        guard poll(&pfd, 1, ms) > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: 2048)
        var from = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let n = buf.withUnsafeMutableBytes { b in
            withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(fd, b.baseAddress, b.count, 0, $0, &len)
                }
            }
        }
        guard n > 0 else { return nil }
        var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &from.sin_addr, &ipBuf, socklen_t(INET_ADDRSTRLEN))
        let bytes = Array(buf[0..<n])
        let ip = String(cString: ipBuf)
        log?("← \(ip)  \(bytes.hex)")
        return (bytes, ip)
    }

    /// Collect frames until `deadline`, passing each decoded one to `handler`.
    /// Return `true` from the handler to stop early.
    public func collect(for seconds: TimeInterval, handler: (Frame, String) -> Bool) {
        let deadline = Date().addingTimeInterval(seconds)
        while true {
            let left = deadline.timeIntervalSinceNow
            guard left > 0, let (bytes, ip) = receive(timeout: left) else { return }
            // A datagram may hold more than one frame; split on 5A … DD using the length byte.
            var i = 0
            while i + Frame.overhead <= bytes.count {
                guard bytes[i] == Frame.start else { i += 1; continue }
                let len = Int(bytes[i + 1])
                guard len >= Frame.overhead, i + len <= bytes.count else { break }
                let chunk = Array(bytes[i..<(i + len)])
                if let f = try? Frame.decode(chunk, strict: false), handler(f, ip) { return }
                i += len
            }
        }
    }

    // MARK: Discovery

    public struct Interface: Sendable, CustomStringConvertible {
        public let name: String
        public let index: UInt32
        public let ip: String
        public let broadcast: String
        public var description: String { "\(name) \(ip) (bcast \(broadcast))" }
    }

    /// Up, non-loopback IPv4 interfaces.
    public static func interfaces() -> [Interface] {
        var out: [Interface] = []
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return out }
        defer { freeifaddrs(ifap) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            let flags = Int32(ifa.ifa_flags)
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == sa_family_t(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, let nm = ifa.ifa_netmask else { continue }
            var ip = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            let mask = nm.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            var bc = in_addr(s_addr: ip.s_addr | ~mask)
            var b1 = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var b2 = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &ip, &b1, socklen_t(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &bc, &b2, socklen_t(INET_ADDRSTRLEN))
            let name = String(cString: ifa.ifa_name)
            out.append(Interface(name: name, index: if_nametoindex(ifa.ifa_name), ip: String(cString: b1),
                                 broadcast: String(cString: b2)))
        }
        return out
    }

    /// Pin outgoing packets to one interface (macOS IP_BOUND_IF); 0 = unpin.
    private func boundInterface(_ index: UInt32) {
        #if canImport(Darwin)
        var idx = index
        setsockopt(fd, IPPROTO_IP, 25 /* IP_BOUND_IF */, &idx, socklen_t(MemoryLayout<UInt32>.size))
        #endif
    }

    /// Discover monitors.
    /// - `targets` nil: do what RemoteTerminal does — on every interface, send the probe to
    ///   255.255.255.255 pinned to that interface (so it leaves every NIC, not just the default
    ///   route), plus the interface's directed broadcast.
    /// - `targets` given: unicast the probe to those IPs only (works across subnets/routers).
    public func discover(timeout: TimeInterval = 1.5, targets: [String]? = nil) throws -> [DiscoveredMonitor] {
        let probe = Frame.discover().encoded()
        if let targets {
            for ip in targets { try send(probe, to: ip) }
        } else {
            for iface in UDPTransport.interfaces() {
                log?("· \(iface)")
                boundInterface(iface.index)
                try? send(probe, to: "255.255.255.255")
                try? send(probe, to: iface.broadcast)
                usleep(50_000)
            }
            boundInterface(0)
            try? send(probe, to: "255.255.255.255")
        }
        var found: [String: DiscoveredMonitor] = [:]
        collect(for: timeout) { f, ip in
            if f.command == Command.discover.rawValue {
                found["\(ip)#\(f.deviceID)"] = DiscoveredMonitor(ip: ip, deviceID: f.deviceID, machineType: f.byte5)
            }
            return false
        }
        return found.values.sorted { ($0.ip, $0.deviceID) < ($1.ip, $1.deviceID) }
    }
}

// MARK: - Monitor

/// One screen on one monitor. Read state with `refresh()`, change it with `update`.
public final class Monitor: @unchecked Sendable {
    public let transport: UDPTransport
    public let ip: String
    public let deviceID: UInt8
    public var screen: Int
    public var extended: Bool
    public private(set) var settings = MonitorSettings()

    public init(transport: UDPTransport, ip: String, deviceID: UInt8, screen: Int = 0, extended: Bool = false) {
        self.transport = transport
        self.ip = ip
        self.deviceID = deviceID
        self.screen = screen
        self.extended = extended
    }

    public convenience init(transport: UDPTransport, discovered d: DiscoveredMonitor, screen: Int = 0) {
        self.init(transport: transport, ip: d.ip, deviceID: d.deviceID, screen: screen, extended: d.extended)
    }

    var screenMask: UInt8 { UInt8(1 << screen) }

    /// Read current settings (command 0xFE).
    @discardableResult
    public func refresh(timeout: TimeInterval = 1.0) throws -> MonitorSettings {
        try transport.send(Frame.readSettings(deviceID: deviceID, screen: screen).encoded(), to: ip)
        var reply: Frame?
        transport.collect(for: timeout) { f, from in
            guard from == ip, f.command == Command.readSettings.rawValue else { return false }
            reply = f
            return true
        }
        guard let reply else { throw TransportError.timeout }
        let label = settings.umdText            // the monitor can't report the label; keep ours
        settings = MonitorSettings(readReply: reply, extended: extended)
        settings.umdText = label
        return settings
    }

    /// Set the UMD label that later tally/UMD writes will carry, without sending anything.
    public func primeUMDText(_ text: String) { settings.umdText = text }

    /// Send one block from `settings` as-is.
    public func send(_ block: Block, settings s: MonitorSettings? = nil) throws {
        let st = s ?? settings
        let f = Frame(link: .lan, screenMask: screenMask, deviceID: deviceID,
                      command: MonitorSettings.command(for: block),
                      payload: st.payload(for: block, extended: extended))
        try transport.send(f.encoded(), to: ip)
    }

    /// Mutate settings and send only the blocks that changed.
    /// Call `refresh()` first so untouched fields in a block keep the monitor's real values.
    public func update(_ change: (inout MonitorSettings) -> Void) throws {
        var next = settings
        change(&next)
        for block in next.changedBlocks(from: settings) { try send(block, settings: next) }
        settings = next
    }

    /// Send a raw payload for a command (for experimenting).
    public func sendRaw(command: UInt8, payload: [UInt8]) throws {
        var f = Frame(link: .lan, screenMask: screenMask, deviceID: deviceID, command: .picture, payload: payload)
        f.command = command
        try transport.send(f.encoded(), to: ip)
    }
}
