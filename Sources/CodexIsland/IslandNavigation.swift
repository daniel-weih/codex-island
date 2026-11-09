import Combine
import Foundation

enum IslandPage: String, Equatable {
    case dashboard, islandSettings, modelInformation

    var isModelInformationPage: Bool { self == .modelInformation }
}

@MainActor
final class IslandNavigation: ObservableObject {
    @Published private(set) var page: IslandPage
    private var returnPage: IslandPage = .dashboard

    init(page: IslandPage = .dashboard) { self.page = page }

    func navigate(to page: IslandPage) {
        if page.isModelInformationPage && !self.page.isModelInformationPage {
            returnPage = self.page
        }
        self.page = page
    }

    func back() {
        page = page.isModelInformationPage ? returnPage : .dashboard
    }

    func toggleModelInformation() {
        if page.isModelInformationPage { back() }
        else { navigate(to: .modelInformation) }
    }

    func reset() {
        returnPage = .dashboard
        guard page != .dashboard else { return }
        page = .dashboard
    }
}
