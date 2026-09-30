import Foundation

struct CommunicationHealthSnapshot: Equatable, Sendable {
    enum ClientState: Equatable, Sendable {
        case notConfigured
        case connecting
        case online
        case offline(String)
    }

    let clientState: ClientState
    let registeredPrincipals: Int?
    let registeredDevices: Int?
    let queuedChunks: Int?
    let queuedBytes: Int?
    let deviceQueues: Int?

    var isClientOnline: Bool {
        clientState == .online
    }

    var clientTitle: String {
        switch clientState {
        case .notConfigured: "Nicht eingerichtet"
        case .connecting: "Verbindet"
        case .online: "Online"
        case .offline: "Offline"
        }
    }

    var clientDetail: String? {
        if case let .offline(message) = clientState { return message }
        return nil
    }
}

@MainActor
extension CommunicationHealthSnapshot {
    init(chatModel: ChatModel, adminStatus: AdminChatStatusV2?, devices: [AdminChatDeviceV2]) {
        let clientState: ClientState
        switch chatModel.state {
        case .notConfigured: clientState = .notConfigured
        case .connecting: clientState = .connecting
        case .online: clientState = .online
        case let .offline(message): clientState = .offline(message)
        }

        self.init(
            clientState: clientState,
            registeredPrincipals: adminStatus?.registeredPrincipals,
            registeredDevices: adminStatus == nil ? nil : devices.count,
            queuedChunks: adminStatus?.chatQueuedChunks,
            queuedBytes: adminStatus?.chatQueuedBytes,
            deviceQueues: adminStatus?.chatDeviceQueues
        )
    }
}
