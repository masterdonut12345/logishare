//
//  ProjectScanner.swift
//  LogiShare
//
//  Created by Caleb Balboni on 1/1/26.
//

import Foundation
import CryptoKit

enum ProjectScannerError: Error, LocalizedError {
    case notDirectory
    case notLogicPackage

    var errorDescription: String? {
        switch self {
        case .notDirectory: return "Selected path is not a folder/package."
        case .notLogicPackage: return "Please select a .logicx project."
        }
    }
}

enum ProjectScanner {
    /// Recursively scans a `.logicx` package and returns file entries.
    static func scanLogicPackage(packageURL: URL) async throws -> [FileEntry] {
        guard packageURL.pathExtension.lowercased() == "logicx" else {
            throw ProjectScannerError.notLogicPackage
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: packageURL.path, isDirectory: &isDir),
              isDir.boolValue else {
            throw ProjectScannerError.notDirectory
        }

        return try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]

            // IMPORTANT: Do NOT use .skipsPackageDescendants here.
            // A .logicx project is itself a package, so that would produce 0 files.
            let enumerator = fm.enumerator(
                at: packageURL,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            )

            var out: [FileEntry] = []
            while let url = enumerator?.nextObject() as? URL {
                let rv = try url.resourceValues(forKeys: Set(keys))
                if rv.isDirectory == true { continue }

                let rel = url.path.replacingOccurrences(of: packageURL.path + "/", with: "")
                let size = Int64(rv.fileSize ?? 0)
                let mod = rv.contentModificationDate ?? Date.distantPast
                let hash = try sha256Hex(of: url)

                out.append(FileEntry(
                    relativePath: rel,
                    sizeBytes: size,
                    modifiedAt: mod,
                    sha256: hash
                ))
            }

            out.sort { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
            return out
        }.value
    }

    private static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

