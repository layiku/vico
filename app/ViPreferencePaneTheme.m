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

#import "ViPreferencePaneTheme.h"
#import "ViThemeStore.h"
#include "logging.h"

@implementation ViPreferencePaneTheme

- (id)init
{
	self = [super initWithNib:nil
			     name:@"Fonts & Colors"
			     icon:[NSImage imageNamed:NSImageNameColorPanel]];
	if (self == nil)
		return nil;

	[self buildView];

	ViThemeStore *ts = [ViThemeStore defaultStore];
	NSArray *themes = [ts availableThemes];
	for (NSString *theme in [themes sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)])
		[themeButton addItemWithTitle:theme];
	[themeButton selectItem:[themeButton itemWithTitle:[[ts defaultTheme] name]]];

	[[NSUserDefaults standardUserDefaults] addObserver:self
						forKeyPath:@"fontsize"
						   options:NSKeyValueObservingOptionNew
						   context:NULL];
	[[NSUserDefaults standardUserDefaults] addObserver:self
						forKeyPath:@"fontname"
						   options:NSKeyValueObservingOptionNew
						   context:NULL];

	[self setSelectedFont];

	return self;
}

- (void)buildView
{
	NSUserDefaultsController *udc = [NSUserDefaultsController sharedUserDefaultsController];

	// Root view (480×209)
	view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 209)];

	// "Theme:" label at {17, 172, 52, 17}
	NSTextField *themeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(17, 172, 52, 17)];
	[themeLabel setStringValue:@"Theme:"];
	[themeLabel setEditable:NO];
	[themeLabel setBordered:NO];
	[themeLabel setDrawsBackground:NO];
	[themeLabel setFont:[NSFont systemFontOfSize:13.0]];
	[view addSubview:themeLabel];

	// Theme popup at {71, 166, 307, 26}
	themeButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(71, 166, 307, 26) pullsDown:NO];
	[themeButton bind:@"selectedValue"
		 toObject:udc
	      withKeyPath:@"values.theme"
		  options:nil];
	[view addSubview:themeButton];

	// "Font:" label at {31, 130, 38, 17}
	NSTextField *fontLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(31, 130, 38, 17)];
	[fontLabel setStringValue:@"Font:"];
	[fontLabel setEditable:NO];
	[fontLabel setBordered:NO];
	[fontLabel setDrawsBackground:NO];
	[fontLabel setFont:[NSFont systemFontOfSize:13.0]];
	[view addSubview:fontLabel];

	// Font display field at {74, 128, 301, 22}
	currentFont = [[NSTextField alloc] initWithFrame:NSMakeRect(74, 128, 301, 22)];
	[currentFont setEditable:NO];
	[currentFont setSelectable:YES];
	[currentFont setBezeled:YES];
	[currentFont setDrawsBackground:YES];
	[currentFont setFont:[NSFont systemFontOfSize:13.0]];
	[view addSubview:currentFont];

	// "Select..." button at {377, 120, 89, 32}
	NSButton *selectButton = [[NSButton alloc] initWithFrame:NSMakeRect(377, 120, 89, 32)];
	[selectButton setTitle:@"Select..."];
	[selectButton setBezelStyle:NSBezelStyleRounded];
	[selectButton setTarget:self];
	[selectButton setAction:@selector(selectFont:)];
	[view addSubview:selectButton];

	// "Anti-alias" checkbox at {72, 104, 84, 18}
	NSButton *antiAlias = [NSButton checkboxWithTitle:@"Anti-alias" target:nil action:nil];
	[antiAlias setFrame:NSMakeRect(72, 104, 84, 18)];
	[antiAlias bind:@"value" toObject:udc withKeyPath:@"values.antialias" options:nil];
	[view addSubview:antiAlias];

	// "Highlight current screen line" checkbox at {72, 84, 202, 18}
	NSButton *cursorLine = [NSButton checkboxWithTitle:@"Highlight current screen line" target:nil action:nil];
	[cursorLine setFrame:NSMakeRect(72, 84, 202, 18)];
	[cursorLine bind:@"value" toObject:udc withKeyPath:@"values.cursorline" options:nil];
	[view addSubview:cursorLine];

	// "Highlight matching smart pairs" checkbox at {72, 64, 219, 18}
	NSButton *matchParen = [NSButton checkboxWithTitle:@"Highlight matching smart pairs" target:nil action:nil];
	[matchParen setFrame:NSMakeRect(72, 64, 219, 18)];
	[matchParen bind:@"value" toObject:udc withKeyPath:@"values.matchparen" options:nil];
	[view addSubview:matchParen];

	// "Flash matching pair briefly" checkbox at {86, 44, 190, 18}
	NSButton *flashParen = [NSButton checkboxWithTitle:@"Flash matching pair briefly" target:nil action:nil];
	[flashParen setFrame:NSMakeRect(86, 44, 190, 18)];
	[flashParen bind:@"value" toObject:udc withKeyPath:@"values.flashparen" options:nil];
	[flashParen bind:@"enabled" toObject:udc withKeyPath:@"values.matchparen" options:nil];
	[view addSubview:flashParen];

	// "Blink caret in mode:" label at {71, 20, 130, 17}
	NSTextField *blinkLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(71, 20, 130, 17)];
	[blinkLabel setStringValue:@"Blink caret in mode:"];
	[blinkLabel setEditable:NO];
	[blinkLabel setBordered:NO];
	[blinkLabel setDrawsBackground:NO];
	[blinkLabel setFont:[NSFont systemFontOfSize:13.0]];
	[view addSubview:blinkLabel];

	// Blink mode popup at {203, 14, 145, 26}
	NSPopUpButton *blinkMode = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(203, 14, 145, 26) pullsDown:NO];
	[blinkMode addItemWithTitle:@"Insert mode"];
	[[blinkMode lastItem] setTag:2];
	[blinkMode addItemWithTitle:@"Normal mode"];
	[[blinkMode lastItem] setTag:5];
	[blinkMode addItemWithTitle:@"Both"];
	[[blinkMode lastItem] setTag:7];
	[blinkMode addItemWithTitle:@"Never"];
	[[blinkMode lastItem] setTag:0];
	[blinkMode bind:@"selectedTag"
		toObject:udc
	     withKeyPath:@"values.blinkmode"
		 options:@{NSValueTransformerNameBindingOption: @"caretBlinkModeTransformer"}];
	[view addSubview:blinkMode];
}

#pragma mark -
#pragma mark Font selection

- (void)setSelectedFont
{
	NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
	[currentFont setStringValue:[NSString stringWithFormat:@"%@ %.1fpt",
	    [defs stringForKey:@"fontname"],
	    [defs floatForKey:@"fontsize"]]];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
		      ofObject:(id)object
			change:(NSDictionary *)change
		       context:(void *)context
{
//	if ([keyPath isEqualToString:@"fontsize"] || [keyPath isEqualToString:@"fontname"])
	[self setSelectedFont];
}

- (IBAction)selectFont:(id)sender
{
	NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
	NSFontManager *fontManager = [NSFontManager sharedFontManager];
	NSFont *font = [NSFont fontWithName:[defs stringForKey:@"fontname"]
				       size:[defs floatForKey:@"fontsize"]];
	[fontManager setTarget:self];
	[fontManager setSelectedFont:font isMultiple:NO];
	[fontManager orderFrontFontPanel:nil];
}

- (void)changeAttributes:(id)sender
{
	DEBUG(@"sender is %@", sender);
}

- (void)changeFont:(id)sender
{
	DEBUG(@"sender is %@", sender);
	NSFontManager *fontManager = [NSFontManager sharedFontManager];
	NSFont *font = [fontManager convertFont:[fontManager selectedFont]];
	[[NSUserDefaults standardUserDefaults] setObject:[font fontName]
						  forKey:@"fontname"];
	NSNumber *fontSize = [NSNumber numberWithFloat:[font pointSize]];
	[[NSUserDefaults standardUserDefaults] setObject:fontSize
						  forKey:@"fontsize"];
}

@end
