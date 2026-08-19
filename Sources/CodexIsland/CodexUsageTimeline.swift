import Foundation

enum CodexUsageTimeline {
    static func lastDaysIncludingToday(
        from buckets: [DailyUsageBucket],
        todayTokens: Int64? = nil,
        count: Int = 30,
        now: Date = Date(),
        calendar inputCalendar: Calendar = .autoupdatingCurrent
    ) -> [DailyUsageBucket] {
        guard count > 0 else { return [] }

        let calendar = inputCalendar
        let today = calendar.startOfDay(for: now)
        guard let firstDay = calendar.date(
            byAdding: .day,
            value: -(count - 1),
            to: today
        ) else {
            return []
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        var tokenByDate = buckets.reduce(into: [String: Int64]()) { result, bucket in
            result[bucket.startDate, default: 0] += max(0, bucket.tokens)
        }
        if let todayTokens {
            tokenByDate[formatter.string(from: today)] = max(0, todayTokens)
        }

        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: firstDay) else {
                return nil
            }
            let dateKey = formatter.string(from: date)
            return DailyUsageBucket(
                startDate: dateKey,
                tokens: tokenByDate[dateKey] ?? 0
            )
        }
    }
}
