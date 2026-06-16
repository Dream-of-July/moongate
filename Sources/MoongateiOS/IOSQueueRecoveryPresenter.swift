import Foundation
import MoongateMobileCore

public struct IOSQueueRecoveryPresentation: Sendable, Equatable {
    public var message: String
    public var recoveryHint: String
    public var systemImage: String
    public var isActionable: Bool
    public var accessibilityHint: String

    public init(
        message: String,
        recoveryHint: String,
        systemImage: String,
        isActionable: Bool,
        accessibilityHint: String
    ) {
        self.message = message
        self.recoveryHint = recoveryHint
        self.systemImage = systemImage
        self.isActionable = isActionable
        self.accessibilityHint = accessibilityHint
    }
}

public struct IOSQueueRecoveryPresenter: Sendable {
    public init() {}

    public func presentation(for task: MobileTaskSnapshot) -> IOSQueueRecoveryPresentation? {
        guard let reason = reason(for: task) else {
            return nil
        }

        let hint = recoveryHint(for: task, error: task.error)
        return IOSQueueRecoveryPresentation(
            message: reason.message,
            recoveryHint: hint.text,
            systemImage: reason.systemImage,
            isActionable: hint.isActionable,
            accessibilityHint: "\(displayName(for: task))：\(reason.message)\(hint.text)"
        )
    }

    private func reason(for task: MobileTaskSnapshot) -> (message: String, systemImage: String)? {
        if task.state == .needsForegroundToContinue,
           task.error == .systemBackgroundLimit ||
           task.backgroundPolicy.resumability == .nonResumable ||
           task.backgroundPolicy.limits.contains(.notResumable) {
            return ("iOS 已暂停后台处理。", "iphone")
        }

        guard let error = task.error else {
            return nil
        }

        switch error {
        case .networkUnavailable:
            return ("网络不可用，下载没有完成。", "wifi.exclamationmark")
        case .credentialRequired:
            return ("需要先保存可用的 API key。", "key")
        case .permissionDenied:
            return ("系统权限不足，当前操作被拒绝。", "hand.raised")
        case .storageFull:
            return ("设备空间不足，文件没有保存完成。", "internaldrive")
        case .systemBackgroundLimit:
            return ("iOS 已暂停后台处理。", "iphone")
        case .exportFailed:
            return ("导出失败，已完成的文件仍可使用。", "exclamationmark.triangle")
        case .sourceUnavailableAfterRelaunch:
            return ("出于隐私保护，原链接没有在重启后保留。", "link.badge.plus")
        case .unsupportedOnMobile:
            return ("这个任务当前不能在 iPhone 上继续。", "iphone.slash")
        case .cancelled:
            return ("任务已取消。", "xmark.circle")
        case .unknown:
            return ("任务没有完成。", "exclamationmark.circle")
        }
    }

    private func recoveryHint(
        for task: MobileTaskSnapshot,
        error: MobileTaskError?
    ) -> (text: String, isActionable: Bool) {
        if task.state == .needsForegroundToContinue,
           task.backgroundPolicy.resumability == .nonResumable ||
           task.backgroundPolicy.limits.contains(.notResumable) {
            return (restartHint(for: task.progress.phase), false)
        }

        switch error {
        case .networkUnavailable:
            return ("联网后点“重试”。", true)
        case .credentialRequired:
            return ("到设置保存密钥后重试。", true)
        case .permissionDenied:
            return ("在系统设置打开权限后重试。", true)
        case .storageFull:
            return ("释放空间后重试。", true)
        case .exportFailed:
            return ("可以打开原文件，或修正后重新导出。", true)
        case .sourceUnavailableAfterRelaunch:
            return ("重新添加原链接后再开始下载。", false)
        case .unsupportedOnMobile:
            return ("请重新添加支持的直接视频文件链接。", false)
        case .systemBackgroundLimit:
            return (restartHint(for: task.progress.phase), false)
        case .cancelled:
            return ("需要时重新添加任务。", false)
        case .unknown:
            return ("请重试；如果再次失败，重新添加任务。", true)
        case nil:
            return ("", false)
        }
    }

    private func restartHint(for phase: MobileTaskPhase) -> String {
        switch phase {
        case .exporting:
            return "回到前台后重新开始这次导出。"
        case .downloading:
            return "回到前台后重新开始下载。"
        case .translating:
            return "回到前台后重新开始翻译。"
        case .waiting, .analyzing:
            return "回到前台后重新开始任务。"
        }
    }

    private func displayName(for task: MobileTaskSnapshot) -> String {
        task.result?.primaryArtifact?.displayName ?? "未命名视频"
    }
}
