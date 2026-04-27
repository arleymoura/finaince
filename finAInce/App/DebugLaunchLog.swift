import Foundation

#if DEBUG
enum DebugLaunchLog {
    private static let storageKey = "debug.launch.logs"
    private static let maxEntries = 120

    static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "\(timestamp) \(message)"
        print(entry)

        var entries = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        UserDefaults.standard.set(entries, forKey: storageKey)
    }

    static func entries() -> [String] {
        UserDefaults.standard.stringArray(forKey: storageKey) ?? []
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
#else
enum DebugLaunchLog {
    static func log(_ message: String) {
        print(message)
    }
}
#endif
