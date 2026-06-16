import XCTest
@testable import MoongateiOS
import MoongateMobileCore

final class IOSArtifactStoreTests: XCTestCase {
    func testResolvesOnlyAppOwnedStorageIdentifiersInsideStorageDirectory() throws {
        let root = URL(fileURLWithPath: "/tmp/moongate-mobile-store", isDirectory: true)
        let store = IOSArtifactStore(storageDirectoryURL: root)
        let artifact = MobileTaskArtifact(
            id: "video",
            kind: .originalMedia,
            displayName: "clip.mp4",
            storageIdentifier: "downloads/clip.mp4"
        )

        let resolved = try store.fileURL(for: artifact)

        XCTAssertEqual(
            resolved.standardizedFileURL.path,
            root.appendingPathComponent("Downloads/clip.mp4").standardizedFileURL.path
        )
    }

    func testRejectsExternalAbsoluteTraversalAndSecretBearingReferences() throws {
        let root = URL(fileURLWithPath: "/tmp/moongate-mobile-store", isDirectory: true)
        let store = IOSArtifactStore(storageDirectoryURL: root)
        let unsafeIdentifiers = [
            "../outside.mp4",
            "/tmp/outside.mp4",
            "file:///tmp/outside.mp4",
            "https://media.example.test/clip.mp4",
            "source:https://media.example.test/clip.mp4?access_token=SECRET_TOKEN",
            "downloads/clip.mp4?X-Amz-Signature=SECRET_TOKEN"
        ]

        for identifier in unsafeIdentifiers {
            let artifact = MobileTaskArtifact(
                id: identifier,
                kind: .originalMedia,
                displayName: "clip.mp4",
                storageIdentifier: identifier
            )

            XCTAssertThrowsError(try store.fileURL(for: artifact), identifier) { error in
                XCTAssertEqual(error as? IOSArtifactStoreError, .unsafeStorageIdentifier)
            }
        }
    }
}
