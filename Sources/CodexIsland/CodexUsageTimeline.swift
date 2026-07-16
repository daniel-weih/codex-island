import Foundation

enum CodexUsageTimeline {
    static func lastCompletedDays(
        from buckets: [DailyUsageBucket],
        count: Int = 30,
        now: Date = Date(),
        calendar inputCalendar: Calendar = .autoupdatingCurrent
    ) -> [DailyUsageBucket] {
        guard count > 0 else { return [] }

        let calendar = inputCalendar
        let today = calendar.startOfDay(for: now)
        guard let finalDay = calendar.date(byAdding: .day, value: -1, to: today),
              let firstDay = calendar.date(byAdding: .day, value: -(count - 1), to: finalDay) else {
            return []
        }

        let tokenByDate = buckets.reduce(into: [String: Int64]()) { result, bucket in
            result[bucket.startDate, default: 0] += max(0, bucket.tokens)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

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
