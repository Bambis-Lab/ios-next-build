import Foundation

/// The production bundle's verified family-broker configuration makes the
/// old plaintext ticket API unavailable, independent of what model or view
/// invokes the request. Do not block the separately authenticated E2EE API.
enum LegacyTicketTransportPolicy {
    static func allows(path:String,familyBrokerConfigured:Bool)->Bool {
        guard familyBrokerConfigured else {return true}
        let route=path.split(separator:"?",maxSplits:1).first.map(String.init) ?? path
        let normalized=route.hasPrefix("/") ? String(route.dropFirst()) : route
        return !["v1/admin/tickets","v1/chat/tickets"].contains {
            normalized==$0 || normalized.hasPrefix($0+"/")
        }
    }
}
