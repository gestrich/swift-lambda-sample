//
//  Configuration.swift
//
//
//  Created by Bill Gestrich on 12/9/23.
//

import Foundation

struct Configuration: Codable {

    let s3: S3Configuration
    let postgres: PostgresConfiguration
    
    static func loadConfiguration(fileURL: URL) throws -> Configuration {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Configuration.self, from: data)
    }

    static func localConfigFileURL() -> URL {
        //appending(path:) is not available on Swift Linux 5.9
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".swiftSampleDemo/swiftLambdaDemo.json")
    }
}
