/*
 * Copyright (c) 2008-2012 Martin Hedenfalk <martin@vicoapp.com>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import <Foundation/Foundation.h>

/* Protocol for commands sent from vicotool to the Vico app. */
@protocol ViShellCommandXPCProtocol <NSObject>

- (void)pingWithReply:(void (^)(void))reply;

- (void)evalScript:(NSString *)script
 additionalBindings:(NSDictionary *)bindings
          withReply:(void (^)(NSString *result, NSString *errorString))reply;

- (void)openURL:(NSString *)pathOrURL
        andWait:(BOOL)waitFlag
      withReply:(void (^)(NSString *errorDescription))reply;

- (void)setStartupBasePath:(NSString *)basePath;

- (void)newDocumentWithData:(NSData *)data
                    andWait:(BOOL)waitFlag
                  withReply:(void (^)(NSString *errorDescription))reply;

- (void)newProject;

@end

/* Protocol for callbacks sent from the Vico app back to vicotool. */
@protocol ViShellThingXPCProtocol <NSObject>

- (void)exitWithCode:(int)code;
- (void)exitWithJSONString:(NSString *)json;
- (void)log:(NSString *)message;

@end
