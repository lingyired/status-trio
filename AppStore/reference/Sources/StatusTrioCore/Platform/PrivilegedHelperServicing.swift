import Combine
import Foundation
import SwiftUI

@MainActor
protocol PrivilegedHelperServicingFacade: AnyObject {
    var presentation: PrivilegedHelperPresentation { get }
    var presentationPublisher: AnyPublisher<PrivilegedHelperPresentation, Never> { get }
    func setEnabled(_ enabled: Bool)
    func restoreUserIntent(_ enabled: Bool)
    func refresh()
    func refreshAfterActivation()
    func openLoginItemsSettings()
}

@MainActor
final class PrivilegedHelperFacade: ObservableObject {
    @Published private(set) var presentation: PrivilegedHelperPresentation

    let service: any PrivilegedHelperServicingFacade
    private var cancellable: AnyCancellable?

    init(service: any PrivilegedHelperServicingFacade) {
        self.service = service
        presentation = service.presentation
        cancellable = service.presentationPublisher
            .removeDuplicates()
            .sink { [weak self] presentation in
                guard let self, self.presentation != presentation else { return }
                self.presentation = presentation
            }
    }

    var isAvailable: Bool { presentation.isAvailable }
    var isEnabled: Bool { presentation.isEnabled }
    var requiresApproval: Bool { presentation.requiresApproval }
    var isReady: Bool { presentation.isReady }
    var didFailLastOperation: Bool { presentation.didFailLastOperation }
    var lastErrorMessage: String? { presentation.lastErrorMessage }

    var isEnabledBinding: Binding<Bool> {
        Binding(
            get: { [weak self] in self?.isEnabled ?? false },
            set: { [weak self] in self?.setEnabled($0) }
        )
    }

    func setEnabled(_ enabled: Bool) {
        service.setEnabled(enabled)
        refreshPresentation()
    }

    func restoreUserIntent(_ enabled: Bool) {
        service.restoreUserIntent(enabled)
        refreshPresentation()
    }

    func refresh() {
        service.refresh()
        refreshPresentation()
    }

    func refreshAfterActivation() {
        service.refreshAfterActivation()
        refreshPresentation()
    }

    func openLoginItemsSettings() {
        service.openLoginItemsSettings()
    }

    private func refreshPresentation() {
        if presentation != service.presentation {
            presentation = service.presentation
        }
    }
}

@MainActor
final class UnsupportedPrivilegedHelperService: PrivilegedHelperServicingFacade {
    let presentation = PrivilegedHelperPresentation.unsupported
    var presentationPublisher: AnyPublisher<PrivilegedHelperPresentation, Never> {
        Just(presentation).eraseToAnyPublisher()
    }

    func setEnabled(_ enabled: Bool) {}
    func restoreUserIntent(_ enabled: Bool) {}
    func refresh() {}
    func refreshAfterActivation() {}
    func openLoginItemsSettings() {}
}
