//
//  FileManager+Helper.swift
//  Pods
//
//  Created by Benjamin Erhart on 11.03.24.
//

import Foundation

public extension URL {

    /**
     Returns whether the URL’s resource exists and is reachable.
     */
    var exists: Bool {
        (try? checkResourceIsReachable()) ?? false
    }

    /**
     Indicates whether the resource is a directory.
     */
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }
}

public extension FileManager {

    func createSecureDirIfNotExists(at url: URL) throws {
        // Try toemove it, if it is *not* a directory.
        if url.exists && !url.isDirectory {
            try removeItem(at: url)
        }

        if !url.exists {
            try createDirectory(
                at: url, withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)])
        }
    }
}
