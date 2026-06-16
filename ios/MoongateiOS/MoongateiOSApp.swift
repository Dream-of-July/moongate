import SwiftUI
import UIKit
import MoongateMobileCore
import MoongateiOS

#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

final class IOSBackgroundURLSessionCompletionRegistry: IOSBackgroundURLSessionCompletionConsuming, @unchecked Sendable {
    static let shared = IOSBackgroundURLSessionCompletionRegistry()

    private var handlers: [String: () -> Void] = [:]
    private let lock = NSLock()

    private init() {}

    func store(identifier: String, completionHandler: @escaping () -> Void) {
        lock.lock()
        handlers[identifier] = completionHandler
        lock.unlock()
    }

    func consumeCompletionHandler(for identifier: String) {
        lock.lock()
        let handler = handlers.removeValue(forKey: identifier)
        lock.unlock()
        guard let handler else { return }
        handler()
    }
}

final class MoongateiOSAppDelegate: NSObject, UIApplicationDelegate {
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.local.videodownloader.ios"
    static var continuedProcessingRenderTaskIdentifierPattern: String {
        "\(bundleIdentifier).render.*"
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        registerContinuedProcessingRenderHandler()
        return true
    }

    // UIApplicationDelegate selector: application(_:handleEventsForBackgroundURLSession:completionHandler:)
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        IOSBackgroundURLSessionCompletionRegistry.shared.store(
            identifier: identifier,
            completionHandler: completionHandler
        )
    }

    private func registerContinuedProcessingRenderHandler() {
        #if canImport(BackgroundTasks)
        if #available(iOS 26.0, *) {
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: Self.continuedProcessingRenderTaskIdentifierPattern,
                using: nil
            ) { task in
                guard let task = task as? BGContinuedProcessingTask,
                      let storageDirectoryURL = Self.mobileStorageDirectoryURL()
                else {
                    task.setTaskCompleted(success: false)
                    return
                }

                let repository = Self.mobileTaskRepository(storageDirectoryURL: storageDirectoryURL)
                let handler = IOSContinuedProcessingTaskHandler(
                    bundleIdentifier: Self.bundleIdentifier,
                    coordinator: IOSContinuedProcessingTaskCoordinator(taskRepository: repository)
                )
                let systemTask = IOSBackgroundContinuedProcessingSystemTask(task: task)
                Task {
                    do {
                        let taskID = try handler.taskID(for: systemTask)
                        try await handler.register(systemTask)
                        let runner = IOSContinuedProcessingRenderTaskRunner(
                            taskRepository: repository,
                            renderExporter: IOSMobileRenderExporter(storageDirectoryURL: storageDirectoryURL),
                            progressObserver: { progress in
                                Task {
                                    await systemTask.updateProgress(progress)
                                }
                            }
                        )
                        let updated = try await runner.run(taskID: taskID)
                        if let progress = updated?.progress {
                            await systemTask.updateProgress(progress)
                        }
                        await systemTask.setTaskCompleted(success: updated?.state == .completed)
                    } catch {
                        await systemTask.setTaskCompleted(success: false)
                    }
                }
            }
        }
        #endif
    }

    private static func mobileStorageDirectoryURL() -> URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("MoongateMobile", isDirectory: true)
    }

    private static func mobileTaskRepository(storageDirectoryURL: URL) -> FileTaskRepository {
        return FileTaskRepository(
            fileURL: storageDirectoryURL.appendingPathComponent("mobile-tasks.json", isDirectory: false)
        )
    }
}

@main
struct MoongateNativeiOSApp: App {
    @UIApplicationDelegateAdaptor(MoongateiOSAppDelegate.self) private var appDelegate
    @StateObject private var model = IOSMobileAppModel.live(
        backgroundCompletionConsumer: IOSBackgroundURLSessionCompletionRegistry.shared
    )

    var body: some Scene {
        WindowGroup {
            MoongateIOSRootView(model: model)
                .task {
                    applyInitialTabArgumentIfPresent()
                    applySmokeAddCandidatesArgumentIfPresent()
                    await model.restoreQueueFromRepository()
                }
        }
    }

    private func applyInitialTabArgumentIfPresent() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "--moongate-ios-initial-tab"),
              arguments.indices.contains(flagIndex + 1),
              let tab = IOSMobileTab(rawValue: arguments[flagIndex + 1])
        else {
            return
        }
        model.selectedTab = tab
    }

    private func applySmokeAddCandidatesArgumentIfPresent() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--moongate-ios-smoke-add-candidates") else {
            return
        }
        model.addSession = Self.smokeAddCandidateSelectionSession()
    }

    private static func smokeAddCandidateSelectionSession() -> MobileAddSessionSnapshot {
        let directCandidate = MobileVideoCandidate(
            id: "smoke-direct-media",
            sourceURL: "https://example.com/mobile-smoke.mp4",
            kind: .directFile,
            title: "本地烟测视频",
            detail: "直接 HTTPS 媒体文件"
        )
        let desktopCandidate = MobileVideoCandidate(
            id: "smoke-desktop-required",
            sourceURL: "https://example.com/watch/mobile-smoke",
            kind: .webPageVideo,
            title: "网页视频候选",
            detail: "网页解析需要桌面端提取器",
            unsupportedReason: .requiresDesktopExtractor
        )
        return MobileAddSessionSnapshot(
            id: "add-smoke-candidates",
            input: MobileInputSource(
                id: "input-smoke-candidates",
                kind: .pastedURL,
                value: "https://example.com/watch/mobile-smoke",
                displayName: "截图烟测"
            ),
            state: .candidateSelection,
            candidates: [directCandidate, desktopCandidate],
            selectedCandidateID: "smoke-direct-media"
        )
    }
}
