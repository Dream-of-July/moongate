import Combine
import Foundation

/// Shared observable state for onboarding and Settings' preparation center.
///
/// The model owns only readiness inspection. It deliberately does not turn a
/// missing ASR runtime into a synthetic download: callers receive the real
/// `ComponentPreparationItem` actions and decide whether an existing settings
/// flow can perform them.
@MainActor
final class PreparationCenterModel: ObservableObject {
    enum RefreshState: Equatable {
        case idle
        case refreshing
        case cancelling
        case failed(String)

        var isInFlight: Bool {
            switch self {
            case .refreshing, .cancelling:
                true
            case .idle, .failed:
                false
            }
        }

        var message: String? {
            switch self {
            case .idle:
                nil
            case .refreshing:
                "正在检查组件…"
            case .cancelling:
                "正在取消检查…"
            case .failed(let message):
                message
            }
        }
    }

    @Published private(set) var snapshot: ComponentPreparationSnapshot?
    @Published private(set) var refreshState: RefreshState = .idle

    private let refreshOperation: @Sendable () async throws -> ComponentPreparationSnapshot
    private var refreshTask: Task<Void, Never>?
    private var activeRefreshID: UUID?

    /// The default uses the app's cache-aware, UI-neutral preparation service.
    /// A throwing operation can be injected by a focused test without teaching
    /// the production UI about transport details.
    init(
        service: ComponentPreparationService = ComponentPreparationService(),
        refreshOperation: (@Sendable () async throws -> ComponentPreparationSnapshot)? = nil
    ) {
        self.refreshOperation = refreshOperation ?? { await service.refresh() }
    }

    deinit {
        refreshTask?.cancel()
    }

    var items: [ComponentPreparationItem] {
        snapshot?.items ?? []
    }

    var isRefreshing: Bool {
        refreshState.isInFlight
    }

    /// Starts the first readiness check only when this shared model has no
    /// result yet. Reopening Settings therefore does not repeatedly hash large
    /// local model files.
    func refreshIfNeeded() {
        guard snapshot == nil, !refreshState.isInFlight else { return }
        refresh()
    }

    /// Starts a fresh cache-aware inspection. The existing inspection remains
    /// cancellable instead of competing with a second checksum pass.
    func refresh() {
        guard refreshTask == nil else { return }

        let refreshID = UUID()
        activeRefreshID = refreshID
        refreshState = .refreshing
        let operation = refreshOperation
        refreshTask = Task { [weak self, operation] in
            do {
                let snapshot = try await operation()
                guard let self else { return }
                if Task.isCancelled {
                    self.finishCancellation(refreshID: refreshID)
                } else {
                    self.finishRefresh(snapshot, refreshID: refreshID)
                }
            } catch is CancellationError {
                self?.finishCancellation(refreshID: refreshID)
            } catch {
                self?.finishFailure(error, refreshID: refreshID)
            }
        }
    }

    /// Cancels the UI request and waits until the current inspection has
    /// unwound before becoming idle. The service itself is local/read-only, so
    /// no component installation or settings change is rolled back here.
    func cancelRefresh() {
        guard refreshTask != nil else { return }
        refreshState = .cancelling
        refreshTask?.cancel()
    }

    func clearRefreshError() {
        guard case .failed = refreshState else { return }
        refreshState = .idle
    }

    private func finishRefresh(_ snapshot: ComponentPreparationSnapshot, refreshID: UUID) {
        guard activeRefreshID == refreshID else { return }
        self.snapshot = snapshot
        activeRefreshID = nil
        refreshTask = nil
        refreshState = .idle
    }

    private func finishCancellation(refreshID: UUID) {
        guard activeRefreshID == refreshID else { return }
        activeRefreshID = nil
        refreshTask = nil
        refreshState = .idle
    }

    private func finishFailure(_ error: Error, refreshID: UUID) {
        guard activeRefreshID == refreshID else { return }
        activeRefreshID = nil
        refreshTask = nil
        let message = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
        refreshState = .failed(message.isEmpty ? "无法检查组件状态。" : message)
    }
}
