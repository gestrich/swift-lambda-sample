//
//  LambdaHandler.swift
//
//
//  Created by Bill Gestrich on 10/23/21.
//

import AWSLambdaEvents
import AWSLambdaRuntime
import Foundation
import SwiftServerApp

@main
struct MyLambda {
    static func main() async throws {
        let handler = DynamicLambdaHandler()
        let adapter = LambdaHandlerAdapter(handler: handler)
        // LambdaCodableAdapter automatically decodes incoming Lambda events into LambdaEvent
        // by calling JSONDecoder().decode(LambdaEvent.self, from: eventData)
        // This triggers LambdaEvent.init(from:) - there are no direct calls to this initializer in our code
        let codableAdapter = LambdaCodableAdapter(encoder: JSONEncoder(), decoder: JSONDecoder(), handler: adapter)
        let runtime = LambdaRuntime(handler: codableAdapter)
        try await runtime.run()
    }
}
