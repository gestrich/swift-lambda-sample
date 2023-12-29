//
//  LambdaHandler.swift
//
//
//  Created by Bill Gestrich on 10/23/21.
//

import AWSLambdaRuntime
import Foundation
import NIO

@main
public struct LambdaHandler: ByteBufferLambdaHandler {

    public func handle(context: Lambda.Context, event: ByteBuffer) -> EventLoopFuture<ByteBuffer?> {
        let handlers: [AnyLambdaHandler] = [
            CreateUserHandler().erased(),
            APIGWHandler().erased(),
        ]
        let dynamicHandler = DynamicLambdaHandler(handlers: handlers)
        return dynamicHandler.handle(context: context, event: event)
    }

    static func main() {
        Lambda.run(LambdaHandler())
    }
}
