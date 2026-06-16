import XCTest
import MoongateMobileCore
import MoongateiOS

final class IOSKeychainCredentialStoreIntegrationTests: XCTestCase {
    func testKeychainCredentialStoreRoundTripsSyntheticCredentialInHostedApp() async throws {
        let store = IOSKeychainCredentialStore()
        let suffix = UUID().uuidString
        let reference = SecureCredentialReference(
            service: "com.local.videodownloader.ios.tests.\(suffix)",
            account: "integration-\(suffix)",
            displayName: "Hosted Keychain Test"
        )
        let secret = "synthetic-keychain-secret-\(suffix)"

        try? await store.deleteCredential(reference)

        do {
            let hasCredentialBeforeSave = try await store.hasCredential(reference)
            let credentialBeforeSave = try await store.credential(for: reference)
            XCTAssertFalse(hasCredentialBeforeSave)
            XCTAssertNil(credentialBeforeSave)

            let saved = try await store.saveCredential(secret, for: reference)

            let hasCredentialAfterSave = try await store.hasCredential(reference)
            let credentialAfterSave = try await store.credential(for: reference)
            XCTAssertEqual(saved, reference)
            XCTAssertTrue(hasCredentialAfterSave)
            XCTAssertEqual(credentialAfterSave, secret)

            try await store.deleteCredential(reference)

            let hasCredentialAfterDelete = try await store.hasCredential(reference)
            let credentialAfterDelete = try await store.credential(for: reference)
            XCTAssertFalse(hasCredentialAfterDelete)
            XCTAssertNil(credentialAfterDelete)
        } catch {
            try? await store.deleteCredential(reference)
            throw error
        }
    }
}
