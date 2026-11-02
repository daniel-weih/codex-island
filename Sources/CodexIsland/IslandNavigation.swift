import Combine
import Foundation

enum IslandPage: String, Equatable {
    case dashboard, islandSettings, configurationSettings

    var isConfigurationPage: Bool { self == .configurationSettings }
}

@MainActor
final class IslandNavigation: ObservableObject {
    @Published private(set) var page: IslandPage
    private var returnPage: IslandPage = .dashboard

    init(page: IslandPage = .dashboard) { self.page = page }

    func navigate(to page: IslandPage) {
        if page.isConfigurationPage && !self.page.isConfigurationPage {
            returnPage = self.page
        }
        self.page = page
    }

    func back() {
        page = page.isConfigurationPage ? returnPage : .dashboard
    }

    func reset() {
        returnPage = .dashboard
        guard page != .dashboard else { return }
        page = .dashboard
    }
}
