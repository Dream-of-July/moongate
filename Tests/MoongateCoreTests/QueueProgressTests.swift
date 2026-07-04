import XCTest
@testable import MoongateCore

final class QueueProgressTests: XCTestCase {
    func testTaskOverallProgressStaysMonotonicWhenPhasePercentFallsBack() throws {
        let plan = QueueProgressPlan(shouldTranscode: true, shouldTranslate: true, shouldBurn: true)

        let afterDownload = try XCTUnwrap(QueueProgressEstimator.taskOverallProgress(
            plan: plan,
            currentPhase: .download,
            phaseProgress: 1.0,
            previousOverallProgress: nil
        ))
        let secondStreamRestart = try XCTUnwrap(QueueProgressEstimator.taskOverallProgress(
            plan: plan,
            currentPhase: .download,
            phaseProgress: 0.05,
            previousOverallProgress: afterDownload
        ))
        let translating = try XCTUnwrap(QueueProgressEstimator.taskOverallProgress(
            plan: plan,
            currentPhase: .translate,
            phaseProgress: 0.10,
            previousOverallProgress: secondStreamRestart
        ))

        XCTAssertEqual(afterDownload, 0.25, accuracy: 0.0001)
        XCTAssertEqual(secondStreamRestart, afterDownload, accuracy: 0.0001)
        XCTAssertGreaterThan(translating, secondStreamRestart)
    }

    func testTaskWorkPlanWeightsASRHeavyTasksByUnits() throws {
        let plan = TaskWorkPlan(
            shouldExtractAudio: true,
            shouldRunASR: true,
            shouldSegmentSubtitles: true,
            shouldTranscode: false,
            shouldTranslate: true,
            shouldBurn: false,
            downloadUnits: 2,
            audioExtractUnits: 1,
            speechRecognitionUnits: 12,
            subtitleSegmentUnits: 1,
            translateUnits: 2
        )

        let downloadDone = try XCTUnwrap(QueueProgressEstimator.taskOverallProgress(
            workPlan: plan,
            currentPhase: .download,
            phaseProgress: 1,
            previousOverallProgress: nil
        ))
        let halfASR = try XCTUnwrap(QueueProgressEstimator.taskOverallProgress(
            workPlan: plan,
            currentPhase: .speechRecognition,
            phaseProgress: 0.5,
            previousOverallProgress: downloadDone
        ))

        XCTAssertEqual(downloadDone, 2.0 / 18.0, accuracy: 0.0001)
        XCTAssertEqual(halfASR, 9.0 / 18.0, accuracy: 0.0001)
        XCTAssertLessThan(downloadDone, 0.25)
    }

    func testEtaParsingAndSlopeRemaining() throws {
        XCTAssertEqual(QueueProgressEstimator.parseEtaSeconds("00:45"), 45)
        XCTAssertEqual(QueueProgressEstimator.parseEtaSeconds("01:02:03"), 3723)
        XCTAssertNil(QueueProgressEstimator.parseEtaSeconds("Unknown"))

        let remaining = try XCTUnwrap(QueueProgressEstimator.estimatedRemainingSeconds(
            elapsedSeconds: 10,
            phaseProgress: 0.25,
            sourceEtaSeconds: nil
        ))

        XCTAssertEqual(remaining.seconds, 30, accuracy: 0.0001)
        XCTAssertEqual(remaining.isApproximate, true)
    }

    func testQueueSnapshotAveragesOverallProgressAndUsesLongestKnownRemaining() {
        let snapshot = QueueProgressEstimator.queueSnapshot(items: [
            TaskProgressSnapshot(overallProgress: 0.50, remainingSeconds: 120, isEstimatingRemaining: false, isTerminal: false),
            TaskProgressSnapshot(overallProgress: 0.25, remainingSeconds: 300, isEstimatingRemaining: false, isTerminal: false),
            TaskProgressSnapshot(overallProgress: nil, remainingSeconds: nil, isEstimatingRemaining: true, isTerminal: false),
            TaskProgressSnapshot(overallProgress: 1.0, remainingSeconds: nil, isEstimatingRemaining: false, isTerminal: true),
        ])

        XCTAssertEqual(snapshot.overallProgress, 0.4375, accuracy: 0.0001)
        XCTAssertEqual(snapshot.remainingSeconds, 300)
        XCTAssertTrue(snapshot.isEstimatingRemaining)
    }

    func testQueueSnapshotUsesPhaseMediansForQueuedWork() {
        let plan = QueueProgressPlan(shouldTranscode: false, shouldTranslate: true, shouldBurn: true)
        let snapshot = QueueProgressEstimator.queueSnapshot(
            items: [
                TaskProgressSnapshot(
                    overallProgress: nil,
                    remainingSeconds: nil,
                    isEstimatingRemaining: false,
                    isTerminal: false,
                    plan: plan,
                    currentPhase: nil
                ),
            ],
            phaseMedianDurations: [
                .download: 60,
                .translate: 120,
                .burn: 180,
            ],
            phaseCapacities: [
                .download: 2,
                .translate: 1,
                .burn: 1,
            ]
        )

        XCTAssertEqual(try XCTUnwrap(snapshot.remainingSeconds), 360, accuracy: 0.0001)
        XCTAssertFalse(snapshot.isEstimatingRemaining)
    }

    func testQueueSnapshotStaysEstimatingWhenQueuedWorkLacksSamples() {
        let plan = QueueProgressPlan(shouldTranscode: false, shouldTranslate: true, shouldBurn: true)
        let snapshot = QueueProgressEstimator.queueSnapshot(
            items: [
                TaskProgressSnapshot(
                    overallProgress: nil,
                    remainingSeconds: nil,
                    isEstimatingRemaining: false,
                    isTerminal: false,
                    plan: plan,
                    currentPhase: nil
                ),
            ],
            phaseMedianDurations: [
                .download: 60,
            ],
            phaseCapacities: [
                .download: 2,
                .translate: 1,
                .burn: 1,
            ]
        )

        XCTAssertNil(snapshot.remainingSeconds)
        XCTAssertTrue(snapshot.isEstimatingRemaining)
    }

    func testQueueSnapshotUsesWorkUnitsForQueuedASRPhases() throws {
        let plan = TaskWorkPlan(
            shouldExtractAudio: true,
            shouldRunASR: true,
            shouldSegmentSubtitles: true,
            shouldTranscode: false,
            shouldTranslate: true,
            shouldBurn: false,
            downloadUnits: 2,
            audioExtractUnits: 1,
            speechRecognitionUnits: 12,
            subtitleSegmentUnits: 1,
            translateUnits: 2
        )
        let snapshot = QueueProgressEstimator.queueSnapshot(
            items: [
                TaskProgressSnapshot(
                    overallProgress: nil,
                    remainingSeconds: nil,
                    isEstimatingRemaining: false,
                    isTerminal: false,
                    currentPhase: nil,
                    workPlan: plan
                ),
            ],
            phaseMedianDurations: [
                .download: 15,
                .audioExtract: 8,
                .speechRecognition: 30,
                .subtitleSegment: 5,
                .translate: 20,
            ],
            phaseCapacities: [
                .download: 2,
                .speechRecognition: 1,
                .translate: 1,
            ]
        )

        XCTAssertEqual(try XCTUnwrap(snapshot.remainingSeconds), 443, accuracy: 0.0001)
        XCTAssertFalse(snapshot.isEstimatingRemaining)
    }

    // MARK: - normalizedFraction 钳制（进度条永不越界/不显示 NaN）

    func testNormalizedFractionClampsAndRejectsNonFinite() {
        // nil / 非有限（NaN/Inf）→ nil（不喂给进度条）。
        XCTAssertNil(QueueProgressEstimator.normalizedFraction(nil))
        XCTAssertNil(QueueProgressEstimator.normalizedFraction(Double.nan))
        XCTAssertNil(QueueProgressEstimator.normalizedFraction(Double.infinity))
        XCTAssertNil(QueueProgressEstimator.normalizedFraction(-Double.infinity))
        // 越界钳到 [0,1]，防止进度条显示负值或 >100%。
        XCTAssertEqual(try XCTUnwrap(QueueProgressEstimator.normalizedFraction(-0.5)), 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(QueueProgressEstimator.normalizedFraction(1.5)), 1, accuracy: 1e-9)
        // 区间内原样。
        XCTAssertEqual(try XCTUnwrap(QueueProgressEstimator.normalizedFraction(0.42)), 0.42, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(QueueProgressEstimator.normalizedFraction(0)), 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(QueueProgressEstimator.normalizedFraction(1)), 1, accuracy: 1e-9)
    }

    // MARK: - parseEtaSeconds 畸形输入（只接受 mm:ss / hh:mm:ss 的整数分段）

    func testParseEtaSecondsRejectsMalformedInput() {
        XCTAssertNil(QueueProgressEstimator.parseEtaSeconds(nil))
        XCTAssertNil(QueueProgressEstimator.parseEtaSeconds(""))
        XCTAssertNil(QueueProgressEstimator.parseEtaSeconds("   "))
        XCTAssertNil(QueueProgressEstimator.parseEtaSeconds("N/A"))
        XCTAssertNil(QueueProgressEstimator.parseEtaSeconds("45"))          // 单段（无冒号）不接受
        XCTAssertNil(QueueProgressEstimator.parseEtaSeconds("1:2:3:4"))     // 4 段不接受
        XCTAssertNil(QueueProgressEstimator.parseEtaSeconds("aa:bb"))       // 非整数段
        XCTAssertNil(QueueProgressEstimator.parseEtaSeconds("1:2.5"))       // 小数段（Int 解析失败）
        // 合法：mm:ss / hh:mm:ss（含前后空白被 trim）。
        XCTAssertEqual(QueueProgressEstimator.parseEtaSeconds(" 02:00 "), 120)
        XCTAssertEqual(QueueProgressEstimator.parseEtaSeconds("00:00"), 0)
    }
}
