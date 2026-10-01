import Foundation

enum MasterActionClientError: LocalizedError {
    case invalidConfiguration
    case invalidResponse
    case rejected(Int)
    case policyDenied(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Master Action Endpoint ist ungültig."
        case .invalidResponse: "Master hat ungültige Action-Daten geliefert."
        case let .rejected(code): "Master hat die Action-Anfrage abgelehnt (HTTP \(code))."
        case let .policyDenied(reason): reason
        }
    }
}

struct MasterActionConfiguration: Equatable, Sendable {
    let baseURL: URL
    let token: String
}

private struct MasterActionPlanRequest: Encodable {
    let intent: MasterActionIntent
}

private struct MasterActionPrecheckRequest: Encodable {
    let planID: String
    let planHash: String

    enum CodingKeys: String, CodingKey {
        case planID = "plan_id"
        case planHash = "plan_hash"
    }
}

private struct MasterActionOperationRequest: Encodable {
    let operationID: String

    enum CodingKeys: String, CodingKey {
        case operationID = "operation_id"
    }
}

actor MasterActionClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    func plan(intent: MasterActionIntent, configuration: MasterActionConfiguration) async throws -> MasterActionPlan {
        try await request(
            path: "v1/actions/plan",
            method: "POST",
            body: MasterActionPlanRequest(intent: intent),
            configuration: configuration
        )
    }

    func precheck(plan: MasterActionPlan, configuration: MasterActionConfiguration) async throws -> MasterActionPrecheck {
        guard !plan.isExpired() else { throw MasterActionClientError.policyDenied("Plan ist abgelaufen") }
        return try await request(
            path: "v1/actions/precheck",
            method: "POST",
            body: MasterActionPrecheckRequest(planID: plan.id, planHash: plan.planHash),
            configuration: configuration
        )
    }

    func execute(
        plan: MasterActionPlan,
        precheck: MasterActionPrecheck,
        approval: MasterActionApproval,
        idempotencyKey: String,
        capabilityActive: Bool,
        authorityFresh: Bool,
        connected: Bool,
        configuration: MasterActionConfiguration
    ) async throws -> MasterActionReceipt {
        let decision = MasterActionPolicy.canApprove(
            plan: plan,
            precheck: precheck,
            capabilityActive: capabilityActive,
            authorityFresh: authorityFresh,
            connected: connected
        )
        guard decision == .allow else {
            if case let .deny(reason) = decision { throw MasterActionClientError.policyDenied(reason) }
            throw MasterActionClientError.policyDenied("Action ist gesperrt")
        }
        guard approval.planID == plan.id else {
            throw MasterActionClientError.policyDenied("Freigabe gehört nicht zu diesem Plan")
        }
        if MasterActionPolicy.requiresBiometrics(for: plan.risk), !approval.biometricConfirmed {
            throw MasterActionClientError.policyDenied("Biometrische Freigabe fehlt")
        }
        if MasterActionPolicy.requiresTypedConfirmation(for: plan.risk), approval.confirmationText?.isEmpty != false {
            throw MasterActionClientError.policyDenied("Explizite Bestätigung fehlt")
        }
        let request = MasterActionExecutionRequest(
            planID: plan.id,
            planHash: plan.planHash,
            nonce: plan.nonce,
            idempotencyKey: idempotencyKey
        )
        return try await self.request(
            path: "v1/actions/execute",
            method: "POST",
            body: request,
            configuration: configuration
        )
    }

    func verify(operationID: String, configuration: MasterActionConfiguration) async throws -> MasterActionVerification {
        try await request(
            path: "v1/actions/verify",
            method: "POST",
            body: MasterActionOperationRequest(operationID: operationID),
            configuration: configuration
        )
    }

    func rollback(operationID: String, configuration: MasterActionConfiguration) async throws -> MasterActionReceipt {
        try await request(
            path: "v1/actions/rollback",
            method: "POST",
            body: MasterActionOperationRequest(operationID: operationID),
            configuration: configuration
        )
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body,
        configuration: MasterActionConfiguration
    ) async throws -> Response {
        guard !configuration.token.isEmpty,
              let url = URL(string: path, relativeTo: configuration.baseURL)?.absoluteURL,
              ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
            throw MasterActionClientError.invalidConfiguration
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MasterActionClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw MasterActionClientError.rejected(http.statusCode) }
        return try decoder.decode(Response.self, from: data)
    }
}
