import Foundation

public enum SecurityScopedResourceAccessError: Error, Equatable, CustomStringConvertible {
    case accessDenied

    public var description: String {
        "文件夹访问授权未生效，请重新授权。"
    }
}

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

    public static func withRequiredAccess<Result>(
        to url: URL,
        startAccessing: (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
        stopAccessing: (URL) -> Void = { $0.stopAccessingSecurityScopedResource() },
        operation: () throws -> Result
    ) throws -> Result {
        guard startAccessing(url) else {
            throw SecurityScopedResourceAccessError.accessDenied
        }
        defer { stopAccessing(url) }
        return try operation()
    }
}
