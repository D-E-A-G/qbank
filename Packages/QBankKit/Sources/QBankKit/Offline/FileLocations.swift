import Foundation

/// Where QBankKit keeps its files and how it writes them.
public enum FileLocations {
    /// `Application Support/QBankKit`. Unlike Caches, iOS does not empty it when space runs low,
    /// so saved courses and unsent answers stay until the app removes them.
    public static func applicationSupport() throws(StorageError) -> URL {
        do {
            let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            return base.appendingPathComponent("QBankKit", isDirectory: true)
        } catch {
            throw StorageError(operation: "find Application Support", reason: error.localizedDescription)
        }
    }

    static func ensureDirectory(_ directory: URL, excludedFromBackup: Bool) throws(StorageError) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            #if canImport(Darwin)
            if excludedFromBackup {
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                var url = directory
                try url.setResourceValues(values)
            }
            #endif
        } catch {
            throw StorageError(operation: "create \(directory.lastPathComponent)", reason: error.localizedDescription)
        }
    }

    /// Writes the whole file or nothing, readable after the first unlock so a background send can read it.
    static func write(_ data: Data, to url: URL, operation: String) throws(StorageError) {
        do {
            #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: url, options: [.atomic])
            #endif
        } catch {
            throw StorageError(operation: operation, reason: error.localizedDescription)
        }
    }

    /// The file's bytes, or nil when it does not exist.
    static func read(_ url: URL, operation: String) throws(StorageError) -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            throw StorageError(operation: operation, reason: error.localizedDescription)
        }
    }
}
