import XCTest
@testable import MoongateCore

/// 下载失败文案分类的行为测试。真实用户环境边界：磁盘满 / 输出目录不可写（只读卷、iCloud 优化存储、
/// 权限拒绝）/ 网络中断 / 403 各应走对应的可行动中文提示，而不是笼统的「下载过程中出现错误」。
/// friendlyDownloadReason 此前无任何测试守护——本文件同时补上 403/网络既有分支的守护。
final class DownloadFailureReasonTests: XCTestCase {

    private var savedLanguage: ResolvedLanguage!

    override func setUp() {
        super.setUp()
        savedLanguage = CoreL10n.language
        CoreL10n.setLanguage(.zhHans)
    }

    override func tearDown() {
        CoreL10n.setLanguage(savedLanguage)
        super.tearDown()
    }

    private func reason(_ stderr: String) -> String {
        YtDlpEngine._testFriendlyDownloadReason(stderrTail: stderr)
    }

    // MARK: - 磁盘空间不足

    func testNoSpaceLeftMapsToDiskFullGuidance() {
        for marker in [
            "ERROR: unable to write data: [Errno 28] No space left on device",
            "OSError: [Errno 28] No space left on device",
            "ffmpeg: Disk quota exceeded",
        ] {
            let text = reason(marker)
            XCTAssertTrue(text.contains("磁盘空间不足"),
                          "磁盘满应给清理磁盘的可行动提示，实际：\(text)")
            XCTAssertFalse(text.hasPrefix("下载过程中出现错误"),
                           "磁盘满不应落到通用兜底文案")
        }
    }

    // MARK: - 输出目录不可写 / 权限 / 只读卷

    func testWritePermissionErrorsMapToOutputFolderGuidance() {
        for marker in [
            "ERROR: unable to open file for writing: [Errno 13] Permission denied",
            "OSError: [Errno 30] Read-only file system",
            "unable to create directory",
        ] {
            let text = reason(marker)
            XCTAssertTrue(text.contains("换一个输出文件夹") || text.contains("只读或没有权限"),
                          "写入失败应引导用户改输出文件夹，实际：\(text)")
            XCTAssertFalse(text.hasPrefix("下载过程中出现错误"),
                           "写入失败不应落到通用兜底文案")
        }
    }

    // MARK: - 网络 / 403 既有分支守护

    func testNetworkErrorsKeepProxyGuidance() {
        for marker in ["Connection timed out", "getaddrinfo failed", "SSL: WRONG_VERSION_NUMBER"] {
            XCTAssertTrue(reason(marker).contains("网络连接不稳定"),
                          "网络类错误应保留代理/VPN 提示，实际：\(reason(marker))")
        }
    }

    func test403MapsToAccessDeniedGuidance() {
        XCTAssertTrue(reason("ERROR: unable to download video data: HTTP Error 403: Forbidden")
            .contains("拒绝访问"), "403 应给防盗链/地区限制提示")
    }

    // MARK: - 分类边界：不误撞

    func testGenericErrorStillFallsBack() {
        let text = reason("ERROR: Postprocessing: some unexpected internal failure")
        XCTAssertTrue(text.hasPrefix("下载过程中出现错误"),
                      "无法归类的错误应落到通用兜底，实际：\(text)")
    }

    /// 磁盘/权限判断不能吃掉网络错误：网络错误里出现的 "connection refused" 不含磁盘/权限标志。
    func testNetworkErrorNotMisclassifiedAsDiskOrPermission() {
        let text = reason("ERROR: [Errno 61] Connection refused")
        XCTAssertTrue(text.contains("网络连接不稳定"),
                      "Errno 61（网络）不应被误判为磁盘/权限，实际：\(text)")
    }
}
