import Darwin
import Foundation

@main
struct ParserChecks {
    private static var failures = 0

    static func main() {
        checkRateLimitsAndResetCredits()
        checkCodexBucketPreference()
        checkTokenConsumptionPolicy()
        checkAccountUsageThreadAndModel()
        checkPlanBadgeLabels()
        checkThreadDeepLinks()
        checkUsageTimeline()
        checkRecentThreads()
        checkEffectiveServiceTier()
        checkThreadRuntimeSettings()
        checkThreadActivityStates()
        checkDailyTokenUsage()

        guard failures == 0 else {
            fputs("\(failures) parser check(s) failed\n", stderr)
            exit(EXIT_FAILURE)
        }
        print("All parser checks passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard !condition() else { return }
        failures += 1
        fputs("FAIL: \(message)\n", stderr)
    }

    private static func checkPlanBadgeLabels() {
        expect(
            CodexDisplayPolicy.planBadgeLabel(
                accountPlanType: "pro",
                rateLimitPlanType: "prolite"
            ) == "PRO 5X",
            "Pro Lite quota bucket displays 5X"
        )
        expect(
            CodexDisplayPolicy.planBadgeLabel(
                accountPlanType: "pro",
                rateLimitPlanType: "pro"
            ) == "PRO 20X",
            "Pro quota bucket displays 20X"
        )
        expect(
            CodexDisplayPolicy.planBadgeLabel(
                accountPlanType: "pro",
                rateLimitPlanType: nil
            ) == "PRO",
            "missing Pro subtype stays generic"
        )
        expect(
            CodexDisplayPolicy.planBadgeLabel(
                accountPlanType: nil,
                rateLimitPlanType: " PROLITE "
            ) == "PRO 5X",
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
        let timeline = CodexUsageTimeline.lastCompletedDays(
            from: [
                DailyUsageBucket(startDate: "2026-07-14", tokens: 140),
                DailyUsageBucket(startDate: "2026-07-12", tokens: 120),
                DailyUsageBucket(startDate: "2026-07-12", tokens: 3)
            ],
            count: 5,
            now: now,
            calendar: calendar
        )

        expect(timeline.count == 5, "usage timeline has one entry per calendar day")
        expect(timeline.first?.startDate == "2026-07-10", "usage timeline starts four days ago")
        expect(timeline.last?.startDate == "2026-07-14", "usage timeline ends yesterday")
        expect(timeline[1].tokens == 0, "missing usage date is filled with zero")
        expect(timeline[2].tokens == 123, "duplicate usage dates are combined")

        var shanghaiCalendar = Calendar(identifier: .gregorian)
        shanghaiCalendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let newYearNow = shanghaiCalendar.date(
            from: DateComponents(year: 2026, month: 1, day: 2, hour: 12)
        )!
        let newYearTimeline = CodexUsageTimeline.lastCompletedDays(
            from: [],
            count: 3,
            now: newYearNow,
            calendar: shanghaiCalendar
        )
        expect(
            newYearTimeline.map(\.startDate)
                == ["2025-12-30", "2025-12-31", "2026-01-01"],
            "usage timeline crosses month and year boundaries"
        )

        var losAngelesCalendar = Calendar(identifier: .gregorian)
        losAngelesCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let daylightSavingNow = losAngelesCalendar.date(
            from: DateComponents(year: 2026, month: 3, day: 10, hour: 12)
        )!
        let daylightSavingTimeline = CodexUsageTimeline.lastCompletedDays(
            from: [],
            count: 5,
            now: daylightSavingNow,
            calendar: losAngelesCalendar
        )
        expect(
            daylightSavingTimeline.map(\.startDate)
                == ["2026-03-05", "2026-03-06", "2026-03-07", "2026-03-08", "2026-03-09"],
            "usage timeline keeps calendar-day continuity across daylight saving time"
        )
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
    }

    private static func checkEffectiveServiceTier() {
        let fast = CodexStatusPayloadParser.parseEffectiveServiceTier([
            "config": ["service_tier": "priority"]
        ])
        expect(fast == "priority", "effective Fast service tier")

        let standard = CodexStatusPayloadParser.parseEffectiveServiceTier([
            "config": [:]
        ])
        expect(standard == "default", "missing service tier means Standard")

        let featureDisabled = CodexStatusPayloadParser.parseEffectiveServiceTier([
            "config": [
                "service_tier": "priority",
                "features": ["fast_mode": false]
            ]
        ])
        expect(featureDisabled == "default", "disabled Fast feature means Standard")
        expect(
            CodexStatusPayloadParser.parseEffectiveServiceTier([:]) == nil,
            "invalid config response stays unknown"
        )
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

            let token1 = #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":2929630,"cached_input_tokens":2806528,"output_tokens":19878,"reasoning_output_tokens":2428,"total_tokens":2949508}}}}"# + "\n"
            try append(token1)
            let usage1 = try snapshot().tokenUsage
            expect(usage1?.inputTokens == 2_929_630, "cumulative input token count")
            expect(usage1?.cachedInputTokens == 2_806_528, "cumulative cached token count")
            expect(usage1?.outputTokens == 19_878, "cumulative output token count")
            expect(usage1?.reasoningOutputTokens == 2_428, "cumulative reasoning token count")
            expect(usage1?.totalTokens == 2_949_508, "cumulative total token count")

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

            let start4 = #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-4"}}"# + "\n"
            let delayedOldComplete = #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-old"}}"# + "\n"
            try append(start4 + delayedOldComplete)
            try expectState(.running, "old turn completion does not stop active turn")

            let complete4 = #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-4"}}"# + "\n"
            try append(complete4)
            try expectState(.idle, "matching completion stops active turn")

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

        func sessionMeta(forked: Bool = false) -> String {
            let forkField = forked ? ",\"forked_from_id\":\"parent\"" : ""
            return "{\"timestamp\":\"\(formatter.string(from: afterMidnight))\",\"type\":\"session_meta\",\"payload\":{\"id\":\"test\",\"source\":\"cli\",\"thread_source\":\"user\"\(forkField)}}"
        }

        func token(_ date: Date, total: Int64, last: Int64?) -> String {
            let lastField = last.map {
                ",\"last_token_usage\":{\"total_tokens\":\($0)}"
            } ?? ""
            return "{\"timestamp\":\"\(formatter.string(from: date))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":\(total)}\(lastField)}}}"
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

        do {
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
            expect(value == 220, "daily tokens use absolute deltas and ignore replayed last usage")

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
            let forked = write(
                [sessionMeta(forked: true), token(afterMidnight, total: 9_999, last: 99)],
                name: "forked.jsonl"
            )
            let forkValue = try CodexDailyTokenUsageReader.readToday(
                from: [forked.path],
                now: now,
                calendar: calendar
            )
            expect(forkValue == 0, "forked rollout history is excluded from daily aggregation")

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
            try Data((sessionMeta() + "\n").utf8).write(to: rootRollout)
            try Data((sessionMeta(forked: true) + "\n").utf8).write(to: forkRollout)
            try FileManager.default.setAttributes(
                [.modificationDate: now],
                ofItemAtPath: rootRollout.path
            )
            try FileManager.default.setAttributes(
                [.modificationDate: now],
                ofItemAtPath: forkRollout.path
            )

            let originalCodexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
            setenv("CODEX_HOME", codexHome.path, 1)
            let discovered = try CodexDailyTokenUsageReader
                .discoverRootConversationRollouts(now: now, calendar: calendar)
            if let originalCodexHome {
                setenv("CODEX_HOME", originalCodexHome, 1)
            } else {
                unsetenv("CODEX_HOME")
            }
            expect(
                discovered == [rootRollout.path],
                "local rollout discovery includes root CLI/App sessions and excludes forks"
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
