import Foundation
import Network

/// Finds the server on the LAN by Bonjour (_kidzy._tcp) and resolves it to an
/// IPv4 address and port by opening a short connection.
@MainActor
final class ServerBrowser {
    var onFound: ((ServerEndpoint) -> Void)?
    private var browser: NWBrowser?
    private var connections: [NWConnection] = []
    private var resolved: Set<String> = []

    func start() {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: "_kidzy._tcp", domain: nil), using: params)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.resolve(results) }
        }
        b.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    self?.start()
                }
            }
        }
        b.start(queue: .main)
        browser = b
    }

    func restart() {
        resolved.removeAll()
        browser?.cancel()
        start()
    }

    private func resolve(_ results: Set<NWBrowser.Result>) {
        for r in results {
            guard case .service(let name, _, _, _) = r.endpoint, !resolved.contains(name) else { continue }
            // The server publishes its .local hostname and port in the TXT record; mDNS resolves it.
            if case .bonjour(let txt) = r.metadata, let host = txt.dictionary["host"], !host.isEmpty {
                let port = Int(txt.dictionary["port"] ?? "") ?? 8800
                resolved.insert(name)
                onFound?(ServerEndpoint(host: host, port: port, name: name))
                continue
            }
            let params = NWParameters.tcp
            if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
            let c = NWConnection(to: r.endpoint, using: params)
            let serviceName = name
            c.stateUpdateHandler = { [weak self, weak c] state in
                guard case .ready = state, let c, let remote = c.currentPath?.remoteEndpoint, case .hostPort(let host, let port) = remote else { return }
                let hostString: String
                switch host {
                case .ipv4(let a): hostString = "\(a)"
                case .name(let n, _): hostString = n
                default: return // an IPv6 link-local address does not fit in a URL; wait for IPv4 or the TXT host
                }
                let ep = ServerEndpoint(host: hostString, port: Int(port.rawValue), name: serviceName)
                c.cancel()
                Task { @MainActor in
                    self?.resolved.insert(serviceName)
                    self?.onFound?(ep)
                }
            }
            c.start(queue: .main)
            connections.append(c)
        }
    }
}
