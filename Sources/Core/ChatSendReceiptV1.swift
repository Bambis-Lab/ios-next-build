import Foundation
import CryptoKit

struct ChatSendReceiptV1: Codable, Sendable {
    let id:String
    let state:String
    let expiresInSeconds:Int
    let receiptVersion:Int
    let envelopeSHA256:String
    let replayed:Bool

    enum CodingKeys:String,CodingKey {
        case id,state,replayed
        case expiresInSeconds="expires_in_seconds"
        case receiptVersion="receipt_version"
        case envelopeSHA256="envelope_sha256"
    }

    static func digest(_ envelope:ChatEnvelope) throws -> String {
        let encoder=JSONEncoder()
        encoder.outputFormatting=[.sortedKeys,.withoutEscapingSlashes]
        return SHA256.hash(data:try encoder.encode(envelope)).map{String(format:"%02x",$0)}.joined()
    }

    func requireMatch(_ envelope:ChatEnvelope) throws {
        guard receiptVersion==1,id==envelope.id,state=="queued_persistent",
              expiresInSeconds>0,envelopeSHA256==((try? Self.digest(envelope)) ?? "")
        else {throw ChatError.invalidResponse}
    }
}
