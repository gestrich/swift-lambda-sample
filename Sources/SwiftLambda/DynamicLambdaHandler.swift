//
//  DynamicLambdaHandler.swift
//
//
//  Created by Bill Gestrich on 1/29/22.
//

import AWSLambdaRuntime
import Foundation
import NIO

@available(macOS 12.0, *)
public struct DynamicLambdaHandler: ByteBufferLambdaHandler {

    private let handlers: [AnyLambdaHandler]

    public init(handlers: [AnyLambdaHandler]){
        self.handlers = handlers
    }

    //MARK: ByteBufferLambdaHandler conformance
    @available(macOS 12.0, *)
    public func handle(context: Lambda.Context, event: ByteBuffer) -> EventLoopFuture<ByteBuffer?> {
        return context.eventLoop.asyncFuture {
            return try await handleAsync(context: context, event: event)
        }
    }

    //Async variant
    @available(macOS 12.0, *)
    private func handleAsync(context: Lambda.Context, event: ByteBuffer) async throws -> ByteBuffer? {
        for handler in handlers {
            if handler.supportsInput(event) {
                let result = try await handler.handle(context: context, event: event).awaitFuture()
                return result
            }
        }

        throw CodecError.unmatchedHandler
    }

    enum CodecError: Error {
        case unmatchedHandler
    }
}

public extension EventLoopLambdaHandler {
    func erased() -> AnyLambdaHandler {
        return AnyLambdaHandler(handler: self)
    }
}

public struct AnyLambdaHandler {

    fileprivate let handlerBlock: (Lambda.Context, ByteBuffer) -> EventLoopFuture<ByteBuffer?>
    fileprivate let supportsInputBlock: (ByteBuffer) -> Bool

    public init<T: EventLoopLambdaHandler>(handler: T) {
        self.handlerBlock = { (context, event) -> EventLoopFuture<ByteBuffer?> in
            return handler.handle(context: context, event: event)
        }

        self.supportsInputBlock = { (input) -> Bool in
            do {
                let _ = try handler.decode(buffer: input)
                return true
            } catch {
                return false
            }
        }
    }

    fileprivate func handle(context : Lambda.Context, event: ByteBuffer) -> EventLoopFuture<ByteBuffer?> {
        return handlerBlock(context, event)
    }

    fileprivate func supportsInput(_ input: ByteBuffer) -> Bool {
        return supportsInputBlock(input)
    }
}

