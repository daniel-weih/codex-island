import Foundation

enum CreditChartLegendKind: String, Equatable, Sendable {
    case standard
    case actual
}

enum IslandPopoverContent: Equatable {
    case token(threadID: String, rank: Int, usage: ThreadTokenUsage)
    case context(threadID: String, rank: Int, usage: ThreadTokenUsage?)
    case reset(ResetCreditSummary)
    case chartLegend(CreditChartLegendKind)

    var identity: String {
        switch self {
        case .token(let threadID, _, _): return "token-\(threadID)"
        case .context(let threadID, _, _): return "context-\(threadID)"
        case .reset: return "reset"
        case .chartLegend(let kind): return "chart-legend-\(kind.rawValue)"
        }
    }

    /// Mouse movement selects the anchor; refreshes supply the displayed values.
    /// A moved/removed row must dismiss its tooltip instead of attaching old
    /// thread data to whichever row now occupies the pointer position.
    func resolved(in snapshot: CodexSnapshot) -> IslandPopoverContent? {
        switch self {
        case .token(let threadID, let rank, _), .context(let threadID, let rank, _):
            let threads = CodexDisplayPolicy.visibleRecentThreads(from: snapshot.recentThreads)
            guard threads.indices.contains(rank), threads[rank].id == threadID else { return nil }
            let usage = threads[rank].tokenUsage
            if case .token = self {
                guard let usage else { return nil }
                return .token(threadID: threadID, rank: rank, usage: usage)
            }
            return .context(threadID: threadID, rank: rank, usage: usage)
        case .reset:
            guard let summary = snapshot.resetCredits, summary.availableCount > 0 else { return nil }
            return .reset(summary)
        case .chartLegend:
            return self
        }
    }
}
