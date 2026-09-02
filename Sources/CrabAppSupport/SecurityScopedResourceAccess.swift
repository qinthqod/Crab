import Foundation

public enum SecurityScopedResourceAccess {
    public static func withAccess<Result>(
        to url: URL,
        startAccessing: (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
        stopAccessing: (URL) -> Void = { $0.stopAccessingSecurityScopedResource() },
        operation: () throws -> Result
    ) rethrows -> Result {
        let didStartAccessing = startAccessing(url)
        defer {
            if didStartAccessing {
                stopAccessing(url)
            }
        }
        return try operation()
    }
}
