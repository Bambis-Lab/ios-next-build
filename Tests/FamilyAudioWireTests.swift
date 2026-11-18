import Foundation
import XCTest
@testable import IOSNext

final class FamilyAudioWireTests: XCTestCase {
    private let configuration = ChatConfiguration(baseURL: URL(string: "https://example.invalid/")!,
        token: "synthetic-token", userID: "gabi", deviceID: "ios-fixture")

    func testEndpointOriginAndCredentialRestrictions() throws {
        let request = try FamilyAudioEndpoint.request(configuration: configuration,
            endpoint: URL(string: "wss://example.invalid/v1/audio")!)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-token")
        for raw in ["wss://other.invalid/v1/audio", "ws://example.invalid/v1/audio",
                    "wss://example.invalid:444/v1/audio", "wss://example.invalid/v1/audio?token=x",
                    "wss://user@example.invalid/v1/audio", "wss://example.invalid/other"] {
            XCTAssertThrowsError(try FamilyAudioEndpoint.request(configuration: configuration,
                endpoint: URL(string: raw)!))
        }
        let local = ChatConfiguration(baseURL: URL(string: "http://127.0.0.1:8080")!,
            token: "fixture", userID: "gabi", deviceID: "ios-fixture")
        let endpoint = URL(string: "ws://127.0.0.1:12345/v1/audio")!
        XCTAssertThrowsError(try FamilyAudioEndpoint.request(configuration: local, endpoint: endpoint))
        XCTAssertNoThrow(try FamilyAudioEndpoint.request(configuration: local, endpoint: endpoint, syntheticLoopback: true))
    }

    func testWireSeparatesEventsAndResponses() throws {
        let bound = Data(#"{"bound":true,"mode":"stream"}"#.utf8)
        guard case .bound = try FamilyAudioInbound.decode(bound) else { return XCTFail("Binding") }
        let response = Data(#"{"status":200,"result":{"queued":true}}"#.utf8)
        guard case let .response(result) = try FamilyAudioInbound.decode(response) else {
            return XCTFail("Response")
        }
        let cipher = Data(repeating: 7, count: 32)
        XCTAssertTrue(FamilyAudioCommand.push(sequence: 0, ciphertext: cipher).accepts(result))
        XCTAssertFalse(FamilyAudioCommand.heartbeat.accepts(result))
        let event = try JSONSerialization.data(withJSONObject: [
            "event": "audio", "packets": [["sequence": 3, "ciphertext": cipher.base64EncodedString()]]
        ])
        guard case let .packets(packets) = try FamilyAudioInbound.decode(event) else {
            return XCTFail("Event")
        }
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(try packets[0].validatedCiphertext(), cipher)
        XCTAssertThrowsError(try FamilyAudioInbound.decode(Data(#"{"status":403,"result":{}}"#.utf8)))
        XCTAssertThrowsError(try FamilyAudioInbound.decode(Data(#"{"bound":true,"mode":"request"}"#.utf8)))
        XCTAssertThrowsError(try FamilyAudioInbound.decode(Data(#"{"event":"audio","packets":[{"sequence":-1,"ciphertext":"bad"}]}"#.utf8)))
        XCTAssertThrowsError(try FamilyAudioCommand.push(sequence: UInt64.max, ciphertext: cipher).wireData())
        XCTAssertThrowsError(try FamilyAudioCommand.refresh("bad\nheader").wireData())
    }

    func testCommandUsesExactBackendFields() throws {
        let bytes = Data(repeating: 4, count: 32)
        let data = try FamilyAudioCommand.push(sequence: 42, ciphertext: bytes).wireData()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["action","sequence","ciphertext"]))
        XCTAssertEqual(object["sequence"] as? Int, 42)
        XCTAssertEqual(object["ciphertext"] as? String, bytes.base64EncodedString())
    }
}
