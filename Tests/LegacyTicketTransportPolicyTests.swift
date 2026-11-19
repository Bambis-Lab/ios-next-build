import XCTest
@testable import IOSNext

final class LegacyTicketTransportPolicyTests:XCTestCase {
    func testFamilyModeRejectsAllPlaintextTicketRoutes() {
        for path in ["v1/admin/tickets?limit=100","/v1/admin/tickets/x","v1/admin/tickets/x/messages",
                     "v1/admin/tickets/x/approve","v1/admin/tickets/x/status","v1/chat/tickets",
                     "/v1/chat/tickets/x","v1/chat/tickets/x/messages"] {
            XCTAssertFalse(LegacyTicketTransportPolicy.allows(path:path,familyBrokerConfigured:true))
            XCTAssertTrue(LegacyTicketTransportPolicy.allows(path:path,familyBrokerConfigured:false))
        }
        for path in ["v2/admin/encrypted-tickets","v2/chat/encrypted-tickets","v1/chat/messages","v1/admin/projects"] {
            XCTAssertTrue(LegacyTicketTransportPolicy.allows(path:path,familyBrokerConfigured:true))
        }
    }
}
