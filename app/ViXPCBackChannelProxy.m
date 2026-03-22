#import "ViXPCBackChannelProxy.h"

@implementation ViXPCBackChannelProxy
{
	id<ViShellThingXPCProtocol> _xpcProxy;
}

- (instancetype)initWithXPCProxy:(id<ViShellThingXPCProtocol>)proxy
{
	if ((self = [super init]) != nil) {
		_xpcProxy = proxy;
	}
	return self;
}

- (void)exit
{
	[_xpcProxy exitWithCode:0];
}

- (void)exitWithObject:(id)obj
{
	NSString *json = nil;
	if (obj != nil) {
		NSError *error = nil;
		NSData *data = [NSJSONSerialization dataWithJSONObject:obj
		                                              options:0
		                                                error:&error];
		if (data != nil)
			json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	}
	[_xpcProxy exitWithJSONString:json];
}

- (void)exitWithError:(int)code
{
	[_xpcProxy exitWithCode:code];
}

- (void)log:(NSString *)message
{
	[_xpcProxy log:message];
}

@end
