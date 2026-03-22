#import <Foundation/Foundation.h>
#import "ViXPCProtocols.h"

/*
 * Wrapper that bridges Nu scripts to the XPC back-channel.
 *
 * Nu scripts call methods like (shellCommand exitWithObject:someDict)
 * using `id` parameters. NSXPCConnection requires concrete types, so
 * this wrapper serializes `id` to JSON and forwards via the XPC protocol.
 */
@interface ViXPCBackChannelProxy : NSObject

- (instancetype)initWithXPCProxy:(id<ViShellThingXPCProtocol>)proxy;

/* Methods matching the old ViShellThingProtocol signatures for Nu compatibility */
- (void)exit;
- (void)exitWithObject:(id)obj;
- (void)exitWithError:(int)code;
- (void)log:(NSString *)message;

@end
