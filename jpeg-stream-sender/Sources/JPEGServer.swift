import Foundation
import Network
import CoreGraphics

/// Exactly one TCP receiver is supported. A frame is dropped if a previous send is pending.
/// No unbounded queue of old screens can accumulate.
final class JPEGServer {
    private let queue = DispatchQueue(label: "dev.tmpmac.jpegstream.network")
    private var listener: NWListener?
    private var connection: NWConnection?
    private var busy = false
    var onStatus: ((String) -> Void)?

    private func report(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.onStatus?(message) }
    }

    func start() {
        queue.async { [weak self] in
            guard let self, self.listener == nil else { return }
            do {
                guard let port = NWEndpoint.Port(rawValue: 5055) else {
                    self.report("TCPポート番号が不正です")
                    return
                }
                let listener = try NWListener(using: .tcp, on: port)
                self.listener = listener
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.report("待機中：TCP 5055 / Androidから接続してください")
                    case .failed(let error):
                        self.report("待受失敗: \(error.localizedDescription)")
                        self.listener = nil
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] peer in
                    guard let self else { peer.cancel(); return }
                    self.connection?.cancel()
                    self.busy = false
                    self.connection = peer
                    peer.stateUpdateHandler = { [weak self, weak peer] state in
                        guard let self, let peer, self.connection === peer else { return }
                        switch state {
                        case .ready:
                            self.report("Android接続：JPEG送信中 (TCP 5055)")
                        case .failed, .cancelled:
                            self.connection = nil
                            self.busy = false
                            self.report("切断：Androidからの再接続待ち")
                        default: break
                        }
                    }
                    peer.start(queue: self.queue)
                }
                listener.start(queue: self.queue)
            } catch {
                self.report("待受エラー: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.connection?.cancel()
            self.connection = nil
            self.listener?.cancel()
            self.listener = nil
            self.busy = false
        }
    }

    func submit(jpeg: Data, cursorX: CGFloat, cursorY: CGFloat) {
        guard !jpeg.isEmpty && jpeg.count <= 4 * 1024 * 1024 else { return }
        let n = UInt32(jpeg.count)
        func u16(_ x: CGFloat) -> UInt16 { UInt16((min(1, max(0, x)) * 65535).rounded()) }
        let x = u16(cursorX), y = u16(cursorY)
        var packet = Data([
            0x4D, 0x4A, 0x50, 0x31,
            UInt8((n >> 24) & 0xFF), UInt8((n >> 16) & 0xFF),
            UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF),
            UInt8((x >> 8) & 0xFF), UInt8(x & 0xFF),
            UInt8((y >> 8) & 0xFF), UInt8(y & 0xFF)
        ])
        packet.append(jpeg)
        queue.async { [weak self] in
            guard let self, let peer = self.connection, !self.busy else { return }
            self.busy = true
            peer.send(content: packet, completion: .contentProcessed { [weak self, weak peer] error in
                guard let self else { return }
                self.queue.async {
                    guard let peer, self.connection === peer else { return }
                    self.busy = false
                    if let error {
                        self.report("送信失敗: \(error.localizedDescription)")
                        peer.cancel()
                    }
                }
            })
        }
    }
}
