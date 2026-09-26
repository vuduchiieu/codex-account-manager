import Foundation

enum UsageParser {
    static func parse(_ result: JSONValue) -> CodexUsageSnapshot {
        let legacy = result["rateLimits"] ?? result
        var windows: [UsageWindow] = []
        appendSnapshot(legacy, fallbackLimitID: "codex", to: &windows)

        if let limits = result["rateLimitsByLimitId"]?.object {
            for limitID in limits.keys.sorted() {
                guard let value = limits[limitID] else { continue }
                appendSnapshot(value, fallbackLimitID: limitID, to: &windows)
            }
        }

        var seen = Set<String>()
        var unique: [UsageWindow] = []
        for window in windows {
            let key = [
                window.limitID ?? "",
                String(window.windowDurationMinutes ?? -1),
                String(window.resetsAt?.timeIntervalSince1970 ?? -1),
            ].joined(separator: ":")
            if seen.insert(key).inserted {
                unique.append(window)
            }
        }

        let fiveHourIndex = unique.firstIndex { $0.windowDurationMinutes == 300 }
        let weeklyIndex = unique.firstIndex { $0.windowDurationMinutes == 10_080 }
        let selectedIndices = Set([fiveHourIndex, weeklyIndex].compactMap { $0 })
        let credits = legacy["credits"]
        return CodexUsageSnapshot(
            fiveHour: fiveHourIndex.map { unique[$0] },
            weekly: weeklyIndex.map { unique[$0] },
            additionalWindows: unique.enumerated().compactMap { index, window in
                selectedIndices.contains(index) ? nil : window
            },
            creditsBalance: credits?["balance"]?.string ?? credits?["balance"]?.double.map { String($0) },
            hasCredits: credits?["hasCredits"]?.bool,
            unlimitedCredits: credits?["unlimited"]?.bool,
            sourcePlan: legacy["planType"]?.string
        )
    }

    private static func appendSnapshot(
        _ snapshot: JSONValue,
        fallbackLimitID: String,
        to windows: inout [UsageWindow]
    ) {
        let limitID = snapshot["limitId"]?.string ?? fallbackLimitID
        let limitName = snapshot["limitName"]?.string
        let normalModelSlug = snapshot["normalModelSlug"]?.string
        appendWindow(snapshot["primary"], limitID: limitID, limitName: limitName, normalModelSlug: normalModelSlug, to: &windows)
        appendWindow(snapshot["secondary"], limitID: limitID, limitName: limitName, normalModelSlug: normalModelSlug, to: &windows)
        appendWindow(snapshot, limitID: limitID, limitName: limitName, normalModelSlug: normalModelSlug, to: &windows)
    }

    private static func appendWindow(
        _ value: JSONValue?,
        limitID: String,
        limitName: String?,
        normalModelSlug: String?,
        to windows: inout [UsageWindow]
    ) {
        guard let value, let used = value["usedPercent"]?.double else { return }
        let timestamp = value["resetsAt"]?.double
        windows.append(UsageWindow(
            usedPercent: used,
            windowDurationMinutes: value["windowDurationMins"]?.int,
            resetsAt: timestamp.map { Date(timeIntervalSince1970: $0) },
            limitID: limitID,
            limitName: limitName,
            normalModelSlug: normalModelSlug
        ))
    }
}
