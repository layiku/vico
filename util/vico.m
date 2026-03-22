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

#import <Cocoa/Cocoa.h>

#include <sys/time.h>

#include <err.h>
#include <stdlib.h>
#include <unistd.h>

#import "ViXPCProtocols.h"

BOOL keepRunning = YES;
int returnCode = 0;
NSString *returnJSONString = nil;

@interface ShellThing : NSObject <ViShellThingXPCProtocol>
@end

@implementation ShellThing

- (void)exitWithCode:(int)code
{
	returnCode = code;
	keepRunning = NO;
	CFRunLoopStop(CFRunLoopGetMain());
}

- (void)exitWithJSONString:(NSString *)json
{
	returnJSONString = json;
	keepRunning = NO;
	CFRunLoopStop(CFRunLoopGetMain());
}

- (void)log:(NSString *)message
{
	fprintf(stderr, "%s\n", [message UTF8String]);
}

@end

void
usage(void)
{
	printf("syntax: vicotool [options] [file ...]    edit specified file(s)\n");
	printf("    or: vicotool [options] -             read text from stdin\n");
	printf("options:\n");
	printf("    -h            show this help\n");
	printf("    -e string     evaluate the string as a Nu script\n");
	printf("    -f file       read file and evaluate as a Nu script\n");
	printf("    -n            open files in a new window\n");
	printf("    -p params     read script parameters as a JSON string\n");
	printf("    -p -          read script parameters as JSON from standard input\n");
	printf("    -r            enter runloop (don't exit script immediately)\n");
	printf("    -w            wait for document to close\n");
}

id jsonValueFor(NSString *json) {
	NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
	if (data == nil)
		return nil;
	return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

static BOOL
connectToVico(NSXPCConnection **outConn, id<ViShellCommandXPCProtocol> *outProxy, BOOL needBackChannel)
{
	NSXPCConnection *conn = [[NSXPCConnection alloc] initWithMachServiceName:@"se.bzero.vico.ipc"
	                                                                 options:0];
	conn.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(ViShellCommandXPCProtocol)];

	if (needBackChannel) {
		conn.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(ViShellThingXPCProtocol)];
		conn.exportedObject = [[ShellThing alloc] init];
	}

	[conn resume];

	/* Try a ping to verify the connection is live. */
	__block BOOL connected = NO;
	dispatch_semaphore_t sem = dispatch_semaphore_create(0);

	id<ViShellCommandXPCProtocol> proxy = [conn remoteObjectProxyWithErrorHandler:^(NSError *error) {
		dispatch_semaphore_signal(sem);
	}];

	[proxy pingWithReply:^{
		connected = YES;
		dispatch_semaphore_signal(sem);
	}];

	dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));

	if (connected) {
		*outConn = conn;
		*outProxy = proxy;
		return YES;
	}

	[conn invalidate];
	return NO;
}

int
main(int argc, char **argv)
{
	NSString				*script = nil;
	NSString				*script_path = nil;
	NSString				*json;
	NSError					*error = nil;
	NSFileHandle				*handle;
	NSMutableDictionary			*bindings = nil;
	NSDictionary				*params;
	const char				*eval_script = NULL;
	const char				*eval_file = NULL;
	int					 i, c;
	BOOL					 runLoop = NO;
	BOOL					 params_from_stdin = NO;
	BOOL					 wait_for_close = NO;
	BOOL					 new_window = NO;
	BOOL					 wasRunning = YES;

	@autoreleasepool {
		bindings = [NSMutableDictionary dictionary];

		while ((c = getopt(argc, argv, "e:f:hnp:rw")) != -1) {
			switch (c) {
			case 'e':
				eval_script = optarg;
				break;
			case 'f':
				eval_file = optarg;
				break;
			case 'h':
				usage();
				return 0;
			case 'n':
				new_window = YES;
				break;
			case 'p':
				if (strcmp(optarg, "-") == 0) {
					params_from_stdin = YES;
				} else {
					if ((json = [NSString stringWithUTF8String:optarg]) == nil)
						errx(1, "parameters not proper UTF8");
					if ((params = jsonValueFor(json)) == nil)
						errx(1, "parameters not proper JSON");
					if (![params isKindOfClass:[NSDictionary class]])
						errx(1, "parameters not a JSON object");
					[bindings addEntriesFromDictionary:params];
				}
				break;
			case 'r':
				runLoop = YES;
				break;
			case 'w':
				wait_for_close = YES;
				break;
			case '?':
			default:
				exit(1);
			}
		}

		/*
		 * Treat remainder of arguments as files that should be opened.
		 */
		argc -= optind;
		argv += optind;

		if (argc > 1 && wait_for_close)
			errx(6, "can't wait for multiple files");
		if (argc == 0 && wait_for_close)
			errx(6, "no document to wait for");
		if (runLoop && eval_script == nil && eval_file == nil)
			errx(6, "no script to wait for");

		if (wait_for_close && (eval_script || eval_file))
			errx(1, "can't both evaluate script and wait for document");

		if (eval_file) {
			if (strcmp(eval_file, "-") == 0) {
				handle = [NSFileHandle fileHandleWithStandardInput];
				script_path = @"stdin";
			} else {
				script_path = [[NSString stringWithUTF8String:eval_file] stringByExpandingTildeInPath];
				NSURL *url = [NSURL fileURLWithPath:script_path isDirectory:NO];
				handle = [NSFileHandle fileHandleForReadingFromURL:url error:&error];
			}

			if (error)
				errx(2, "%s: %s", eval_file, [[error localizedDescription] UTF8String]);
			NSData *data = [handle readDataToEndOfFile];
			if (data == nil)
				errx(2, "%s: read failure", eval_file);
			script = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
			if (script == nil)
				errx(2, "%s: invalid UTF8 encoding", eval_file);
		} else if (eval_script) {
			script_path = @"command line";
			script = [NSString stringWithUTF8String:eval_script];
			if (script == nil)
				errx(2, "invalid UTF8 encoding");
		}

		if (params_from_stdin) {
			handle = [NSFileHandle fileHandleWithStandardInput];
			NSData *data = [handle readDataToEndOfFile];
			if (data == nil)
				errx(2, "stdin: read failure");
			if ((json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]) == nil)
				errx(1, "parameters not proper UTF8");

			if ((params = jsonValueFor(json)) == nil)
				errx(1, "parameters not proper JSON");
			if (![params isKindOfClass:[NSDictionary class]])
				errx(1, "parameters not a JSON object");
			[bindings addEntriesFromDictionary:params];
		}

		/* Connect to Vico app via XPC */
		BOOL needBackChannel = (runLoop || wait_for_close);
		NSXPCConnection *conn = nil;
		id<ViShellCommandXPCProtocol> proxy = nil;

		if (!connectToVico(&conn, &proxy, needBackChannel)) {
			wasRunning = NO;

			/* Failed to connect, try to start Vico */
			NSMutableArray *openArgs = [NSMutableArray arrayWithObjects:@"-b", @"se.bzero.Vico", nil];
			if (argc > 0)
				[openArgs addObjectsFromArray:@[@"--args", @"-skip-untitled"]];

			NSTask *openTask = [[NSTask alloc] init];
			[openTask setExecutableURL:[NSURL fileURLWithPath:@"/usr/bin/open"]];
			[openTask setArguments:openArgs];
			NSError *taskError = nil;
			if (![openTask launchAndReturnError:&taskError])
				errx(1, "failed to start Vico");

			/* Poll until Vico responds */
			for (i = 0; i < 50; i++) {
				usleep(200000); // sleep for 0.2 seconds
				if (connectToVico(&conn, &proxy, needBackChannel))
					break;
			}

			if (conn == nil)
				errx(1, "failed to connect");
		}

		if (script) {
			dispatch_semaphore_t sem = dispatch_semaphore_create(0);
			__block NSString *errStr = nil;
			__block NSString *result = nil;
			[proxy evalScript:script
			additionalBindings:bindings
				 withReply:^(NSString *r, NSString *e) {
				result = r;
				errStr = e;
				dispatch_semaphore_signal(sem);
			}];
			dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

			if (errStr) {
				fprintf(stderr, "%s\n", [errStr UTF8String]);
				return 3;
			}
			if (!runLoop && [result length] > 0)
				printf("%s\n", [result UTF8String]);
		}

		if (argc > 0 && new_window)
			[proxy newProject];

		NSString *basePath = [[NSFileManager defaultManager] currentDirectoryPath];
		for (i = 0; i < argc; i++) {
			NSString *path = [NSString stringWithUTF8String:argv[i]];

			if (i == 0 && [path isEqualToString:@"-"]) {
				handle = [NSFileHandle fileHandleWithStandardInput];
				NSData *data = [handle readDataToEndOfFile];
				dispatch_semaphore_t sem = dispatch_semaphore_create(0);
				__block NSString *errDesc = nil;
				[proxy newDocumentWithData:data andWait:wait_for_close withReply:^(NSString *e) {
					errDesc = e;
					dispatch_semaphore_signal(sem);
				}];
				dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
				if (errDesc)
					errx(2, "%s", [errDesc UTF8String]);
				break;
			}

			if ([path rangeOfString:@"://"].location == NSNotFound) {
				path = [path stringByExpandingTildeInPath];
				if (![path isAbsolutePath])
					path = [basePath stringByAppendingPathComponent:path];
				path = [[[NSURL fileURLWithPath:path] URLByResolvingSymlinksInPath] absoluteString];
			}

			dispatch_semaphore_t sem = dispatch_semaphore_create(0);
			__block NSString *errDesc = nil;
			[proxy openURL:path andWait:wait_for_close withReply:^(NSString *e) {
				errDesc = e;
				dispatch_semaphore_signal(sem);
			}];
			dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

			if (errDesc)
				errx(2, "%s: %s", argv[i], [errDesc UTF8String]);
		}

		if (!wasRunning) {
			[proxy setStartupBasePath:basePath];
		}

		if (argc == 0 && script == nil) {
			/* Just activate Vico */
			dispatch_semaphore_t sem = dispatch_semaphore_create(0);
			[proxy evalScript:@"((NSApplication sharedApplication) activateIgnoringOtherApps:YES)"
			additionalBindings:nil
				 withReply:^(NSString *r, NSString *e) {
				dispatch_semaphore_signal(sem);
			}];
			dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
		}

		if ((runLoop && script) || wait_for_close) {
			NSRunLoop *loop = [NSRunLoop currentRunLoop];
			while (keepRunning && [loop runMode:NSDefaultRunLoopMode
						 beforeDate:[NSDate distantFuture]])
				;

			if (returnJSONString != nil)
				printf("%s\n", [returnJSONString UTF8String]);
		}

		[conn invalidate];
	}

	return returnCode;
}
