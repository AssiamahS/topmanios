import Foundation
import Network

/// Finds the Mac running the TopMan server via Bonjour, then asks it for its
/// Tailscale hostname so the saved address keeps working off the home network.
@MainActor
final class MacDiscovery: ObservableObject {
    enum Status: Equatable {
        case idle
        case searching
        case found(String)
        case failed
    }

    @Published var status: Status = .idle

    var onFound: ((String) -> Void)?

    private var browser: NWBrowser?
    private var connection: NWConnection?

    func start() {
        guard status == .idle || status == .failed else { return }
        status = .searching
        let browser = NWBrowser(for: .bonjour(type: "_topman._tcp", domain: nil), using: .tcp)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let endpoint = results.first?.endpoint else { return }
            Task { @MainActor in self?.resolve(endpoint) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                Task { @MainActor in self?.status = .failed }
            }
        }
        browser.start(queue: .main)
    }

    func stop() {
        browser?.cancel()
        browser = nil
        connection?.cancel()
        connection = nil
    }

    private func resolve(_ endpoint: NWEndpoint) {
        guard connection == nil else { return }
        let conn = NWConnection(to: endpoint, using: .tcp)
        connection = conn
        conn.stateUpdateHandler = { [weak self] state in
            guard case .ready = state else { return }
            let remote = conn.currentPath?.remoteEndpoint
            Task { @MainActor in
                guard let self, case let .hostPort(host, port) = remote,
                      let address = Self.string(for: host) else {
                    self?.status = .failed
                    return
                }
                self.stop()
                await self.confirm(address: address, port: Int(port.rawValue))
            }
        }
        conn.start(queue: .main)
    }

    /// Hit /api/whoami on the discovered address; prefer the tailnet name it
    /// reports so the app still reaches the Mac away from this Wi-Fi.
    private func confirm(address: String, port: Int) async {
        let direct = port == 4477 ? address : "\(address):\(port)"
        var best = direct
        if let url = URL(string: "http://\(address):\(port)/api/whoami") {
            var req = URLRequest(url: url)
            req.timeoutInterval = 4
            if let (data, _) = try? await URLSession.shared.data(for: req),
               let who = try? JSONDecoder().decode(WhoAmI.self, from: data),
               let tailnet = who.tailnet, !tailnet.isEmpty {
                best = tailnet
            }
        }
        status = .found(best)
        onFound?(best)
    }

    private static func string(for host: NWEndpoint.Host) -> String? {
        switch host {
        case .ipv4(let addr):
            return "\(addr)"
        case .ipv6(let addr):
            var s = "\(addr)"
            if let pct = s.firstIndex(of: "%") { s = String(s[..<pct]) }
            return "[\(s)]"
        case .name(let name, _):
            return name
        @unknown default:
            return nil
        }
    }

    private struct WhoAmI: Decodable {
        let tailnet: String?
    }
}
