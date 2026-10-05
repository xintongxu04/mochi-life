import Foundation
@preconcurrency import Network
import RelayCore

/// Listens on TCP with PSK TLS and relay framing, advertised over Bonjour. Only peers that
/// complete the PSK handshake from a local-network address get to send requests.
final class RelayServer: @unchecked Sendable {
    private let listener: NWListener
    private let service: LookupService
    private let queue = DispatchQueue(label: "com.xintongxu.MochiRelay.server")
    private var connectionCount = 0
    private let maximumConnections = 4

    init(config: RelayConfig, secret: Data, service: LookupService) throws {
        let parameters = RelayTLS.parameters(secret: secret)
        parameters.allowLocalEndpointReuse = true
        let port = config.port == 0 ? NWEndpoint.Port.any : (NWEndpoint.Port(rawValue: config.port) ?? .any)
        listener = try NWListener(using: parameters, on: port)
        listener.service = NWListener.Service(type: RelayProtocol.bonjourServiceType)
        self.service = service
    }

    func start() {
        listener.stateUpdateHandler = { [listener] state in
            switch state {
            case .ready:
                RelayLog.shared.info("listening port=\(listener.port?.rawValue ?? 0) service=\(RelayProtocol.bonjourServiceType)")
            case let .failed(error):
                RelayLog.shared.error("listener failed: \(error)")
                exit(1)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
    }

    private func accept(_ connection: NWConnection) {
        guard Self.isLocalNetwork(connection.endpoint) else {
            RelayLog.shared.info("rejected connection from outside the local network")
            connection.cancel()
            return
        }
        guard connectionCount < maximumConnections else {
            RelayLog.shared.info("rejected connection: too many open connections")
            connection.cancel()
            return
        }
        connectionCount += 1
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                // The TLS handshake succeeded, so the peer has the pairing secret.
                RelayLog.shared.info("peer authenticated")
                self.receive(on: connection)
            case let .failed(error):
                RelayLog.shared.info("connection closed: \(error)")
                connection.cancel()
            case .waiting:
                connection.cancel()
            case .cancelled:
                // State updates arrive on `queue`, so the count is only touched there.
                self.connectionCount -= 1
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, _, _, error in
            guard let self else { return }
            if error != nil {
                connection.cancel()
                return
            }
            guard let content, !content.isEmpty else {
                connection.cancel()
                return
            }
            self.handle(content, on: connection)
            self.receive(on: connection)
        }
    }

    private func handle(_ data: Data, on connection: NWConnection) {
        guard let request = try? JSONDecoder().decode(RelayRequest.self, from: data) else {
            let id = (try? JSONDecoder().decode(RequestID.self, from: data))?.id ?? UUID()
            RelayLog.shared.info("request=\(id) status=invalid_request")
            send(.failure(id: id, RelayError(code: .invalidRequest, message: "The request isn't valid relay JSON.")), on: connection)
            return
        }
        if let error = request.validationError() {
            RelayLog.shared.info("request=\(request.id) status=\(error.code.rawValue)")
            send(.failure(id: request.id, error), on: connection)
            return
        }
        switch request.type {
        case .ping:
            send(.pong(id: request.id, relayVersion: LookupService.relayVersion), on: connection)
        case .lookup:
            guard let query = request.lookup else { return }
            let service = service
            // The server lives for the whole process, so holding it strongly here is fine.
            Task { [self] in
                let response = await service.lookup(id: request.id, query: query) { stage in
                    self.send(.progress(id: request.id, stage), on: connection)
                }
                self.send(response, on: connection)
            }
        }
    }

    private func send(_ response: RelayResponse, on connection: NWConnection) {
        connection.sendRelayMessage(response) { error in
            if let error {
                RelayLog.shared.info("request=\(response.id) send failed: \(error)")
            }
        }
    }

    /// Private IPv4 ranges, IPv6 link-local and unique-local addresses, and loopback.
    static func isLocalNetwork(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else { return false }
        switch host {
        case let .ipv4(address):
            return isPrivate(ipv4: [UInt8](address.rawValue))
        case let .ipv6(address):
            let bytes = [UInt8](address.rawValue)
            guard bytes.count == 16 else { return false }
            if bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80 { return true } // fe80::/10 link-local
            if (bytes[0] & 0xFE) == 0xFC { return true } // fc00::/7 unique local
            if bytes == [UInt8](repeating: 0, count: 15) + [1] { return true } // ::1
            if bytes[0..<10].allSatisfy({ $0 == 0 }) && bytes[10] == 0xFF && bytes[11] == 0xFF {
                return isPrivate(ipv4: Array(bytes[12..<16])) // IPv4-mapped
            }
            return false
        default:
            return false
        }
    }

    private static func isPrivate(ipv4 bytes: [UInt8]) -> Bool {
        guard bytes.count == 4 else { return false }
        switch (bytes[0], bytes[1]) {
        case (10, _), (127, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        default: return false
        }
    }
}

/// Just the id of a request that otherwise didn't decode, so the error can refer to it.
private struct RequestID: Decodable {
    var id: UUID
}
