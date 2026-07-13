import Foundation
import XCTest
@testable import MoongateCore

final class LibraryArtifactRelinkerTests: XCTestCase {
    func testReplacementPreservesArtifactIdentityAndStoresOnlyManagedRelativePath() throws {
        let artifactID = UUID()
        let original = try LibraryArtifact(
            id: artifactID,
            role: .renderedVideo,
            relativePath: "Old/Movie.mp4",
            size: 1,
            modifiedAt: Date(timeIntervalSince1970: 10)
        )
        let root = URL(fileURLWithPath: "/tmp/moongate-downloads", isDirectory: true)
        let selected = root.appendingPathComponent("Recovered/Movie.mp4")
        let modifiedAt = Date(timeIntervalSince1970: 100)

        let replacement = try LibraryArtifactRelinker.replacement(
            for: original,
            selectedURL: selected,
            managedRootURL: root,
            size: 42,
            modifiedAt: modifiedAt
        )

        XCTAssertEqual(replacement.id, artifactID)
        XCTAssertEqual(replacement.role, .renderedVideo)
        XCTAssertEqual(replacement.relativePath, "Recovered/Movie.mp4")
        XCTAssertEqual(replacement.size, 42)
        XCTAssertEqual(replacement.modifiedAt, modifiedAt)
    }

    func testReplacementRejectsFileOutsideManagedDownloads() throws {
        let original = try LibraryArtifact(role: .video, relativePath: "Old/Movie.mp4")
        let root = URL(fileURLWithPath: "/tmp/moongate-downloads", isDirectory: true)
        let external = URL(fileURLWithPath: "/tmp/moongate-downloads-copy/Movie.mp4")

        XCTAssertThrowsError(
            try LibraryArtifactRelinker.replacement(
                for: original,
                selectedURL: external,
                managedRootURL: root,
                size: nil,
                modifiedAt: nil
            )
        ) { error in
            XCTAssertEqual(error as? LibraryArtifactRelinkError, .outsideManagedDirectory)
        }
    }
}
