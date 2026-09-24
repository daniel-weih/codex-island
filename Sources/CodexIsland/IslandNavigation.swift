import Combine
import Foundation

enum IslandPage: String, Equatable {
    case dashboard, islandSettings, resetDetails, resetSettings

    var isSubscriptionPage: Bool { self == .resetDetails || self == .resetSettings }
}

@MainActor
final class IslandNavigation: ObservableObject {
    @Published private(set) var page: IslandPage
    private var returnPage: IslandPage = .dashboard

    init(page: IslandPage = .dashboard) { self.page = page }

    func navigate(to page: IslandPage) {
        if page.isSubscriptionPage && !self.page.isSubscriptionPage {
            returnPage = self.page
        }
        self.page = page
    }

    func back() {
        page = page.isSubscriptionPage ? returnPage : .dashboard
    }

    func reset() {
        returnPage = .dashboard
        guard page != .dashboard else { return }
        page = .dashboard
    }
}
