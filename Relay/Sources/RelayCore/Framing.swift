import Foundation
@preconcurrency import Network

/// Frames each message as a 4-byte big-endian length followed by that many bytes of UTF-8 JSON.
/// A frame longer than `RelayProtocol.maximumFrameSize` fails the connection.
public final class RelayFramer: NWProtocolFramerImplementation {
    public static let definition = NWProtocolFramer.Definition(implementation: RelayFramer.self)
    public static let label = "MochiRelayFrame"

    private static let headerSize = 4

    public required init(framer: NWProtocolFramer.Instance) {}

    public func start(framer: NWProtocolFramer.Instance) -> NWProtocolFramer.StartResult { .ready }

    public func wakeup(framer: NWProtocolFramer.Instance) {}

    public func stop(framer: NWProtocolFramer.Instance) -> Bool { true }

    public func cleanup(framer: NWProtocolFramer.Instance) {}

    public func handleInput(framer: NWProtocolFramer.Instance) -> Int {
        while true {
            var length: UInt32?
            let parsed = framer.parseInput(minimumIncompleteLength: Self.headerSize, maximumLength: Self.headerSize) { buffer, _ in
                guard let buffer, buffer.count >= Self.headerSize else { return 0 }
                length = buffer.prefix(Self.headerSize).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
                return Self.headerSize
            }
            guard parsed, let length else { return Self.headerSize }
            guard length > 0, Int(length) <= RelayProtocol.maximumFrameSize else {
                framer.markFailed(error: .posix(.EMSGSIZE))
                return 0
            }
            let message = NWProtocolFramer.Message(definition: Self.definition)
            // Returns false until the whole body has arrived; the framer delivers it then.
            if !framer.deliverInputNoCopy(length: Int(length), message: message, isComplete: true) {
                return 0
            }
        }
    }

    public func handleOutput(framer: NWProtocolFramer.Instance, message: NWProtocolFramer.Message,
                             messageLength: Int, isComplete: Bool) {
        guard messageLength > 0, messageLength <= RelayProtocol.maximumFrameSize else {
            framer.markFailed(error: .posix(.EMSGSIZE))
            return
        }
        let length = UInt32(messageLength).bigEndian
        framer.writeOutput(data: withUnsafeBytes(of: length) { Data($0) })
        do {
            try framer.writeOutputNoCopy(length: messageLength)
        } catch {
            framer.markFailed(error: .posix(.EIO))
        }
    }
}

public extension NWConnection {
    /// Sends one relay message as a single frame.
    func sendRelayMessage<Message: Encodable>(_ value: Message, completion: @escaping @Sendable (NWError?) -> Void) {
        let data: Data
        do {
            data = try JSONEncoder.relay.encode(value)
        } catch {
            completion(.posix(.EINVAL))
            return
        }
        let context = NWConnection.ContentContext(
            identifier: "MochiRelayMessage",
            metadata: [NWProtocolFramer.Message(definition: RelayFramer.definition)]
        )
        send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed(completion))
    }
}
