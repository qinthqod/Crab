import CrabAppSupport
import Foundation

enum CrabL10n {
    static var language: CrabLanguage {
        CrabLanguagePreference(
            storedValue: UserDefaults.standard.string(forKey: CrabLanguagePreference.defaultsKey)
        ).resolve(preferredLanguages: Locale.preferredLanguages)
    }

    static func text(_ chinese: String, _ english: String) -> String {
        language.choose(chinese: chinese, english: english)
    }

    static func format(
        _ chinese: String,
        _ english: String,
        _ arguments: CVarArg...
    ) -> String {
        let format = text(chinese, english)
        let locale = Locale(identifier: language.rawValue)
        return String(format: format, locale: locale, arguments: arguments)
    }

    static func runtime(_ chineseSource: String) -> String {
        guard language == .english else { return chineseSource }
        if chineseSource.hasSuffix(" 应用数据") {
            return String(chineseSource.dropLast(" 应用数据".count)) + " Application Data"
        }
        return runtimeEnglish[chineseSource] ?? chineseSource
    }

    private static let runtimeEnglish: [String: String] = [
        "可再生缓存": "Regenerable Cache",
        "应用缓存": "App Cache",
        "更新缓存": "Update Cache",
        "诊断日志": "Diagnostic Logs",
        "窗口恢复状态": "Window Restoration State",
        "应用偏好设置": "App Preferences",
        "网络存储": "Network Storage",
        "网络 Cookie": "Network Cookies",
        "网页数据": "Web Data",
        "应用数据": "Application Data",
        "卸载后遗留的可重新生成缓存。": "Regenerable cache left after uninstalling.",
        "应用运行时留下的诊断日志。": "Diagnostic logs left by the app.",
        "用于恢复上次窗口状态的数据。": "Data used to restore the previous window state.",
        "包含应用设置，重新安装时可能继续使用。": "Contains settings that may be reused after reinstalling.",
        "可能包含登录状态或网页组件数据。": "May contain sign-in state or embedded web data.",
        "可能包含账号、会话、扩展或其他用户数据。": "May contain accounts, sessions, extensions, or other user data.",
        "ChatGPT 可重新生成的本地缓存。": "Regenerable local ChatGPT cache.",
        "再次使用 ChatGPT 时可能重新下载资源。": "ChatGPT may download these resources again when next used.",
        "Claude Desktop 已下载的更新缓存。": "Downloaded Claude Desktop update cache.",
        "Claude 可重新生成的本地缓存。": "Regenerable local Claude cache.",
        "再次使用 Claude 时可能重新下载资源。": "Claude may download these resources again when next used.",
        "Codex 可重新生成的本地缓存。": "Regenerable local Codex cache.",
        "再次使用 Codex 时可能重新下载资源。": "Codex may download these resources again when next used.",
        "Cursor 可重新生成的本地缓存。": "Regenerable local Cursor cache.",
        "再次使用 Cursor 时可能重新下载资源。": "Cursor may download these resources again when next used.",
        "Ollama 桌面应用可重新生成的界面缓存。": "Regenerable interface cache for the Ollama desktop app.",
        "再次使用 Ollama 时可能重新构建界面资源；本地模型不会受影响。": "Ollama may rebuild interface resources when next used; local models are not affected.",
        "TRAE SOLO 可重新生成的界面缓存。": "Regenerable TRAE SOLO interface cache.",
        "再次使用 TRAE SOLO 时可能重新构建或下载界面资源。": "TRAE SOLO may rebuild or download interface resources when next used.",
        "TRAE SOLO 已下载的更新缓存。": "Downloaded TRAE SOLO update cache.",
        "TRAE 可重新生成的本地缓存。": "Regenerable local TRAE cache.",
        "再次使用 TRAE 时可能重新下载资源。": "TRAE may download these resources again when next used.",
        "TRAE 已下载的更新缓存。": "Downloaded TRAE update cache.",
        "Windsurf 可重新生成的本地缓存。": "Regenerable local Windsurf cache.",
        "再次使用 Windsurf 时可能重新下载资源。": "Windsurf may download these resources again when next used.",
        "Zed 可重新生成的本地缓存。": "Regenerable local Zed cache.",
        "Zed 可重新生成的系统缓存。": "Regenerable Zed system cache.",
        "再次使用 Zed 时可能重新构建临时资源。": "Zed may rebuild temporary resources when next used.",
        "豆包可重新生成的本地缓存。": "Regenerable local Doubao cache.",
        "再次使用豆包时可能重新下载资源。": "Doubao may download these resources again when next used.",
        "豆包工作版可重新生成的本地缓存。": "Regenerable local Doubao for Business cache.",
        "再次使用豆包工作版时可能重新下载资源。": "Doubao for Business may download these resources again when next used.",
        "豆包工作版网页组件缓存。": "Doubao for Business web component cache.",
        "再次使用豆包工作版时可能重建网页资源。": "Doubao for Business may rebuild web resources when next used.",
        "豆包系统组件的可再生缓存。": "Regenerable cache for Doubao system components.",
        "再次使用豆包时可能重建缓存。": "Doubao may rebuild this cache when next used.",
        "豆包网页组件的可再生缓存。": "Regenerable cache for Doubao web components.",
        "再次使用豆包时可能重建网页资源。": "Doubao may rebuild web resources when next used.",
        "需要更新时可能重新下载安装资源。": "Update resources may be downloaded and installed again when needed.",
    ]
}
