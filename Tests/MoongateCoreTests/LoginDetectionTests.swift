import XCTest
@testable import MoongateCore

/// 验证「需要登录/验证导致失败」会被识别为 .siteCookieRequired（failed 页据此打开原网页捕获 Cookie）。
final class LoginDetectionTests: XCTestCase {

    private func isSiteCookieRequired(_ error: MoongateError?) -> Bool {
        if case .siteCookieRequired = error { return true }
        return false
    }

    func testYouTubeSignInPromptIsRecognizedAsLoginIssue() {
        let error = YtDlpEngine._testLoginRequired(
            stderr: "ERROR: [youtube] abc: Sign in to confirm you're not a bot.",
            url: "https://www.youtube.com/watch?v=abc"
        )
        switch error {
        case .siteCookieRequired(let site, let url, let reason):
            XCTAssertEqual(site, "youtube.com")
            XCTAssertEqual(url, "https://www.youtube.com/watch?v=abc")
            XCTAssertTrue(reason.contains("YouTube"))
        default:
            XCTFail("YouTube Sign in 提示应被识别为站点验证，实际：\(String(describing: error))")
        }
    }

    func testBilibiliMemberOnlyVideoNeedsLogin() {
        let error = YtDlpEngine._testLoginRequired(
            stderr: "ERROR: [BiliBili] BV1: 该视频需要登录大会员账号才能观看",
            url: "https://www.bilibili.com/video/BV1"
        )
        XCTAssertTrue(isSiteCookieRequired(error))
        if case .siteCookieRequired(let site, let url, _) = error {
            XCTAssertEqual(site, "bilibili.com")
            XCTAssertEqual(url, "https://www.bilibili.com/video/BV1")
        }
    }

    func testGenericNeedLoginEnglishMessageNeedsLogin() {
        let error = YtDlpEngine._testLoginRequired(
            stderr: "ERROR: This video requires login. Use --cookies to provide account cookies.",
            url: "https://example.com/v/1"
        )
        XCTAssertTrue(isSiteCookieRequired(error))
    }

    func testGenericWebpage404OffersSiteCookieVerification() {
        let error = YtDlpEngine._testLoginRequired(
            stderr: "ERROR: [generic] Unable to download webpage: HTTP Error 404: Not Found (caused by <HTTPError 404: Not Found>)",
            url: "https://missav.live/cn/hublk-074"
        )
        if case .siteCookieRequired(let site, let url, let reason) = error {
            XCTAssertEqual(site, "missav.live")
            XCTAssertEqual(url, "https://missav.live/cn/hublk-074")
            XCTAssertTrue(reason.contains("浏览器验证"))
        } else {
            XCTFail("generic webpage 404 should offer site cookie verification, actual: \(String(describing: error))")
        }
    }

    func testBilibili412WithoutSavedCookiesPromptsLogin() {
        // B 站首次未登录直接贴链接时常以 412 表现，用户需要的是登录引导/WebView。
        let stderr = "ERROR: [BiliBili] BV1: Unable to download JSON metadata: HTTP Error 412: Precondition Failed"
        let loginError = YtDlpEngine._testLoginRequired(
            stderr: stderr,
            url: "https://www.bilibili.com/video/BV1",
            hasCookies: false
        )
        XCTAssertTrue(isSiteCookieRequired(loginError))
        if case .siteCookieRequired(let site, _, _) = loginError {
            XCTAssertEqual(site, "bilibili.com")
        }
    }

    func testBilibili412WithSavedCookiesKeepsRiskControlHint() {
        let stderr = "ERROR: [BiliBili] BV1: Unable to download JSON metadata: HTTP Error 412: Precondition Failed"
        let loginError = YtDlpEngine._testLoginRequired(
            stderr: stderr,
            url: "https://www.bilibili.com/video/BV1",
            hasCookies: true
        )
        XCTAssertFalse(isSiteCookieRequired(loginError))

        let riskMessage = YtDlpEngine._testRiskControlMessage(stderr: stderr, host: "www.bilibili.com")
        XCTAssertNotNil(riskMessage)
        XCTAssertTrue(riskMessage?.contains("风控") == true)
    }

    func testPlainNetworkErrorIsNeitherLoginNorRisk() {
        let stderr = "ERROR: Unable to download webpage: <urlopen error timed out>"
        XCTAssertFalse(isSiteCookieRequired(YtDlpEngine._testLoginRequired(stderr: stderr, url: "https://www.bilibili.com/video/BV1")))
        XCTAssertNil(YtDlpEngine._testRiskControlMessage(stderr: stderr, host: "www.bilibili.com"))
    }

    func testPageSnifferRecognizesCloudflareChallenge() {
        XCTAssertTrue(PageSniffer._testIsCloudflareChallenge(statusCode: 403, headerValue: "challenge"))
        XCTAssertTrue(PageSniffer._testIsCloudflareChallenge(statusCode: 503, headerValue: "Challenge"))
        XCTAssertFalse(PageSniffer._testIsCloudflareChallenge(statusCode: 403, headerValue: nil))
        XCTAssertFalse(PageSniffer._testIsCloudflareChallenge(statusCode: 500, headerValue: "challenge"))
        XCTAssertTrue(PageSniffer.cloudflareChallengeMessage.contains("Cloudflare"))

        let error = PageSniffer._testCloudflareChallengeError(for: URL(string: "https://missav.live/cn/hublk-074")!)
        if case .siteCookieRequired(let site, let url, let reason) = error {
            XCTAssertEqual(site, "missav.live")
            XCTAssertEqual(url, "https://missav.live/cn/hublk-074")
            XCTAssertTrue(reason.contains("Cloudflare"))
        } else {
            XCTFail("Cloudflare challenge should map to siteCookieRequired")
        }
    }

    func testDynamicCookieFileUsesHostScopedJar() {
        let known = YtDlpEngine._testCookieFile(for: "https://www.youtube.com/watch?v=abc")
        XCTAssertEqual(known?.lastPathComponent, "youtube.txt")

        let dynamic = YtDlpEngine._testCookieFile(for: "https://missav.live/cn/hublk-074")
        XCTAssertEqual(dynamic?.lastPathComponent, "site-missav.live.txt")
    }

    func testNativeExtractorHostsIncludeShortVideoSites() {
        for host in [
            "www.tiktok.com",
            "vt.tiktok.com",
            "v.douyin.com",
            "www.douyin.com",
            "www.xiaohongshu.com",
            "xhslink.com",
        ] {
            XCTAssertTrue(YtDlpEngine._testIsNativeExtractorHost(host), host)
        }
        XCTAssertFalse(YtDlpEngine._testIsNativeExtractorHost("example.com"))
    }
}
