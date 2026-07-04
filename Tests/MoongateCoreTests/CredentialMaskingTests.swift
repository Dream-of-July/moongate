import XCTest
@testable import MoongateCore

/// CredentialMasking 脱敏契约：凭证 token 打印到日志/CLI 前必须脱敏，防止变相回显泄露。
/// 从 moongate-cli 下沉到 Core 后补测（executable target 无法 @testable import，下沉是为了可测+复用）。
final class CredentialMaskingTests: XCTestCase {
    func testShortTokensAreFullyMasked() {
        // <=8 字符：全打码（露任何前缀都可能泄露短密钥）。
        XCTAssertEqual(CredentialMasking.masked(""), "…")
        XCTAssertEqual(CredentialMasking.masked("abc"), "…")
        XCTAssertEqual(CredentialMasking.masked("12345678"), "…", "恰好 8 字符仍全打码（边界用 >8）")
    }

    func testLongTokensKeepOnlySixCharPrefix() {
        // >8 字符：只留前 6 + 省略号，其余不回显。
        XCTAssertEqual(CredentialMasking.masked("123456789"), "123456…", "9 字符（>8）留前 6")
        XCTAssertEqual(CredentialMasking.masked("sk-abcdefghijklmnop"), "sk-abc…")
        // 脱敏结果绝不包含第 7 字符及之后的原文。
        let secret = "sk-SUPERSECRETvalue1234567890"
        let masked = CredentialMasking.masked(secret)
        XCTAssertEqual(masked, "sk-SUP…")
        XCTAssertFalse(masked.contains("SECRET"), "脱敏后不得含 7 位之后的敏感内容")
    }
}
