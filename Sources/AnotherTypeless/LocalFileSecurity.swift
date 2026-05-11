import Foundation

enum LocalFileSecurity {
    static func protectDirectory(_ url: URL, fileManager: FileManager = .default) {
        try? fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: url.path
        )
    }

    static func protectFile(_ url: URL, fileManager: FileManager = .default) {
        try? fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
    }
}
