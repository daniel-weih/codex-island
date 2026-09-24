import Foundation

/// Ephemeral analysis turns have no rollout file. Merge their cumulative turn
/// counters once per record into the same local buckets as ordinary tasks.
enum ResetSubscriptionUsage {
    struct Aggregation: Equatable, Sendable {
        var today: Int64 = 0
        var hourly: [HourlyUsageBucket] = []
        var daily: [DailyUsageBucket] = []
        var credits: [Date: CodexChartCreditTotal] = [:]
    }

    /// The expensive reduction changes only with turn records or calendar boundaries.
    /// Store the result after computing it off the main actor, then reuse it on UI ticks.
    struct AggregationCache {
        private struct Key: Equatable {
            let revision: UInt64
            let hour: Date?
            let calendar: Calendar.Identifier
            let timeZone: String

            init(revision: UInt64, now: Date, calendar: Calendar) {
                self.revision = revision
                hour = calendar.dateInterval(of: .hour, for: now)?.start
                self.calendar = calendar.identifier
                timeZone = calendar.timeZone.identifier
            }
        }
        private var key: Key?
        private var aggregation: Aggregation?

        func value(revision: UInt64, now: Date, calendar: Calendar = .autoupdatingCurrent) -> Aggregation? {
            key == Key(revision: revision, now: now, calendar: calendar) ? aggregation : nil
        }

        mutating func store(_ value: Aggregation, revision: UInt64, now: Date, calendar: Calendar = .autoupdatingCurrent) {
            key = Key(revision: revision, now: now, calendar: calendar)
            aggregation = value
        }
    }

    static func merge(
        records: [ResetUsageRecord],
        today: Int64, hourly: [HourlyUsageBucket], daily: [DailyUsageBucket],
        credits: [Date: CodexChartCreditTotal], now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> (today: Int64, hourly: [HourlyUsageBucket], daily: [DailyUsageBucket], credits: [Date: CodexChartCreditTotal]) {
        merge(aggregation: aggregate(records: records, now: now, calendar: calendar),
              today: today, hourly: hourly, daily: daily, credits: credits)
    }

    static func merge(
        aggregation: Aggregation,
        today: Int64, hourly: [HourlyUsageBucket], daily: [DailyUsageBucket],
        credits: [Date: CodexChartCreditTotal]
    ) -> (today: Int64, hourly: [HourlyUsageBucket], daily: [DailyUsageBucket], credits: [Date: CodexChartCreditTotal]) {
        var total = today
        var hours = Dictionary(hourly.map { ($0.hourStart, $0.tokens) }, uniquingKeysWith: max)
        var days = Dictionary(daily.map { ($0.startDate, $0.tokens) }, uniquingKeysWith: max)
        var prices = credits
        total = add(total, aggregation.today)
        for bucket in aggregation.hourly { hours[bucket.hourStart] = add(hours[bucket.hourStart] ?? 0, bucket.tokens) }
        for bucket in aggregation.daily { days[bucket.startDate] = add(days[bucket.startDate] ?? 0, bucket.tokens) }
        for (hour, cost) in aggregation.credits { prices[hour, default: CodexChartCreditTotal()].merge(cost) }
        return (total, hours.map { HourlyUsageBucket(hourStart: $0.key, tokens: $0.value) }.sorted { $0.hourStart < $1.hourStart },
                days.map { DailyUsageBucket(startDate: $0.key, tokens: $0.value) }.sorted { $0.startDate < $1.startDate }, prices)
    }

    static func aggregate(records: [ResetUsageRecord], now: Date, calendar: Calendar = .autoupdatingCurrent) -> Aggregation {
        var total: Int64 = 0
        var hours: [Date: Int64] = [:]
        var days: [String: Int64] = [:]
        var prices: [Date: CodexChartCreditTotal] = [:]
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        let hourStart = calendar.date(byAdding: .hour, value: -47, to: calendar.dateInterval(of: .hour, for: now)!.start)!
        let records = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, second in
            if first.recordedAt == second.recordedAt { return first.totalTokens >= second.totalTokens ? first : second }
            return first.recordedAt > second.recordedAt ? first : second
        })
        for record in records.values where record.totalTokens >= 0 && record.recordedAt <= now {
            guard let hour = calendar.dateInterval(of: .hour, for: record.recordedAt)?.start else { continue }
            if record.recordedAt >= start && record.recordedAt < end { total = add(total, record.totalTokens) }
            if hour >= hourStart { hours[hour] = add(hours[hour] ?? 0, record.totalTokens) }
            let day = formatter.string(from: record.recordedAt)
            days[day] = add(days[day] ?? 0, record.totalTokens)
            let actual = CodexCreditRateCard.credits(model: record.model, serviceTier: record.serviceTier,
                inputTokens: record.inputTokens, cachedInputTokens: record.cachedInputTokens, outputTokens: record.outputTokens)
            let standard = CodexCreditRateCard.credits(model: record.model, serviceTier: "default",
                inputTokens: record.inputTokens, cachedInputTokens: record.cachedInputTokens, outputTokens: record.outputTokens)
            prices[hour, default: CodexChartCreditTotal()].merge(CodexChartCreditTotal(
                tokens: Double(record.totalTokens), credits: actual ?? 0,
                standardCredits: standard ?? 0, unpricedCalls: actual == nil ? 1 : 0))
        }
        return Aggregation(today: total,
            hourly: hours.map { HourlyUsageBucket(hourStart: $0.key, tokens: $0.value) }.sorted { $0.hourStart < $1.hourStart },
            daily: days.map { DailyUsageBucket(startDate: $0.key, tokens: $0.value) }.sorted { $0.startDate < $1.startDate }, credits: prices)
    }

    private static func add(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int64.max : sum
    }
}
