import Darwin
import Foundation

public enum ProjectScanAccessError: Error, Equatable, CustomStringConvertible {
    case unavailable
    case wrongDirectory
    case linkedDirectory

    public var description: String {
        switch self {
        case .unavailable:
            "无法读取所选个人文件夹。"
        case .wrongDirectory:
            "请选择当前用户的个人文件夹，以便一次授权后完整扫描项目。"
        case .linkedDirectory:
            "不能使用符号链接作为项目扫描授权范围。"
        }
    }
}

public enum ProjectScanAccessPolicy {
    public static func authorizedRoot(
        selectedURL: URL,
        homeURL: URL
    ) throws -> URL {
        let selected = selectedURL.standardizedFileURL
        let home = homeURL.standardizedFileURL

        var selectedMetadata = stat()
        guard lstat(selected.path, &selectedMetadata) == 0,
              selectedMetadata.st_mode & S_IFMT == S_IFDIR
        else {
            if selectedURL.resolvingSymlinksInPath().standardizedFileURL == home {
                throw ProjectScanAccessError.linkedDirectory
            }
            throw ProjectScanAccessError.unavailable
        }

        var homeMetadata = stat()
        guard lstat(home.path, &homeMetadata) == 0,
              homeMetadata.st_mode & S_IFMT == S_IFDIR
        else { throw ProjectScanAccessError.unavailable }

        guard selected.path == home.path,
              selectedMetadata.st_dev == homeMetadata.st_dev,
              selectedMetadata.st_ino == homeMetadata.st_ino
        else { throw ProjectScanAccessError.wrongDirectory }

        // Keep the exact URL supplied by NSOpenPanel (or restored from its
        // bookmark). Reconstructing the same filesystem path creates a new URL
        // value without the security-scoped grant attached to the original.
        return selectedURL
    }
}
