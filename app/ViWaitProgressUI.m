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

#import "ViWaitProgressUI.h"
#import "ViTaskRunner.h"

@implementation ViWaitProgressUI

+ (BOOL)createWaitProgressWindowWithOwner:(id)owner
{
	NSWindow *win = [[NSWindow alloc] initWithContentRect:NSMakeRect(717, 630, 329, 85)
						    styleMask:NSWindowStyleMaskTitled
						      backing:NSBackingStoreBuffered
							defer:YES];
	[win setTitle:@"Window"];

	NSView *contentView = [win contentView];

	NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(17, 48, 295, 17)];
	[label setStringValue:@"Label"];
	[label setEditable:NO];
	[label setBordered:NO];
	[label setDrawsBackground:NO];
	[label setFont:[NSFont systemFontOfSize:13.0]];
	[label setLineBreakMode:NSLineBreakByClipping];
	[contentView addSubview:label];

	NSProgressIndicator *progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(18, 18, 201, 20)];
	[progress setMaxValue:100];
	[progress setIndeterminate:YES];
	[progress setStyle:NSProgressIndicatorStyleBar];
	[contentView addSubview:progress];

	NSButton *cancel = [[NSButton alloc] initWithFrame:NSMakeRect(219, 12, 96, 32)];
	[cancel setTitle:@"Cancel"];
	[cancel setBezelStyle:NSBezelStyleRounded];
	[cancel setKeyEquivalent:@"\033"]; // Escape
	[cancel setTarget:owner];
	[cancel setAction:@selector(cancelTask:)];
	[contentView addSubview:cancel];

	[owner setValue:win forKey:@"waitWindow"];
	[owner setValue:cancel forKey:@"cancelButton"];
	[owner setValue:progress forKey:@"progressIndicator"];
	[owner setValue:label forKey:@"waitLabel"];

	return YES;
}

@end
