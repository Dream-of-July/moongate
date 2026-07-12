import XCTest
@testable import MoongateCore

final class LibraryModelsTests: XCTestCase {
    func testSourceDescriptorStripsCredentialsQueryAndFragment() throws {
        let descriptor = try XCTUnwrap(
            LibrarySourceDescriptor(urlString: "https://name:secret@example.com/watch?id=123&token=secret#section")
        )

        XCTAssertEqual(descriptor.urlString, "https://example.com/watch")
    }

    func testArtifactRejectsAbsoluteAndTraversingPaths() {
        XCTAssertThrowsError(try LibraryArtifact(role: .video, relativePath: "/Users/me/movie.mp4"))
        XCTAssertThrowsError(try LibraryArtifact(role: .video, relativePath: "../movie.mp4"))
        XCTAssertThrowsError(try LibraryArtifact(role: .video, relativePath: "clips/../../movie.mp4"))
    }

    func testEnvelopeRoundTripsOnlySafeProcessingConfiguration() throws {
        let artifact = try LibraryArtifact(
            role: .video,
            relativePath: "Mate 80/Mate 80.mp4",
            size: 2_140_000_000,
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        let processing = ProcessingSummary(
            state: .completed,
            stage: .burning,
            progress: 1,
            actualModels: .init(transcription: "Whisper large-v3-turbo", translation: "GPT-4.1 mini"),
            configuration: .init(
                outputFormat: "H.264 · 1080p",
                subtitleSource: "manual",
                transcriptionModel: "Whisper large-v3-turbo",
                translationModel: "GPT-4.1 mini",
                targetLanguage: "zh-Hans",
                subtitleStyle: "bilingual"
            ),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let version = LibraryVersion(
            number: 1,
            processing: processing,
            artifacts: [artifact],
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let item = LibraryItem(
            title: "Mate 80",
            source: try XCTUnwrap(LibrarySourceDescriptor(urlString: "https://example.com/watch?apiKey=nope")),
            tags: ["科技"],
            isPinned: true,
            note: "保留人工字幕核对版本",
            versions: [version],
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let envelope = LibraryEnvelope(schemaVersion: LibraryEnvelope.currentSchemaVersion, tags: [LibraryTag(name: "科技")], items: [item])

        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(LibraryEnvelope.self, from: data)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8)).lowercased()

        XCTAssertEqual(decoded, envelope)
        XCTAssertFalse(json.contains("apikey"))
        XCTAssertFalse(json.contains("token"))
        XCTAssertFalse(json.contains("cookie"))
        XCTAssertFalse(json.contains("secret"))
        XCTAssertEqual(decoded.items[0].source?.urlString, "https://example.com/watch")
    }

    func testItemRoundTripsSanitizedThumbnailDescriptor() throws {
        let item = LibraryItem(
            title: "Mate 80",
            thumbnail: try XCTUnwrap(
                LibrarySourceDescriptor(urlString: "https://images.example.com/mate.png?signature=private#crop")
            )
        )

        let decoded = try JSONDecoder().decode(
            LibraryItem.self,
            from: JSONEncoder().encode(item)
        )

        XCTAssertEqual(decoded.thumbnail?.urlString, "https://images.example.com/mate.png")
    }

    func testSanitizedYouTubeWatchURLCannotRestart() throws {
        let source = try XCTUnwrap(LibrarySourceDescriptor(urlString: "https://www.youtube.com/watch?v=id"))
        XCTAssertFalse(source.supportsRestart)
    }
}
