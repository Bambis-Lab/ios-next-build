import Foundation

extension LiveOperation {
    var runnerName: String? { metadataValue("runner", "runner_name", "runner_id") ?? host }
    var branchName: String? { metadataValue("branch", "ref", "git_branch") }
    var workflowName: String? { metadataValue("workflow", "workflow_name") }
    var jobName: String? { metadataValue("job", "job_name") }
    var phaseName: String? { metadataValue("phase") }
    var stepName: String? { metadataValue("step", "step_name") }
    var lastEvent: String? { metadataValue("last_event", "event") }
    var nextExpectedEvent: String? { metadataValue("next_expected_event", "next_event") }
    var evidenceSource: String { metadataValue("evidence_source", "source") ?? source.title }
    var authorityName: String { metadataValue("authority", "authority_name") ?? "Master Runtime" }
    var capabilityName: String { metadataValue("capability") ?? "READ_ONLY" }
    var verificationText: String {
        switch metadataValue("verification", "evidence_state", "confidence")?.lowercased() {
        case "verified", "authoritative", "high": "Verifiziert"
        case "observed", "medium": "Beobachtet"
        case "uncertain", "low": "Unsicher"
        default: "Beobachtet"
        }
    }

    var durationText: String {
        let milliseconds: Int
        if let durationMS {
            milliseconds = max(0, durationMS)
        } else {
            let end = completedAt ?? Date()
            milliseconds = max(0, Int(end.timeIntervalSince(startedAt) * 1_000))
        }
        let seconds = milliseconds / 1_000
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        if minutes < 60 { return "\(minutes)m \(remainder)s" }
        let hours = minutes / 60
        return "\(hours)h \(minutes % 60)m"
    }

    var freshnessText: String {
        let age = max(0, Int(Date().timeIntervalSince(updatedAt)))
        if age < 5 { return "gerade eben" }
        if age < 60 { return "vor \(age)s" }
        if age < 3_600 { return "vor \(age / 60)m" }
        return "vor \(age / 3_600)h"
    }

    var freshnessStateText: String {
        let age = max(0, Int(Date().timeIntervalSince(updatedAt)))
        if age < 30 { return "Frisch" }
        if age < 300 { return "Aktuell" }
        return "Veraltet"
    }

    private func metadataValue(_ keys: String...) -> String? {
        for key in keys {
            if let value = metadata?[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
