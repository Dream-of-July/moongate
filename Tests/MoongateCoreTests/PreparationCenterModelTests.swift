import XCTest
@testable import Moongate
@testable import MoongateCore

@MainActor
final class PreparationCenterModelTests: XCTestCase {
    func testRefreshPublishesInjectedReadinessSnapshot() async {
        let expected = ComponentPreparationSnapshot(items: [fixtureItem(status: .ready())])
        let model = PreparationCenterModel(refreshOperation: { expected })

        model.refresh()
        await waitForRefresh(of: model)

        XCTAssertEqual(model.snapshot, expected)
        XCTAssertEqual(model.refreshState, .idle)
        XCTAssertEqual(model.items.map(\.id), ["fixture.toolchain"])
    }

    func testRefreshFailureRemainsVisibleInsteadOfPretendingComponentsAreReady() async {
        let model = PreparationCenterModel(refreshOperation: {
            throw PreparationFixtureError.unavailable
        })

        model.refresh()
        await waitForRefresh(of: model)

        guard case .failed(let message) = model.refreshState else {
            return XCTFail("Expected the preparation center to expose its refresh failure")
        }
        XCTAssertTrue(message.contains("fixture unavailable"))
        XCTAssertNil(model.snapshot)
    }

    private func waitForRefresh(of model: PreparationCenterModel) async {
        for _ in 0 ..< 40 where model.isRefreshing {
            await Task.yield()
        }
    }

    private func fixtureItem(status: ComponentReadiness) -> ComponentPreparationItem {
        ComponentPreparationItem(
            component: Component(
                id: "fixture.toolchain",
                displayName: "Fixture toolchain",
                kind: .downloadToolchain,
                capabilities: [.mediaDownload],
                source: .existingDependencySetup,
                installPolicy: .existingDependencySetup,
                isOptional: false,
                readiness: status
            ),
            sourceDetail: "fixture",
            allowedOperations: [.refresh]
        )
    }
}

private enum PreparationFixtureError: LocalizedError {
    case unavailable

    var errorDescription: String? { "fixture unavailable" }
}
