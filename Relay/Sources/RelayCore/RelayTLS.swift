import CryptoKit
import Foundation
@preconcurrency import Network
import Security

/// TLS settings shared by the relay and its clients: authentication and encryption with a
/// pre-shared key only (no certificates), following Apple's Network.framework peer-to-peer
/// sample. A peer without the same key can't complete the handshake.
public enum RelayTLS {
    public static let pskIdentity = "mochi-relay-v1"

    /// TLS options for both sides of a relay connection.
    /// - Parameter secret: The 32-byte pairing secret.
    public static func options(secret: Data) -> NWProtocolTLS.Options {
        let tls = NWProtocolTLS.Options()
        let security = tls.securityProtocolOptions
        // As in Apple's sample, the key used in TLS is an HMAC of the identity keyed by the secret.
        let key = HMAC<SHA256>.authenticationCode(for: Data(pskIdentity.utf8), using: SymmetricKey(data: secret))
        let keyData = Data(key).withUnsafeBytes { DispatchData(bytes: $0) }
        let identityData = Data(pskIdentity.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(security, keyData as __DispatchData, identityData as __DispatchData)
        // PSK cipher suites exist only in TLS 1.2. Strongest first.
        sec_protocol_options_set_min_tls_protocol_version(security, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(security, .TLSv12)
        for suite in [TLS_PSK_WITH_AES_256_GCM_SHA384, TLS_PSK_WITH_AES_128_GCM_SHA256] {
            if let ciphersuite = tls_ciphersuite_t(rawValue: UInt16(suite)) {
                sec_protocol_options_append_tls_ciphersuite(security, ciphersuite)
            }
        }
        return tls
    }

    /// TCP + PSK TLS + relay framing, local network only (no peer-to-peer / AWDL).
    public static func parameters(secret: Data) -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 30
        let parameters = NWParameters(tls: options(secret: secret), tcp: tcp)
        parameters.includePeerToPeer = false
        parameters.prohibitedInterfaceTypes = [.cellular]
        let framer = NWProtocolFramer.Options(definition: RelayFramer.definition)
        parameters.defaultProtocolStack.applicationProtocols.insert(framer, at: 0)
        return parameters
    }
}
