import Foundation

/// File isolation for a library reprocess. Translators name output subtitles
/// deterministically, so operating beside v1 would overwrite its translation.
/// Every reprocess therefore receives a sibling version directory and copies
/// only the artifacts it needs into that directory before work begins.
public enum ReprocessWorkspace {
    public static func createVersionDirectory(
        beside sourceDirectory: URL,
        versionNumber: Int,
        fileManager: FileManager = .default
    ) throws -> URL {
        let versionsDirectory = sourceDirectory
            .appendingPathComponent(".moongate-versions", isDirectory: true)
        let identifier = UUID().uuidString.prefix(8).lowercased()
        let directory = versionsDirectory.appendingPathComponent(
            "v\(max(versionNumber, 1))-\(identifier)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static func copyArtifacts(
        _ sourceURLs: [URL],
        to destinationDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        var copied: [URL] = []
        var seenSources = Set<String>()

        for sourceURL in sourceURLs {
            let source = sourceURL.standardizedFileURL
            guard seenSources.insert(source.path).inserted,
                  fileManager.fileExists(atPath: source.path) else {
                continue
            }

            let filename = source.lastPathComponent
            let stem = source.deletingPathExtension().lastPathComponent
            let ext = source.pathExtension
            let initialDestination = destinationDirectory.appendingPathComponent(filename)
            let destination = fileManager.fileExists(atPath: initialDestination.path)
                ? UniqueFilename.url(in: destinationDirectory, stem: stem, ext: ext)
                : initialDestination
            try fileManager.copyItem(at: source, to: destination)
            copied.append(destination)
        }

        return copied
    }
}
