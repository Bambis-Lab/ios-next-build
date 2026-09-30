import Foundation
import Network

enum NetworkReachability {
    static func statuses() -> AsyncStream<Bool> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "de.nicofroeba16.iosnext.network-path")
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            continuation.onTermination = { _ in
                monitor.cancel()
            }
            monitor.start(queue: queue)
        }
    }
}
