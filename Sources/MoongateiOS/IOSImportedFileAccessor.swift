import Foundation

public protocol IOSImportedFileAccessing: Sendable {
    func withAccess<T>(
        to url: URL,
        _ operation: () throws -> T
    ) rethrows -> T
}

public struct IOSImportedFileAccessor: IOSImportedFileAccessing {
    public init() {}

    public func withAccess<T>(
        to url: URL,
        _ operation: () throws -> T
    ) rethrows -> T {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try operation()
    }
}
