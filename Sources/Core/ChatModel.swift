import Foundation
import LocalAuthentication
import Observation
import UIKit

@MainActor
@Observable
final class ChatModel {
    enum State: Equatable {
        case notConfigured
        case connecting
        case online
        case offline(String)
    }

    private struct PartialMessage {
        let senderUserID: String
        let kind: ChatMessageKind
        let contentType: String
        let createdAt: Date
        let chunkCount: Int
        var chunks: [Int: Data]
        var lastUpdated: Date
    }

    static let chunkSize = 384 * 1024
    static let maximumBytes: [ChatMessageKind: Int] = [
        .text: 16 * 1024,
        .image: 12 * 1024 * 1024,
        .voice: 24 * 1024 * 1024,
        .video: 30 * 1024 * 1024,
    ]

    var state: State = .notConfigured
    var messages: [ChatMessage] = []
    var draft = ""
    var recipientUserID = ""
    var contacts: [ChatContact] = []
    var lastError: String?
    var ownSafetyNumber = ""
    var recipientSafetyNumbers: [String] = []
    var isSending = false
    var accessRole: ChatAccessRole?
    var lastCreatedTicketID: String?

    private let relay = ChatRelayClient()
    private var configuration: ChatConfiguration?
    private var keys: ChatDeviceKeys?
    private var receiveTask: Task<Void, Never>?
    private var partialMessages: [String: PartialMessage] = [:]
    private var seenEnvelopeIDs: [String: Date] = [:]
    private let endpointKey = "chatRelayEndpoint"
    private let userKey = "chatUserID"
    private let deviceKey = "chatDeviceID"
    private let recipientKey = "chatRecipientUserID"
    private let tokenAccount = "chatRelayToken"
    private let haUserKey = "chatHomeAssistantUserID"

    init() {
        restoreConfiguration()
    }

    var canSend: Bool {
        state == .online && !recipientUserID.isEmpty
    }

    func start(using appModel: AppModel) async {
        if let context = appModel.chatBootstrapContext() {
            let boundHAUser = UserDefaults.standard.string(forKey: haUserKey)
            if let boundHAUser, boundHAUser != context.homeAssistantUserID {
                forgetConfiguration()
            }
            if configuration == nil {
                do {
                    try await automaticConfigure(using: context)
                } catch {
                    state = .offline("Automatische Chat-Einrichtung fehlgeschlagen: \(error.localizedDescription)")
                    return
                }
            } else if boundHAUser == nil, let configuration {
                // A pre-1.0.10 credential has no HA-user binding. Only migrate it
                // automatically when the local legacy identity label agrees with the
                // authenticated HA profile; otherwise discard it to prevent a second
                // HA account on the same device from inheriting the first user's chat.
                if Self.legacyIdentityMatchesHomeAssistant(
                    chatUserID: configuration.userID,
                    displayName: context.displayName
                ) {
                    if (try? await relay.linkHomeAssistant(
                        accessToken: context.homeAssistantAccessToken,
                        configuration: configuration
                    )) != nil {
                        UserDefaults.standard.set(context.homeAssistantUserID, forKey: haUserKey)
                    }
                } else {
                    forgetConfiguration()
                    do {
                        try await automaticConfigure(using: context)
                    } catch {
                        state = .offline("Automatische Chat-Einrichtung fehlgeschlagen: \(error.localizedDescription)")
                        return
                    }
                }
            }
        }
        await start()
    }

    func configure(endpoint: String, token: String, userID: String, recipientUserID: String) throws {
        guard let url = URL(string: endpoint), isAllowedEndpoint(url),
              Self.validIdentifier(userID), Self.validIdentifier(recipientUserID), token.count >= 32 else {
            throw ChatError.invalidConfiguration
        }
        stop()
        let deviceID = UserDefaults.standard.string(forKey: deviceKey) ?? "ios-\(UUID().uuidString.lowercased())"
        UserDefaults.standard.set(deviceID, forKey: deviceKey)
        UserDefaults.standard.set(url.absoluteString, forKey: endpointKey)
        UserDefaults.standard.set(userID, forKey: userKey)
        UserDefaults.standard.set(recipientUserID, forKey: recipientKey)
        try KeychainStore.save(token, account: tokenAccount)
        self.recipientUserID = recipientUserID
        configuration = ChatConfiguration(baseURL: url, token: token, userID: userID, deviceID: deviceID)
        state = .connecting
    }

    func start() async {
        guard receiveTask == nil, let configuration else { return }
        do {
            let keys = try ChatDeviceKeys.loadOrCreate()
            self.keys = keys
            ownSafetyNumber = keys.safetyNumber
            try await relay.register(
                identity: keys.publicIdentity(userID: configuration.userID, deviceID: configuration.deviceID),
                configuration: configuration
            )
            let session = try await relay.session(configuration: configuration)
            guard session.userID == configuration.userID else {
                throw ChatError.invalidResponse
            }
            accessRole = session.role
            do {
                contacts = try await relay.contacts(configuration: configuration)
                    .filter { $0.userID != configuration.userID }
                    .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            } catch ChatError.rejected(404) {
                // Backward compatibility with relay 0.1.x while the add-on is being upgraded.
                contacts = recipientUserID.isEmpty
                    ? []
                    : [ChatContact(userID: recipientUserID, displayName: recipientUserID)]
            }
            if !recipientUserID.isEmpty, !contacts.contains(where: { $0.userID == recipientUserID }) {
                recipientUserID = ""
                UserDefaults.standard.removeObject(forKey: recipientKey)
            }
            if recipientUserID.isEmpty, contacts.count == 1, let onlyContact = contacts.first {
                recipientUserID = onlyContact.userID
                UserDefaults.standard.set(onlyContact.userID, forKey: recipientKey)
            }
            try await updateRecipientSafetyNumbers()
            state = .online
            receiveTask = Task { [weak self] in await self?.receiveLoop() }
        } catch {
            state = .offline(error.localizedDescription)
        }
    }

    func stop() {
        receiveTask?.cancel()
        receiveTask = nil
        if configuration != nil { state = .offline("Empfang pausiert") }
    }

    func forgetConfiguration() {
        stop()
        messages.removeAll(keepingCapacity: false)
        partialMessages.removeAll(keepingCapacity: false)
        seenEnvelopeIDs.removeAll(keepingCapacity: false)
        configuration = nil
        contacts = []
        recipientUserID = ""
        accessRole = nil
        lastCreatedTicketID = nil
        KeychainStore.delete(account: tokenAccount)
        UserDefaults.standard.removeObject(forKey: endpointKey)
        UserDefaults.standard.removeObject(forKey: userKey)
        UserDefaults.standard.removeObject(forKey: recipientKey)
        UserDefaults.standard.removeObject(forKey: haUserKey)
        state = .notConfigured
    }

    func selectContact(_ contact: ChatContact) {
        recipientUserID = contact.userID
        UserDefaults.standard.set(contact.userID, forKey: recipientKey)
        recipientSafetyNumbers = []
        Task { try? await updateRecipientSafetyNumbers() }
    }

    nonisolated static func legacyIdentityMatchesHomeAssistant(
        chatUserID: String,
        displayName: String
    ) -> Bool {
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return false }
        return chatUserID.caseInsensitiveCompare(normalizedName) == .orderedSame
    }

    nonisolated static func automaticRelayEndpoint(for homeAssistantURL: URL) -> URL? {
        if let host = homeAssistantURL.host?.lowercased(), host.hasSuffix(".ts.net") {
            let labels = host.split(separator: ".")
            if labels.count >= 3 {
                let tailnet = labels.dropFirst().joined(separator: ".")
                return URL(string: "https://iosnext-chat.\(tailnet)/")
            }
        }
        return URL(string: "https://iosnext-chat.tailff745a.ts.net/")
    }

    private func automaticConfigure(using context: ChatBootstrapContext) async throws {
        guard let endpoint = Self.automaticRelayEndpoint(for: context.homeAssistantBaseURL),
              isAllowedEndpoint(endpoint) else {
            throw ChatError.invalidConfiguration
        }
        stop()
        state = .connecting
        let deviceID = UserDefaults.standard.string(forKey: deviceKey) ?? "ios-\(UUID().uuidString.lowercased())"
        UserDefaults.standard.set(deviceID, forKey: deviceKey)
        let keys = try ChatDeviceKeys.loadOrCreate()
        self.keys = keys
        ownSafetyNumber = keys.safetyNumber
        // The relay derives the canonical chat identity from the authenticated
        // Home Assistant token. The bootstrap user ID is never trusted.
        let provisionalIdentity = keys.publicIdentity(
            userID: "bootstrap",
            deviceID: deviceID
        )
        let bootstrap = try await relay.bootstrap(
            endpoint: endpoint,
            homeAssistantAccessToken: context.homeAssistantAccessToken,
            identity: provisionalIdentity
        )
        guard Self.validIdentifier(bootstrap.userID), bootstrap.token.count >= 32 else {
            throw ChatError.invalidResponse
        }
        UserDefaults.standard.set(endpoint.absoluteString, forKey: endpointKey)
        UserDefaults.standard.set(bootstrap.userID, forKey: userKey)
        UserDefaults.standard.set(context.homeAssistantUserID, forKey: haUserKey)
        try KeychainStore.save(bootstrap.token, account: tokenAccount)
        configuration = ChatConfiguration(
            baseURL: endpoint,
            token: bootstrap.token,
            userID: bootstrap.userID,
            deviceID: deviceID
        )
    }

    func sendDraft() async {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        draft = ""
        await send(Data(value.utf8), kind: .text, contentType: "text/plain; charset=utf-8")
    }

    func sendImage(_ originalData: Data) async {
        do {
            let data = try Self.preparedImageData(originalData)
            await send(data, kind: .image, contentType: "image/jpeg")
        } catch {
            lastError = error.localizedDescription
        }
    }

    func sendVideo(_ data: Data, contentType: String = "video/mp4") async {
        await send(data, kind: .video, contentType: contentType)
    }

    func sendVoice(_ data: Data) async {
        await send(data, kind: .voice, contentType: "audio/wav")
    }

    func send(_ data: Data, kind: ChatMessageKind, contentType: String) async {
        guard let configuration, let keys, !recipientUserID.isEmpty else {
            lastError = "Bitte zuerst einen Chat-Kontakt auswählen."
            return
        }
        guard data.count <= (Self.maximumBytes[kind] ?? 0) else {
            lastError = ChatError.contentTooLarge.localizedDescription
            return
        }
        isSending = true
        defer { isSending = false }
        let groupID = UUID().uuidString.lowercased()
        let localMessage = ChatMessage(
            id: groupID,
            senderUserID: configuration.userID,
            kind: kind,
            contentType: contentType,
            data: data,
            createdAt: .now,
            direction: .outgoing,
            delivery: .sending
        )
        appendMessage(localMessage)
        do {
            let recipients = try await relay.identities(for: recipientUserID, configuration: configuration)
            guard !recipients.isEmpty else { throw ChatError.noRecipientDevice }
            recipientSafetyNumbers = try recipients.map { identity in
                try ChatDeviceKeys.pin(identity)
                guard let number = ChatDeviceKeys.safetyNumber(for: identity) else { throw ChatError.invalidEnvelope }
                return number
            }
            let chunks = Self.chunks(of: data)
            let sender = keys.publicIdentity(userID: configuration.userID, deviceID: configuration.deviceID)
            let createdAt = ISO8601DateFormatter().string(from: localMessage.createdAt)
            for recipient in recipients {
                for (index, chunk) in chunks.enumerated() {
                    let envelope = try keys.encrypt(
                        chunk,
                        kind: kind,
                        contentType: contentType,
                        groupID: groupID,
                        chunkIndex: index,
                        chunkCount: chunks.count,
                        sender: sender,
                        recipient: recipient,
                        createdAt: createdAt
                    )
                    _ = try await relay.send(envelope, configuration: configuration)
                }
            }
            updateDelivery(id: groupID, to: .queued)
        } catch {
            updateDelivery(id: groupID, to: .failed)
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    func createSupportTicket(message: String) async -> String? {
        guard let configuration else { return nil }
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 4000 else {
            lastError = "Das Ticket muss zwischen 1 und 4.000 Zeichen enthalten."
            return nil
        }
        do {
            lastError = nil
            let ticket = try await relay.createSupportTicket(
                message: normalized,
                configuration: configuration
            )
            lastCreatedTicketID = ticket.id
            return ticket.id
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func updateRecipientSafetyNumbers() async throws {
        guard let configuration, !recipientUserID.isEmpty else { return }
        let recipients = try await relay.identities(for: recipientUserID, configuration: configuration)
        recipientSafetyNumbers = recipients.compactMap(ChatDeviceKeys.safetyNumber(for:))
    }

    func approveCurrentRecipientKeys() async {
        guard let configuration else { return }
        do {
            let context = LAContext()
            context.localizedCancelTitle = "Abbrechen"
            var policyError: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &policyError),
                  try await context.evaluatePolicy(
                    .deviceOwnerAuthenticationWithBiometrics,
                    localizedReason: "Neue Chat-Sicherheitsnummern bestätigen"
                  ) else { throw ChatError.authenticationFailed }
            let identities = try await relay.identities(for: recipientUserID, configuration: configuration)
            guard !identities.isEmpty else { throw ChatError.noRecipientDevice }
            try identities.forEach { try ChatDeviceKeys.replacePin(with: $0) }
            recipientSafetyNumbers = identities.compactMap(ChatDeviceKeys.safetyNumber(for:))
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func receiveLoop() async {
        var retryNanoseconds: UInt64 = 500_000_000
        while !Task.isCancelled, let configuration {
            do {
                let envelopes = try await relay.receive(configuration: configuration)
                for envelope in envelopes { try await accept(envelope, configuration: configuration) }
                state = .online
                retryNanoseconds = 500_000_000
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                state = .offline(error.localizedDescription)
                try? await Task.sleep(nanoseconds: retryNanoseconds)
                retryNanoseconds = min(retryNanoseconds * 2, 8_000_000_000)
            }
        }
        receiveTask = nil
    }

    private func accept(_ envelope: ChatEnvelope, configuration: ChatConfiguration) async throws {
        let now = Date.now
        seenEnvelopeIDs = seenEnvelopeIDs.filter { now.timeIntervalSince($0.value) < 600 }
        guard seenEnvelopeIDs[envelope.id] == nil,
              let envelopeDate = ISO8601DateFormatter().date(from: envelope.createdAt),
              abs(now.timeIntervalSince(envelopeDate)) < 600 else {
            throw ChatError.invalidEnvelope
        }
        guard envelope.recipientUserID == configuration.userID,
              envelope.recipientDeviceID == configuration.deviceID,
              envelope.chunkCount <= 256,
              envelope.chunkIndex >= 0,
              envelope.chunkIndex < envelope.chunkCount,
              let keys else { throw ChatError.invalidEnvelope }
        let identities = try await relay.identities(for: envelope.senderUserID, configuration: configuration)
        guard let sender = identities.first(where: { $0.deviceID == envelope.senderDeviceID }) else {
            throw ChatError.invalidEnvelope
        }
        try ChatDeviceKeys.pin(sender)
        let plaintext = try keys.decrypt(envelope, sender: sender)
        seenEnvelopeIDs[envelope.id] = now
        partialMessages = partialMessages.filter { now.timeIntervalSince($0.value.lastUpdated) < 120 }
        let bufferedBytes = partialMessages.values.reduce(0) { total, partial in
            total + partial.chunks.values.reduce(0) { $0 + $1.count }
        }
        guard bufferedBytes + envelope.ciphertext.utf8.count < 96 * 1024 * 1024 else {
            partialMessages.removeAll(keepingCapacity: false)
            throw ChatError.contentTooLarge
        }
        let assemblyID = "\(envelope.senderUserID)|\(envelope.senderDeviceID)|\(envelope.groupID)"
        var partial = partialMessages[assemblyID] ?? PartialMessage(
            senderUserID: envelope.senderUserID,
            kind: envelope.messageType,
            contentType: envelope.contentType,
            createdAt: envelopeDate,
            chunkCount: envelope.chunkCount,
            chunks: [:],
            lastUpdated: now
        )
        guard partial.senderUserID == envelope.senderUserID,
              partial.kind == envelope.messageType,
              partial.contentType == envelope.contentType,
              partial.chunkCount == envelope.chunkCount else { throw ChatError.invalidEnvelope }
        partial.chunks[envelope.chunkIndex] = plaintext
        partial.lastUpdated = now
        partialMessages[assemblyID] = partial
        guard partial.chunks.count == partial.chunkCount else { return }
        var complete = Data()
        for index in 0..<partial.chunkCount {
            guard let chunk = partial.chunks[index] else { throw ChatError.invalidEnvelope }
            complete.append(chunk)
        }
        partialMessages.removeValue(forKey: assemblyID)
        guard complete.count <= (Self.maximumBytes[partial.kind] ?? 0) else { throw ChatError.contentTooLarge }
        appendMessage(ChatMessage(
            id: envelope.groupID,
            senderUserID: partial.senderUserID,
            kind: partial.kind,
            contentType: partial.contentType,
            data: complete,
            createdAt: partial.createdAt,
            direction: .incoming,
            delivery: .received
        ))
    }

    private func updateDelivery(id: String, to delivery: ChatMessage.Delivery) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].delivery = delivery
    }

    private func appendMessage(_ message: ChatMessage) {
        messages.append(message)
        var totalBytes = messages.reduce(0) { $0 + $1.data.count }
        while messages.count > 200 || totalBytes > 160 * 1024 * 1024 {
            guard !messages.isEmpty else { break }
            totalBytes -= messages.removeFirst().data.count
        }
    }

    private func restoreConfiguration() {
        guard let endpoint = UserDefaults.standard.string(forKey: endpointKey),
              let url = URL(string: endpoint), isAllowedEndpoint(url),
              let userID = UserDefaults.standard.string(forKey: userKey),
              let recipient = UserDefaults.standard.string(forKey: recipientKey),
              let deviceID = UserDefaults.standard.string(forKey: deviceKey),
              let token = try? KeychainStore.value(account: tokenAccount) else { return }
        recipientUserID = recipient
        configuration = ChatConfiguration(baseURL: url, token: token, userID: userID, deviceID: deviceID)
        state = .connecting
    }

    private func isAllowedEndpoint(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), url.host != nil else { return false }
#if DEBUG
        return scheme == "https" || scheme == "http"
#else
        return scheme == "https"
#endif
    }

    private static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 64 && value.allSatisfy { $0.isLetter || $0.isNumber || "-_.@".contains($0) }
    }

    private static func chunks(of data: Data) -> [Data] {
        if data.isEmpty { return [Data()] }
        return stride(from: 0, to: data.count, by: chunkSize).map { offset in
            data.subdata(in: offset..<min(offset + chunkSize, data.count))
        }
    }

    private static func preparedImageData(_ data: Data) throws -> Data {
        guard let image = UIImage(data: data) else { throw ChatError.unsupportedMedia }
        let maximumDimension: CGFloat = 2_560
        let scale = min(1, maximumDimension / max(image.size.width, image.size.height))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        guard let result = resized.jpegData(compressionQuality: 0.82) else { throw ChatError.unsupportedMedia }
        guard result.count <= (maximumBytes[.image] ?? 0) else { throw ChatError.contentTooLarge }
        return result
    }
}
