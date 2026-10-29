import Darwin
import Foundation
import SQLite3

@main
struct ParserChecks {
    private static var failures = 0

    static func main() {
        checkTerminalInputRaces()
        expect(CodexDisplayPolicy.remainingCredits(plan: .plus, remainingPercent: 100) == 2000,
               "Plus credits use the requested 2000 baseline")
        expect(CodexDisplayPolicy.remainingCredits(plan: .prolite, remainingPercent: 50) == 5000,
               "5X credits scale the baseline and remaining percentage")
        expect(CodexDisplayPolicy.remainingCredits(plan: .pro, remainingPercent: 99) == 19800,
               "Pro 200 credits use 10X instead of the obsolete 20X multiplier")
        expect(CodexDisplayPolicy.remainingCredits(plan: .pro, remainingPercent: 97) == 19400,
               "the documented remaining balance uses the current Plus baseline")
        expect(CodexDisplayPolicy.remainingCredits(plan: .promax, remainingPercent: 99) == nil,
               "Pro 500 does not infer an unconfirmed allowance from its price")
        expect(CodexDisplayPolicy.remainingCredits(plan: .plus, remainingPercent: nil) == nil,
               "missing quota cannot show a credits balance")
        expect(CodexChartCreditTotal(tokens: 100, credits: 12.346, unpricedCalls: 1)
            .displayText(matching: 100) == "≥12.3 credits",
               "unknown historical calls preserve the priced subtotal rounded down")
        expect(CodexChartCreditTotal().displayText(matching: 100) == "— credits",
               "account-only historical tokens cannot invent credits")
        expect(CodexChartCreditTotal(tokens: 100, credits: 12.346)
            .displayText(matching: 100) == "12.3 credits",
               "complete historical costs keep their normal rounded total")
        expect(CodexChartCreditTotal(tokens: 100, credits: 12.346)
            .displayText(matching: 1000) == "12.3 credits",
               "other computers do not mark complete local credits as partial")
        expect(CodexChartCreditTotal(tokens: 100, credits: 12.346)
            .displayText(matching: 50) == "12.3 credits",
               "delayed account totals do not hide complete local credits")
        expect(CodexThreadCreditEstimate(credits: 0).displayText == "0 credits",
               "zero credits omit the decimal fraction")
        expect(CodexThreadCreditEstimate(credits: 1).displayText == "1.0 credits",
               "nonzero credits retain one decimal place")
        let partialCredits = CodexChartCreditTotal(
            tokens: 100, credits: 1.26, standardCredits: 0.56, unpricedCalls: 1
        )
        expect(partialCredits.chartDisplayText(matching: 100, showsStandard: true, showsActual: true)
            == "≥0.5 / ≥1.2", "both credit series show conservative, separately labeled lower bounds")
        expect(partialCredits.chartDisplayText(matching: 100, showsStandard: false, showsActual: true)
            == "≥1.2", "actual-only credits do not round a lower bound upward")
        expect(partialCredits.chartDisplayText(matching: 100, showsStandard: true, showsActual: false)
            == "≥0.5", "standard-only credits do not round a lower bound upward")
        expect(partialCredits.displayText(matching: 100) == "≥1.2 credits",
               "token mode uses the same conservative lower bound")
        expect(CodexChartCreditTotal(tokens: 100, credits: 1.26, standardCredits: 0.56)
            .chartDisplayText(matching: 100, showsStandard: true, showsActual: true) == "0.6 / 1.3",
               "fully priced credit totals retain normal rounding")
        expect(CodexChartCreditTotal(tokens: 100, credits: 0.04, unpricedCalls: 1)
            .chartDisplayText(matching: 100, showsStandard: false, showsActual: true) == "—",
               "tiny incomplete costs do not claim a positive lower bound")
        expect(CodexChartCreditTotal().chartDisplayText(matching: 100, showsStandard: true, showsActual: true)
            == "—", "credit mode does not invent costs for account-only history")
        checkRateLimitsAndResetCredits()
        checkResetCreditExpiryWarning()
        checkCodexBucketPreference()
        checkTokenConsumptionPolicy()
        checkQuotaConsumptionPace()
        checkQuotaRemainingLevels()
        checkCreditRateCard()
        checkCreditUsageRollouts()
        checkFastModeUsageMultipliers()
        checkDisplayModelNames()
        checkReasoningEffortLabels()
        checkHeaderTokenCounts()
        checkTaskCompletionTransitions()
        checkVisibleThreadPriority()
        checkLivePopoverContent()
        checkAccountUsageThreadAndModel()
        checkPlanBadgeLabels()
        checkLanguageResolution()
        checkDisplayTargetResolution()
        checkLaunchAtLoginSetting()
        checkLegacyLaunchAgentCleanup()
        checkCodexExecutableLocator()
        checkThreadDeepLinks()
        checkUsageTimeline()
        checkRecentThreads()
        checkThreadRequestServiceTiers()
        checkThreadRuntimeSettings()
        checkPartiallyWrittenThreadSettings()
        checkThreadActivityStates()
        checkLargeRolloutRecords()
        checkThreadCreditUsage()
        checkOversizedUsageRecords()
        checkDailyTokenUsage()
        checkReviewBoundaryRegressions()
        checkProtocolStateRegressions()

        guard failures == 0 else {
            fputs("\(failures) parser check(s) failed\n", stderr)
            exit(EXIT_FAILURE)
        }
        print("All parser checks passed")
    }

    private static func checkTerminalInputRaces() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-input-races-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let start = #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"a"}}"#
        let request = #"{"type":"response_item","payload":{"type":"function_call","name":"request_user_input","call_id":"input-a"}}"#
        let response = #"{"type":"response_item","payload":{"type":"function_call_output","call_id":"input-a","output":"cancelled"}}"#
        let complete = #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"a"}}"#
        let error = #"{"type":"event_msg","payload":{"type":"error","codex_error_info":"unauthorized"}}"#
        let abort = #"{"type":"event_msg","payload":{"type":"turn_aborted","turn_id":"a"}}"#
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (index, terminal) in [error, abort, complete].enumerated() {
                let url = directory.appendingPathComponent("incremental-\(index).jsonl")
                let expected: ThreadExecutionState = index == 0 ? .failed : (index == 1 ? .interrupted : .idle)
                var content = ""
                for (step, line) in [start, request, terminal, response, request, complete].enumerated() {
                    content += line + "\n"
                    if step == 0 { try Data(content.utf8).write(to: url) }
                    else {
                        let handle = try FileHandle(forWritingTo: url)
                        try handle.seekToEnd()
                        try handle.write(contentsOf: Data((line + "\n").utf8))
                        try handle.close()
                    }
                    let incremental = try CodexThreadActivityReader.readLatest(from: url.path, validatePath: false)
                    let coldURL = directory.appendingPathComponent("cold-\(index)-\(step).jsonl")
                    try Data(content.utf8).write(to: coldURL)
                    let cold = try CodexThreadActivityReader.readLatest(from: coldURL.path, validatePath: false)
                    expect(incremental.executionState == cold.executionState,
                           "cold and incremental lifecycle scans agree after late input events")
                    if step >= 2 {
                        expect(incremental.executionState == expected,
                               "late input requests/results cannot resurrect terminal turn \(index), step \(step)")
                    }
                }
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                let staleTerminal = #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"older-turn","error":{"message":"old failure"}}}"#
                try handle.write(contentsOf: Data((staleTerminal + "\n").utf8))
                let afterStaleTerminal = try CodexThreadActivityReader.readLatest(from: url.path, validatePath: false)
                expect(afterStaleTerminal.executionState == expected,
                       "late terminal records from another turn cannot replace the finished turn state")
                try handle.write(contentsOf: Data((start + "\n" + request + "\n").utf8))
                try handle.close()
                let restarted = try CodexThreadActivityReader.readLatest(from: url.path, validatePath: false)
                expect(restarted.executionState == .waitingForInput, "an explicit new turn restores input tracking")
            }
            let url = directory.appendingPathComponent("parallel-inputs.jsonl")
            let secondRequest = request.replacingOccurrences(of: "input-a", with: "input-b")
            let secondResponse = response.replacingOccurrences(of: "input-a", with: "input-b")
            let content = [start, request, secondRequest, secondResponse].joined(separator: "\n") + "\n"
            try Data(content.utf8).write(to: url)
            let waiting = try CodexThreadActivityReader.readLatest(from: url.path, validatePath: false)
            expect(waiting.executionState == .waitingForInput,
                   "answering one of two pending input calls must not clear the other")
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((response + "\n").utf8))
            try handle.close()
            let resumed = try CodexThreadActivityReader.readLatest(from: url.path, validatePath: false)
            expect(resumed.executionState == .running, "receiving all pending answers resumes the turn")
        } catch { expect(false, "terminal input races: \(error)") }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard !condition() else { return }
        failures += 1
        fputs("FAIL: \(message)\n", stderr)
    }

    private static func checkProtocolStateRegressions() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-island-protocol-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            func line(_ type: String, _ payload: JSONObject) throws -> Data {
                var data = try JSONSerialization.data(withJSONObject: [
                    "timestamp": "2026-10-16T12:00:00Z", "type": type, "payload": payload
                ], options: [.sortedKeys])
                data.append(10)
                return data
            }
            func append(_ data: Data, to url: URL) throws {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            }
            let start = try line("event_msg", ["type": "task_started", "turn_id": "active"])
            for (index, info) in (["thread_rollback_failed",
                                   ["active_turn_not_steerable": ["turn_kind": "review"]]] as [Any]).enumerated() {
                let url = directory.appendingPathComponent("nonfatal-\(index).jsonl")
                try start.write(to: url)
                _ = try CodexThreadActivityReader.readLatest(from: url.path, validatePath: false)
                try append(line("event_msg", ["type": "error", "codex_error_info": info]), to: url)
                let running = try CodexThreadActivityReader.readLatest(from: url.path, validatePath: false)
                expect(running.executionState == .running, "nonfatal protocol error \(index) does not stop the active turn")
                try append(line("event_msg", ["type": "task_complete", "turn_id": "active"]), to: url)
                let finished = try CodexThreadActivityReader.readLatest(from: url.path, validatePath: false)
                expect(finished.executionState == .idle, "successful completion survives nonfatal protocol error \(index)")
                let coldURL = directory.appendingPathComponent("nonfatal-cold-\(index).jsonl")
                try FileManager.default.copyItem(at: url, to: coldURL)
                let cold = try CodexThreadActivityReader.readLatest(from: coldURL.path, validatePath: false)
                expect(cold.executionState == .idle, "cold replay agrees about nonfatal protocol error \(index)")
            }
            let aliases = directory.appendingPathComponent("turn-aliases.jsonl")
            try line("event_msg", ["type": "turn_started", "turn_id": "active"]).write(to: aliases)
            let aliasStart = try CodexThreadActivityReader.readLatest(from: aliases.path, validatePath: false)
            expect(aliasStart.executionState == .running, "v2 turn_started alias starts activity")
            try append(line("event_msg", ["type": "turn_complete", "turn_id": "active"]), to: aliases)
            let aliasEnd = try CodexThreadActivityReader.readLatest(from: aliases.path, validatePath: false)
            expect(aliasEnd.executionState == .idle, "v2 turn_complete alias completes activity")

            let url = directory.appendingPathComponent("default-tier.jsonl")
            var settings: JSONObject = ["model": "gpt-6-sol", "model_provider_id": "openai",
                "cwd": directory.path, "approval_policy": "never", "reasoning_effort": "max",
                "service_tier": "priority"]
            func settingsLine() throws -> Data {
                try line("event_msg", ["type": "thread_settings_applied", "thread_settings": settings])
            }
            func token(_ total: Int64) throws -> Data {
                try line("event_msg", ["type": "token_count", "info": [
                    "total_token_usage": ["input_tokens": total, "cached_input_tokens": 0,
                                          "output_tokens": 0, "total_tokens": total],
                    "last_token_usage": ["input_tokens": 1_000_000, "cached_input_tokens": 0,
                                         "output_tokens": 0, "total_tokens": 1_000_000]
                ]])
            }
            var content = try line("session_meta", ["source": "cli", "model_provider": "openai"])
            content.append(try settingsLine())
            content.append(try token(1_000_000))
            try content.write(to: url)
            _ = try CodexThreadSettingsReader.readLatest(from: url.path, validatePath: false)
            var usage = ThreadTokenUsage(inputTokens: 1_000_000, cachedInputTokens: 0,
                outputTokens: 0, reasoningOutputTokens: 0, totalTokens: 1_000_000)
            _ = try CodexThreadCreditUsageReader.estimate(from: url.path, matching: usage, validatePath: false)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 13))!
            try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
            _ = try CodexDailyTokenUsageReader.readRecentHours(from: [url.path], now: now, calendar: calendar)
            settings.removeValue(forKey: "service_tier")
            settings.removeValue(forKey: "reasoning_effort")
            try append(settingsLine(), to: url)
            try append(token(2_000_000), to: url)
            usage.inputTokens = 2_000_000; usage.totalTokens = 2_000_000
            for path in [url, directory.appendingPathComponent("default-tier-cold.jsonl")] {
                if path != url { try FileManager.default.copyItem(at: url, to: path) }
                try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: path.path)
                let resolved = try CodexThreadSettingsReader.readLatest(from: path.path, validatePath: false)
                expect(resolved?.serviceTier == "default", "complete snapshots clear omitted Fast tier in \(path.lastPathComponent)")
                expect(resolved?.reasoningEffort == nil, "complete snapshots clear omitted reasoning effort in \(path.lastPathComponent)")
                let price = try CodexThreadCreditUsageReader.estimate(from: path.path, matching: usage, validatePath: false)
                expect(price?.credits == 175 && price?.assumesStandardTier == false,
                       "thread credits price Fast then Standard separately in \(path.lastPathComponent)")
                let daily = try CodexDailyTokenUsageReader.readRecentHours(from: [path.path], now: now, calendar: calendar)
                expect(daily.todayTokens == 2_000_000 && daily.chartCreditTotals.values.reduce(0, { $0 + $1.credits }) == 175,
                       "daily credits agree after leaving Fast in \(path.lastPathComponent)")
            }
            let cleared = directory.appendingPathComponent("cleared-effort.jsonl")
            try line("turn_context", ["model": "gpt-6-sol", "effort": "max"]).write(to: cleared)
            _ = try CodexThreadSettingsReader.readLatest(from: cleared.path, validatePath: false)
            try append(line("turn_context", ["effort": NSNull()]), to: cleared)
            let clearedSettings = try CodexThreadSettingsReader.readLatest(from: cleared.path, validatePath: false)
            expect(clearedSettings?.reasoningEffort == nil, "an explicit null effort clears a cached effort")
        } catch {
            expect(false, "protocol state regressions: \(error)")
        }

        let repeated = CodexStatusPayloadParser.parseRecentThreads(["data": [
            ["id": "same", "name": "newest"], ["threadId": "same", "name": "duplicate"],
            ["id": "next", "name": "next"]
        ]], limit: 2)
        expect(repeated.map(\.id) == ["same", "next"] && repeated.first?.title == "newest",
               "duplicate explicit thread identities cannot crash state dictionaries or consume the row limit")
    }

    private static func checkReviewBoundaryRegressions() {
        let numbers: JSONObject = [
            "max": NSNumber(value: Int64.max), "min": NSNumber(value: Int64.min),
            "maxString": String(Int64.max), "one": 1, "zero": 0,
            "overflow": NSNumber(value: UInt64.max), "fraction": 1.5,
            "integralDouble": 42.0, "largeIntegralDouble": Double(Int64.max - 1023),
            "boolean": true, "nan": "NaN", "infinity": "inf"
        ]
        expect(numbers.int64("max") == .max && numbers.int64("min") == .min,
               "JSON integers preserve the exact Int64 range")
        expect(numbers.int64("maxString") == .max && numbers.int64("one") == 1
               && numbers.int64("zero") == 0,
               "integer strings and numeric zero and one remain distinct from booleans")
        expect(numbers.int64("overflow") == nil && numbers.int("overflow") == nil,
               "out-of-range JSON integers never wrap into negative counters")
        expect(numbers.int64("fraction") == nil && numbers.int64("boolean") == nil,
               "fractional and boolean JSON values are not token counters")
        expect(numbers.int64("integralDouble") == 42
               && numbers.int64("largeIntegralDouble") == Int64.max - 1023,
               "exact integral floating-point JSON values remain supported")
        let decimalNumbers = try? JSONSerialization.jsonObject(
            with: Data(#"{"fraction":1.00000000000000000001,"integer":1.00000000000000000000}"#.utf8)
        ) as? JSONObject
        expect(decimalNumbers?.int64("fraction") == nil && decimalNumbers?.int64("integer") == 1,
               "decimal JSON fractions cannot disappear through Double rounding")
        expect(numbers.double("nan") == nil && numbers.double("infinity") == nil
               && numbers.double("boolean") == nil,
               "invalid numeric quota inputs cannot enter UI arithmetic")

        var usage = ThreadTokenUsage(inputTokens: 0, cachedInputTokens: 0,
                                    outputTokens: 0, reasoningOutputTokens: 0, totalTokens: 0,
                                    contextTokensUsed: .max, contextWindowTokens: 1)
        expect(usage.contextUsedPercent == 100, "extreme context counters clamp before Int conversion")
        usage.contextTokensUsed = 1; usage.contextWindowTokens = 3
        expect(usage.contextUsedPercent == 33, "normal context percentages round to the nearest integer")
        usage.contextTokensUsed = 2
        expect(usage.contextUsedPercent == 67, "context percentage rounding retains its upward half")
        usage.contextTokensUsed = -1
        expect(usage.contextUsedPercent == nil, "negative context counters stay unavailable")
        usage.contextTokensUsed = 0; usage.contextWindowTokens = 0
        expect(usage.contextUsedPercent == nil, "zero context capacity cannot be divided")
        usage.contextWindowTokens = 1
        expect(usage.contextUsedPercent == 0, "empty contexts display zero percent")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 16))!
        let timeline = CodexUsageTimeline.lastDaysIncludingToday(
            from: [.init(startDate: "2026-10-16", tokens: .max),
                   .init(startDate: "2026-10-16", tokens: 1)],
            count: 1, now: now, calendar: calendar
        )
        expect(timeline.first?.tokens == .max, "duplicate date totals saturate without crashing")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-island-review-boundaries-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("settings.jsonl")
            let old = #"{"type":"turn_context","payload":{"model":"gpt-6-sol","service_tier":"default"}}"# + "\n"
            let new = old.replacingOccurrences(of: "gpt-6-sol", with: "gpt-5.4  ")
            try Data(old.utf8).write(to: url)
            let before = try CodexThreadSettingsReader.readLatest(from: url.path, validatePath: false)
            expect(before?.model == "gpt-6-sol", "settings rewrite fixture primes the cache")
            let handle = try FileHandle(forWritingTo: url)
            try handle.write(contentsOf: Data(new.utf8))
            try handle.close()
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)],
                                                 ofItemAtPath: url.path)
            let after = try CodexThreadSettingsReader.readLatest(from: url.path, validatePath: false)
            expect(after?.model == "gpt-5.4  ", "same-inode same-length rewrites invalidate settings")

            let activityURL = directory.appendingPathComponent("activity.jsonl")
            let start = #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"one"}}"# + "\n"
            try Data(start.utf8).write(to: activityURL)
            let running = try CodexThreadActivityReader.readLatest(from: activityURL.path, validatePath: false)
            expect(running.executionState == .running, "whitespace error fixture primes activity cache")
            let error = #"{"type": "event_msg", "payload": {"type": "error", "codex_error_info": "unauthorized"}}"# + "\n"
            let activityHandle = try FileHandle(forWritingTo: activityURL)
            try activityHandle.seekToEnd()
            try activityHandle.write(contentsOf: Data(error.utf8))
            try activityHandle.close()
            let failed = try CodexThreadActivityReader.readLatest(from: activityURL.path, validatePath: false)
            expect(failed.executionState == .failed, "spaced error JSON marks an appended turn failed")
            let coldURL = directory.appendingPathComponent("activity-cold.jsonl")
            try FileManager.default.copyItem(at: activityURL, to: coldURL)
            let cold = try CodexThreadActivityReader.readLatest(from: coldURL.path, validatePath: false)
            expect(cold.executionState == .failed, "spaced error JSON also marks a cold-read turn failed")

            let usageURL = directory.appendingPathComponent("usage.jsonl")
            let timestamp = ISO8601DateFormatter().string(from: now)
            func usageLines(input: Int64, output: Int64, total: Int64) throws -> Data {
                let counts: JSONObject = ["input_tokens": input, "cached_input_tokens": 0,
                                          "output_tokens": output, "total_tokens": total]
                let records: [JSONObject] = [
                    ["type": "session_meta", "timestamp": timestamp,
                     "payload": ["source": "cli", "model_provider": "openai"]],
                    ["type": "turn_context", "timestamp": timestamp,
                     "payload": ["model": "gpt-6-sol", "service_tier": "default "]],
                    ["type": "event_msg", "timestamp": timestamp,
                     "payload": ["type": "token_count",
                                 "info": ["total_token_usage": counts, "last_token_usage": counts]]]
                ]
                return try records.reduce(into: Data()) { data, record in
                    data.append(try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
                    data.append(0x0A)
                }
            }
            let originalUsage = try usageLines(input: 1_000_000, output: 0, total: 1_000_000)
            try originalUsage.write(to: usageURL)
            try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: usageURL.path)
            var matchingUsage = ThreadTokenUsage(inputTokens: 1_000_000, cachedInputTokens: 0,
                                                outputTokens: 0, reasoningOutputTokens: 0, totalTokens: 1_000_000)
            let originalThreadCredits = try CodexThreadCreditUsageReader.estimate(
                from: usageURL.path, matching: matchingUsage, validatePath: false)
            let originalDaily = try CodexDailyTokenUsageReader.readRecentHours(
                from: [usageURL.path], now: now, calendar: calendar)
            expect(originalThreadCredits?.credits == 50
                   && originalDaily.chartCreditTotals.values.reduce(0, { $0 + $1.credits }) == 50,
                   "usage rewrite fixtures prime both incremental caches")
            let rewrittenUsage = String(decoding: originalUsage, as: UTF8.self)
                .replacingOccurrences(of: "default ", with: "priority")
            let usageHandle = try FileHandle(forWritingTo: usageURL)
            try usageHandle.write(contentsOf: Data(rewrittenUsage.utf8))
            try usageHandle.close()
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(2)],
                                                 ofItemAtPath: usageURL.path)
            let rewrittenThreadCredits = try CodexThreadCreditUsageReader.estimate(
                from: usageURL.path, matching: matchingUsage, validatePath: false)
            let rewrittenDaily = try CodexDailyTokenUsageReader.readRecentHours(
                from: [usageURL.path], now: now, calendar: calendar)
            expect(rewrittenThreadCredits?.credits == 125
                   && rewrittenDaily.chartCreditTotals.values.reduce(0, { $0 + $1.credits }) == 125
                   && rewrittenDaily.todayTokens == 1_000_000,
                   "same-length usage rewrites rebuild both credits without double counting tokens")

            let oversizedInteger: Int64 = 9_007_199_254_740_992
            let inconsistentURL = directory.appendingPathComponent("inconsistent-counts.jsonl")
            try usageLines(input: oversizedInteger, output: 1, total: oversizedInteger).write(to: inconsistentURL)
            try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: inconsistentURL.path)
            let inconsistentDaily = try CodexDailyTokenUsageReader.readRecentHours(
                from: [inconsistentURL.path], now: now, calendar: calendar)
            matchingUsage.inputTokens = oversizedInteger
            matchingUsage.outputTokens = 1
            matchingUsage.totalTokens = oversizedInteger
            let inconsistentCredits = try CodexThreadCreditUsageReader.estimate(
                from: inconsistentURL.path, matching: matchingUsage, validatePath: false)
            expect(inconsistentDaily.chartCreditTotals.values.reduce(0, { $0 + $1.credits }) == 0
                   && inconsistentDaily.chartCreditTotals.values.reduce(0, { $0 + $1.unpricedCalls }) == 1
                   && inconsistentCredits == nil,
                   "inconsistent token counts above Double precision stay unpriced in both readers")
        } catch {
            expect(false, "review boundary regressions: \(error.localizedDescription)")
        }
    }

    private static func checkCodexExecutableLocator() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("codex-island-cli-checks-\(UUID().uuidString) space")
        defer { try? fm.removeItem(at: root) }
        do {
            let bin = root.appendingPathComponent("bin", isDirectory: true)
            try fm.createDirectory(at: bin, withIntermediateDirectories: true)
            let executable = bin.appendingPathComponent("codex")
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
            var environment = ProcessInfo.processInfo.environment
            // Never read or change the user's actual login profiles.
            environment["ZDOTDIR"] = root.path
            let profile = root.appendingPathComponent(".zprofile")
            let customPath = "export PATH=\"$ZDOTDIR/bin\"\n"
            try Data(customPath.utf8).write(to: profile)
            expect(CodexExecutableLocator.locateWithLoginShell(environment: environment)?.executableURL == executable,
                   "login-shell lookup finds a custom CLI path containing spaces")

            let banner = root.appendingPathComponent("banner.txt")
            try Data(repeating: 65, count: 512 * 1024).write(to: banner)
            try Data(("/bin/cat \"$ZDOTDIR/banner.txt\"\n" + customPath).utf8).write(to: profile)
            expect(CodexExecutableLocator.locateWithLoginShell(environment: environment)?.executableURL == executable,
                   "large login-profile output neither blocks nor contaminates CLI lookup")

            // The interpreter lives elsewhere, as with npm and a Node version
            // manager. Adding only the CLI's directory to PATH is insufficient.
            let runtimeBin = root.appendingPathComponent("version manager/bin", isDirectory: true)
            try fm.createDirectory(at: runtimeBin, withIntermediateDirectories: true)
            let interpreter = runtimeBin.appendingPathComponent("codex_fixture_node")
            try Data("#!/bin/sh\n[ \"$CODEX_FIXTURE_MARKER\" = retained ]\n".utf8).write(to: interpreter)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: interpreter.path)
            try Data("#!/usr/bin/env codex_fixture_node\n".utf8).write(to: executable)
            environment["PATH"] = "/usr/bin:/bin"
            environment["CODEX_FIXTURE_MARKER"] = "retained"
            try Data("export PATH=\"$ZDOTDIR/bin:$ZDOTDIR/version manager/bin:/usr/bin:/bin\"\n".utf8).write(to: profile)
            func runCLI(environment: [String: String], executableURL: URL? = nil) throws -> Int32 {
                let process = Process()
                process.executableURL = executableURL ?? executable
                process.environment = environment
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus
            }
            let withoutShellPath = try runCLI(environment: environment)
            expect(withoutShellPath == 127, "isolated CLI requires its login-shell interpreter path")
            if let launch = CodexExecutableLocator.locateWithLoginShell(environment: environment) {
                expect(launch.executableURL == executable, "launch configuration retains the located CLI")
                let withShellPath = try runCLI(environment: launch.environment)
                expect(withShellPath == 0, "located CLI starts with its interpreter PATH and inherited environment")
            } else {
                expect(false, "login shell returns a launch configuration for the custom CLI")
            }

            let selectedCLI = root.appendingPathComponent("selected-codex")
            try fm.copyItem(at: executable, to: selectedCLI)
            environment["CODEX_CLI_PATH"] = selectedCLI.path
            if let launch = CodexExecutableLocator.locate(environment: environment) {
                expect(launch.executableURL == selectedCLI,
                       "explicit CLI path keeps precedence over a different CLI on the login-shell PATH")
                let status = try runCLI(environment: launch.environment, executableURL: launch.executableURL)
                expect(status == 0,
                       "direct CLI candidate restores a missing login-shell interpreter PATH")
            } else {
                expect(false, "direct CLI candidate remains discoverable")
            }
            try Data("export PATH=\"$ZDOTDIR/version manager/bin:/usr/bin:/bin\"\n".utf8).write(to: profile)
            if let launch = CodexExecutableLocator.locate(environment: environment) {
                expect(launch.executableURL == selectedCLI,
                       "PATH recovery retains an explicit CLI absent from the shell PATH")
                let status = try runCLI(environment: launch.environment, executableURL: launch.executableURL)
                expect(status == 0,
                       "PATH recovery succeeds independently of shell CLI discovery")
            } else {
                expect(false, "shell CLI discovery is not required for an explicit candidate")
            }

            try Data("#!/usr/bin/env -S codex_fixture_node --fixture-option\n".utf8).write(to: selectedCLI)
            if let launch = CodexExecutableLocator.locate(environment: environment) {
                let status = try runCLI(environment: launch.environment, executableURL: launch.executableURL)
                expect(status == 0, "env -S scripts also recover their missing interpreter PATH")
            } else {
                expect(false, "env -S CLI remains discoverable")
            }

            try Data("exit 7\n".utf8).write(to: profile)
            let failedRecovery = CodexExecutableLocator.locate(environment: environment)
            expect(failedRecovery?.executableURL == selectedCLI
                && failedRecovery?.environment == CodexExecutableLocator.augmentedEnvironment(environment: environment),
                   "a failing login shell retains the explicit CLI and its fallback environment")

            try Data("trap '' TERM\nexec /bin/sleep 30\n".utf8).write(to: profile)
            let recoveryBegan = ProcessInfo.processInfo.systemUptime
            expect(CodexExecutableLocator.locate(environment: environment, loginShellTimeout: 0.1)?.executableURL == selectedCLI,
                   "a stalled PATH recovery does not discard the explicit CLI")
            expect(ProcessInfo.processInfo.systemUptime - recoveryBegan < 2,
                   "direct-candidate PATH recovery respects the shell deadline")

            let profileMarker = root.appendingPathComponent("profile-ran")
            try Data("print -r -- reached > \"$ZDOTDIR/profile-ran\"\nexec /bin/sleep 30\n".utf8).write(to: profile)
            let nativeCLI = root.appendingPathComponent("native-codex")
            try fm.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: nativeCLI)
            var nativeEnvironment = environment
            nativeEnvironment["CODEX_CLI_PATH"] = nativeCLI.path
            expect(CodexExecutableLocator.locate(environment: nativeEnvironment, loginShellTimeout: 0.1)?.executableURL == nativeCLI,
                   "native CLI retains the direct lookup path")
            expect(!fm.fileExists(atPath: profileMarker.path), "native CLI lookup never evaluates a login profile")
            try? fm.removeItem(at: profileMarker)

            var readyEnvironment = environment
            readyEnvironment["PATH"] = runtimeBin.path + ":/usr/bin:/bin"
            if let launch = CodexExecutableLocator.locate(environment: readyEnvironment, loginShellTimeout: 0.1) {
                let status = try runCLI(environment: launch.environment, executableURL: launch.executableURL)
                expect(status == 0, "scripts with an available interpreter launch without PATH recovery")
            } else {
                expect(false, "script with an available interpreter remains discoverable")
            }
            expect(!fm.fileExists(atPath: profileMarker.path), "available interpreters do not incur a login-shell delay")

            try Data("export PATH=\"$ZDOTDIR/empty\"\n".utf8).write(to: profile)
            expect(CodexExecutableLocator.locateWithLoginShell(environment: environment) == nil,
                   "missing CLI in the login-shell path returns no executable")

            let pidURL = root.appendingPathComponent("pid")
            try Data("trap '' TERM\nprint -r -- $$ > \"$ZDOTDIR/pid\"\nexec /bin/sleep 30\n".utf8).write(to: profile)
            let began = ProcessInfo.processInfo.systemUptime
            expect(CodexExecutableLocator.locateWithLoginShell(environment: environment, timeout: 1) == nil,
                   "a stalled login profile returns no executable after its deadline")
            expect(ProcessInfo.processInfo.systemUptime - began < 4,
                   "CLI lookup timeout is bounded even when the child ignores termination")
            let pidText = try String(contentsOf: pidURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let pid = Int32(pidText) {
                let result = kill(pid, 0)
                expect(result == -1 && errno == ESRCH, "timed-out CLI lookup reaps its own child")
            } else {
                expect(false, "stalled login profile records its child PID")
            }

            let childPIDURL = root.appendingPathComponent("child-pid")
            let stubbornChild = "/bin/sh -c 'trap \"\" TERM; echo \"$$\" > \"$ZDOTDIR/child-pid\"; exec /bin/sleep 30' &\nwait $!\n"
            try Data(stubbornChild.utf8).write(to: profile)
            expect(CodexExecutableLocator.locateWithLoginShell(environment: environment, timeout: 1) == nil,
                   "CLI lookup times out when a profile waits for an unresponsive subprocess")
            let childPIDText = try String(contentsOf: childPIDURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let pid = Int32(childPIDText) {
                // Also clean this isolated fixture if the regression returns.
                defer { if kill(pid, 0) == 0 { kill(pid, SIGKILL) } }
                let reapDeadline = ProcessInfo.processInfo.systemUptime + 1
                while kill(pid, 0) == 0, ProcessInfo.processInfo.systemUptime < reapDeadline {
                    Thread.sleep(forTimeInterval: 0.02)
                }
                let result = kill(pid, 0)
                expect(result == -1 && errno == ESRCH,
                       "timed-out CLI lookup leaves no stubborn subprocess behind after its shell exits")
            } else {
                expect(false, "stalled login profile records its subprocess PID")
            }
        } catch {
            expect(false, "login-shell CLI lookup: \(error.localizedDescription)")
        }
    }

    private static func checkLargeRolloutRecords() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-island-large-log-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let settings = #"{"type":"turn_context","payload":{"model":"gpt-6.1-sol","effort":"high","service_tier":"default"}}"# + "\n"
            let start = #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"large-image"}}"# + "\n"
            let tokens = #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":5,"output_tokens":5,"total_tokens":15}}}}"# + "\n"
            let image = #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_image","image_url":"data:image/png;base64,"#
                + String(repeating: "A", count: 16 * 1024 * 1024) + #""}]}}"# + "\n"
            let complete = #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"large-image"}}"# + "\n"
            let cold = root.appendingPathComponent("cold.jsonl")
            let appended = root.appendingPathComponent("appended.jsonl")
            try Data((settings + start + tokens + image + complete).utf8).write(to: cold)
            try Data((settings + start + tokens).utf8).write(to: appended)
            _ = try CodexThreadSettingsReader.readLatest(from: appended.path, validatePath: false)
            _ = try CodexThreadActivityReader.readLatest(from: appended.path, validatePath: false)
            let handle = try FileHandle(forWritingTo: appended)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((image + complete).utf8))
            try handle.close()

            let began = ProcessInfo.processInfo.systemUptime
            for file in [cold, appended] {
                let actualSettings = try CodexThreadSettingsReader.readLatest(from: file.path, validatePath: false)
                let actualActivity = try CodexThreadActivityReader.readLatest(from: file.path, validatePath: false)
                expect(actualSettings == ThreadRuntimeSettings(model: "gpt-6.1-sol", reasoningEffort: "high", serviceTier: "default"),
                       "large image records preserve settings on cold and incremental reads")
                expect(actualActivity.executionState == .idle && actualActivity.tokenUsage?.totalTokens == 15,
                       "large image records do not hide completion or cumulative tokens")
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - began
            // The old growing-buffer scan took over 30 seconds for the cold
            // reads alone. Leave ample headroom for slow test machines.
            expect(elapsed < 10, "large image logs must not stall state refresh for tens of seconds")
            print(String(format: "Large log cold and incremental scan: %.2f s", elapsed))
        } catch {
            expect(false, "large rollout records: \(error.localizedDescription)")
        }
    }

    private static func checkVisibleThreadPriority() {
        func thread(_ id: String, _ state: ThreadExecutionState) -> ThreadSummary {
            ThreadSummary(
                id: id,
                title: id,
                status: "notLoaded",
                clientSource: .app,
                model: nil,
                reasoningEffort: nil,
                serviceTier: nil,
                serviceTierSource: nil,
                tokenUsage: nil,
                executionState: state,
                cwd: nil,
                rolloutPath: nil,
                updatedAt: nil
            )
        }

        let visible = CodexDisplayPolicy.visibleRecentThreads(
            from: [
                thread("recent-1", .idle),
                thread("active-1", .running),
                thread("recent-2", .failed),
                thread("active-2", .running),
                thread("recent-3", .unknown)
            ]
        )
        expect(visible.count == 3, "dashboard displays exactly three recent tasks")
        expect(
            visible.map(\.id) == ["active-1", "active-2", "recent-1"],
            "running tasks are shown first while preserving recency within groups"
        )
        expect(
            CodexDisplayPolicy.recentThreadFetchLimit
                > CodexDisplayPolicy.recentThreadLimit,
            "thread query keeps a wider candidate set than the visible dashboard"
        )
    }

    private static func checkLivePopoverContent() {
        var snapshot = CodexSnapshot.initial
        var usage = ThreadTokenUsage(inputTokens: 100, cachedInputTokens: 0,
            outputTokens: 10, reasoningOutputTokens: 0, totalTokens: 110,
            contextTokensUsed: 110, contextWindowTokens: 1000)
        var thread = ThreadSummary(id: "hovered", title: "Task", status: "idle",
            clientSource: .app, model: nil, reasoningEffort: nil, serviceTier: nil,
            serviceTierSource: nil, tokenUsage: usage, executionState: .idle,
            cwd: nil, rolloutPath: nil, updatedAt: nil)
        snapshot.recentThreads = [thread]
        let token = IslandPopoverContent.token(threadID: thread.id, rank: 0, usage: usage)
        let context = IslandPopoverContent.context(threadID: thread.id, rank: 0, usage: usage)

        // Keep the original hover selection while a refresh changes its values.
        usage.totalTokens = 500
        usage.contextTokensUsed = 300
        thread.tokenUsage = usage
        snapshot.recentThreads = [thread]
        expect(token.resolved(in: snapshot) == .token(threadID: thread.id, rank: 0, usage: usage),
               "stationary token tooltips reflect new counters without a mouse event")
        expect(context.resolved(in: snapshot) == .context(threadID: thread.id, rank: 0, usage: usage),
               "stationary context tooltips reflect new context usage")
        snapshot.recentThreads[0].tokenUsage = nil
        expect(token.resolved(in: snapshot) == nil,
               "lost usage dismisses a token tooltip instead of retaining stale counters")
        expect(context.resolved(in: snapshot) == .context(threadID: thread.id, rank: 0, usage: nil),
               "context tooltips can return to the unavailable state")

        var active = thread
        active.id = "new-active"
        active.executionState = .running
        snapshot.recentThreads = [thread, active]
        expect(token.resolved(in: snapshot) == nil && context.resolved(in: snapshot) == nil,
               "active-thread reprioritization dismisses tooltips anchored to the previous row")
        snapshot.recentThreads = []
        expect(context.resolved(in: snapshot) == nil, "removed threads dismiss their tooltips")

        let oldReset = ResetCreditSummary(availableCount: 3, earliestExpiration: nil)
        let reset = IslandPopoverContent.reset(oldReset)
        let newReset = ResetCreditSummary(availableCount: 1, earliestExpiration: Date(timeIntervalSince1970: 2_000_000_000))
        snapshot.resetCredits = newReset
        expect(reset.resolved(in: snapshot) == .reset(newReset),
               "stationary reset tooltips update the count and expiration")
        snapshot.resetCredits = .empty
        expect(reset.resolved(in: snapshot) == nil, "exhausted reset credits dismiss their tooltip")
        snapshot.resetCredits = nil
        expect(reset.resolved(in: snapshot) == nil, "unavailable reset credits dismiss their tooltip")
        expect(IslandPopoverContent.chartLegend(.actual).resolved(in: snapshot) == .chartLegend(.actual),
               "unrelated account refreshes preserve static chart explanations")
    }

    private static func checkTaskCompletionTransitions() {
        func thread(_ id: String, _ state: ThreadExecutionState) -> ThreadSummary {
            ThreadSummary(
                id: id,
                title: id,
                status: "notLoaded",
                clientSource: .app,
                model: nil,
                reasoningEffort: nil,
                serviceTier: nil,
                serviceTierSource: nil,
                tokenUsage: nil,
                executionState: state,
                cwd: nil,
                rolloutPath: nil,
                updatedAt: nil
            )
        }

        let previous: [String: ThreadExecutionState] = [
            "completed": .running,
            "interrupted": .running,
            "failed": .running,
            "already-idle": .idle,
            "removed": .running
        ]
        let completed = CodexDisplayPolicy.completedThreadIDs(
            previousStates: previous,
            currentThreads: [
                thread("completed", .idle),
                thread("interrupted", .interrupted),
                thread("failed", .failed),
                thread("already-idle", .idle),
                thread("new-history", .idle)
            ]
        )
        expect(
            completed == ["completed"],
            "completion sound only observes a running-to-idle transition"
        )

        let inputRequested = CodexDisplayPolicy.inputRequestedThreadIDs(
            previousStates: ["waiting": .running, "already-waiting": .waitingForInput],
            currentThreads: [
                thread("waiting", .waitingForInput),
                thread("already-waiting", .waitingForInput),
                thread("running", .running)
            ]
        )
        expect(
            inputRequested == ["waiting"],
            "approval sound only observes a transition into waiting for input"
        )
    }

    private static func checkPlanBadgeLabels() {
        let labels: [(String, String)] = [
            ("free", "FREE"), ("go", "GO"), ("plus", "PLUS"),
            ("prolite", "PRO 100"), ("pro", "PRO 200"), ("promax", "PRO 500"),
            ("team", "TEAM"), ("self_serve_business_prolite", "BUSINESS+"),
            ("self_serve_business_usage_based", "BUSINESS"), ("business", "BUSINESS"),
            ("ent26", "ENTERPRISE"), ("enterprise_cbp_automation", "ENTERPRISE"),
            ("enterprise_cbp_usage_based", "ENTERPRISE"), ("enterprise", "ENTERPRISE"),
            ("edu", "EDU"), ("edu_plus", "EDU PLUS"), ("edu_pro", "EDU PRO")
        ]
        expect(Set(labels.map(\.0) + ["unknown"]) == Set(CodexSubscriptionPlan.allCases.map(\.rawValue)),
               "badge coverage includes every current protocol plan enum")
        for (rawValue, label) in labels {
            let account = CodexStatusPayloadParser.parseAccount([
                "account": ["type": "chatgpt", "planType": rawValue]
            ])
            let limits = CodexStatusPayloadParser.parseRateLimits([
                "rateLimits": ["planType": rawValue]
            ])
            expect(CodexDisplayPolicy.planBadgeLabel(
                accountPlanType: account.planType, rateLimitPlanType: limits.bucket?.planType
            ) == label, "protocol plan \(rawValue) has a readable badge")
            expect(CodexDisplayPolicy.planBadgeLabel(
                accountPlanType: nil, rateLimitPlanType: rawValue
            ) == label, "quota-only plan \(rawValue) has the same badge")
            expect(label.count <= 10, "\(rawValue) badge fits without truncating enum names")
        }
        expect(
            CodexDisplayPolicy.planBadgeLabel(
                accountPlanType: "pro",
                rateLimitPlanType: "prolite"
            ) == "PRO 100",
            "specific Pro Lite quota resolves an older generic Pro account"
        )
        expect(
            CodexDisplayPolicy.planBadgeLabel(
                accountPlanType: "pro",
                rateLimitPlanType: "pro"
            ) == "PRO 200",
            "Pro quota bucket displays the current subscription name"
        )
        expect(
            CodexDisplayPolicy.planBadgeLabel(
                accountPlanType: "pro",
                rateLimitPlanType: nil
            ) == "PRO 200",
            "the current Pro enum identifies Pro 200 without quota metadata"
        )
        expect(
            CodexDisplayPolicy.planBadgeLabel(
                accountPlanType: nil,
                rateLimitPlanType: " PROLITE "
            ) == "PRO 100",
            "quota bucket can supply plan while account data is unavailable"
        )
        expect(
            CodexDisplayPolicy.planBadgeLabel(
                accountPlanType: "plus",
                rateLimitPlanType: "prolite"
            ) == "PLUS",
            "account plan wins for non-Pro accounts"
        )
        expect(
            CodexDisplayPolicy.planBadgeLabel(
                accountPlanType: nil,
                rateLimitPlanType: nil
            ) == nil,
            "missing plan stays hidden"
        )
        for (account, quota, expectedPlan, expectedAllowance) in [
            ("plus", "plus", CodexSubscriptionPlan.plus, 2_000.0),
            ("pro", "prolite", .prolite, 10_000.0),
            ("prolite", "pro", .prolite, 10_000.0),
            ("pro", "pro", .pro, 20_000.0),
            ("pro", "", .pro, 20_000.0),
            (" PRO ", " PRO ", .pro, 20_000.0)
        ] {
            let plan = CodexDisplayPolicy.subscriptionPlan(
                accountPlanType: account, rateLimitPlanType: quota
            )
            expect(plan == expectedPlan, "account/quota precedence: \(account)/\(quota)")
            expect(CodexDisplayPolicy.remainingCredits(plan: plan, remainingPercent: 100) == expectedAllowance,
                   "resolved enum supplies its allowance independently of the badge: \(account)/\(quota)")
        }
        for (account, quota) in [("pro", "promax"), ("promax", "pro"), ("unknown", "promax")] {
            expect(CodexDisplayPolicy.subscriptionPlan(
                accountPlanType: account, rateLimitPlanType: quota
            ) == .promax, "Pro Max remains distinct from Pro: \(account)/\(quota)")
        }
        for rawValue in ["unknown", "future_plan", "", "  "] {
            expect(CodexDisplayPolicy.planBadgeLabel(
                accountPlanType: rawValue, rateLimitPlanType: nil
            ) == nil, "unrecognized plan does not expose an internal enum or invent a tier")
        }
        expect(CodexDisplayPolicy.subscriptionPlan(accountPlanType: "unknown", rateLimitPlanType: "plus") == .plus,
               "unknown account plan can fall back to recognized quota metadata")
        for plan in CodexSubscriptionPlan.allCases where ![.plus, .prolite, .pro].contains(plan) {
            expect(CodexDisplayPolicy.remainingCredits(plan: plan, remainingPercent: 100) == nil,
                   "no unconfirmed reference allowance for \(plan.rawValue)")
        }
        expect(CodexDisplayPolicy.remainingCredits(plan: nil, remainingPercent: 100) == nil,
               "missing plan cannot produce a credits estimate")
        expect(CodexDisplayPolicy.remainingCredits(plan: .pro, remainingPercent: -1) == 0,
               "negative remaining quota is clamped")
        expect(CodexDisplayPolicy.remainingCredits(plan: .pro, remainingPercent: 101) == 20_000,
               "remaining estimate cannot exceed the reference allowance")
        for percent in [Double.nan, .infinity, -.infinity] {
            expect(CodexDisplayPolicy.remainingCredits(plan: .pro, remainingPercent: percent) == nil,
                   "invalid quota does not produce a credits estimate")
        }
    }

    private static func checkLanguageResolution() {
        expect(
            IslandLanguagePreference.stored(nil) == .automatic,
            "missing language preference defaults to automatic"
        )
        expect(
            IslandLanguagePreference.stored("unsupported") == .automatic,
            "invalid stored language preference defaults to automatic"
        )
        expect(
            IslandLanguageResolver.resolve(
                preference: .automatic,
                preferredLanguages: ["zh-Hans-CN"]
            ) == .chinese,
            "automatic language selects Chinese for zh-Hans"
        )
        expect(
            IslandLanguageResolver.resolve(
                preference: .automatic,
                preferredLanguages: ["en-US"]
            ) == .english,
            "automatic language selects English for en-US"
        )
        expect(
            IslandLanguageResolver.resolve(
                preference: .automatic,
                preferredLanguages: ["ja-JP", "zh-Hans-CN"]
            ) == .english,
            "automatic language falls back to English when the primary OS language is unsupported"
        )
        expect(
            IslandLanguageResolver.resolve(
                preference: .chinese,
                preferredLanguages: ["en-US"]
            ) == .chinese,
            "manual Chinese overrides the OS language"
        )
        expect(
            IslandLanguageResolver.resolve(
                preference: .english,
                preferredLanguages: ["zh-Hans-CN"]
            ) == .english,
            "manual English overrides the OS language"
        )
    }

    private static func checkDisplayTargetResolution() {
        let builtIn = IslandDisplayDescriptor(
            identifier: "built-in-uuid",
            name: "Built-in Retina Display",
            isBuiltIn: true,
            sortIndex: 0
        )
        let externalLeft = IslandDisplayDescriptor(
            identifier: "external-left-uuid",
            name: "HP Z27s",
            isBuiltIn: false,
            sortIndex: 1
        )
        let externalRight = IslandDisplayDescriptor(
            identifier: "external-right-uuid",
            name: "HP Z27s",
            isBuiltIn: false,
            sortIndex: 2
        )
        let displays = [builtIn, externalLeft, externalRight]

        expect(
            IslandDisplayTargetPreference.stored(nil) == .automatic,
            "missing display preference defaults to automatic"
        )
        expect(
            IslandDisplayTargetPreference.stored("unsupported") == .automatic,
            "invalid display preference defaults to automatic"
        )
        expect(
            IslandDisplayTargetPreference.stored("external:external-left-uuid")
                == .external(identifier: "external-left-uuid"),
            "external display preference round-trips its stable identifier"
        )
        expect(
            IslandDisplayTargetPreference.builtIn.storedValue == "built-in",
            "built-in display preference has a stable persisted value"
        )
        expect(
            IslandDisplayTargetPreference
                .external(identifier: externalRight.identifier)
                .storedValue == "external:external-right-uuid",
            "external display preference persists the stable display identifier"
        )
        expect(
            IslandDisplaySelectionResolver.resolveIdentifier(
                preference: .automatic,
                displays: displays,
                automaticIdentifier: builtIn.identifier
            ) == builtIn.identifier,
            "automatic display selection preserves the existing resolver result"
        )
        expect(
            IslandDisplaySelectionResolver.resolveIdentifier(
                preference: .builtIn,
                displays: displays,
                automaticIdentifier: externalLeft.identifier
            ) == builtIn.identifier,
            "built-in preference overrides the automatic external display"
        )
        expect(
            IslandDisplaySelectionResolver.resolveIdentifier(
                preference: .external(identifier: externalRight.identifier),
                displays: displays,
                automaticIdentifier: builtIn.identifier
            ) == externalRight.identifier,
            "named external display resolves by stable identifier"
        )
        expect(
            IslandDisplaySelectionResolver.resolveIdentifier(
                preference: .external(identifier: externalRight.identifier),
                displays: [builtIn, externalLeft],
                automaticIdentifier: builtIn.identifier
            ) == builtIn.identifier,
            "disconnected external display temporarily falls back to automatic"
        )
        expect(
            IslandDisplaySelectionResolver.resolveIdentifier(
                preference: .external(identifier: externalRight.identifier),
                displays: displays,
                automaticIdentifier: builtIn.identifier
            ) == externalRight.identifier,
            "reconnected external display restores the saved target"
        )

        let choices = IslandDisplayChoiceBuilder.makeChoices(
            displays: displays,
            selection: .external(identifier: externalRight.identifier)
        )
        expect(
            choices.map(\.target) == [
                .automatic,
                .builtIn,
                .external(identifier: externalLeft.identifier),
                .external(identifier: externalRight.identifier)
            ],
            "display choices include automatic, built-in, and every external display"
        )
        expect(
            choices.compactMap(\.duplicateIndex) == [1, 2],
            "same-name external displays receive deterministic disambiguation indexes"
        )

        let disconnectedChoices = IslandDisplayChoiceBuilder.makeChoices(
            displays: [builtIn, externalLeft],
            selection: .external(identifier: externalRight.identifier)
        )
        expect(
            disconnectedChoices.last == IslandDisplayChoice(
                target: .external(identifier: externalRight.identifier),
                display: nil,
                duplicateIndex: nil,
                isAvailable: false
            ),
            "a disconnected saved display remains visible without losing the preference"
        )
    }

    private static func checkLegacyLaunchAgentCleanup() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("island-legacy-agents-\(UUID())")
        defer { try? fm.removeItem(at: root) }
        let directory = root.appendingPathComponent("LaunchAgents")
        let canonical = directory.appendingPathComponent("com.codexisland.app.login-item.plist")
        let legacy = directory.appendingPathComponent("legacy.codex-island.login-item.plist")
        let app = root.appendingPathComponent("Applications/Codex Island.app")
        let oldApp = root.appendingPathComponent("deleted build/Codex Island.app")
        let executable = app.appendingPathComponent("Contents/MacOS/Codex Island")
        // Construct before any plists exist: inventory must stay live afterward.
        let backend = LaunchAtLoginBackend.launchAgent(
            plistURL: canonical, appBundleURL: app,
            appExecutableURL: executable, bundleIdentifier: "com.codexisland.app"
        )
        func write(_ url: URL, label: String, arguments: [String], active: Bool = true) throws {
            try PropertyListSerialization.data(fromPropertyList: [
                "Label": label, "ProgramArguments": arguments, "RunAtLoad": active
            ], format: .xml, options: 0).write(to: url, options: .atomic)
        }
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            // Similar names or paths alone cannot establish ownership.
            let unrelated = [
                ("codex-island-helper.plist", "example.codex-island-helper", ["/usr/bin/true"]),
                ("other.plist", "example.other", ["/usr/bin/open", "-g", oldApp.path]),
                ("example.codex-island.plist", "example.codex-island", ["/usr/bin/open", "-g", "/Applications/Other.app"]),
                ("codex-island-wrapper.plist", "example.codex-island", ["/bin/sh", "-c", executable.path])
            ]
            for (name, label, args) in unrelated {
                try write(directory.appendingPathComponent(name), label: label, arguments: args)
            }
            var setting = LaunchAtLoginSettingModel(backend: backend)
            expect(setting.state == .disabled, "unrelated launch jobs never enable the login switch")
            for arguments in [
                ["/usr/bin/open", "-g", oldApp.path],
                [oldApp.appendingPathComponent("Contents/MacOS/Codex Island").path]
            ] {
                try write(legacy, label: "legacy.codex-island.login-item", arguments: arguments)
                expect(backend.readStatus() == .legacyRegistered,
                       "a renamed agent at a missing old installation is discovered after backend initialization")
                setting.refresh()
                expect(setting.state == .enabled && !fm.fileExists(atPath: legacy.path),
                       "refresh migrates renamed and relocated agents and removes the old plist")
                let plist = try? PropertyListSerialization.propertyList(
                    from: Data(contentsOf: canonical), options: [], format: nil
                ) as? JSONObject
                expect(plist?["ProgramArguments"] as? [String] == [executable.path],
                       "legacy migration targets the current executable")

                // Old and current agents may coexist after an older build runs.
                try write(legacy, label: "legacy.codex-island.login-item", arguments: arguments)
                expect(backend.readStatus() == .legacyRegistered,
                       "an enabled current agent does not hide a duplicate legacy registration")
                setting.setEnabled(true)
                expect(setting.state == .enabled && !fm.fileExists(atPath: legacy.path),
                       "enabling an already enabled setting still removes duplicate legacy jobs")
                try write(legacy, label: "legacy.codex-island.login-item", arguments: arguments)
                setting.setEnabled(false)
                expect(setting.state == .disabled && !fm.fileExists(atPath: canonical.path)
                       && !fm.fileExists(atPath: legacy.path),
                       "disable removes both current and relocated legacy registrations")

                try write(legacy, label: "legacy.codex-island.login-item", arguments: arguments, active: false)
                setting.refresh()
                expect(setting.state == .disabled && !fm.fileExists(atPath: canonical.path),
                       "refresh never enables an inactive legacy job")
                setting.setEnabled(false)
                expect(!fm.fileExists(atPath: legacy.path),
                       "explicit disable cleans inactive legacy jobs at old paths too")
            }
            let renamed = directory.appendingPathComponent("renamed-registration.plist")
            try write(renamed, label: "com.codexisland.app.login-item",
                      arguments: [oldApp.appendingPathComponent("Contents/MacOS/Codex Island").path])
            setting.refresh()
            expect(setting.state == .enabled && !fm.fileExists(atPath: renamed.path),
                   "the app-owned label identifies an agent even when its filename has changed")
            setting.setEnabled(false)
            for (name, _, _) in unrelated {
                expect(fm.fileExists(atPath: directory.appendingPathComponent(name).path),
                       "migration and disable preserve unrelated job \(name)")
            }
        } catch {
            expect(false, "legacy launch agent cleanup: \(error.localizedDescription)")
        }
    }

    private static func checkLaunchAtLoginSetting() {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("codex-island-launch-agent-\(UUID().uuidString)")
        let plistURL = directory
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent("com.codexisland.app.login-item.plist")
        let appBundleURL = URL(
            fileURLWithPath: "/Applications/Codex Island.app",
            isDirectory: true
        )
        let appExecutableURL = appBundleURL
            .appendingPathComponent("Contents/MacOS/Codex Island")
        let bundleIdentifier = "com.codexisland.app"
        defer { try? fileManager.removeItem(at: directory) }

        let productionBackend = LaunchAtLoginBackend.launchAgent(
            plistURL: plistURL,
            appBundleURL: appBundleURL,
            appExecutableURL: appExecutableURL,
            bundleIdentifier: bundleIdentifier,
            fileManager: fileManager
        )
        var productionSetting = LaunchAtLoginSettingModel(
            backend: productionBackend
        )
        expect(productionSetting.state == .disabled, "missing launch agent defaults off")
        expect(!fileManager.fileExists(atPath: plistURL.path), "initialization never creates launch agent")
        productionSetting.refresh()
        expect(!fileManager.fileExists(atPath: plistURL.path), "refresh never creates launch agent")

        productionSetting.setEnabled(true)
        expect(productionSetting.state == .enabled, "valid launch agent enables login launch")
        expect(fileManager.fileExists(atPath: plistURL.path), "enable writes the launch agent plist")

        do {
            let data = try Data(contentsOf: plistURL)
            let propertyList = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
            expect(
                propertyList?["Label"] as? String
                    == "\(bundleIdentifier).login-item",
                "launch agent uses the dedicated label"
            )
            expect(propertyList?["RunAtLoad"] as? Bool == true, "launch agent runs when loaded")
            expect(
                propertyList?["ProgramArguments"] as? [String]
                    == [appExecutableURL.path],
                "launch agent directly executes the branded app binary"
            )
            expect(
                propertyList?["AssociatedBundleIdentifiers"] as? [String]
                    == [bundleIdentifier],
                "launch agent is associated with the Codex Island bundle"
            )
            expect(propertyList?["KeepAlive"] == nil, "launch agent never keeps or relaunches the app")
            expect(
                !String(decoding: data, as: UTF8.self).contains("/usr/bin/open"),
                "launch agent never exposes the generic open executable"
            )

            let attributes = try fileManager.attributesOfItem(atPath: plistURL.path)
            expect(
                attributes[.posixPermissions] as? Int == 0o644,
                "launch agent plist has user-writable standard permissions"
            )

            let plutil = Process()
            plutil.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
            plutil.arguments = ["-lint", plistURL.path]
            plutil.standardOutput = FileHandle.nullDevice
            plutil.standardError = FileHandle.nullDevice
            try plutil.run()
            plutil.waitUntilExit()
            expect(plutil.terminationStatus == 0, "launch agent plist passes plutil lint")
        } catch {
            expect(false, "launch agent plist inspection: \(error.localizedDescription)")
        }

        productionSetting.setEnabled(true)
        expect(productionSetting.state == .enabled, "repeated enable remains idempotent")
        productionSetting.setEnabled(false)
        expect(productionSetting.state == .disabled, "disable removes login launch")
        expect(!fileManager.fileExists(atPath: plistURL.path), "disable removes only the launch agent plist")
        productionSetting.setEnabled(false)
        expect(productionSetting.state == .disabled, "repeated disable remains idempotent")

        do {
            let previousAppURL = directory.appendingPathComponent("dist/Codex Island.app")
            let previousExecutableURL = previousAppURL
                .appendingPathComponent("Contents/MacOS/Codex Island")
            for arguments in [
                [previousExecutableURL.path],
                ["/usr/bin/open", "-g", previousAppURL.path]
            ] {
                var oldRegistration: [String: Any] = [
                    "Label": "\(bundleIdentifier).login-item",
                    "ProgramArguments": arguments,
                    "RunAtLoad": true
                ]
                if arguments.count == 1 {
                    oldRegistration["AssociatedBundleIdentifiers"] = [bundleIdentifier]
                }
                let oldData = try PropertyListSerialization.data(
                    fromPropertyList: oldRegistration, format: .xml, options: 0
                )
                try oldData.write(to: plistURL, options: .atomic)
                expect(
                    productionBackend.readStatus() == .legacyRegistered,
                    "registration at a previous installation path is recognized"
                )
                let relocatedSetting = LaunchAtLoginSettingModel(backend: productionBackend)
                let relocated = try PropertyListSerialization.propertyList(
                    from: Data(contentsOf: plistURL), options: [], format: nil
                ) as? [String: Any]
                expect(
                    relocatedSetting.state == .enabled
                        && relocated?["ProgramArguments"] as? [String] == [appExecutableURL.path],
                    "moving the app migrates login launch to its current executable"
                )

                // The app may move after the setting model has been initialized.
                try oldData.write(to: plistURL, options: .atomic)
                productionSetting.setEnabled(false)
                expect(
                    productionSetting.state == .disabled
                        && !fileManager.fileExists(atPath: plistURL.path),
                    "explicit disable removes the registration at the old installation path"
                )
            }
            let inactiveData = try PropertyListSerialization.data(
                fromPropertyList: [
                    "Label": "\(bundleIdentifier).login-item",
                    "RunAtLoad": false
                ],
                format: .xml, options: 0
            )
            try inactiveData.write(to: plistURL, options: .atomic)
            productionSetting.setEnabled(false)
            expect(
                !fileManager.fileExists(atPath: plistURL.path),
                "explicit disable also cleans an inactive app launch agent"
            )
        } catch {
            expect(false, "relocated launch agent: \(error.localizedDescription)")
        }

        do {
            try fileManager.createDirectory(
                at: plistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let legacyData = try PropertyListSerialization.data(
                fromPropertyList: [
                    "Label": "\(bundleIdentifier).login-item",
                    "ProgramArguments": [
                        "/usr/bin/open",
                        "-g",
                        appBundleURL.path
                    ],
                    "RunAtLoad": true
                ],
                format: .xml,
                options: 0
            )
            try legacyData.write(to: plistURL, options: .atomic)

            let migratedSetting = LaunchAtLoginSettingModel(
                backend: productionBackend
            )
            expect(
                migratedSetting.state == .enabled,
                "legacy open registration migrates without disabling login launch"
            )

            let migratedData = try Data(contentsOf: plistURL)
            let migratedPropertyList = try PropertyListSerialization.propertyList(
                from: migratedData,
                options: [],
                format: nil
            ) as? [String: Any]
            expect(
                migratedPropertyList?["ProgramArguments"] as? [String]
                    == [appExecutableURL.path],
                "legacy registration is rewritten to the branded executable"
            )
            expect(
                migratedPropertyList?["AssociatedBundleIdentifiers"] as? [String]
                    == [bundleIdentifier],
                "legacy migration adds app attribution"
            )
        } catch {
            expect(false, "legacy launch agent migration: \(error.localizedDescription)")
        }

        var migratedSetting = LaunchAtLoginSettingModel(backend: productionBackend)
        migratedSetting.setEnabled(false)
        expect(!fileManager.fileExists(atPath: plistURL.path), "migrated registration remains removable")

        let previousPlistURL = plistURL.deletingLastPathComponent()
            .appendingPathComponent("legacy.codex-island.login-item.plist")
        do {
            let previousData = try PropertyListSerialization.data(
                fromPropertyList: [
                    "AssociatedBundleIdentifiers": ["legacy.codex-island"],
                    "Label": "legacy.codex-island.login-item",
                    "ProgramArguments": [appExecutableURL.path],
                    "RunAtLoad": true
                ],
                format: .xml,
                options: 0
            )
            try previousData.write(to: previousPlistURL, options: .atomic)

            let renamedBackend = LaunchAtLoginBackend.launchAgent(
                plistURL: plistURL,
                legacyPlistURLs: [previousPlistURL],
                appBundleURL: appBundleURL,
                appExecutableURL: appExecutableURL,
                bundleIdentifier: bundleIdentifier,
                fileManager: fileManager
            )
            let renamedSetting = LaunchAtLoginSettingModel(
                backend: renamedBackend
            )
            expect(
                renamedSetting.state == .enabled,
                "renamed bundle registration migrates without disabling login launch"
            )
            expect(
                fileManager.fileExists(atPath: plistURL.path),
                "renamed bundle migration writes the current launch agent"
            )
            expect(
                !fileManager.fileExists(atPath: previousPlistURL.path),
                "renamed bundle migration removes the previous launch agent"
            )

            var removableSetting = renamedSetting
            removableSetting.setEnabled(false)
            expect(
                !fileManager.fileExists(atPath: plistURL.path),
                "renamed bundle migration remains removable"
            )
        } catch {
            expect(false, "renamed launch agent migration: \(error.localizedDescription)")
        }

        let initialService = FakeLaunchAtLoginService(status: .notRegistered)
        var initialSetting = LaunchAtLoginSettingModel(
            backend: initialService.backend
        )
        expect(initialSetting.state == .disabled, "launch at login defaults off")
        expect(initialService.registerCallCount == 0, "initialization never registers login item")
        initialSetting.refresh()
        expect(initialService.registerCallCount == 0, "refresh never registers login item")

        let enabledService = FakeLaunchAtLoginService(status: .notRegistered)
        enabledService.statusAfterRegister = .enabled
        enabledService.statusAfterUnregister = .notRegistered
        var enabledSetting = LaunchAtLoginSettingModel(
            backend: enabledService.backend
        )
        enabledSetting.setEnabled(true)
        expect(enabledSetting.state == .enabled, "successful registration enables login item")
        expect(enabledService.registerCallCount == 1, "enable registers exactly once")
        enabledSetting.setEnabled(true)
        expect(enabledService.registerCallCount == 1, "already enabled login item is idempotent")
        enabledSetting.setEnabled(false)
        expect(enabledSetting.state == .disabled, "successful unregistration disables login item")
        expect(enabledService.unregisterCallCount == 1, "disable unregisters exactly once")
        enabledSetting.setEnabled(false)
        expect(enabledService.unregisterCallCount == 2, "explicit disable always requests idempotent cleanup")

        let failedEnableService = FakeLaunchAtLoginService(status: .notRegistered)
        failedEnableService.registerError = LaunchAtLoginTestError.operationFailed
        var failedEnableSetting = LaunchAtLoginSettingModel(
            backend: failedEnableService.backend
        )
        let readsBeforeEnable = failedEnableService.statusReadCount
        failedEnableSetting.setEnabled(true)
        expect(
            failedEnableSetting.state == .updateFailed(isEnabled: false),
            "failed registration preserves actual disabled state"
        )
        expect(
            failedEnableService.statusReadCount > readsBeforeEnable,
            "failed registration rereads system state"
        )

        let failedDisableService = FakeLaunchAtLoginService(status: .enabled)
        failedDisableService.unregisterError = LaunchAtLoginTestError.operationFailed
        var failedDisableSetting = LaunchAtLoginSettingModel(
            backend: failedDisableService.backend
        )
        failedDisableSetting.setEnabled(false)
        expect(
            failedDisableSetting.state == .updateFailed(isEnabled: true),
            "failed unregistration preserves actual enabled state"
        )

        let migrationService = FakeLaunchAtLoginService(status: .legacyRegistered)
        migrationService.statusAfterRegister = .enabled
        let migrationSetting = LaunchAtLoginSettingModel(
            backend: migrationService.backend
        )
        expect(migrationSetting.state == .enabled, "successful legacy migration stays enabled")
        expect(migrationService.registerCallCount == 1, "legacy migration rewrites exactly once")

        let failedMigrationService = FakeLaunchAtLoginService(status: .legacyRegistered)
        failedMigrationService.registerError = LaunchAtLoginTestError.operationFailed
        let failedMigrationSetting = LaunchAtLoginSettingModel(
            backend: failedMigrationService.backend
        )
        expect(
            failedMigrationSetting.state == .updateFailed(isEnabled: true),
            "failed legacy migration preserves the actual enabled state"
        )
        expect(
            failedMigrationService.statusReadCount >= 2,
            "failed legacy migration rereads disk-backed state"
        )
    }

    private static func checkTokenConsumptionPolicy() {
        expect(
            !CodexDisplayPolicy.shouldAnimateTokenConsumption(
                previous: nil,
                current: 100
            ),
            "initial token load does not animate"
        )
        expect(
            CodexDisplayPolicy.shouldAnimateTokenConsumption(
                previous: 100,
                current: 101
            ),
            "positive token growth animates"
        )
        expect(
            !CodexDisplayPolicy.shouldAnimateTokenConsumption(
                previous: 100,
                current: 100
            ),
            "unchanged token usage does not animate"
        )
        expect(
            !CodexDisplayPolicy.shouldAnimateTokenConsumption(
                previous: 100,
                current: 90
            ),
            "token reset does not animate"
        )
        expect(
            !CodexDisplayPolicy.shouldAnimateTokenConsumption(
                previous: 100,
                current: nil
            ),
            "missing token usage does not animate"
        )

        var highWater = CodexDisplayPolicy.updatedTokenConsumptionHighWater(
            previous: nil,
            current: 100
        )
        expect(highWater == 100, "initial token value establishes the high-water mark")
        highWater = CodexDisplayPolicy.updatedTokenConsumptionHighWater(
            previous: highWater,
            current: 90
        )
        expect(highWater == 100, "temporary token drop preserves the high-water mark")
        expect(
            !CodexDisplayPolicy.shouldAnimateTokenConsumption(
                previous: highWater,
                current: 100
            ),
            "recovering from a temporary drop does not animate"
        )
        expect(
            CodexDisplayPolicy.shouldAnimateTokenConsumption(
                previous: highWater,
                current: 101
            ),
            "surpassing the high-water mark animates"
        )
    }

    private static func checkQuotaConsumptionPace() {
        let lastReset = Date(timeIntervalSince1970: 2_000_000_000)
        let nextReset = lastReset.addingTimeInterval(100 * 60)
        let halfway = lastReset.addingTimeInterval(50 * 60)

        func assessment(usedPercent: Double) -> QuotaConsumptionPaceAssessment? {
            CodexDisplayPolicy.quotaConsumptionPace(
                window: RateLimitWindow(
                    usedPercent: usedPercent,
                    windowDurationMinutes: 100,
                    resetsAt: nextReset
                ),
                now: halfway
            )
        }

        expect(
            assessment(usedPercent: 40)?.pace == .slow,
            "pace is slow only when the projected unused capacity is meaningful"
        )
        expect(
            assessment(usedPercent: 50)?.pace == .normal,
            "quota use close to the elapsed cycle is normal"
        )
        expect(
            assessment(usedPercent: 57.5)?.pace == .normal,
            "ample remaining capacity does not warn for a modestly fast pace"
        )
        expect(
            assessment(usedPercent: 70)?.pace == .warning,
            "low remaining capacity with insufficient runway warns"
        )
        expect(
            assessment(usedPercent: 85)?.pace == .critical,
            "very low remaining capacity with insufficient runway is critical"
        )
        expect(
            assessment(usedPercent: 57.5)?.elapsedPercent == 50,
            "pace assessment derives the last reset from duration and next reset"
        )
        expect(
            abs(
                (assessment(usedPercent: 57.5)?.relativeDifferencePercent ?? 0)
                    - 15
            ) < 0.000_001,
            "pace assessment reports the difference relative to expected use"
        )
        let shortlyAfterReset = lastReset.addingTimeInterval(1 * 60)
        expect(
            CodexDisplayPolicy.quotaConsumptionPace(
                window: RateLimitWindow(
                    usedPercent: 6,
                    windowDurationMinutes: 100,
                    resetsAt: nextReset
                ),
                now: shortlyAfterReset
            )?.pace == .normal,
            "a fresh-cycle burst stays normal while 94 percent remains"
        )
        let nearReset = lastReset.addingTimeInterval(95 * 60)
        expect(
            CodexDisplayPolicy.quotaConsumptionPace(
                window: RateLimitWindow(
                    usedPercent: 90,
                    windowDurationMinutes: 100,
                    resetsAt: nextReset
                ),
                now: nearReset
            )?.pace == .normal,
            "low capacity is not urgent when projected runway reaches reset"
        )
        expect(
            CodexDisplayPolicy.quotaConsumptionPace(
                window: RateLimitWindow(
                    usedPercent: 50,
                    windowDurationMinutes: nil,
                    resetsAt: nextReset
                ),
                now: halfway
            ) == nil,
            "pace hint stays hidden when the reset window duration is unavailable"
        )
        expect(
            CodexDisplayPolicy.quotaConsumptionPace(
                window: RateLimitWindow(
                    usedPercent: 50,
                    windowDurationMinutes: 100,
                    resetsAt: nextReset
                ),
                now: nextReset
            ) == nil,
            "stale quota windows do not show a pace hint"
        )
    }

    private static func checkQuotaRemainingLevels() {
        expect(
            CodexDisplayPolicy.quotaRemainingLevel(for: 30.01) == .healthy,
            "remaining quota above 30 percent stays green"
        )
        expect(
            CodexDisplayPolicy.quotaRemainingLevel(for: 30) == .warning,
            "30 percent remaining is yellow"
        )
        expect(
            CodexDisplayPolicy.quotaRemainingLevel(for: 10.01) == .warning,
            "remaining quota above 10 percent stays yellow"
        )
        expect(
            CodexDisplayPolicy.quotaRemainingLevel(for: 10) == .critical,
            "10 percent remaining is red"
        )
    }

    private static func checkCreditRateCard() {
        // The official example has 20K uncached + 80K cached + 5K output.
        // Rollouts express the first two together as input_tokens = 100K.
        let credits = CodexCreditRateCard.credits(
            model: "gpt-5.5", serviceTier: "default",
            inputTokens: 100_000, cachedInputTokens: 80_000, outputTokens: 5_000
        )
        expect(credits == 7.25, "official credit example excludes cached input from the full input rate")
        expect(
            CodexCreditRateCard.credits(
                model: "gpt-5.5", serviceTier: "priority",
                inputTokens: 100_000, cachedInputTokens: 80_000, outputTokens: 5_000
            ) == 18.125,
            "Fast multiplies all three token rates"
        )
        expect(CodexCreditRateCard.rate(for: "openai/gpt-6-astra-2026-09-01")?.input == 250,
               "dated model IDs resolve the exact documented model")
        expect(CodexCreditRateCard.rate(for: "gpt-5.3-codex-spark") == nil,
               "Spark is never assigned the Codex rate or shared quota")
        expect(CodexCreditRateCard.rate(for: "gpt-5.4-mini")?.input == 18.75,
               "mini uses its own documented rate")
        expect(CodexCreditRateCard.rate(for: "gpt-6-astra-unknown") == nil,
               "undocumented variants stay unpriced")
        for (model, rate) in [
            ("gpt-6.1-sol", CodexCreditRateCard.Rate(input: 50, cachedInput: 2.5, output: 250)),
            ("gpt-6.1-terra", CodexCreditRateCard.Rate(input: 25, cachedInput: 1.25, output: 125)),
            ("gpt-6-sol", CodexCreditRateCard.Rate(input: 50, cachedInput: 5, output: 250)),
            ("gpt-6-luna", CodexCreditRateCard.Rate(input: 2.5, cachedInput: 0.25, output: 12.5))
        ] {
            expect(CodexCreditRateCard.rate(for: model) == rate,
                   "\(model) uses its own official input, cache, and output rates")
            expect(CodexCreditRateCard.rate(for: " openai/\(model.uppercased())-2026-09-30 ") == rate,
                   "\(model) rates resolve provider-prefixed dated snapshots")
            expect(CodexCreditRateCard.rate(for: "\(model)-unknown") == nil,
                   "\(model) rates do not price undocumented variants")
        }
        for tier in ["default", "standard", "fast", "priority"] {
            expect(CodexCreditRateCard.credits(
                model: "gpt-6.1-terra", serviceTier: tier,
                inputTokens: 100_000, cachedInputTokens: 80_000, outputTokens: 5_000
            ).map { abs($0 - (tier == "fast" || tier == "priority" ? 3.0625 : 1.225)) < 0.000001 } == true,
                   "GPT-6.1 Terra charges half the Sol rate and applies the subscription Fast multiplier for \(tier)")
            expect(CodexCreditRateCard.credits(
                model: "gpt-6.1-sol", serviceTier: tier,
                inputTokens: 100_000, cachedInputTokens: 80_000, outputTokens: 5_000
            ).map { abs($0 - (tier == "fast" || tier == "priority" ? 6.125 : 2.45)) < 0.000001 } == true,
                   "GPT-6.1 Sol prices cached input separately and applies the subscription Fast multiplier for \(tier)")
        }
        expect(CodexCreditRateCard.rate(for: "gpt-6.1") == nil
               && CodexCreditRateCard.rate(for: "gpt-6.1-sol-mini") == nil
               && CodexCreditRateCard.rate(for: "gpt-6.1-terra-mini") == nil,
               "GPT-6.1 support does not guess prices for undocumented models")
        expect(CodexCreditRateCard.credits(
            model: "gpt-6.1-terra", serviceTier: "ultrafast",
            inputTokens: 100_000, cachedInputTokens: 80_000, outputTokens: 5_000
        ) == nil, "Terra does not support Ultrafast pricing")
        expect(CodexCreditRateCard.credits(
            model: "gpt-6.1-sol", serviceTier: "ultrafast",
            inputTokens: 100_000, cachedInputTokens: 80_000, outputTokens: 5_000
        ) == nil, "GPT-6.1 Sol does not inherit Astra's unsupported Ultrafast pricing")
        expect(CodexCreditRateCard.credits(
            model: "gpt-5.5", serviceTier: "default",
            inputTokens: 100, cachedInputTokens: 101, outputTokens: 0
        ) == nil, "invalid cache counts cannot become negative credit cost")
    }

    private static func checkCreditUsageRollouts() {
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = now.addingTimeInterval(-3_600)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-island-priced-usage-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: directory)
            CodexDailyTokenUsageReader.resetCacheForTesting()
        }
        func line(_ type: String, _ payload: JSONObject, _ date: Date = start) throws -> String {
            let object: JSONObject = [
                "type": type, "timestamp": formatter.string(from: date), "payload": payload
            ]
            return String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
        }
        func token(total: Int64, last: Int64, at date: Date) throws -> String {
            let lastUsage: JSONObject = [
                "total_tokens": last,
                "input_tokens": last * 9 / 10,
                "cached_input_tokens": last * 8 / 10,
                "output_tokens": last / 10,
                "reasoning_output_tokens": last / 20
            ]
            return try line("event_msg", [
                "type": "token_count",
                "info": [
                    "total_token_usage": ["total_tokens": total],
                    "last_token_usage": lastUsage
                ]
            ], date)
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let meta = try line("session_meta", ["source": "cli", "model_provider": "openai"])
            let settings = try line("turn_context", ["model": "gpt-5.6-sol", "service_tier": "default"])
            var lines = [[meta, settings], [meta, settings]]
            var totals: [Int64] = [0, 0]
            for index in 0...12 {
                let slot = index % 2
                let delta: Int64 = index == 0 ? 0 : 1_000_000
                totals[slot] += delta
                let event = try token(total: totals[slot], last: delta,
                                      at: start.addingTimeInterval(Double(index * 60)))
                lines[slot].append(contentsOf: [event, event])
            }
            let urls = (0...1).map { directory.appendingPathComponent("usage-\($0).jsonl") }
            for index in 0...1 {
                try Data((lines[index].joined(separator: "\n") + "\n").utf8).write(to: urls[index])
            }
            CodexDailyTokenUsageReader.resetCacheForTesting()
            let usage = try CodexDailyTokenUsageReader.readRecentHours(
                from: urls.map(\.path), now: now, calendar: calendar
            )
            expect(abs(usage.chartCreditTotals.values.reduce(0) { $0 + $1.credits } - 816) < 0.000001,
                   "chart credits sum concurrent calls without charging duplicate notifications")
            expect(usage.chartCreditTotals.values.allSatisfy { $0.unpricedCalls == 0 },
                   "complete token breakdowns produce fully priced chart buckets")

            let customURL = directory.appendingPathComponent("custom-provider.jsonl")
            let customMeta = try line("session_meta", ["source": "cli", "model_provider": "custom"])
            let customCall = try token(total: 100_000_000, last: 100_000_000,
                                       at: start.addingTimeInterval(800))
            try Data(([customMeta, settings, customCall].joined(separator: "\n") + "\n").utf8).write(to: customURL)
            let customUsage = try CodexDailyTokenUsageReader.readRecentHours(
                from: urls.map(\.path) + [customURL.path], now: now.addingTimeInterval(31),
                calendar: calendar
            )
            expect(abs(customUsage.chartCreditTotals.values.reduce(0) { $0 + $1.credits } - 816) < 0.000001,
                   "third-party providers do not add invented ChatGPT credit costs")
            expect(customUsage.chartCreditTotals.values.reduce(0) { $0 + $1.unpricedCalls } == 1,
                   "third-party usage is marked unpriced without losing the known credit subtotal")

            lines[0].append(try line("turn_context", ["model": "gpt-5.6-sol", "service_tier": "priority"], start.addingTimeInterval(900)))
            totals[0] += 1_000_000
            lines[0].append(try token(total: totals[0], last: 1_000_000, at: start.addingTimeInterval(901)))
            lines[0].append(try line("turn_context", ["model": "gpt-5.6-sol", "service_tier": NSNull()], start.addingTimeInterval(960)))
            totals[0] += 1_000_000
            lines[0].append(try token(total: totals[0], last: 1_000_000, at: start.addingTimeInterval(961)))
            let handle = try FileHandle(forWritingTo: urls[0])
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((lines[0].suffix(4).joined(separator: "\n") + "\n").utf8))
            try handle.close()
            let resumed = try CodexDailyTokenUsageReader.readRecentHours(
                from: urls.map(\.path), now: now.addingTimeInterval(32), calendar: calendar
            )
            expect(resumed.dailyBuckets.reduce(Int64(0)) { $0 + $1.tokens } == 14_000_000,
                   "switching Fast off keeps actual tokens unweighted")
            expect(abs(resumed.chartCreditTotals.values.reduce(0) { $0 + $1.credits } - 1054) < 0.000001,
                   "incremental chart credits retain Standard calls and apply Fast only to new calls")
            expect(abs(resumed.chartCreditTotals.values.reduce(0) { $0 + $1.standardCredits } - 952) < 0.000001,
                   "credit chart Standard prices every call without its Fast multiplier")
            expect(abs(resumed.chartCreditTotals.values.reduce(0) { $0 + $1.wastedCredits } - 102) < 0.000001,
                   "credit chart Wasted includes only the extra Fast cost")
            let apiUsage = try CodexDailyTokenUsageReader.readRecentHours(
                from: urls.map(\.path), now: now.addingTimeInterval(33), calendar: calendar,
                usesChatGPTCredits: false
            )
            expect(apiUsage.chartCreditTotals.values.contains { $0.unpricedCalls > 0 },
                   "non-ChatGPT chart usage cannot silently display zero credits")
            let historyURL = directory.appendingPathComponent("chart-history.jsonl")
            let old = start.addingTimeInterval(-10 * 86_400)
            let oldSettings = try line("turn_context", ["model": "gpt-5.6-sol", "service_tier": "default"], old)
            let first = try token(total: 1_000_000, last: 1_000_000, at: old)
            let newSettings = try line("turn_context", ["model": "gpt-6-astra", "service_tier": "priority"])
            let second = try token(total: 2_000_000, last: 1_000_000, at: start)
            let oldMeta = try line("session_meta", ["source": "cli", "model_provider": "openai"], old)
            try Data(([oldMeta, oldSettings, first, newSettings, second].joined(separator: "\n") + "\n").utf8).write(to: historyURL)
            let history = try CodexDailyTokenUsageReader.readRecentHours(
                from: [historyURL.path], now: now, calendar: calendar
            )
            let oldHour = calendar.dateInterval(of: .hour, for: old)!.start
            let newHour = calendar.dateInterval(of: .hour, for: start)!.start
            expect(history.chartCreditTotals[oldHour]?.credits == 68,
                   "30-day chart retains historical priced calls")
            expect(history.chartCreditTotals[newHour]?.standardCredits == 170
                   && history.chartCreditTotals[newHour]?.wastedCredits == 255,
                   "Astra Fast splits into Standard 170 plus extra 255 credits")
            expect(history.chartCreditTotals[newHour]?.credits == 425,
                   "switching models in one rollout prices each hour with its recorded model")
            expect(history.chartCreditTotals[newHour]?.displayText(matching: 1_000_001) == "425.0 credits",
                   "historical credits use local logs even when account history includes another computer")

            let gpt6URL = directory.appendingPathComponent("gpt6-sol-luna-gpt61-sol.jsonl")
            var gpt6Lines = [meta]
            let calls = [
                ("gpt-6-sol", "default"), ("gpt-6-sol", "priority"),
                ("openai/gpt-6-luna-2026-09-23", "fast"), ("gpt-6-luna", "standard"),
                ("gpt-6.1-sol", "default"), ("openai/gpt-6.1-sol-2026-09-30", "fast"),
                ("gpt-6.1-terra", "standard"), ("openai/gpt-6.1-terra-2026-10-27", "priority")
            ]
            for (index, call) in calls.enumerated() {
                let date = start.addingTimeInterval(Double(index * 60))
                gpt6Lines.append(try line("turn_context", ["model": call.0, "service_tier": call.1], date))
                gpt6Lines.append(try token(total: Int64(index + 1) * 1_000_000, last: 1_000_000,
                                          at: date.addingTimeInterval(1)))
            }
            try Data((gpt6Lines.joined(separator: "\n") + "\n").utf8).write(to: gpt6URL)
            let gpt6Usage = try CodexDailyTokenUsageReader.readRecentHours(
                from: [gpt6URL.path], now: now, calendar: calendar
            )
            // Each call has 100K uncached input, 800K cache, and 100K output:
            // Sol costs 34 / 85 credits; Luna costs 1.7 / 4.25 (Standard / Fast).
            // GPT-6.1 Sol costs 32 / 80 because cached input is half the Sol rate.
            // GPT-6.1 Terra costs 16 / 40, half the GPT-6.1 Sol rates.
            expect(abs(gpt6Usage.chartCreditTotals.values.reduce(0) { $0 + $1.credits } - 292.95) < 0.000001
                   && abs(gpt6Usage.chartCreditTotals.values.reduce(0) { $0 + $1.standardCredits } - 167.4) < 0.000001,
                   "Sol, Luna, and GPT-6.1 Sol/Terra chart credits price each call using its own model and Fast setting")
            expect(abs(gpt6Usage.chartCreditTotals.values.reduce(0) { $0 + $1.wastedCredits } - 125.55) < 0.000001,
                   "mixed model chart overhead includes the GPT-6.1 Sol/Terra Fast surcharge")
            expect(gpt6Usage.chartCreditTotals.values.allSatisfy { $0.unpricedCalls == 0 },
                   "Sol, Luna, and GPT-6.1 Sol/Terra calls leave no gaps in chart credit coverage")
            expect(gpt6Usage.hourlyBuckets.reduce(Int64(0)) { $0 + $1.tokens } == 8_000_000
                   && gpt6Usage.dailyBuckets.reduce(Int64(0)) { $0 + $1.tokens } == 8_000_000,
                   "Fast usage leaves actual hourly and daily tokens unchanged across models")

        } catch {
            expect(false, "priced rollout credits: \(error.localizedDescription)")
        }
        checkLargeDailyUsageSettings()
    }

    private static func checkLargeDailyUsageSettings() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date()
        let timestamp = now.addingTimeInterval(-60)
        let formatter = ISO8601DateFormatter()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-island-large-usage-settings-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: directory)
            CodexDailyTokenUsageReader.resetCacheForTesting()
        }
        func line(_ type: String, _ payload: JSONObject, at date: Date = timestamp) throws -> String {
            // Deliberately put type after payload: field order is not part of JSON's contract.
            let body = String(decoding: try JSONSerialization.data(withJSONObject: payload, options: .sortedKeys), as: UTF8.self)
            return "{\"payload\":\(body),\"timestamp\":\"\(formatter.string(from: date))\",\"type\":\"\(type)\"}\n"
        }
        let instructions = String(repeating: "Follow project rules; quoted \\\"type\\\":\\\"turn_context\\\" is prose. ", count: 2_000)
        func settings(_ model: String, provider: String = "openai", tier: Any = "default", large: Bool = false, at date: Date = timestamp) throws -> String {
            try line("event_msg", ["type": "thread_settings_applied", "thread_settings": [
                "model": model, "model_provider_id": provider, "service_tier": tier,
                "collaboration_mode": ["mode": "default", "settings": ["model": model, "developer_instructions": large ? instructions : ""]]
            ]], at: date)
        }
        func token(_ total: Int64, at date: Date = timestamp) throws -> String {
            try line("event_msg", ["type": "token_count", "info": [
                "total_token_usage": ["total_tokens": total * 1_000_000],
                "last_token_usage": ["total_tokens": 1_000_000, "input_tokens": 900_000,
                                     "cached_input_tokens": 800_000, "output_tokens": 100_000]
            ]], at: date)
        }
        func append(_ text: String, to url: URL) throws {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
        }
        func read(_ url: URL) throws -> LocalTokenUsageSnapshot {
            try CodexDailyTokenUsageReader.readRecentHours(from: [url.path], now: now, calendar: calendar)
        }
        func expectCost(_ snapshot: LocalTokenUsageSnapshot, _ credits: Double, unpriced: Int, _ message: String) {
            expect(abs(snapshot.chartCreditTotals.values.reduce(0) { $0 + $1.credits } - credits) < 0.000001
                   && snapshot.chartCreditTotals.values.reduce(0) { $0 + $1.unpricedCalls } == unpriced, message)
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("large-settings.jsonl")
            let meta = try line("session_meta", ["source": "cli", "model_provider": "openai"])
            try Data((meta + settings("gpt-6-luna") + token(1)).utf8).write(to: url)
            expectCost(try read(url), 1.7, unpriced: 0, "large-settings fixture starts at Luna pricing")
            let context = try line("turn_context", ["model": "gpt-6-astra", "service_tier": "priority",
                "collaboration_mode": ["mode": "default", "settings": ["model": "gpt-6-astra", "developer_instructions": instructions]]])
            expect(context.utf8.count > 64 * 1024, "large turn context exceeds the normal line buffer")
            try append(String(context.dropLast()), to: url)
            expectCost(try read(url), 1.7, unpriced: 0, "uncommitted large settings do not change pricing")
            try append("\n" + token(2), to: url)
            expectCost(try read(url), 426.7, unpriced: 0, "appended large turn context switches model and Fast pricing")
            try append(settings("gpt-6-astra", provider: "custom", large: true) + token(3)
                       + settings("gpt-6-sol", tier: NSNull(), large: true) + token(4), to: url)
            expectCost(try read(url), 460.7, unpriced: 1, "large settings preserve provider changes and explicit Standard resets")
            CodexDailyTokenUsageReader.resetCacheForTesting()
            expectCost(try read(url), 460.7, unpriced: 1, "cold scans match incrementally applied large settings")

            // A large unrelated record may mention settings in its text. It must
            // remain skipped rather than being decoded or interpreted as settings.
            let image = "{\"payload\":{\"type\":\"message\",\"text\":\"turn_context thread_settings_applied\",\"image\":\""
                + String(repeating: "x", count: 16 * 1024 * 1024) + "\"},\"type\":\"response_item\"}\n"
            try append(image, to: url)
            let started = Date()
            expectCost(try read(url), 460.7, unpriced: 1, "large image content cannot impersonate a settings record")
            CodexDailyTokenUsageReader.resetCacheForTesting()
            expectCost(try read(url), 460.7, unpriced: 1, "cold daily scans skip a payload-first image without changing its surrounding prices")
            let imageElapsed = Date().timeIntervalSince(started)
            print(String(format: "Daily usage payload-first 16 MB image cold and incremental scan: %.2f s", imageElapsed))
            expect(imageElapsed < 10, "skipping a payload-first 16 MB image remains bounded and fast")

            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
            try append(settings("gpt-6-luna", large: true, at: tomorrow) + token(5, at: tomorrow), to: url)
            let rolled = try CodexDailyTokenUsageReader.readRecentHours(
                from: [url.path], now: tomorrow, calendar: calendar
            )
            expectCost(rolled, 462.4, unpriced: 1, "large configuration changes retain correct pricing as the cached day rolls forward")
            expect(rolled.todayTokens == 1_000_000, "day rollover keeps the new call separate from yesterday's tokens")
            CodexDailyTokenUsageReader.resetCacheForTesting()
            let rolledCold = try CodexDailyTokenUsageReader.readRecentHours(
                from: [url.path], now: tomorrow, calendar: calendar
            )
            expect(rolled == rolledCold, "cold and warm oversized-setting scans agree after midnight")

            let historyURL = directory.appendingPathComponent("large-settings-baseline.jsonl")
            let old = calendar.date(byAdding: .day, value: -35, to: timestamp)!
            let beforeRange = calendar.date(byAdding: .day, value: -31, to: timestamp)!
            let oldMeta = try line("session_meta", ["source": "cli", "model_provider": "openai"], at: old)
            try Data((oldMeta + settings("gpt-6-luna", at: old) + token(1, at: old)
                      + settings("gpt-6-astra", tier: "priority", large: true, at: beforeRange)
                      + token(2, at: beforeRange) + token(3)).utf8).write(to: historyURL)
            expectCost(try read(historyURL), 425, unpriced: 0, "backward baseline search retains large settings before the 30-day boundary")
        } catch {
            expect(false, "large daily usage settings: \(error.localizedDescription)")
        }
    }

    private static func checkFastModeUsageMultipliers() {
        expect(
            CodexFastModeUsagePolicy.multiplier(for: "gpt-5.4") == 2.0,
            "GPT-5.4 Fast usage counts as 2x Standard-mode quota"
        )
        expect(
            CodexFastModeUsagePolicy.multiplier(for: " openai/GPT-5.4-codex ") == 2.0,
            "GPT-5.4 family matching handles provider prefixes, suffixes, and case"
        )
        expect(
            CodexFastModeUsagePolicy.multiplier(for: "gpt-5.5") == 2.5,
            "GPT-5.5 Fast usage counts as 2.5x Standard-mode quota"
        )
        expect(
            CodexFastModeUsagePolicy.multiplier(for: "gpt-5.6-sol") == 2.5,
            "GPT-5.6 variants count as 2.5x Standard-mode quota"
        )
        expect(
            CodexFastModeUsagePolicy.multiplier(for: "gpt-6-astra") == 2.5,
            "GPT-6 Astra Fast usage counts as 2.5x Standard-mode quota"
        )
        expect(
            CodexFastModeUsagePolicy.multiplier(for: " openai/GPT-6-ASTRA ") == 2.5,
            "GPT-6 Astra matching handles provider prefixes, whitespace, and case"
        )
        for model in ["gpt-6.1-sol", "gpt-6.1-terra", "gpt-6-sol", "gpt-6-luna"] {
            expect(CodexFastModeUsagePolicy.multiplier(for: model) == 2.5,
                   "\(model) Fast usage counts as 2.5x Standard-mode quota")
            expect(CodexFastModeUsagePolicy.multiplier(for: " openai/\(model.uppercased())-2026-09-30 ") == 2.5,
                   "\(model) Fast matching handles provider prefixes, case, whitespace, and dated snapshots")
            expect(CodexFastModeUsagePolicy.multiplier(for: "\(model)2") == nil,
                   "\(model) Fast support does not match unrelated names")
        }
        expect(
            CodexFastModeUsagePolicy.multiplier(for: "gpt-6-astra2") == nil,
            "Astra support does not match unrelated model names"
        )
        expect(
            CodexFastModeUsagePolicy.multiplier(for: "gpt-6-future") == nil,
            "Astra support does not assign a multiplier to every GPT-6 model"
        )
        expect(
            CodexFastModeUsagePolicy.multiplier(for: "future-model") == nil,
            "models outside the official Fast support list are not guessed"
        )
        expect(
            CodexFastModeUsagePolicy.multiplier(for: nil) == nil,
            "missing models are not assigned a guessed multiplier"
        )
    }

    private static func checkDisplayModelNames() {
        expect(
            CodexDisplayPolicy.displayModelName("openai/gpt-5.6-sol") == "5.6-Sol",
            "model display removes provider and GPT prefixes"
        )
        expect(
            CodexDisplayPolicy.displayModelName("GPT-5.5") == "5.5",
            "model display removes the GPT prefix case-insensitively"
        )
        expect(
            CodexDisplayPolicy.displayModelName("o3") == "O3",
            "non-GPT model names preserve their compact family name"
        )
        expect(
            CodexDisplayPolicy.displayModelName(" gpt ") == "gpt",
            "a bare GPT family name remains non-empty after trimming"
        )
    }

    private static func checkReasoningEffortLabels() {
        expect(
            CodexDisplayPolicy.reasoningEffortLabel("low") == "low",
            "low reasoning uses the lowercase low label"
        )
        expect(
            CodexDisplayPolicy.reasoningEffortLabel("minimal") == "low",
            "legacy minimal reasoning is folded into low"
        )
        expect(
            CodexDisplayPolicy.reasoningEffortLabel("medium") == "medium",
            "medium reasoning keeps its full label"
        )
        expect(
            CodexDisplayPolicy.reasoningEffortLabel("high") == "high",
            "high reasoning keeps its full label"
        )
        expect(
            CodexDisplayPolicy.reasoningEffortLabel("extra high") == "xhigh",
            "Extra High is the only abbreviated effort label"
        )
        expect(
            CodexDisplayPolicy.reasoningEffortLabel("xhigh") == "xhigh",
            "the runtime xhigh value uses the Codex App spelling"
        )
        expect(
            CodexDisplayPolicy.reasoningEffortLabel("max") == "max",
            "max reasoning keeps its full label"
        )
        expect(
            CodexDisplayPolicy.reasoningEffortLabel("ultra") == "ultra",
            "ultra reasoning keeps its full label"
        )
    }

    private static func checkHeaderTokenCounts() {
        expect(
            CodexDisplayPolicy.headerTokenCount(51_850) == "51.9K",
            "expanded header keeps one decimal for two-digit thousands"
        )
        expect(
            CodexDisplayPolicy.headerTokenCount(123_456) == "123K",
            "expanded header omits decimals for three-digit thousands"
        )
        expect(
            CodexDisplayPolicy.headerTokenCount(14_123_000_000) == "14.1B",
            "expanded header keeps one decimal for two-digit billions"
        )
        expect(
            CodexDisplayPolicy.headerTokenCount(123_456_789) == "123M",
            "expanded header omits decimals for three-digit millions"
        )
        expect(
            CodexDisplayPolicy.headerTokenCount(987_654_321_000) == "988B",
            "expanded header omits decimals for three-digit billions"
        )
        expect(
            CodexDisplayPolicy.headerTokenCount(123_456_789_012_345) == "123T",
            "expanded header omits decimals for three-digit trillions"
        )
        expect(
            CodexDisplayPolicy.headerTokenCount(99_960_000) == "100M",
            "expanded header avoids rendering a rounded three-digit million with a decimal"
        )
        expect(
            CodexDisplayPolicy.headerTokenCount(999_500_000) == "1.0B",
            "expanded header promotes three-digit millions that round into billions"
        )
        expect(
            CodexDisplayPolicy.headerTokenCount(999_950) == "1.0M",
            "expanded header promotes values that round into the next unit"
        )
        expect(
            CodexDisplayPolicy.headerTokenCount(999) == "999",
            "expanded header keeps unscaled values exact"
        )
    }

    private static func checkThreadDeepLinks() {
        let threadID = "019f1234-5678-7abc-8def-0123456789ab"
        expect(
            CodexLauncher.settingsURL?.absoluteString == "codex://settings",
            "settings deep link uses Codex's canonical route"
        )
        expect(
            CodexLauncher.threadURL(threadID: threadID)?.absoluteString
                == "codex://threads/\(threadID)",
            "thread deep link uses Codex's canonical local-task route"
        )
        expect(
            CodexLauncher.threadURL(threadID: "  \n") == nil,
            "blank thread IDs do not produce deep links"
        )
        expect(
            CodexLauncher.threadURL(threadID: "fallback-0123456789abcdef") == nil,
            "synthetic UI identities do not produce invalid Codex deep links"
        )
    }

    private static func checkRateLimitsAndResetCredits() {
        let result: JSONObject = [
            "rateLimits": [
                "primary": [
                    "usedPercent": 24.5,
                    "windowDurationMins": 300,
                    "resetsAt": 2_000_000_000
                ],
                "secondary": [
                    "usedPercent": 41,
                    "windowDurationMins": 10_080,
                    "resetsAt": 2_000_100_000
                ]
            ],
            "rateLimitResetCredits": [
                "availableCount": 3,
                "credits": [
                    [
                        "status": "available",
                        "expiresAt": 2_000_200_000
                    ],
                    [
                        "status": "available",
                        "expiresAt": 2_000_150_000
                    ],
                    [
                        "status": "used",
                        "expiresAt": 2_000_100_000
                    ]
                ]
            ]
        ]

        let parsed = CodexStatusPayloadParser.parseRateLimits(result)
        expect(parsed.bucket?.primary?.usedPercent == 24.5, "primary used percent")
        expect(parsed.bucket?.primary?.remainingPercent == 75.5, "primary remaining percent")
        expect(parsed.bucket?.secondary?.windowDurationMinutes == 10_080, "secondary window")
        expect(parsed.resetCredits?.availableCount == 3, "authoritative reset count")
        expect(
            parsed.resetCredits?.earliestExpiration?.timeIntervalSince1970 == 2_000_150_000,
            "earliest reset expiration"
        )
        expect(
            parsed.resetCredits?.expirationDates.map(\.timeIntervalSince1970)
                == [2_000_150_000, 2_000_200_000],
            "available reset expirations are filtered and sorted"
        )

        let legacyCredits = CodexStatusPayloadParser.parseRateLimits([
            "rateLimitResetCredits": [
                "credits": [
                    ["status": " AVAILABLE ", "expiresAt": 2_000_300_000],
                    ["status": "used", "expiresAt": 2_000_100_000],
                    ["expiresAt": 2_000_250_000],
                    ["status": "available"],
                    ["status": "unknown", "expiresAt": 2_000_050_000]
                ]
            ]
        ]).resetCredits
        expect(legacyCredits?.availableCount == 3, "legacy reset count includes only available rows")
        expect(
            legacyCredits?.expirationDates.map(\.timeIntervalSince1970)
                == [2_000_250_000, 2_000_300_000],
            "reset parser normalizes status and retains rows with missing expiry"
        )

        let invalidCount = CodexStatusPayloadParser.parseRateLimits([
            "rateLimitResetCredits": ["availableCount": -4, "credits": []]
        ]).resetCredits
        expect(invalidCount?.availableCount == 0, "negative reset count is clamped to zero")
    }

    private static func checkResetCreditExpiryWarning() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let week = CodexDisplayPolicy.resetCreditExpiryWarningInterval

        func summary(
            availableCount: Int = 1,
            expirations: [TimeInterval]
        ) -> ResetCreditSummary {
            ResetCreditSummary(
                availableCount: availableCount,
                earliestExpiration: expirations.min().map {
                    Date(timeIntervalSince1970: $0)
                },
                expirationDates: expirations.map {
                    Date(timeIntervalSince1970: $0)
                }
            )
        }

        expect(
            CodexDisplayPolicy.hasResetCreditExpiringWithinWeek(
                summary(expirations: [now.timeIntervalSince1970 + week]),
                now: now
            ),
            "reset credit expiring exactly seven days out warns"
        )
        expect(
            CodexDisplayPolicy.hasResetCreditExpiringWithinWeek(
                summary(expirations: [now.timeIntervalSince1970]),
                now: now
            ),
            "reset credit expiring now warns"
        )
        expect(
            !CodexDisplayPolicy.hasResetCreditExpiringWithinWeek(
                summary(expirations: [now.timeIntervalSince1970 + week + 1]),
                now: now
            ),
            "reset credit beyond seven days stays normal"
        )
        expect(
            !CodexDisplayPolicy.hasResetCreditExpiringWithinWeek(
                summary(expirations: [now.timeIntervalSince1970 - 1]),
                now: now
            ),
            "expired reset credit does not warn"
        )
        expect(
            !CodexDisplayPolicy.hasResetCreditExpiringWithinWeek(
                summary(availableCount: 0, expirations: [now.timeIntervalSince1970 + 60]),
                now: now
            ),
            "zero available reset credits do not warn"
        )
        expect(
            !CodexDisplayPolicy.hasResetCreditExpiringWithinWeek(
                summary(expirations: []),
                now: now
            ),
            "missing reset expiration dates stay normal"
        )
    }

    private static func checkCodexBucketPreference() {
        let result: JSONObject = [
            "rateLimits": ["primary": ["usedPercent": 90]],
            "rateLimitsByLimitId": [
                "other": ["primary": ["usedPercent": 10]],
                "codex": ["primary": ["usedPercent": 35]]
            ]
        ]

        let parsed = CodexStatusPayloadParser.parseRateLimits(result)
        expect(parsed.bucket?.primary?.usedPercent == 35, "prefer the codex rate-limit bucket")
    }

    private static func checkAccountUsageThreadAndModel() {
        let account = CodexStatusPayloadParser.parseAccount([
            "account": ["type": "chatgpt", "email": "hello@example.com", "planType": "pro"]
        ])
        let usage = CodexStatusPayloadParser.parseUsage([
            "summary": ["lifetimeTokens": 1_234_567, "currentStreakDays": 7],
            "dailyUsageBuckets": [
                ["startDate": "2026-07-14", "tokens": 42],
                ["tokens": 99],
                ["startDate": "2026-07-12", "tokens": 12],
                ["startDate": "2026-07-13", "tokens": -5]
            ]
        ])
        let usageWithoutSummary = CodexStatusPayloadParser.parseUsage([
            "dailyUsageBuckets": [["startDate": "2026-07-14", "tokens": 7]]
        ])
        let thread = CodexStatusPayloadParser.parseLatestThread([
            "data": [[
                "id": "thread-1",
                "name": "实现顶部状态岛",
                "status": ["type": "notLoaded"],
                "path": "/Users/test/.codex/sessions/rollout-thread-1.jsonl",
                "updatedAt": 2_000_000_000
            ]]
        ])
        let model = CodexStatusPayloadParser.parseDefaultModel([
            "data": [["id": "gpt-5.6-sol", "displayName": "GPT-5.6 Sol", "isDefault": true]]
        ])

        expect(account.planType == "pro", "account plan")
        expect(usage.lifetimeTokens == 1_234_567, "lifetime tokens")
        expect(usage.currentStreakDays == 7, "usage streak")
        expect(
            usage.dailyUsageBuckets.map(\.startDate)
                == ["2026-07-12", "2026-07-13", "2026-07-14"],
            "daily usage buckets are validated and sorted"
        )
        expect(usage.dailyUsageBuckets[1].tokens == 0, "negative daily usage is clamped")
        expect(
            usageWithoutSummary.dailyUsageBuckets.first?.tokens == 7,
            "daily usage survives a missing summary"
        )
        expect(thread?.title == "实现顶部状态岛", "thread title")
        expect(thread?.status == "notLoaded", "thread status")
        expect(thread?.rolloutPath?.hasSuffix("rollout-thread-1.jsonl") == true, "thread rollout path")
        expect(model?.id == "gpt-5.6-sol", "default model")
    }

    private static func checkUsageTimeline() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 15, hour: 12)
        )!
        let timeline = CodexUsageTimeline.lastDaysIncludingToday(
            from: [
                DailyUsageBucket(startDate: "2026-07-15", tokens: 5),
                DailyUsageBucket(startDate: "2026-07-14", tokens: 140),
                DailyUsageBucket(startDate: "2026-07-12", tokens: 120),
                DailyUsageBucket(startDate: "2026-07-12", tokens: 3)
            ],
            todayTokens: 150,
            localDailyBuckets: [
                DailyUsageBucket(startDate: "2026-07-14", tokens: 150),
                DailyUsageBucket(startDate: "2026-07-13", tokens: 80)
            ],
            count: 5,
            now: now,
            calendar: calendar
        )

        expect(timeline.count == 5, "usage timeline has one entry per calendar day")
        expect(timeline.first?.startDate == "2026-07-11", "usage timeline starts four days ago")
        expect(timeline.last?.startDate == "2026-07-15", "usage timeline ends today")
        expect(
            timeline[2].tokens == 80,
            "local daily history fills an account date that is missing"
        )
        expect(timeline[1].tokens == 123, "duplicate usage dates are combined")
        expect(
            timeline[3].tokens == 150,
            "local hourly usage keeps yesterday visible while account data lags"
        )
        expect(
            timeline.last?.tokens == 150,
            "local real-time usage replaces a delayed account bucket for today"
        )

        let accountAheadTimeline = CodexUsageTimeline.lastDaysIncludingToday(
            from: [DailyUsageBucket(startDate: "2026-07-14", tokens: 175)],
            localDailyBuckets: [
                DailyUsageBucket(startDate: "2026-07-14", tokens: 150)
            ],
            count: 2,
            now: now,
            calendar: calendar
        )
        expect(
            accountAheadTimeline.first?.tokens == 175,
            "yesterday uses the larger account total without double counting"
        )

        var shanghaiCalendar = Calendar(identifier: .gregorian)
        shanghaiCalendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let newYearNow = shanghaiCalendar.date(
            from: DateComponents(year: 2026, month: 1, day: 2, hour: 12)
        )!
        let newYearTimeline = CodexUsageTimeline.lastDaysIncludingToday(
            from: [],
            count: 3,
            now: newYearNow,
            calendar: shanghaiCalendar
        )
        expect(
            newYearTimeline.map(\.startDate)
                == ["2025-12-31", "2026-01-01", "2026-01-02"],
            "usage timeline crosses month and year boundaries"
        )

        var losAngelesCalendar = Calendar(identifier: .gregorian)
        losAngelesCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let daylightSavingNow = losAngelesCalendar.date(
            from: DateComponents(year: 2026, month: 3, day: 10, hour: 12)
        )!
        let daylightSavingTimeline = CodexUsageTimeline.lastDaysIncludingToday(
            from: [],
            count: 5,
            now: daylightSavingNow,
            calendar: losAngelesCalendar
        )
        expect(
            daylightSavingTimeline.map(\.startDate)
                == ["2026-03-06", "2026-03-07", "2026-03-08", "2026-03-09", "2026-03-10"],
            "usage timeline keeps calendar-day continuity across daylight saving time"
        )

        for identifier: Calendar.Identifier in [.buddhist, .hebrew, .persian] {
            var systemCalendar = Calendar(identifier: identifier)
            systemCalendar.timeZone = shanghaiCalendar.timeZone
            let timeline = CodexUsageTimeline.lastDaysIncludingToday(
                from: [DailyUsageBucket(startDate: "2026-01-01", tokens: 175)],
                count: 3, now: newYearNow, calendar: systemCalendar
            )
            expect(timeline.map(\.startDate) == ["2025-12-31", "2026-01-01", "2026-01-02"],
                   "\(identifier) system calendars preserve Gregorian account date keys in the local time zone")
            expect(timeline[1].tokens == 175,
                   "\(identifier) system calendars retain account history instead of displaying zeros")
            let credits = CodexUsageTimeline.dailyCreditTotals(
                from: [newYearNow: CodexChartCreditTotal(tokens: 175, credits: 2)],
                calendar: systemCalendar
            )
            expect(credits["2026-01-02"]?.credits == 2 && credits.count == 1,
                   "\(identifier) chart credits use the same Gregorian keys as token history")
        }
    }

    private static func checkThreadRuntimeSettings() {
        let threadID = UUID().uuidString
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rollout-\(threadID).jsonl")
        let older = #"{"type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"model":"gpt-5.5","reasoning_effort":"high","service_tier":"priority"}}}"#
        let newer = #"{"type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"model":"gpt-5.6-sol","reasoning_effort":"ultra","service_tier":"default"}}}"#
        let context = #"{"type":"turn_context","payload":{"model":"gpt-5.6-sol","effort":"ultra"}}"#
        let filler = "{\"type\":\"response_item\",\"payload\":{\"text\":\"\(String(repeating: "x", count: 70_000))\"}}"

        do {
            try ([older, newer, context, filler].joined(separator: "\n") + "\n")
                .data(using: .utf8)?
                .write(to: url)
            let settings = try CodexThreadSettingsReader.readLatest(
                from: url.path,
                threadID: threadID,
                validatePath: false
            )
            expect(settings?.model == "gpt-5.6-sol", "thread model from latest settings event")
            expect(settings?.reasoningEffort == "ultra", "thread reasoning effort")
            expect(settings?.serviceTier == "default", "thread service tier")

            let appended = #"{"type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"model":"gpt-5.7","reasoning_effort":"high","service_tier":"priority"}}}"# + "\n"
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(appended.utf8))
            try handle.close()

            let refreshed = try CodexThreadSettingsReader.readLatest(
                from: url.path,
                threadID: threadID,
                validatePath: false
            )
            expect(refreshed?.model == "gpt-5.7", "thread settings cache refreshes after append")
            expect(refreshed?.reasoningEffort == "high", "refreshed reasoning effort")
            expect(refreshed?.serviceTier == "priority", "refreshed fast service tier")

            let largeAppend = "{\"type\":\"response_item\",\"payload\":{\"text\":\"\(String(repeating: "y", count: 70_000))\"}}\n"
            let largeAppendHandle = try FileHandle(forWritingTo: url)
            try largeAppendHandle.seekToEnd()
            try largeAppendHandle.write(contentsOf: Data(largeAppend.utf8))
            try largeAppendHandle.close()
            _ = try CodexThreadSettingsReader.readLatest(
                from: url.path,
                threadID: threadID,
                validatePath: false
            )

            let contextOnly = #"{"type":"turn_context","payload":{"model":"gpt-5.7","effort":"max"}}"# + "\n"
            let contextHandle = try FileHandle(forWritingTo: url)
            try contextHandle.seekToEnd()
            try contextHandle.write(contentsOf: Data(contextOnly.utf8))
            try contextHandle.close()

            let contextRefreshed = try CodexThreadSettingsReader.readLatest(
                from: url.path,
                threadID: threadID,
                validatePath: false
            )
            expect(contextRefreshed?.reasoningEffort == "max", "new turn context updates effort")
            expect(
                contextRefreshed?.serviceTier == "priority",
                "turn context append preserves recorded Fast tier"
            )
        } catch {
            expect(false, "thread settings reader: \(error.localizedDescription)")
        }
        try? FileManager.default.removeItem(at: url)

        let tuiThreadID = UUID().uuidString
        let tuiURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rollout-\(tuiThreadID).jsonl")
        let tuiContext = #"{"type":"turn_context","payload":{"model":"gpt-5.6-sol","effort":"max"}}"#
        do {
            try (tuiContext + "\n").data(using: .utf8)?.write(to: tuiURL)
            let settings = try CodexThreadSettingsReader.readLatest(
                from: tuiURL.path,
                threadID: tuiThreadID,
                validatePath: false
            )
            expect(settings?.model == "gpt-5.6-sol", "TUI fallback model")
            expect(settings?.reasoningEffort == "max", "TUI fallback reasoning effort")
            expect(settings?.serviceTier == nil, "missing TUI service tier stays unknown")
        } catch {
            expect(false, "TUI settings fallback: \(error.localizedDescription)")
        }
        try? FileManager.default.removeItem(at: tuiURL)

        let resumedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rollout-\(UUID().uuidString).jsonl")
        let coldURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rollout-\(UUID().uuidString).jsonl")
        defer {
            try? FileManager.default.removeItem(at: resumedURL)
            try? FileManager.default.removeItem(at: coldURL)
        }
        do {
            try Data((older + "\n").utf8).write(to: resumedURL)
            _ = try CodexThreadSettingsReader.readLatest(
                from: resumedURL.path, validatePath: false
            )
            let resumedContext = #"{"type": "turn_context", "payload": {"model": "gpt-6-astra", "effort": "max", "service_tier": null}}"#
            let handle = try FileHandle(forWritingTo: resumedURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((resumedContext + "\n").utf8))
            try handle.close()
            try FileManager.default.copyItem(at: resumedURL, to: coldURL)
            for path in [resumedURL.path, coldURL.path] {
                let settings = try CodexThreadSettingsReader.readLatest(
                    from: path, validatePath: false
                )
                expect(
                    settings?.model == "gpt-6-astra"
                        && settings?.reasoningEffort == "max"
                        && settings?.serviceTier == "default",
                    "latest turn context overrides old applied settings on warm and cold reads"
                )
            }
            let partialApplied = #"{"type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"reasoning_effort":"high"}}}"#
            let partialContext = #"{"type":"turn_context","payload":{"model":"gpt-6-sol"}}"#
            let appendHandle = try FileHandle(forWritingTo: resumedURL)
            try appendHandle.seekToEnd()
            try appendHandle.write(contentsOf: Data((partialApplied + "\n" + partialContext + "\n").utf8))
            try appendHandle.close()
            let merged = try CodexThreadSettingsReader.readLatest(
                from: resumedURL.path, validatePath: false
            )
            expect(
                merged?.model == "gpt-6-sol"
                    && merged?.reasoningEffort == "high"
                    && merged?.serviceTier == "default",
                "partial settings and contexts preserve the newest value of each field"
            )
        } catch {
            expect(false, "resumed thread settings: \(error.localizedDescription)")
        }
    }

    private static func checkPartiallyWrittenThreadSettings() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-island-partial-settings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("warm.jsonl")
            let coldURL = directory.appendingPathComponent("cold.jsonl")
            let old = #"{"type":"turn_context","payload":{"model":"gpt-6-sol","effort":"max","service_tier":"default"}}"# + "\n"
            var new = try JSONSerialization.data(withJSONObject: [
                "type": "turn_context", "payload": [
                    "model": "gpt-6-astra", "effort": "ultra", "service_tier": "priority",
                    "user_instructions": String(repeating: "x", count: 150_000)
                ]
            ], options: [.sortedKeys])
            new.append(0x0A)
            try Data(old.utf8).write(to: url)
            _ = try CodexThreadSettingsReader.readLatest(from: url.path, validatePath: false)
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            var offset = 0
            for end in [90_000, 120_000] {
                try handle.write(contentsOf: new[offset..<end])
                offset = end
                let partial = try CodexThreadSettingsReader.readLatest(from: url.path, validatePath: false)
                expect(partial?.model == "gpt-6-sol" && partial?.serviceTier == "default",
                       "incomplete large settings retain the previous complete values")
            }
            try handle.write(contentsOf: new[offset...])
            let completed = try CodexThreadSettingsReader.readLatest(from: url.path, validatePath: false)
            try FileManager.default.copyItem(at: url, to: coldURL)
            let cold = try CodexThreadSettingsReader.readLatest(from: coldURL.path, validatePath: false)
            expect(completed?.model == "gpt-6-astra" && completed?.reasoningEffort == "ultra"
                   && completed?.serviceTier == "priority" && completed == cold,
                   "completing a settings line larger than the read chunk updates every field on warm and cold reads")

            let partialUpdate = #"{"type":"turn_context","payload":{"service_tier":null}}"# + "\n"
            try handle.write(contentsOf: Data(partialUpdate.utf8))
            let merged = try CodexThreadSettingsReader.readLatest(from: url.path, validatePath: false)
            expect(merged?.model == "gpt-6-astra" && merged?.reasoningEffort == "ultra"
                   && merged?.serviceTier == "default",
                   "subsequent partial settings preserve the recovered model and effort while clearing Fast")
        } catch {
            expect(false, "partially written thread settings: \(error.localizedDescription)")
        }
    }

    private static func checkThreadRequestServiceTiers() {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("codex-island-fast-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: directory) }
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("logs_2.sqlite")
            let missingURL = directory.appendingPathComponent("missing.sqlite")
            expect(CodexThreadServiceTierReader.readLatest(for: ["top"], from: missingURL).isEmpty
                   && !fm.fileExists(atPath: missingURL.path), "missing request logs stay unknown and are not created")
            var database: OpaquePointer?
            guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
                expect(false, "create Fast request-log fixture")
                return
            }
            defer { sqlite3_close(database) }
            func execute(_ sql: String) throws {
                guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
                    throw NSError(domain: "FastFixture", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
                }
            }
            let indexSQL = "CREATE INDEX idx_logs_thread_id_ts ON logs(thread_id, ts DESC, ts_nanos DESC, id DESC)"
            try execute("PRAGMA journal_mode=WAL")
            try execute("CREATE TABLE logs(id INTEGER PRIMARY KEY, ts INTEGER, ts_nanos INTEGER, target TEXT, feedback_log_body TEXT, thread_id TEXT)")
            try execute(indexSQL)
            func append(_ id: String, _ tier: String?, at time: Int64, nanos: Int64 = 0,
                        target: String = "feedback_tags", body: String? = nil) throws {
                let tags: [String: String] = tier.map { ["service_tier": $0] } ?? ["other": "tag"]
                let payload = try JSONSerialization.data(withJSONObject: tags, options: [.sortedKeys])
                let text = body ?? "session_loop{thread_id=\(id)}: feedback tags_json=\(String(decoding: payload, as: UTF8.self))"
                var statement: OpaquePointer?
                defer { sqlite3_finalize(statement) }
                guard sqlite3_prepare_v2(database, "INSERT INTO logs(ts,ts_nanos,target,feedback_log_body,thread_id) VALUES(?,?,?,?,?)", -1, &statement, nil) == SQLITE_OK else {
                    throw NSError(domain: "FastFixture", code: 2)
                }
                let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                sqlite3_bind_int64(statement, 1, time)
                sqlite3_bind_int64(statement, 2, nanos)
                sqlite3_bind_text(statement, 3, target, -1, transient)
                sqlite3_bind_text(statement, 4, text, -1, transient)
                sqlite3_bind_text(statement, 5, id, -1, transient)
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw NSError(domain: "FastFixture", code: 3)
                }
            }
            let threads = CodexStatusPayloadParser.parseRecentThreads(["data": [
                ["id": "top", "name": "same title", "cwd": directory.path, "source": "cli"],
                ["id": "middle", "name": "same title", "cwd": directory.path, "source": "cli"],
                ["id": "recorded", "cwd": directory.path, "serviceTier": "priority"],
                ["id": "unknown", "cwd": directory.path]
            ]])
            try append("top", "priority", at: 100)
            try append("middle", "priority", at: 100)
            try append("recorded", "default", at: 100)
            let initial = CodexThreadServiceTierReader.fillingMissing(in: threads, from: url)
            expect(initial[0].serviceTier == "priority" && initial[1].serviceTier == "priority",
                   "same-directory TUI tasks each recover their own Fast request")
            expect(initial[1].serviceTierSource == .runtimeLog && initial[2].serviceTierSource == .recorded,
                   "request-log fallback has distinct provenance and preserves recorded settings")

            try Data("service_tier = \"default\"\n".utf8).write(to: directory.appendingPathComponent("config.toml"))
            try append("top", "default", at: 200)
            // Other targets can contain quoted tool output. They are not settings.
            try append("middle", "default", at: 201, target: "codex_core::tools")
            let refreshed = CodexThreadServiceTierReader.fillingMissing(in: threads, from: url)
            expect(refreshed[0].serviceTier == "default" && refreshed[1].serviceTier == "priority",
                   "turning off Fast in one TUI cannot clear another same-directory task's Fast state")
            expect(refreshed[2].serviceTier == "priority" && refreshed[3].serviceTier == nil,
                   "shared Standard config neither overrides recorded Fast nor invents missing state")
            expect(CodexThreadServiceTierReader.readLatest(for: ["middle' OR 1=1 --"], from: url).isEmpty,
                   "request tiers are matched by bound thread identity")

            try append("middle", "default", at: 300, nanos: 1)
            try append("middle", "fast", at: 300, nanos: 2)
            expect(CodexThreadServiceTierReader.readLatest(for: ["middle"], from: url)["middle"] == "fast",
                   "nanosecond ordering selects the latest request tier")
            try append("middle", "default", at: 300, nanos: 2)
            try append("middle", "priority", at: 299)
            expect(CodexThreadServiceTierReader.readLatest(for: ["middle"], from: url)["middle"] == "default",
                   "same-time row identity breaks ties without letting older backfilled requests win")
            try append("middle", "unrecognized", at: 301)
            expect(CodexThreadServiceTierReader.readLatest(for: ["middle"], from: url)["middle"] == nil,
                   "unknown newer tiers do not resurrect an older Fast state")

            try append("malformed", nil, at: 100, body: "feedback tags_json={invalid}")
            try append("oversized", nil, at: 100,
                       body: "feedback tags_json={\"padding\":\"\(String(repeating: "x", count: 70_000))\",\"service_tier\":\"priority\"}")
            try append("buried", "priority", at: 100)
            for offset in 0..<129 { try append("buried", nil, at: Int64(200 + offset), target: "other") }
            expect(CodexThreadServiceTierReader.readLatest(for: ["malformed", "oversized", "buried"], from: url).isEmpty,
                   "malformed, oversized, or outside-budget feedback leaves Fast unknown")
            try execute("DROP INDEX idx_logs_thread_id_ts")
            expect(CodexThreadServiceTierReader.readLatest(for: ["top"], from: url).isEmpty,
                   "unsupported log indexes fail closed without scanning the database")
            try execute(indexSQL)
            expect(CodexThreadServiceTierReader.readLatest(for: ["top"], from: url)["top"] == "default",
                   "read-only queries recover after an unavailable schema without a stale cache")
        } catch {
            expect(false, "thread request service tiers: \(error.localizedDescription)")
        }
    }

    private static func checkThreadActivityStates() {
        let threadID = UUID().uuidString
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rollout-\(threadID).jsonl")

        func append(_ text: String) throws {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
            try handle.close()
        }

        func snapshot() throws -> ThreadActivitySnapshot {
            try CodexThreadActivityReader.readLatest(
                from: url.path,
                threadID: threadID,
                validatePath: false
            )
        }

        func state() throws -> ThreadExecutionState {
            try snapshot().executionState
        }

        func expectState(_ expected: ThreadExecutionState, _ message: String) throws {
            let actual = try state()
            expect(actual == expected, message)
        }

        do {
            try Data().write(to: url)
            try expectState(.unknown, "empty rollout activity is unknown")

            let start1 = #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}"# + "\n"
            try append(start1)
            try expectState(.running, "task_started becomes running")

            let inputRequest = #"{"type":"response_item","payload":{"type":"function_call","name":"request_user_input","call_id":"input-1"}}"# + "\n"
            try append(inputRequest)
            try expectState(.waitingForInput, "request_user_input waits for input")

            let waitingAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let waitingModifiedAt = waitingAttributes[.modificationDate] as? Date ?? Date()
            let longPendingApproval = try CodexThreadActivityReader.readLatest(
                from: url.path,
                threadID: threadID,
                validatePath: false,
                now: waitingModifiedAt.addingTimeInterval(24 * 60 * 60),
                staleInterval: 30 * 60
            )
            expect(
                longPendingApproval.executionState == .waitingForInput,
                "waiting for input does not expire while approval is pending"
            )

            let inputResponse = #"{"type":"response_item","payload":{"type":"function_call_output","call_id":"input-1","output":"ok"}}"# + "\n"
            try append(inputResponse)
            try expectState(.running, "request_user_input response resumes running")

            let token1 = #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":2929630,"cached_input_tokens":2806528,"output_tokens":19878,"reasoning_output_tokens":2428,"total_tokens":2949508},"last_token_usage":{"input_tokens":93600,"cached_input_tokens":90000,"output_tokens":1400,"reasoning_output_tokens":300,"total_tokens":95000},"model_context_window":258400}}}"# + "\n"
            try append(token1)
            let usage1 = try snapshot().tokenUsage
            expect(usage1?.inputTokens == 2_929_630, "cumulative input token count")
            expect(usage1?.cachedInputTokens == 2_806_528, "cumulative cached token count")
            expect(usage1?.outputTokens == 19_878, "cumulative output token count")
            expect(usage1?.reasoningOutputTokens == 2_428, "cumulative reasoning token count")
            expect(usage1?.totalTokens == 2_949_508, "cumulative total token count")
            expect(usage1?.contextTokensUsed == 95_000, "current context token count")
            expect(usage1?.contextWindowTokens == 258_400, "model context window")

            let filler = "{\"type\":\"response_item\",\"payload\":{\"text\":\"\(String(repeating: "x", count: 70_000))\"}}\n"
            try append(filler)
            try expectState(.running, "large unrelated append preserves running")

            let complete1 = #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1"}}"#
            let splitIndex = complete1.index(complete1.startIndex, offsetBy: complete1.count / 2)
            try append(String(complete1[..<splitIndex]))
            try expectState(.running, "partial lifecycle line keeps prior state")
            try append(String(complete1[splitIndex...]) + "\n")
            try expectState(.idle, "completed partial line becomes idle")

            let token2 = #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":3000000,"cached_input_tokens":2850000,"output_tokens":25000,"reasoning_output_tokens":3000,"total_tokens":3025000}}}}"# + "\n"
            try append(token2)
            let usage2 = try snapshot().tokenUsage
            expect(
                usage2?.totalTokens == 3_025_000,
                "appended token_count refreshes cumulative total"
            )

            let start2 = #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-2"}}"# + "\n"
            let abort2 = #"{"type":"event_msg","payload":{"type":"turn_aborted","turn_id":"turn-2","reason":"interrupted"}}"# + "\n"
            try append(start2 + abort2)
            try expectState(.interrupted, "turn_aborted becomes interrupted")

            let start3 = #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-3"}}"# + "\n"
            let failure = #"{"type":"event_msg","payload":{"type":"error","codex_error_info":"unauthorized"}}"# + "\n"
            let complete3 = #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-3"}}"# + "\n"
            try append(start3 + failure + complete3)
            try expectState(.failed, "fatal turn error survives task_complete")

            // Current Codex persists terminal errors inside task_complete,
            // without a separate error event in the rollout.
            let persistedStart = #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"persisted-failure"}}"# + "\n"
            let persistedFailure = #"{"type": "event_msg", "payload": {"type": "task_complete", "turn_id": "persisted-failure", "error": {"message": "quota exceeded", "codex_error_info": "usage_limit_exceeded"}}}"# + "\n"
            try append(persistedStart)
            try expectState(.running, "persisted failure fixture starts running")
            try append(persistedFailure)
            let failedActivity = try snapshot()
            expect(failedActivity.executionState == .failed,
                   "appended task_complete error marks the turn failed")

            let coldURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("rollout-\(UUID().uuidString).jsonl")
            defer { try? FileManager.default.removeItem(at: coldURL) }
            try FileManager.default.copyItem(at: url, to: coldURL)
            let coldFailure = try CodexThreadActivityReader.readLatest(
                from: coldURL.path, validatePath: false
            )
            expect(coldFailure.executionState == .failed,
                   "cold task_complete error also marks the turn failed")
            var failedThread = CodexStatusPayloadParser.parseRecentThreads([
                "data": [["id": threadID, "path": url.path]]
            ])[0]
            failedThread.executionState = failedActivity.executionState
            expect(
                CodexDisplayPolicy.completedThreadIDs(
                    previousStates: [threadID: .running], currentThreads: [failedThread]
                ).isEmpty,
                "a persisted terminal error never triggers the success completion sound"
            )

            let start4 = #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-4"}}"# + "\n"
            let delayedOldComplete = #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-old","error":{"message":"old turn failed"}}}"# + "\n"
            try append(start4 + delayedOldComplete)
            try expectState(.running, "old turn failure does not stop the active turn")

            let complete4 = #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-4","error":null}}"# + "\n"
            try append(complete4)
            try expectState(.idle, "matching completion with a null error stops the active turn")

            let start5 = #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-5"}}"# + "\n"
            try append(start5)
            try expectState(.running, "large partial terminal fixture starts running")

            let hugeCompletePrefix =
                #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-5","details":""#
                + String(repeating: "q", count: 140_000)
            try append(hugeCompletePrefix)
            try expectState(.running, "incomplete terminal record keeps prior state")
            try append(#""}}"# + "\n")
            try expectState(
                .idle,
                "terminal record split across polls by more than 64 KiB is not lost"
            )
        } catch {
            expect(false, "thread activity reader: \(error.localizedDescription)")
        }
        try? FileManager.default.removeItem(at: url)

        let initialThreadID = UUID().uuidString
        let initialURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rollout-\(initialThreadID).jsonl")
        let oldOrphan = #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"old-orphan"}}"#
        let previousTokenCount = #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":120000,"cached_input_tokens":100000,"output_tokens":4000,"reasoning_output_tokens":1000,"total_tokens":124000}}}}"#
        let latestStart = #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"latest"}}"#
        let oldCompletion = #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"old-orphan"}}"#
        let largeTail = "{\"type\":\"response_item\",\"payload\":{\"text\":\"\(String(repeating: "z", count: 140_000))\"}}"
        do {
            try ([oldOrphan, previousTokenCount, latestStart, oldCompletion, largeTail].joined(separator: "\n") + "\n")
                .data(using: .utf8)?
                .write(to: initialURL)
            let initial = try CodexThreadActivityReader.readLatest(
                from: initialURL.path,
                threadID: initialThreadID,
                validatePath: false
            )
            expect(
                initial.executionState == .running,
                "initial backwards scan ignores delayed completion for older turn"
            )
            expect(
                initial.tokenUsage?.totalTokens == 124_000,
                "initial backwards scan recovers latest cumulative tokens before a new turn"
            )
        } catch {
            expect(false, "initial thread activity scan: \(error.localizedDescription)")
        }
        try? FileManager.default.removeItem(at: initialURL)

        let staleThreadID = UUID().uuidString
        let staleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rollout-\(staleThreadID).jsonl")
        let startedAt = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: startedAt)
        let staleStart =
            #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"task_started","turn_id":"stale-turn"}}"#
            + "\n"
        do {
            try Data(staleStart.utf8).write(to: staleURL)
            try FileManager.default.setAttributes(
                [.modificationDate: startedAt.addingTimeInterval(-3_600)],
                ofItemAtPath: staleURL.path
            )

            let fresh = try CodexThreadActivityReader.readLatest(
                from: staleURL.path,
                threadID: staleThreadID,
                validatePath: false,
                now: startedAt.addingTimeInterval(20 * 60),
                staleInterval: 30 * 60
            )
            expect(
                fresh.executionState == .running,
                "fresh lifecycle timestamp keeps an unmatched start running"
            )

            let stale = try CodexThreadActivityReader.readLatest(
                from: staleURL.path,
                threadID: staleThreadID,
                validatePath: false,
                now: startedAt.addingTimeInterval(31 * 60),
                staleInterval: 30 * 60
            )
            expect(
                stale.executionState == .unknown,
                "cached unmatched start ages from running to unknown"
            )
        } catch {
            expect(false, "stale thread activity guard: \(error.localizedDescription)")
        }
        try? FileManager.default.removeItem(at: staleURL)
    }

    private static func checkThreadCreditUsage() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-credit-checks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        func line(_ object: JSONObject) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self) + "\n"
        }
        func settings(_ model: String, tier: Any? = "default") throws -> String {
            var payload: JSONObject = ["model": model]
            if let tier { payload["service_tier"] = tier }
            return try line(["type": "turn_context", "payload": payload])
        }
        func count(input: Int64, cache: Int64, output: Int64) -> JSONObject {
            ["input_tokens": input, "cached_input_tokens": cache,
             "output_tokens": output, "reasoning_output_tokens": output / 2,
             "total_tokens": input + output]
        }
        let officialCounts = count(input: 100_000, cache: 80_000, output: 5_000)
        func token(_ total: JSONObject, last: JSONObject?) throws -> String {
            var info: JSONObject = ["total_token_usage": total]
            if let last { info["last_token_usage"] = last }
            return try line(["type": "event_msg", "payload": ["type": "token_count", "info": info]])
        }
        func write(_ content: String, to url: URL) throws {
            try Data(content.utf8).write(to: url, options: .atomic)
        }
        func append(_ content: String, to url: URL) throws {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(content.utf8))
        }
        func estimate(_ url: URL) throws -> CodexThreadCreditEstimate? {
            guard let usage = try CodexThreadActivityReader.readLatest(
                from: url.path, validatePath: false
            ).tokenUsage else { return nil }
            return try CodexThreadCreditUsageReader.estimate(
                from: url.path, matching: usage, validatePath: false
            )
        }
        func expectCredits(_ value: CodexThreadCreditEstimate?, _ expected: Double, _ message: String) {
            expect(value.map { abs($0.credits - expected) < 0.000_001 } == true, message)
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("mixed.jsonl")
            let official = try token(officialCounts, last: officialCounts)
            try write(settings("gpt-5.5") + official, to: url)
            expectCredits(try estimate(url), 7.25, "thread credits match the official 7.25 example without charging reasoning twice")
            try append(official, to: url)
            expectCredits(try estimate(url), 7.25, "duplicate token notifications do not increase credits")

            let astraCall = count(input: 10_000, cache: 8_000, output: 1_000)
            let afterAstra = count(input: 110_000, cache: 88_000, output: 6_000)
            try append(settings("gpt-6-astra", tier: "priority") + token(afterAstra, last: astraCall), to: url)
            expectCredits(try estimate(url), 12.125, "model changes and Fast apply only to their own calls")
            let afterSol = count(input: 120_000, cache: 96_000, output: 7_000)
            try append(settings("gpt-5.6-sol", tier: NSNull()) + token(afterSol, last: astraCall), to: url)
            expectCredits(try estimate(url), 12.905, "explicit null returns to Standard without repricing past Fast calls")

            let hugeResponse = try line(["type": "response_item", "payload": ["text": String(repeating: "x", count: 1_100_000)]])
            let afterAnotherSol = count(input: 130_000, cache: 104_000, output: 8_000)
            let next = try token(afterAnotherSol, last: astraCall)
            try append(hugeResponse + String(next.prefix(next.count / 2)), to: url)
            expectCredits(try estimate(url), 12.905, "large tool output and an incomplete token line preserve prior credits")
            try append(String(next.dropFirst(next.count / 2)), to: url)
            expectCredits(try estimate(url), 13.685, "completed appended token lines are charged once")

            let afterUnknown = count(input: 140_000, cache: 112_000, output: 9_000)
            try append(settings("unknown-model") + token(afterUnknown, last: astraCall), to: url)
            let unknownEstimate = try estimate(url)
            expect(unknownEstimate == nil, "unknown model cost is not shown as a complete total")
            try append(settings("gpt-5.5") + official, to: url)
            expectCredits(try estimate(url), 7.25, "counter resets keep credits aligned with the displayed token total")

            try write(settings("gpt-5.5", tier: "priority") + official, to: url)
            expectCredits(try estimate(url), 18.125, "file replacement invalidates the credit cache")
            let standardURL = directory.appendingPathComponent("standard.jsonl")
            try write(settings("gpt-5.5", tier: nil) + official, to: standardURL)
            let standard = try estimate(standardURL)
            expectCredits(standard, 7.25, "separate sessions retain independent Fast settings")
            expect(standard?.assumesStandardTier == true, "missing tier is disclosed as a Standard assumption")

            let gpt6URL = directory.appendingPathComponent("gpt6-sol-luna.jsonl")
            try write(settings("gpt-6-sol", tier: "priority") + official, to: gpt6URL)
            expectCredits(try estimate(gpt6URL), 6.625, "Sol Fast uses its own credit rates")
            let doubled = count(input: 200_000, cache: 160_000, output: 10_000)
            try append(settings("gpt-6-luna", tier: "fast") + token(doubled, last: officialCounts), to: gpt6URL)
            expectCredits(try estimate(gpt6URL), 6.95625, "switching to Luna Fast preserves earlier Sol costs")
            let tripled = count(input: 300_000, cache: 240_000, output: 15_000)
            try append(settings("gpt-6-luna", tier: NSNull()) + token(tripled, last: officialCounts), to: gpt6URL)
            expectCredits(try estimate(gpt6URL), 7.08875, "disabling Luna Fast prices only the new call at Standard")
            let quadrupled = count(input: 400_000, cache: 320_000, output: 20_000)
            try append(settings("openai/gpt-6.1-sol-2026-09-30", tier: "fast") + token(quadrupled, last: officialCounts), to: gpt6URL)
            expectCredits(try estimate(gpt6URL), 13.21375, "switching to GPT-6.1 Sol Fast uses its reduced cache rate without repricing prior calls")
            let quintupled = count(input: 500_000, cache: 400_000, output: 25_000)
            try append(settings("gpt-6.1-sol", tier: NSNull()) + token(quintupled, last: officialCounts), to: gpt6URL)
            expectCredits(try estimate(gpt6URL), 15.66375, "disabling GPT-6.1 Sol Fast preserves the previous Fast cost and prices the new call at Standard")
            let sextupled = count(input: 600_000, cache: 480_000, output: 30_000)
            try append(settings("openai/gpt-6.1-terra-2026-10-27", tier: "priority") + token(sextupled, last: officialCounts), to: gpt6URL)
            expectCredits(try estimate(gpt6URL), 18.72625, "switching to Terra Fast preserves earlier model costs")
            let septupled = count(input: 700_000, cache: 560_000, output: 35_000)
            let terraStandard = try settings("gpt-6.1-terra", tier: NSNull()) + token(septupled, last: officialCounts)
            try append(terraStandard, to: gpt6URL)
            expectCredits(try estimate(gpt6URL), 19.95125, "disabling Terra Fast prices only the new call at Standard")
            try append(terraStandard, to: gpt6URL)
            expectCredits(try estimate(gpt6URL), 19.95125, "duplicate Terra usage notifications do not increase credits")

            let jumpURL = directory.appendingPathComponent("jump.jsonl")
            try write(settings("gpt-5.5") + token(afterAstra, last: astraCall), to: jumpURL)
            let jumpEstimate = try estimate(jumpURL)
            expect(jumpEstimate == nil, "unattributed inherited usage is not priced using the latest model")
            try write(settings("gpt-5.5") + token(officialCounts, last: nil), to: jumpURL)
            let missingEstimate = try estimate(jumpURL)
            expect(missingEstimate == nil, "missing per-call details do not fabricate historical pricing")
            let customMeta = try line(["type": "session_meta", "payload": ["model_provider": "custom"]])
            try write(customMeta + settings("gpt-5.5") + official, to: jumpURL)
            let customEstimate = try estimate(jumpURL)
            expect(customEstimate == nil, "custom provider does not inherit OpenAI credit prices")
            try write(settings("gpt-5.5", tier: "flex") + official, to: jumpURL)
            let flexEstimate = try estimate(jumpURL)
            expect(flexEstimate == nil, "unlisted service tiers do not inherit Standard pricing")

            let screenshotURL = directory.appendingPathComponent("screenshot.jsonl")
            let screenshotCounts = count(input: 1_266_278, cache: 1_199_104, output: 6_717)
            try write(settings("gpt-6-astra") + token(screenshotCounts, last: screenshotCounts), to: screenshotURL)
            let screenshot = try estimate(screenshotURL)
            expectCredits(screenshot, 55.16735, "user screenshot tokens cost 55.16735 Astra Standard credits")
            expect(screenshot?.displayText == "55.2 credits", "credit label rounds only the final sum")
            let mismatched = ThreadTokenUsage(inputTokens: 1, cachedInputTokens: 0, outputTokens: 0,
                                             reasoningOutputTokens: 0, totalTokens: 1)
            let stale = try CodexThreadCreditUsageReader.estimate(
                from: screenshotURL.path, matching: mismatched, validatePath: false
            )
            expect(stale == nil, "credits from a newer scan cannot be paired with an older token snapshot")
            expect(CodexThreadCreditEstimate(credits: 0.001).displayText == "<0.1 credits", "small positive costs do not round to zero")
        } catch {
            expect(false, "thread credit usage: \(error.localizedDescription)")
        }
    }

    private static func checkOversizedUsageRecords() {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("island-oversized-usage-\(UUID())")
        defer {
            try? fm.removeItem(at: directory)
            CodexDailyTokenUsageReader.resetCacheForTesting()
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
        let timestamp = ISO8601DateFormatter().string(from: now.addingTimeInterval(-60))
        let instructions = String(repeating: "规则 { \"type\": \"turn_context\" } \\ thread_settings_applied; ", count: 24_000)
        func line(_ type: String, _ payload: JSONObject, typeFirst: Bool = false, at date: Date? = nil) throws -> String {
            let body = String(decoding: try JSONSerialization.data(withJSONObject: payload, options: .sortedKeys), as: UTF8.self)
            let dateString = date.map { ISO8601DateFormatter().string(from: $0) } ?? timestamp
            let fields = "\"payload\":\(body),\"timestamp\":\"\(dateString)\""
            return typeFirst ? "{\"type\":\"\(type)\",\(fields)}\n" : "{\(fields),\"type\":\"\(type)\"}\n"
        }
        func counts(_ n: Int64) -> JSONObject {
            ["input_tokens": n * 900_000, "cached_input_tokens": n * 800_000,
             "output_tokens": n * 100_000, "total_tokens": n * 1_000_000]
        }
        func token(_ n: Int64, large: Bool = false, at date: Date? = nil) throws -> String {
            var payload: JSONObject = ["type": "token_count", "info": [
                "total_token_usage": counts(n), "last_token_usage": counts(1)
            ]]
            if large { payload["extra"] = instructions }
            return try line("event_msg", payload, at: date)
        }
        func settings(_ fields: JSONObject, context: Bool = false) throws -> String {
            var fields = fields
            fields["collaboration_mode"] = ["settings": ["developer_instructions": instructions]]
            return try context ? line("turn_context", fields) : line("event_msg", [
                "type": "thread_settings_applied", "thread_settings": fields
            ], typeFirst: true)
        }
        func append(_ data: Data, to url: URL) throws {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        }
        func thread(_ url: URL, _ n: Int64) throws -> CodexThreadCreditEstimate? {
            try CodexThreadCreditUsageReader.estimate(from: url.path, matching: ThreadTokenUsage(
                inputTokens: n * 900_000, cachedInputTokens: n * 800_000,
                outputTokens: n * 100_000, reasoningOutputTokens: 0, totalTokens: n * 1_000_000
            ), validatePath: false)
        }
        func daily(_ url: URL) throws -> LocalTokenUsageSnapshot {
            try fm.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
            return try CodexDailyTokenUsageReader.readRecentHours(from: [url.path], now: now, calendar: calendar)
        }
        func verify(_ url: URL, _ n: Int64, _ credits: Double, unpriced: Int = 0, _ message: String) throws {
            let estimate = try thread(url, n)
            expect(unpriced > 0 ? estimate == nil : estimate.map { abs($0.credits - credits) < 0.000001 } == true,
                   "thread credits: \(message)")
            let snapshot = try daily(url)
            expect(snapshot.todayTokens == n * 1_000_000
                   && abs(snapshot.chartCreditTotals.values.reduce(0) { $0 + $1.credits } - credits) < 0.000001
                   && snapshot.chartCreditTotals.values.reduce(0) { $0 + $1.unpricedCalls } == unpriced,
                   "daily credits and tokens: \(message)")
        }
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            expect(instructions.utf8.count > 1024 * 1024, "oversized usage fixtures exceed both readers' former limits")
            let url = directory.appendingPathComponent("mixed.jsonl")
            let meta = try line("session_meta", ["source": "cli", "model_provider": "openai"])
            let luna = try line("turn_context", ["model": "gpt-6-luna", "service_tier": "default"])
            try Data((meta + luna + token(1)).utf8).write(to: url)
            try verify(url, 1, 1.7, "initial Luna call")
            let unrelated = try line("response_item", ["type": "function_call_output",
                "output": "turn_context thread_settings_applied " + instructions,
                "nested": ["type": "turn_context", "payload": ["model": "gpt-6-astra"]]
            ])
            try append(Data((unrelated + token(2)).utf8), to: url)
            try verify(url, 2, 3.4, "settings words in large tool output do not change the model")

            let context = try settings(["model": "gpt-6-astra", "service_tier": "priority"], context: true)
            try append(Data(context.dropLast().utf8), to: url)
            try verify(url, 2, 3.4, "a large valid JSON tail is not committed before its newline")
            let largeToken = try token(3, large: true)
            let bytes = Data(largeToken.utf8)
            try append(Data("\n".utf8) + bytes.prefix(65_537), to: url)
            try verify(url, 2, 3.4, "an incomplete oversized token event does not advance counters")
            try append(Data(bytes.dropFirst(65_537)), to: url)
            try verify(url, 3, 428.4, "large context and token records apply Astra Fast once")
            try append(Data((settings(["service_tier": NSNull()]) + token(4)).utf8), to: url)
            try verify(url, 4, 598.4, "large partial settings retain the model and reset Fast")
            let cold = directory.appendingPathComponent("cold.jsonl")
            try fm.copyItem(at: url, to: cold)
            try verify(cold, 4, 598.4, "cold and incremental reads agree across field ordering and large records")
            try append(Data((settings(["model": "gpt-6-luna", "model_provider_id": "custom"]) + token(5)).utf8), to: url)
            try verify(url, 5, 598.4, unpriced: 1, "large provider changes cannot inherit OpenAI prices")
            try append(Data((settings(["model_provider_id": "openai"]) + token(6)).utf8), to: url)
            try verify(url, 6, 600.1, unpriced: 1, "restoring the provider does not invent costs for the unknown call")

            // Backward baseline discovery must retain an oversized old token
            // counter, or its repeated notification today becomes a new call.
            let history = directory.appendingPathComponent("large-token-baseline.jsonl")
            let old = calendar.date(byAdding: .day, value: -35, to: now)!
            let oldMeta = try line("session_meta", ["source": "cli", "model_provider": "openai"], at: old)
            let oldContext = try line("turn_context", ["model": "gpt-6-luna", "service_tier": "default"], at: old)
            try Data((oldMeta + oldContext + token(1, large: true, at: old) + token(1)).utf8).write(to: history)
            let repeated = try daily(history)
            expect(repeated.todayTokens == 0 && repeated.chartCreditTotals.values.allSatisfy { $0.tokens == 0 },
                   "backward scans retain large counters before the visible range and suppress duplicate notifications")
            try append(Data(token(2).utf8), to: history)
            let advanced = try daily(history)
            expect(advanced.todayTokens == 1_000_000
                   && abs(advanced.chartCreditTotals.values.reduce(0) { $0 + $1.credits } - 1.7) < 0.000001,
                   "appends advance a large historical baseline by exactly the new call")
            CodexDailyTokenUsageReader.resetCacheForTesting()
            let coldHistory = try daily(history)
            expect(advanced == coldHistory, "large historical token baselines agree on cold and incremental scans")

            for provider in ["openai", "custom"] {
                let headerURL = directory.appendingPathComponent("large-header-\(provider).jsonl")
                let header = try line("session_meta", ["source": "cli", "model_provider": provider,
                    "base_instructions": ["text": instructions]])
                try Data(header.utf8.prefix(700_000)).write(to: headerURL)
                let pending = try daily(headerURL)
                expect(pending.todayTokens == 0, "an incomplete large session header remains pending")
                try append(Data(header.utf8.dropFirst(700_000)) + Data((luna + token(1)).utf8), to: headerURL)
                try verify(headerURL, 1, provider == "openai" ? 1.7 : 0,
                           unpriced: provider == "openai" ? 0 : 1,
                           "large session metadata preserves its source and provider after append")
            }

            for kind in ["fork", "subagent"] {
                let child = directory.appendingPathComponent("large-\(kind).jsonl")
                var payload: JSONObject = ["id": kind, "source": "cli", "model_provider": "openai",
                    "base_instructions": ["text": instructions]]
                if kind == "fork" { payload["forked_from_id"] = "parent" }
                else { payload["thread_source"] = "subagent" }
                let header = try line("session_meta", payload)
                let boundary = try kind == "fork" ? header : line("inter_agent_communication_metadata", [
                    "trigger_turn": true, "message": instructions
                ])
                try Data((header + luna + token(1) + unrelated + String(boundary.dropLast())).utf8).write(to: child)
                let pending = try daily(child)
                expect(pending.todayTokens == 0, "\(kind) excludes inherited history while its large boundary is uncommitted")
                try append(Data(("\n" + token(2)).utf8), to: child)
                let warm = try daily(child)
                expect(warm.todayTokens == 1_000_000
                       && abs(warm.chartCreditTotals.values.reduce(0) { $0 + $1.credits } - 1.7) < 0.000001,
                       "\(kind) recognizes its large activity boundary and counts only its own call")
                CodexDailyTokenUsageReader.resetCacheForTesting()
                let cold = try daily(child)
                expect(warm == cold, "\(kind) large metadata has identical cold and incremental attribution")
            }
        } catch {
            expect(false, "oversized usage records: \(error.localizedDescription)")
        }
    }

    private static func checkDailyTokenUsage() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let dayStart = calendar.startOfDay(for: Date())
        let now = calendar.date(byAdding: .hour, value: 12, to: dayStart)!
        let beforeMidnight = calendar.date(byAdding: .minute, value: -1, to: dayStart)!
        let afterMidnight = calendar.date(byAdding: .minute, value: 1, to: dayStart)!
        let laterToday = calendar.date(byAdding: .minute, value: 2, to: dayStart)!
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-island-daily-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        func sessionMeta(
            forked: Bool = false,
            startedAt: Date? = nil,
            subagent: Bool = false,
            modelProvider: String? = "openai"
        ) -> String {
            let forkField = forked ? ",\"forked_from_id\":\"parent\"" : ""
            let providerField = modelProvider.map {
                ",\"model_provider\":\"\($0)\""
            } ?? ""
            let sourceFields = subagent
                ? "\"source\":{\"subagent\":{\"thread_spawn\":{\"parent_thread_id\":\"parent\"}}},\"thread_source\":\"subagent\""
                : "\"source\":\"cli\",\"thread_source\":\"user\""
            return "{\"timestamp\":\"\(formatter.string(from: startedAt ?? afterMidnight))\",\"type\":\"session_meta\",\"payload\":{\"id\":\"test\",\(sourceFields)\(providerField)\(forkField)}}"
        }

        func token(_ date: Date, total: Int64, last: Int64?) -> String {
            let lastField = last.map {
                ",\"last_token_usage\":{\"total_tokens\":\($0)}"
            } ?? ""
            return "{\"timestamp\":\"\(formatter.string(from: date))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":\(total)}\(lastField)}}}"
        }

        func runtimeFields(
            model: String?,
            modelProviderID: String? = nil,
            serviceTier: String?
        ) -> String {
            [
                model.map { "\"model\":\"\($0)\"" },
                modelProviderID.map { "\"model_provider_id\":\"\($0)\"" },
                serviceTier.map { "\"service_tier\":\"\($0)\"" }
            ]
            .compactMap { $0 }
            .joined(separator: ",")
        }

        func threadSettings(
            _ date: Date,
            model: String? = nil,
            modelProviderID: String? = nil,
            serviceTier: String? = nil
        ) -> String {
            let fields = runtimeFields(
                model: model,
                modelProviderID: modelProviderID,
                serviceTier: serviceTier
            )
            return "{\"timestamp\":\"\(formatter.string(from: date))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"thread_settings_applied\",\"thread_settings\":{\(fields)}}}"
        }

        func turnContext(
            _ date: Date,
            model: String? = nil,
            serviceTier: String? = nil
        ) -> String {
            let fields = runtimeFields(model: model, serviceTier: serviceTier)
            return "{\"timestamp\":\"\(formatter.string(from: date))\",\"type\":\"turn_context\",\"payload\":{\(fields)}}"
        }

        func serviceTier(_ date: Date, _ value: String) -> String {
            threadSettings(date, serviceTier: value)
        }

        func subagentBoundary(_ date: Date, triggerTurn: Bool = true) -> String {
            "{\"timestamp\":\"\(formatter.string(from: date))\",\"type\":\"inter_agent_communication_metadata\",\"payload\":{\"trigger_turn\":\(triggerTurn)}}"
        }

        func write(_ lines: [String], name: String) -> URL {
            let url = directory.appendingPathComponent(name)
            try? Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
            try? FileManager.default.setAttributes(
                [.modificationDate: now],
                ofItemAtPath: url.path
            )
            return url
        }

        func appendLines(_ lines: [String], to url: URL) throws {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(
                contentsOf: Data((lines.joined(separator: "\n") + "\n").utf8)
            )
        }

        func hourlyTokens(
            _ buckets: [HourlyUsageBucket],
            containing date: Date
        ) -> Int64? {
            guard let hourStart = calendar.dateInterval(
                of: .hour,
                for: date
            )?.start else {
                return nil
            }
            return buckets.first { $0.hourStart == hourStart }?.tokens
        }

        func dailyTokens(
            _ buckets: [DailyUsageBucket],
            containing date: Date
        ) -> Int64? {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.calendar = calendar
            dateFormatter.timeZone = calendar.timeZone
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateLabel = dateFormatter.string(from: date)
            return buckets.first { $0.startDate == dateLabel }?.tokens
        }

        do {
            let calendarFixture = write(
                [sessionMeta(), token(afterMidnight, total: 100, last: 100)],
                name: "calendar.jsonl"
            )
            let gregorianUsage = try CodexDailyTokenUsageReader.readRecentHours(
                from: [calendarFixture.path], now: now, calendar: calendar
            )
            for identifier: Calendar.Identifier in [.buddhist, .hebrew, .persian] {
                var systemCalendar = Calendar(identifier: identifier)
                systemCalendar.timeZone = calendar.timeZone
                let usage = try CodexDailyTokenUsageReader.readRecentHours(
                    from: [calendarFixture.path], now: now, calendar: systemCalendar
                )
                expect(usage.dailyBuckets == gregorianUsage.dailyBuckets && usage.todayTokens == 100,
                       "\(identifier) rollout dates remain compatible with Gregorian account history")
            }
            CodexDailyTokenUsageReader.resetCacheForTesting()
            let pricedCounts = #""input_tokens":1000,"cached_input_tokens":0,"output_tokens":100,"total_tokens":1100"#
            for source in ["cli", "subagent", "fork"] {
                let isChild = source != "cli"
                let meta = sessionMeta(forked: source == "fork", subagent: source == "subagent")
                let header = Data(meta.utf8)
                let initialTotal: Int64 = isChild ? 9_000 : 0
                let pricedCall = "{\"timestamp\":\"\(formatter.string(from: laterToday))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":\(initialTotal + 1100)},\"last_token_usage\":{\(pricedCounts)}}}}"
                var body = [turnContext(laterToday, model: "gpt-6-sol", serviceTier: "default")]
                if isChild {
                    body.append(token(laterToday, total: initialTotal, last: initialTotal))
                    body.append(source == "fork" ? meta : subagentBoundary(laterToday))
                }
                body.append(pricedCall)
                for prefixSize in [0, header.count / 2, header.count - 1] {
                    CodexDailyTokenUsageReader.resetCacheForTesting()
                    let url = directory.appendingPathComponent("initializing-\(source)-\(prefixSize).jsonl")
                    try Data(header.prefix(prefixSize)).write(to: url)
                    try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
                    let initial = try CodexDailyTokenUsageReader.readToday(from: [url.path], now: now, calendar: calendar)
                    expect(initial == 0, "an empty or incomplete \(source) session header contributes no usage")
                    let handle = try FileHandle(forWritingTo: url)
                    try handle.seekToEnd()
                    var remainder = Data(header.dropFirst(prefixSize))
                    remainder.append(Data(("\n" + body.joined(separator: "\n") + "\n").utf8))
                    try handle.write(contentsOf: remainder)
                    try handle.close()
                    try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
                    let ready = try CodexDailyTokenUsageReader.readRecentHours(from: [url.path], now: now, calendar: calendar)
                    expect(ready.todayTokens == 1100,
                           "\(source) usage recovers after its initially incomplete header is appended, excluding inherited calls")
                    let credits = ready.chartCreditTotals.values.reduce(0) { $0 + $1.credits }
                    expect(abs(credits - 0.075) < 0.000001,
                           "\(source) initialization restores provider and runtime settings for credit pricing")
                    let repeated = try CodexDailyTokenUsageReader.readRecentHours(from: [url.path], now: now, calendar: calendar)
                    expect(repeated == ready, "repeated reads of an initialized \(source) rollout do not count usage twice")
                }
            }

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let normal = write(
                [
                    sessionMeta(),
                    token(afterMidnight, total: 100, last: 100),
                    token(laterToday, total: 160, last: 60),
                    token(laterToday.addingTimeInterval(1), total: 160, last: 12),
                    token(laterToday.addingTimeInterval(2), total: 220, last: 60)
                ],
                name: "normal.jsonl"
            )
            let value = try CodexDailyTokenUsageReader.readToday(
                from: [normal.path],
                now: now,
                calendar: calendar
            )
            expect(value == 220, "daily tokens count each new message and ignore replayed last usage")

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let weighted = write(
                [
                    sessionMeta(),
                    serviceTier(afterMidnight, "default"),
                    token(afterMidnight.addingTimeInterval(1), total: 100, last: 100),
                    serviceTier(afterMidnight.addingTimeInterval(2), "priority"),
                    token(afterMidnight.addingTimeInterval(3), total: 200, last: 100),
                    token(afterMidnight.addingTimeInterval(4), total: 200, last: 100),
                    serviceTier(afterMidnight.addingTimeInterval(5), "default"),
                    token(afterMidnight.addingTimeInterval(6), total: 260, last: 60)
                ],
                name: "weighted.jsonl"
            )
            let weightedValue = try CodexDailyTokenUsageReader.readToday(
                from: [weighted.path],
                now: now,
                calendar: calendar
            )
            expect(
                weightedValue == 260,
                "actual Token usage is not multiplied by Fast billing"
            )
            let weightedSnapshot = try CodexDailyTokenUsageReader.readRecentHours(
                from: [weighted.path],
                now: now,
                calendar: calendar
            )
            expect(
                weightedSnapshot.todayTokens == 260,
                "Fast messages without model metadata keep their actual token count"
            )
            expect(
                weightedSnapshot.hourlyBuckets.reduce(Int64(0)) {
                    $0 + $1.tokens
                } == 260
                    && weightedSnapshot.dailyBuckets.reduce(Int64(0)) {
                        $0 + $1.tokens
                    } == 260,
                "hourly and daily charts retain actual tokens without model metadata"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let modelWeighted = write(
                [
                    sessionMeta(),
                    threadSettings(
                        afterMidnight,
                        model: "gpt-5.4",
                        serviceTier: "priority"
                    ),
                    token(afterMidnight.addingTimeInterval(1), total: 100, last: 100),
                    turnContext(
                        afterMidnight.addingTimeInterval(2),
                        model: "gpt-5.5"
                    ),
                    token(afterMidnight.addingTimeInterval(3), total: 200, last: 100),
                    threadSettings(
                        afterMidnight.addingTimeInterval(4),
                        model: "gpt-5.6-sol"
                    ),
                    token(afterMidnight.addingTimeInterval(5), total: 300, last: 100),
                    turnContext(
                        afterMidnight.addingTimeInterval(6),
                        model: "gpt-6-astra",
                        serviceTier: "fast"
                    ),
                    token(afterMidnight.addingTimeInterval(7), total: 400, last: 100),
                    turnContext(
                        afterMidnight.addingTimeInterval(8),
                        model: "future-model"
                    ),
                    token(afterMidnight.addingTimeInterval(9), total: 500, last: 100),
                    turnContext(
                        afterMidnight.addingTimeInterval(10),
                        model: "gpt-6-astra",
                        serviceTier: "default"
                    ),
                    token(afterMidnight.addingTimeInterval(11), total: 600, last: 100)
                ],
                name: "model-weighted.jsonl"
            )
            let modelWeightedSnapshot = try CodexDailyTokenUsageReader.readRecentHours(
                from: [modelWeighted.path],
                now: now,
                calendar: calendar
            )
            expect(
                modelWeightedSnapshot.todayTokens == 600,
                "switching models and Fast settings does not change actual tokens"
            )
            expect(
                hourlyTokens(modelWeightedSnapshot.hourlyBuckets, containing: afterMidnight) == 600
                    && dailyTokens(modelWeightedSnapshot.dailyBuckets, containing: afterMidnight) == 600,
                "Fast usage leaves actual hourly and daily chart tokens unchanged"
            )

            let modelWeightedHandle = try FileHandle(forWritingTo: modelWeighted)
            try modelWeightedHandle.seekToEnd()
            try modelWeightedHandle.write(contentsOf: Data(([
                threadSettings(
                    afterMidnight.addingTimeInterval(12),
                    serviceTier: "priority"
                ),
                token(afterMidnight.addingTimeInterval(13), total: 700, last: 100)
            ].joined(separator: "\n") + "\n").utf8))
            try modelWeightedHandle.close()
            let appendedModelWeightedSnapshot = try CodexDailyTokenUsageReader.readRecentHours(
                from: [modelWeighted.path],
                now: now,
                calendar: calendar
            )
            expect(
                appendedModelWeightedSnapshot.todayTokens == 700,
                "incremental scans count actual tokens when switching to priority"
            )

            let nonChatGPTSnapshot = try CodexDailyTokenUsageReader.readRecentHours(
                from: [modelWeighted.path],
                now: now,
                calendar: calendar,
                usesChatGPTCredits: false
            )
            expect(
                nonChatGPTSnapshot.todayTokens == 700,
                "API-key usage retains the same actual token count"
            )
            let reenabledChatGPTSnapshot = try CodexDailyTokenUsageReader.readRecentHours(
                from: [modelWeighted.path],
                now: now,
                calendar: calendar,
                usesChatGPTCredits: true
            )
            expect(
                reenabledChatGPTSnapshot.todayTokens == 700,
                "switching back to ChatGPT preserves the actual token count"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let providerWeighted = write(
                [
                    sessionMeta(modelProvider: "openai"),
                    threadSettings(
                        afterMidnight,
                        model: "gpt-6-astra",
                        modelProviderID: "custom-provider",
                        serviceTier: "priority"
                    ),
                    token(afterMidnight.addingTimeInterval(1), total: 100, last: 100),
                    threadSettings(
                        afterMidnight.addingTimeInterval(2),
                        modelProviderID: "openai"
                    ),
                    token(afterMidnight.addingTimeInterval(3), total: 200, last: 100)
                ],
                name: "provider-weighted.jsonl"
            )
            let providerWeightedSnapshot = try CodexDailyTokenUsageReader.readRecentHours(
                from: [providerWeighted.path],
                now: now,
                calendar: calendar
            )
            expect(
                providerWeightedSnapshot.todayTokens == 200,
                "provider switches do not multiply actual token counts"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let customSessionProvider = write(
                [
                    sessionMeta(modelProvider: "custom-provider"),
                    threadSettings(
                        afterMidnight,
                        model: "gpt-5.4",
                        serviceTier: "priority"
                    ),
                    token(afterMidnight.addingTimeInterval(1), total: 100, last: 100)
                ],
                name: "custom-session-provider.jsonl"
            )
            let customSessionProviderSnapshot = try CodexDailyTokenUsageReader.readRecentHours(
                from: [customSessionProvider.path],
                now: now,
                calendar: calendar
            )
            expect(
                customSessionProviderSnapshot.todayTokens == 100,
                "custom providers retain actual token counts"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let dailyRangeStart = calendar.date(
                byAdding: .day,
                value: -(CodexDailyTokenUsageReader.recentDayCount - 1),
                to: dayStart
            )!
            let baselineWeighted = write(
                [
                    sessionMeta(
                        startedAt: calendar.date(
                            byAdding: .day,
                            value: -40,
                            to: dayStart
                        )
                    ),
                    threadSettings(
                        dailyRangeStart.addingTimeInterval(-180),
                        serviceTier: "priority"
                    ),
                    turnContext(
                        dailyRangeStart.addingTimeInterval(-120),
                        model: "gpt-5.4"
                    ),
                    token(
                        dailyRangeStart.addingTimeInterval(-60),
                        total: 100,
                        last: 100
                    ),
                    token(afterMidnight, total: 200, last: 100)
                ],
                name: "baseline-model-weighted.jsonl"
            )
            let baselineWeightedSnapshot = try CodexDailyTokenUsageReader.readRecentHours(
                from: [baselineWeighted.path],
                now: now,
                calendar: calendar
            )
            expect(
                baselineWeightedSnapshot.todayTokens == 100,
                "a pre-range Fast setting does not multiply the first counted call"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let absorbedChildCounter = write(
                [
                    sessionMeta(),
                    token(afterMidnight, total: 100, last: 100),
                    token(laterToday, total: 1_000, last: 100)
                ],
                name: "absorbed-child-counter.jsonl"
            )
            let absorbedChildValue = try CodexDailyTokenUsageReader.readToday(
                from: [absorbedChildCounter.path],
                now: now,
                calendar: calendar
            )
            expect(
                absorbedChildValue == 200,
                "message-level usage ignores cumulative jumps absorbed from child tasks"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let crossMidnight = write(
                [
                    sessionMeta(),
                    token(beforeMidnight, total: 1_000, last: 1_000),
                    token(afterMidnight, total: 1_200, last: 200),
                    token(laterToday, total: 50, last: 50)
                ],
                name: "cross-midnight.jsonl"
            )
            let crossValue = try CodexDailyTokenUsageReader.readToday(
                from: [crossMidnight.path],
                now: now,
                calendar: calendar
            )
            expect(crossValue == 250, "daily tokens keep midnight baseline and handle epoch resets")

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let firstToday = write(
                [sessionMeta(), token(afterMidnight, total: 1_000, last: 100)],
                name: "first-today.jsonl"
            )
            let firstValue = try CodexDailyTokenUsageReader.readToday(
                from: [firstToday.path],
                now: now,
                calendar: calendar
            )
            expect(firstValue == 100, "first daily absolute counter uses last usage as its baseline")

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let currentHourStart = calendar.dateInterval(of: .hour, for: now)!.start
            let firstHourlyStart = calendar.date(
                byAdding: .hour,
                value: -(CodexDailyTokenUsageReader.recentHourCount - 1),
                to: currentHourStart
            )!
            let historicalDay = calendar.date(
                byAdding: .day,
                value: -10,
                to: dayStart
            )!
            let hourlyWindow = write(
                [
                    sessionMeta(
                        startedAt: calendar.date(
                            byAdding: .day,
                            value: -15,
                            to: now
                        )
                    ),
                    token(
                        historicalDay.addingTimeInterval(60),
                        total: 40,
                        last: 40
                    ),
                    token(firstHourlyStart.addingTimeInterval(-60), total: 100, last: 100),
                    token(firstHourlyStart.addingTimeInterval(60), total: 160, last: 60),
                    token(currentHourStart.addingTimeInterval(60), total: 220, last: 60)
                ],
                name: "hourly-window.jsonl"
            )
            let hourlyValue = try CodexDailyTokenUsageReader.readRecentHours(
                from: [hourlyWindow.path],
                now: now,
                calendar: calendar
            )
            expect(
                hourlyValue.hourlyBuckets.count
                    == CodexDailyTokenUsageReader.recentHourCount,
                "hourly timeline always contains exactly 48 clock-hour buckets"
            )
            expect(
                hourlyValue.hourlyBuckets.first?.tokens == 60,
                "hourly timeline uses the event before its window as a cumulative baseline"
            )
            expect(
                hourlyValue.hourlyBuckets.last?.tokens == 60,
                "hourly timeline includes the current partial hour"
            )
            expect(
                hourlyValue.hourlyBuckets.reduce(Int64(0)) { $0 + $1.tokens } == 120,
                "hourly timeline excludes activity older than 48 clock hours"
            )
            let dailyFormatter = DateFormatter()
            dailyFormatter.locale = Locale(identifier: "en_US_POSIX")
            dailyFormatter.calendar = calendar
            dailyFormatter.timeZone = calendar.timeZone
            dailyFormatter.dateFormat = "yyyy-MM-dd"
            expect(
                hourlyValue.dailyBuckets.first {
                    $0.startDate == dailyFormatter.string(from: historicalDay)
                }?.tokens == 40,
                "local daily timeline retains message-level history for 30 days"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let rolloverHourStart = calendar.date(
                byAdding: .hour,
                value: 10,
                to: dayStart
            )!
            let rolloverEvent = rolloverHourStart.addingTimeInterval(30 * 60)
            let hourRollover = write(
                [
                    sessionMeta(
                        startedAt: rolloverHourStart.addingTimeInterval(-60)
                    ),
                    token(rolloverEvent, total: 80, last: 80)
                ],
                name: "hour-rollover.jsonl"
            )
            let beforeHourRollover = try CodexDailyTokenUsageReader.readRecentHours(
                from: [hourRollover.path],
                now: rolloverHourStart.addingTimeInterval(59 * 60),
                calendar: calendar
            )
            let beforeHourDiagnostics = CodexDailyTokenUsageReader
                .cacheDiagnosticsForTesting()
            let afterHourRollover = try CodexDailyTokenUsageReader.readRecentHours(
                from: [hourRollover.path],
                now: rolloverHourStart.addingTimeInterval(61 * 60),
                calendar: calendar
            )
            let afterHourDiagnostics = CodexDailyTokenUsageReader
                .cacheDiagnosticsForTesting()
            expect(
                beforeHourRollover.hourlyBuckets.last?.tokens == 80,
                "cached hourly usage starts in the current partial hour"
            )
            expect(
                hourlyTokens(
                    afterHourRollover.hourlyBuckets,
                    containing: rolloverEvent
                ) == 80
                    && afterHourRollover.hourlyBuckets.last?.tokens == 0
                    && afterHourRollover.todayTokens == 80,
                "the same cache rolls across an hour boundary without losing usage"
            )
            expect(
                beforeHourDiagnostics.baselineScanCount == 1
                    && afterHourDiagnostics == beforeHourDiagnostics,
                "hour rollover reuses the reducer without another baseline scan"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let futureHourStart = calendar.date(
                byAdding: .hour,
                value: 14,
                to: dayStart
            )!
            let futureHourEvent = futureHourStart.addingTimeInterval(0.25)
            let prewrittenFutureHour = write(
                [
                    sessionMeta(
                        startedAt: futureHourStart.addingTimeInterval(-120)
                    ),
                    token(futureHourEvent, total: 42, last: 42)
                ],
                name: "prewritten-future-hour.jsonl"
            )
            try FileManager.default.setAttributes(
                [.modificationDate: futureHourEvent],
                ofItemAtPath: prewrittenFutureHour.path
            )
            let beforeFutureHour = try CodexDailyTokenUsageReader.readRecentHours(
                from: [prewrittenFutureHour.path],
                now: futureHourStart.addingTimeInterval(-1),
                calendar: calendar
            )
            let afterFutureHour = try CodexDailyTokenUsageReader.readRecentHours(
                from: [prewrittenFutureHour.path],
                now: futureHourStart.addingTimeInterval(1),
                calendar: calendar
            )
            expect(
                beforeFutureHour.hourlyBuckets.last?.tokens == 0
                    && afterFutureHour.hourlyBuckets.last?.tokens == 42,
                "a prewritten next-hour event appears after rollover without another append"
            )
            expect(
                CodexDailyTokenUsageReader.cacheDiagnosticsForTesting()
                    .baselineScanCount == 1,
                "a prewritten next-hour event does not require a cold rescan"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let midnightRollover = write(
                [
                    sessionMeta(
                        startedAt: beforeMidnight.addingTimeInterval(-60)
                    ),
                    token(beforeMidnight, total: 75, last: 75)
                ],
                name: "midnight-rollover.jsonl"
            )
            let beforeMidnightRollover = try CodexDailyTokenUsageReader.readRecentHours(
                from: [midnightRollover.path],
                now: beforeMidnight.addingTimeInterval(30),
                calendar: calendar
            )
            expect(
                beforeMidnightRollover.todayTokens == 75,
                "usage immediately before midnight belongs to the old day"
            )
            try appendLines(
                [token(afterMidnight, total: 105, last: 30)],
                to: midnightRollover
            )
            let afterMidnightRollover = try CodexDailyTokenUsageReader.readRecentHours(
                from: [midnightRollover.path],
                now: afterMidnight.addingTimeInterval(30),
                calendar: calendar
            )
            expect(
                afterMidnightRollover.todayTokens == 30
                    && dailyTokens(
                        afterMidnightRollover.dailyBuckets,
                        containing: beforeMidnight
                    ) == 75
                    && dailyTokens(
                        afterMidnightRollover.dailyBuckets,
                        containing: afterMidnight
                    ) == 30,
                "the same cache rolls across midnight and separates both days"
            )
            expect(
                afterMidnightRollover.hourlyBuckets.reduce(Int64(0)) {
                    $0 + $1.tokens
                } == 105
                    && afterMidnightRollover.dailyBuckets.reduce(Int64(0)) {
                        $0 + $1.tokens
                    } == 105,
                "hourly and daily histories remain intact across midnight"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let prewrittenFutureDay = write(
                [
                    sessionMeta(
                        startedAt: beforeMidnight.addingTimeInterval(-60)
                    ),
                    token(afterMidnight, total: 30, last: 30)
                ],
                name: "prewritten-future-day.jsonl"
            )
            let beforeFutureDay = try CodexDailyTokenUsageReader.readRecentHours(
                from: [prewrittenFutureDay.path],
                now: dayStart.addingTimeInterval(-1),
                calendar: calendar
            )
            let afterFutureDay = try CodexDailyTokenUsageReader.readRecentHours(
                from: [prewrittenFutureDay.path],
                now: afterMidnight.addingTimeInterval(60),
                calendar: calendar
            )
            expect(
                beforeFutureDay.todayTokens == 0
                    && afterFutureDay.todayTokens == 30
                    && dailyTokens(
                        afterFutureDay.dailyBuckets,
                        containing: afterMidnight
                    ) == 30,
                "a prewritten next-day event enters today's totals after midnight"
            )
            expect(
                CodexDailyTokenUsageReader.cacheDiagnosticsForTesting()
                    .baselineScanCount == 1,
                "midnight rollover promotes a future daily bucket without rescanning"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let jumpEvent = calendar.date(
                byAdding: .minute,
                value: 70,
                to: dayStart
            )!
            let jumpInitialNow = calendar.date(
                byAdding: .minute,
                value: 90,
                to: dayStart
            )!
            let jumpRollover = write(
                [
                    sessionMeta(startedAt: dayStart),
                    token(jumpEvent, total: 55, last: 55)
                ],
                name: "multi-window-rollover.jsonl"
            )
            let jumpInitial = try CodexDailyTokenUsageReader.readRecentHours(
                from: [jumpRollover.path],
                now: jumpInitialNow,
                calendar: calendar
            )
            expect(
                jumpInitial.todayTokens == 55
                    && hourlyTokens(
                        jumpInitial.hourlyBuckets,
                        containing: jumpEvent
                    ) == 55,
                "forward-jump fixture starts inside the hourly and daily windows"
            )
            let afterSixHourJump = try CodexDailyTokenUsageReader.readRecentHours(
                from: [jumpRollover.path],
                now: jumpInitialNow.addingTimeInterval(6 * 60 * 60),
                calendar: calendar
            )
            expect(
                afterSixHourJump.todayTokens == 55
                    && hourlyTokens(
                        afterSixHourJump.hourlyBuckets,
                        containing: jumpEvent
                    ) == 55,
                "the same cache handles a multi-hour forward jump"
            )
            let afterThreeDayJump = try CodexDailyTokenUsageReader.readRecentHours(
                from: [jumpRollover.path],
                now: jumpInitialNow.addingTimeInterval(3 * 24 * 60 * 60),
                calendar: calendar
            )
            expect(
                afterThreeDayJump.todayTokens == 0
                    && afterThreeDayJump.hourlyBuckets.allSatisfy {
                        $0.tokens == 0
                    }
                    && dailyTokens(
                        afterThreeDayJump.dailyBuckets,
                        containing: jumpEvent
                    ) == 55,
                "a multi-day jump expires hourly usage while retaining 30-day history"
            )
            let afterThirtyFiveDayJump = try CodexDailyTokenUsageReader.readRecentHours(
                from: [jumpRollover.path],
                now: jumpInitialNow.addingTimeInterval(35 * 24 * 60 * 60),
                calendar: calendar
            )
            expect(
                afterThirtyFiveDayJump.todayTokens == 0
                    && afterThirtyFiveDayJump.hourlyBuckets.count
                        == CodexDailyTokenUsageReader.recentHourCount
                    && afterThirtyFiveDayJump.hourlyBuckets.allSatisfy {
                        $0.tokens == 0
                    }
                    && afterThirtyFiveDayJump.dailyBuckets.count
                        == CodexDailyTokenUsageReader.recentDayCount
                    && afterThirtyFiveDayJump.dailyBuckets.allSatisfy {
                        $0.tokens == 0
                    },
                "a large forward jump expires usage outside both rolling windows"
            )
            let beforeClockRewindDiagnostics = CodexDailyTokenUsageReader
                .cacheDiagnosticsForTesting()
            let afterClockRewind = try CodexDailyTokenUsageReader.readRecentHours(
                from: [jumpRollover.path],
                now: jumpInitialNow,
                calendar: calendar
            )
            expect(
                afterClockRewind.todayTokens == 55
                    && hourlyTokens(
                        afterClockRewind.hourlyBuckets,
                        containing: jumpEvent
                    ) == 55
                    && dailyTokens(
                        afterClockRewind.dailyBuckets,
                        containing: jumpEvent
                    ) == 55,
                "moving the clock backward rebuilds the cached windows correctly"
            )
            expect(
                beforeClockRewindDiagnostics.baselineScanCount == 1
                    && CodexDailyTokenUsageReader.cacheDiagnosticsForTesting()
                        .baselineScanCount == 2,
                "clock rewind intentionally performs one new baseline scan"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let appendHourStart = calendar.date(
                byAdding: .hour,
                value: 8,
                to: dayStart
            )!
            let firstAppendEvent = appendHourStart.addingTimeInterval(50 * 60)
            let appendAfterRollover = write(
                [
                    sessionMeta(
                        startedAt: appendHourStart.addingTimeInterval(-60)
                    ),
                    token(firstAppendEvent, total: 100, last: 100)
                ],
                name: "append-after-window-rollover.jsonl"
            )
            _ = try CodexDailyTokenUsageReader.readRecentHours(
                from: [appendAfterRollover.path],
                now: appendHourStart.addingTimeInterval(55 * 60),
                calendar: calendar
            )
            let appendRolledNow = appendHourStart.addingTimeInterval(65 * 60)
            let beforeRolloverAppend = try CodexDailyTokenUsageReader.readRecentHours(
                from: [appendAfterRollover.path],
                now: appendRolledNow,
                calendar: calendar
            )
            expect(
                beforeRolloverAppend.hourlyBuckets.last?.tokens == 0
                    && hourlyTokens(
                        beforeRolloverAppend.hourlyBuckets,
                        containing: firstAppendEvent
                    ) == 100,
                "the cache rolls before a new token is appended"
            )
            let secondAppendEvent = appendHourStart.addingTimeInterval(66 * 60)
            try appendLines(
                [token(secondAppendEvent, total: 160, last: 60)],
                to: appendAfterRollover
            )
            let afterRolloverAppend = try CodexDailyTokenUsageReader.readRecentHours(
                from: [appendAfterRollover.path],
                now: appendHourStart.addingTimeInterval(67 * 60),
                calendar: calendar
            )
            let repeatedAfterRolloverAppend = try CodexDailyTokenUsageReader
                .readRecentHours(
                    from: [appendAfterRollover.path],
                    now: appendHourStart.addingTimeInterval(67 * 60),
                    calendar: calendar
                )
            expect(
                afterRolloverAppend.todayTokens == 160
                    && hourlyTokens(
                        afterRolloverAppend.hourlyBuckets,
                        containing: firstAppendEvent
                    ) == 100
                    && hourlyTokens(
                        afterRolloverAppend.hourlyBuckets,
                        containing: secondAppendEvent
                    ) == 60
                    && afterRolloverAppend.hourlyBuckets.reduce(Int64(0)) {
                        $0 + $1.tokens
                    } == 160,
                "a token appended after window rollover is added to the new hour"
            )
            expect(
                repeatedAfterRolloverAppend == afterRolloverAppend,
                "an appended token remains counted exactly once after window rollover"
            )
            expect(
                CodexDailyTokenUsageReader.cacheDiagnosticsForTesting()
                    .baselineScanCount == 1,
                "an append after rollover uses the incremental cursor"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let forked = write(
                [
                    sessionMeta(forked: true, startedAt: laterToday),
                    token(laterToday, total: 9_900, last: 9_900),
                    threadSettings(
                        laterToday,
                        model: "gpt-5.6-sol",
                        modelProviderID: "openai",
                        serviceTier: "priority"
                    ),
                    sessionMeta(
                        forked: true,
                        startedAt: laterToday
                    ),
                    token(laterToday, total: 9_999, last: 99)
                ],
                name: "forked.jsonl"
            )
            let forkValue = try CodexDailyTokenUsageReader.readToday(
                from: [forked.path],
                now: now,
                calendar: calendar
            )
            expect(
                forkValue == 99,
                "forked rollout counts new model calls but skips copied history"
            )
            let forkUsage = try CodexDailyTokenUsageReader.readRecentHours(
                from: [forked.path],
                now: now,
                calendar: calendar,
                usesChatGPTCredits: true
            )
            expect(
                forkUsage.todayTokens == 99,
                "forked Fast usage counts only actual tokens after the activity boundary"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let pendingFork = write(
                [
                    sessionMeta(forked: true, startedAt: laterToday),
                    token(laterToday.addingTimeInterval(0.5), total: 9_000, last: 9_000)
                ],
                name: "pending-fork.jsonl"
            )
            let pendingForkValue = try CodexDailyTokenUsageReader.readToday(
                from: [pendingFork.path],
                now: now,
                calendar: calendar
            )
            expect(
                pendingForkValue == 0,
                "fork replay stays hidden until the fork's own first turn starts"
            )
            let pendingForkHandle = try FileHandle(forWritingTo: pendingFork)
            try pendingForkHandle.seekToEnd()
            try pendingForkHandle.write(contentsOf: Data(([
                sessionMeta(
                    forked: true,
                    startedAt: laterToday.addingTimeInterval(1)
                ),
                token(laterToday.addingTimeInterval(2), total: 9_080, last: 80)
            ].joined(separator: "\n") + "\n").utf8))
            try pendingForkHandle.close()
            let readyForkValue = try CodexDailyTokenUsageReader.readToday(
                from: [pendingFork.path],
                now: now,
                calendar: calendar
            )
            expect(
                readyForkValue == 80,
                "fork cache rebuilds when its real activity boundary is appended"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let subagent = write(
                [
                    sessionMeta(startedAt: laterToday, subagent: true),
                    threadSettings(
                        laterToday,
                        model: "gpt-5.6-sol",
                        modelProviderID: "openai",
                        serviceTier: "priority"
                    ),
                    token(laterToday, total: 500, last: 500),
                    subagentBoundary(laterToday, triggerTurn: false),
                    token(laterToday, total: 570, last: 70),
                    #"{"type":"response_item","payload":{"text":"inter_agent_communication_metadata"}}"#,
                    subagentBoundary(laterToday),
                    token(laterToday, total: 640, last: 70)
                ],
                name: "subagent.jsonl"
            )
            let subagentValue = try CodexDailyTokenUsageReader.readToday(
                from: [subagent.path],
                now: now,
                calendar: calendar
            )
            expect(
                subagentValue == 70,
                "subagent rollout treats timestamp-rewritten parent history as a baseline"
            )
            let subagentHourlyValue = try CodexDailyTokenUsageReader.readRecentHours(
                from: [subagent.path],
                now: now,
                calendar: calendar
            )
            expect(
                subagentHourlyValue.hourlyBuckets.reduce(Int64(0)) {
                    $0 + $1.tokens
                } == 70
                    && subagentHourlyValue.dailyBuckets.reduce(Int64(0)) {
                        $0 + $1.tokens
                    } == 70,
                "subagent Fast usage keeps actual tokens without counting replayed history"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let pendingSubagent = write(
                [
                    sessionMeta(startedAt: laterToday, subagent: true),
                    threadSettings(
                        laterToday,
                        model: "gpt-5.6-sol",
                        modelProviderID: "openai",
                        serviceTier: "priority"
                    ),
                    token(laterToday, total: 9_000, last: 9_000)
                ],
                name: "pending-subagent.jsonl"
            )
            let pendingValue = try CodexDailyTokenUsageReader.readToday(
                from: [pendingSubagent.path],
                now: now,
                calendar: calendar
            )
            expect(
                pendingValue == 0,
                "subagent history stays hidden until its activity boundary is committed"
            )

            let pendingHandle = try FileHandle(forWritingTo: pendingSubagent)
            try pendingHandle.seekToEnd()
            try pendingHandle.write(contentsOf: Data(([
                subagentBoundary(laterToday),
                token(laterToday, total: 9_080, last: 80)
            ].joined(separator: "\n") + "\n").utf8))
            try pendingHandle.close()
            let readyValue = try CodexDailyTokenUsageReader.readToday(
                from: [pendingSubagent.path],
                now: now,
                calendar: calendar
            )
            expect(
                readyValue == 80,
                "subagent cache rebuilds when the activity boundary is appended"
            )
            let readyUsage = try CodexDailyTokenUsageReader.readRecentHours(
                from: [pendingSubagent.path],
                now: now,
                calendar: calendar,
                usesChatGPTCredits: true
            )
            expect(
                readyUsage.todayTokens == 80,
                "appended subagent activity counts actual tokens after the boundary"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            func pricedInputToken(total: Int64) -> String {
                "{\"timestamp\":\"\(formatter.string(from: laterToday))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":\(total)},\"last_token_usage\":{\"input_tokens\":1000000,\"cached_input_tokens\":0,\"output_tokens\":0,\"total_tokens\":1000000}}}}"
            }
            let pricedChild = write(
                [
                    sessionMeta(startedAt: laterToday, subagent: true),
                    threadSettings(laterToday, model: "gpt-6-luna", serviceTier: "default"),
                    pricedInputToken(total: 1_000_000),
                    subagentBoundary(laterToday),
                    pricedInputToken(total: 2_000_000)
                ],
                name: "same-timestamp-priced-child.jsonl"
            )
            let childUsage = try CodexDailyTokenUsageReader.readRecentHours(
                from: [pricedChild.path], now: now, calendar: calendar
            )
            expect(
                childUsage.todayTokens == 1_000_000
                    && childUsage.chartCreditTotals.values.reduce(0) { $0 + $1.credits } == 2.5
                    && childUsage.chartCreditTotals.values.reduce(0) { $0 + $1.unpricedCalls } == 0,
                "same-timestamp inherited calls supply settings without adding tokens or credits"
            )
            try appendLines([pricedInputToken(total: 3_000_000)], to: pricedChild)
            let appendedChildUsage = try CodexDailyTokenUsageReader.readRecentHours(
                from: [pricedChild.path], now: now, calendar: calendar,
                priorityRolloutPaths: [pricedChild.path]
            )
            CodexDailyTokenUsageReader.resetCacheForTesting()
            let coldChildUsage = try CodexDailyTokenUsageReader.readRecentHours(
                from: [pricedChild.path], now: now, calendar: calendar
            )
            expect(
                appendedChildUsage == coldChildUsage
                    && coldChildUsage.todayTokens == 2_000_000
                    && coldChildUsage.chartCreditTotals.values.reduce(0) { $0 + $1.credits } == 5,
                "cold and appended child usage count each new call once across the byte boundary"
            )

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let partial = directory.appendingPathComponent("partial.jsonl")
            let second = token(laterToday, total: 160, last: 60)
            let split = second.index(second.startIndex, offsetBy: second.count / 2)
            let initial = [
                sessionMeta(),
                token(afterMidnight, total: 100, last: 100),
                String(second[..<split])
            ].joined(separator: "\n")
            try Data(initial.utf8).write(to: partial)
            try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: partial.path)
            let partialValue = try CodexDailyTokenUsageReader.readToday(
                from: [partial.path],
                now: now,
                calendar: calendar
            )
            expect(partialValue == 100, "unterminated token record is not counted early")

            let handle = try FileHandle(forWritingTo: partial)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((String(second[split...]) + "\n").utf8))
            try handle.close()
            let completedValue = try CodexDailyTokenUsageReader.readToday(
                from: [partial.path],
                now: now,
                calendar: calendar
            )
            expect(completedValue == 160, "completed appended token record is counted exactly once")

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let completeWithoutNewline = directory.appendingPathComponent(
                "complete-without-newline.jsonl"
            )
            let uncommitted = sessionMeta() + "\n"
                + token(afterMidnight, total: 100, last: 100)
            try Data(uncommitted.utf8).write(to: completeWithoutNewline)
            try FileManager.default.setAttributes(
                [.modificationDate: now],
                ofItemAtPath: completeWithoutNewline.path
            )
            let uncommittedValue = try CodexDailyTokenUsageReader.readToday(
                from: [completeWithoutNewline.path],
                now: now,
                calendar: calendar
            )
            expect(uncommittedValue == 0, "valid JSONL tail waits for its newline delimiter")

            let delimiterHandle = try FileHandle(forWritingTo: completeWithoutNewline)
            try delimiterHandle.seekToEnd()
            try delimiterHandle.write(contentsOf: Data("\n".utf8))
            try delimiterHandle.close()
            // Appending resets mtime to wall-clock time. Keep this fixture on
            // the test clock so it stays eligible for the next metadata poll.
            try FileManager.default.setAttributes(
                [.modificationDate: now],
                ofItemAtPath: completeWithoutNewline.path
            )
            let committedValue = try CodexDailyTokenUsageReader.readToday(
                from: [completeWithoutNewline.path],
                now: now,
                calendar: calendar
            )
            expect(committedValue == 100, "newline commits a previously complete JSONL tail")

            let replacement = sessionMeta() + "\n"
                + token(afterMidnight, total: 40, last: 40) + "\n"
            try Data(replacement.utf8).write(to: completeWithoutNewline)
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(1)],
                ofItemAtPath: completeWithoutNewline.path
            )
            let replacementValue = try CodexDailyTokenUsageReader.readToday(
                from: [completeWithoutNewline.path],
                now: now,
                calendar: calendar
            )
            expect(replacementValue == 40, "truncated rollout rebuilds its daily cache")

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let largeUnrelated = write(
                [
                    sessionMeta(),
                    token(beforeMidnight, total: 100, last: 100),
                    "{\"type\":\"response_item\",\"payload\":{\"text\":\""
                        + String(repeating: "x", count: 140_000)
                        + "\"}}",
                    token(afterMidnight, total: 160, last: 60)
                ],
                name: "large-unrelated.jsonl"
            )
            let largeValue = try CodexDailyTokenUsageReader.readToday(
                from: [largeUnrelated.path],
                now: now,
                calendar: calendar
            )
            expect(largeValue == 60, "oversized unrelated rollout rows do not break daily scanning")

            CodexDailyTokenUsageReader.resetCacheForTesting()
            let coldHistory = write(
                [
                    sessionMeta(),
                    token(afterMidnight, total: 10, last: 10)
                ],
                name: "cold-history.jsonl"
            )
            let liveHistory = write(
                [
                    sessionMeta(),
                    token(afterMidnight, total: 20, last: 20)
                ],
                name: "live-history.jsonl"
            )
            let inactiveModifiedAt = now.addingTimeInterval(-2 * 60 * 60)
            try FileManager.default.setAttributes(
                [.modificationDate: inactiveModifiedAt],
                ofItemAtPath: coldHistory.path
            )
            try FileManager.default.setAttributes(
                [.modificationDate: inactiveModifiedAt],
                ofItemAtPath: liveHistory.path
            )
            let splitPaths = [coldHistory.path, liveHistory.path]
            let initialSplitUsage = try CodexDailyTokenUsageReader.readRecentHours(
                from: splitPaths,
                now: now,
                calendar: calendar,
                priorityRolloutPaths: [liveHistory.path]
            )
            let initialPerformance = CodexDailyTokenUsageReader
                .performanceDiagnosticsForTesting()
            let repeatedSplitUsage = try CodexDailyTokenUsageReader.readRecentHours(
                from: splitPaths,
                now: now.addingTimeInterval(1),
                calendar: calendar,
                priorityRolloutPaths: [liveHistory.path]
            )
            let repeatedPerformance = CodexDailyTokenUsageReader
                .performanceDiagnosticsForTesting()
            expect(
                initialSplitUsage.todayTokens == 30
                    && repeatedSplitUsage == initialSplitUsage,
                "hot and cold rollout polling preserves the aggregated usage"
            )
            expect(
                initialPerformance.metadataCheckCount == 2
                    && repeatedPerformance.metadataCheckCount == 3,
                "one-second polling skips metadata checks for inactive history"
            )

            try appendLines(
                [token(laterToday, total: 15, last: 5)],
                to: coldHistory
            )
            let beforeHistoricalRefresh = try CodexDailyTokenUsageReader
                .readRecentHours(
                    from: splitPaths,
                    now: now.addingTimeInterval(2),
                    calendar: calendar,
                    priorityRolloutPaths: [liveHistory.path]
                )
            let afterHistoricalRefresh = try CodexDailyTokenUsageReader
                .readRecentHours(
                    from: splitPaths,
                    now: now.addingTimeInterval(31),
                    calendar: calendar,
                    priorityRolloutPaths: [liveHistory.path]
                )
            let refreshedPerformance = CodexDailyTokenUsageReader
                .performanceDiagnosticsForTesting()
            expect(
                beforeHistoricalRefresh.todayTokens == 30
                    && afterHistoricalRefresh.todayTokens == 35,
                "inactive history refreshes within the bounded 30-second interval"
            )
            expect(
                refreshedPerformance.metadataCheckCount == 6
                    && refreshedPerformance.aggregateRebuildCount == 0,
                "changed files update cached aggregates by delta"
            )
            let afterColdPathRemoval = try CodexDailyTokenUsageReader
                .readRecentHours(
                    from: [liveHistory.path],
                    now: now.addingTimeInterval(32),
                    calendar: calendar,
                    priorityRolloutPaths: [liveHistory.path]
                )
            expect(
                afterColdPathRemoval.todayTokens == 20,
                "removing a rollout path subtracts its cached aggregate"
            )

            let codexHome = directory.appendingPathComponent("codex-home")
            let sessions = codexHome
                .appendingPathComponent("sessions")
                .appendingPathComponent("2026/07/15")
            try FileManager.default.createDirectory(
                at: sessions,
                withIntermediateDirectories: true
            )
            let rootRollout = sessions.appendingPathComponent("root.jsonl")
            let forkRollout = sessions.appendingPathComponent("fork.jsonl")
            let subagentRollout = sessions.appendingPathComponent("subagent.jsonl")
            try Data((sessionMeta() + "\n").utf8).write(to: rootRollout)
            try Data((sessionMeta(forked: true) + "\n").utf8).write(to: forkRollout)
            try Data((sessionMeta(subagent: true) + "\n").utf8).write(to: subagentRollout)
            try FileManager.default.setAttributes(
                [.modificationDate: now],
                ofItemAtPath: rootRollout.path
            )
            try FileManager.default.setAttributes(
                [.modificationDate: now],
                ofItemAtPath: forkRollout.path
            )
            try FileManager.default.setAttributes(
                [.modificationDate: now],
                ofItemAtPath: subagentRollout.path
            )

            let originalCodexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
            setenv("CODEX_HOME", codexHome.path, 1)
            let discovered = try CodexDailyTokenUsageReader
                .discoverLocalUsageRollouts(now: now, calendar: calendar)
            if let originalCodexHome {
                setenv("CODEX_HOME", originalCodexHome, 1)
            } else {
                unsetenv("CODEX_HOME")
            }
            expect(
                discovered == [
                    forkRollout.path,
                    rootRollout.path,
                    subagentRollout.path
                ].sorted(),
                "local rollout discovery includes roots, forks, and subagents"
            )
        } catch {
            expect(false, "daily token usage reader: \(error.localizedDescription)")
        }
    }

    private static func checkRecentThreads() {
        let rows: [JSONObject] = (1...6).map { index in
            [
                "id": "thread-\(index)",
                "name": "会话 \(index)",
                "source": index.isMultiple(of: 2) ? "vscode" : "cli",
                "status": ["type": "notLoaded"],
                "updatedAt": 2_000_000_000 - index
            ]
        }
        let threads = CodexStatusPayloadParser.parseRecentThreads(["data": rows])
        expect(threads.count == 5, "recent thread limit")
        expect(
            threads.map(\.id) == ["thread-1", "thread-2", "thread-3", "thread-4", "thread-5"],
            "recent thread order"
        )
        expect(
            threads.map(\.clientSource) == [.tui, .app, .tui, .app, .tui],
            "CLI and Desktop thread sources map to TUI and APP"
        )

        let sourceVariants = CodexStatusPayloadParser.parseRecentThreads([
            "data": [
                ["id": "trimmed-cli", "source": "  CLI \n"],
                ["id": "uppercase-vscode", "source": "VSCODE"],
                ["id": "exec", "source": "exec"],
                ["id": "app-server", "source": "appServer"],
                ["id": "custom", "source": ["custom": "example"]]
            ]
        ])
        expect(
            sourceVariants.map(\.clientSource) == [.tui, .app, nil, nil, nil],
            "only cli and vscode receive visible source labels"
        )

        let missingIDRows: [JSONObject] = [
            [
                "name": "无 ID 会话 A",
                "path": "/Users/test/.codex/sessions/rollout-fallback-a.jsonl",
                "status": ["type": "notLoaded"],
                "updatedAt": 2_000_000_100
            ],
            [
                "name": "无 ID 会话 B",
                "path": "/Users/test/.codex/sessions/rollout-fallback-b.jsonl",
                "status": ["type": "active"],
                "updatedAt": 2_000_000_200
            ],
            ["id": "  \n", "name": "空白 ID 旧会话"],
            ["name": "完全相同的旧 payload"],
            ["name": "完全相同的旧 payload"]
        ]
        let firstParse = CodexStatusPayloadParser.parseRecentThreads([
            "data": missingIDRows
        ])
        let secondParse = CodexStatusPayloadParser.parseRecentThreads([
            "data": missingIDRows
        ])
        expect(
            firstParse.allSatisfy { !$0.id.isEmpty },
            "missing thread IDs receive non-empty fallbacks"
        )
        expect(
            Set(firstParse.map(\.id)).count == missingIDRows.count,
            "multiple missing thread IDs remain unique, including duplicate payloads"
        )
        expect(
            firstParse.map(\.id) == secondParse.map(\.id),
            "fallback thread IDs are reproducible for the same payload"
        )

        let changedMetadata: [JSONObject] = [[
            "name": "重命名后的会话",
            "path": "/Users/test/.codex/sessions/rollout-fallback-a.jsonl",
            "status": ["type": "active"],
            "updatedAt": 2_000_999_999
        ]]
        expect(
            CodexStatusPayloadParser.parseRecentThreads(["data": changedMetadata]).first?.id
                == firstParse.first?.id,
            "rollout path keeps a fallback identity stable across mutable metadata changes"
        )

        let alternateID = CodexStatusPayloadParser.parseRecentThreads([
            "data": [["threadId": "legacy-thread-id", "name": "旧字段会话"]]
        ]).first
        expect(
            alternateID?.id == "legacy-thread-id",
            "legacy stable thread ID fields are preferred over synthetic fallbacks"
        )
    }
}

private enum LaunchAtLoginTestError: Error {
    case operationFailed
}

private final class FakeLaunchAtLoginService {
    var status: LaunchAtLoginServiceStatus
    var statusAfterRegister: LaunchAtLoginServiceStatus?
    var statusAfterUnregister: LaunchAtLoginServiceStatus?
    var registerError: Error?
    var unregisterError: Error?
    private(set) var statusReadCount = 0
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(status: LaunchAtLoginServiceStatus) {
        self.status = status
    }

    var backend: LaunchAtLoginBackend {
        LaunchAtLoginBackend(
            readStatus: { [self] in
                statusReadCount += 1
                return status
            },
            register: { [self] in
                registerCallCount += 1
                if let registerError { throw registerError }
                if let statusAfterRegister { status = statusAfterRegister }
            },
            unregister: { [self] in
                unregisterCallCount += 1
                if let unregisterError { throw unregisterError }
                if let statusAfterUnregister { status = statusAfterUnregister }
            }
        )
    }
}
