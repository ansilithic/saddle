import Foundation

enum Paths {
    private static let env = ProcessInfo.processInfo.environment

    static var configDir: String {
        let base = env["XDG_CONFIG_HOME"] ?? defaultConfigBase
        return "\(FS.expandPath(base))/saddle"
    }

    static var dataDir: String {
        let base = env["XDG_DATA_HOME"] ?? defaultDataBase
        return "\(FS.expandPath(base))/saddle"
    }

    static var cacheDir: String {
        let base = env["XDG_CACHE_HOME"] ?? defaultCacheBase
        return "\(FS.expandPath(base))/saddle"
    }

    static var manifestPath: String { "\(configDir)/manifest.toml" }
    static var hooksDir: String { "\(configDir)/hooks" }
    static var stateFile: String { "\(dataDir)/state.json" }
    static var hostCachePath: String { "\(cacheDir)/host-cache.json" }
    static var urlCacheDir: String { "\(cacheDir)/urlcache" }

    #if os(macOS)
    private static let defaultConfigBase = "~/Library/Application Support"
    private static let defaultDataBase = "~/Library/Application Support"
    private static let defaultCacheBase = "~/Library/Caches"
    #else
    private static let defaultConfigBase = "~/.config"
    private static let defaultDataBase = "~/.local/share"
    private static let defaultCacheBase = "~/.cache"
    #endif

    /// Migrate from old com.ansilithic.saddle directory if needed.
    static func migrateIfNeeded() {
        let oldDir = FS.expandPath("~/Library/Application Support/com.ansilithic.saddle")
        guard FS.isDirectory(oldDir), !FS.isDirectory(configDir) else { return }
        do {
            let parent = URL(fileURLWithPath: configDir).deletingLastPathComponent().path
            try FS.createDirectory(parent)
            try FileManager.default.moveItem(atPath: oldDir, toPath: configDir)
        } catch {}
    }
}
