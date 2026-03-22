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

#import "ViPreferencePaneGeneral.h"
#import "ViBundleStore.h"

@implementation undoStyleTagTransformer
+ (Class)transformedValueClass { return [NSNumber class]; }
+ (BOOL)allowsReverseTransformation { return YES; }
- (id)init { return [super init]; }
- (id)transformedValue:(id)value
{
	if ([value isKindOfClass:[NSNumber class]]) {
		switch ([value integerValue]) {
		case 2:
			return @"nvi";
		case 1:
		default:
			return @"vim";
		}
	} else if ([value isKindOfClass:[NSString class]]) {
		int tag = 1;
		if ([value isEqualToString:@"nvi"])
			tag = 2;
		return [NSNumber numberWithInt:tag];
	}

	return nil;
}
@end

@implementation ViPreferencePaneGeneral

- (id)init
{
	self = [super initWithNib:nil
			     name:@"General"
			     icon:[NSImage imageNamed:NSImageNamePreferencesGeneral]];
	if (self == nil)
		return nil;

	/* Convert between tags and undo style strings (vim and nvi). */
	[NSValueTransformer setValueTransformer:[[undoStyleTagTransformer alloc] init]
					forName:@"undoStyleTagTransformer"];

	[self buildView];

	[defaultSyntaxButton removeAllItems];
	NSArray *sortedLanguages = [[ViBundleStore defaultStore] sortedLanguages];
	for (ViLanguage *lang in sortedLanguages) {
		NSMenuItem *item;
		item = [[defaultSyntaxButton menu] addItemWithTitle:[lang displayName] action:nil keyEquivalent:@""];
		[item setRepresentedObject:[lang name]];
	}

	NSString *defaultName = [[[ViBundleStore defaultStore] defaultLanguage] displayName];
	if (defaultName)
		[defaultSyntaxButton selectItemWithTitle:defaultName];

	return self;
}

- (void)buildView
{
	NSUserDefaultsController *udc = [NSUserDefaultsController sharedUserDefaultsController];

	// Root view (480×326)
	view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 326)];

	// --- Search section ---

	// "Ignore case in searches" checkbox at {18, 290, 170, 18}
	NSButton *ignoreCase = [NSButton checkboxWithTitle:@"Ignore case in searches" target:nil action:nil];
	[ignoreCase setFrame:NSMakeRect(18, 290, 170, 18)];
	[ignoreCase setToolTip:@":set ignorecase"];
	[ignoreCase bind:@"value" toObject:udc withKeyPath:@"values.ignorecase" options:nil];
	[view addSubview:ignoreCase];

	// "unless pattern includes uppercase letters" at {36, 270, 282, 18}
	NSButton *smartCase = [NSButton checkboxWithTitle:@"unless pattern includes uppercase letters" target:nil action:nil];
	[smartCase setFrame:NSMakeRect(36, 270, 282, 18)];
	[smartCase setToolTip:@":set smartcase"];
	[smartCase bind:@"value" toObject:udc withKeyPath:@"values.smartcase" options:nil];
	[smartCase bind:@"enabled" toObject:udc withKeyPath:@"values.ignorecase" options:nil];
	[view addSubview:smartCase];

	// "Show line numbers" at {18, 248, 142, 18}
	NSButton *lineNumbers = [NSButton checkboxWithTitle:@"Show line numbers" target:nil action:nil];
	[lineNumbers setFrame:NSMakeRect(18, 248, 142, 18)];
	[lineNumbers setToolTip:@":set number"];
	[lineNumbers bind:@"value" toObject:udc withKeyPath:@"values.number" options:nil];
	[view addSubview:lineNumbers];

	// "count lines relative to the cursor" at {36, 228, 227, 18}
	NSButton *relativeNumber = [NSButton checkboxWithTitle:@"count lines relative to the cursor" target:nil action:nil];
	[relativeNumber setFrame:NSMakeRect(36, 228, 227, 18)];
	[relativeNumber setToolTip:@":set relativenumber"];
	[relativeNumber bind:@"value" toObject:udc withKeyPath:@"values.relativenumber" options:nil];
	[relativeNumber bind:@"enabled" toObject:udc withKeyPath:@"values.number" options:nil];
	[view addSubview:relativeNumber];

	// "Show invisibles" at {18, 208, 118, 18}
	NSButton *showInvisibles = [NSButton checkboxWithTitle:@"Show invisibles" target:nil action:nil];
	[showInvisibles setFrame:NSMakeRect(18, 208, 118, 18)];
	[showInvisibles setToolTip:@":set list"];
	[showInvisibles bind:@"value" toObject:udc withKeyPath:@"values.list" options:nil];
	[view addSubview:showInvisibles];

	// "Show page guide" at {18, 188, 130, 18}
	NSButton *showGuide = [NSButton checkboxWithTitle:@"Show page guide" target:nil action:nil];
	[showGuide setFrame:NSMakeRect(18, 188, 130, 18)];
	[showGuide setToolTip:@":set showguide"];
	[showGuide bind:@"value" toObject:udc withKeyPath:@"values.showguide" options:nil];
	[view addSubview:showGuide];

	// "Display at column:" label at {35, 165, 122, 17}
	NSTextField *guideLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(35, 165, 122, 17)];
	[guideLabel setStringValue:@"Display at column:"];
	[guideLabel setEditable:NO];
	[guideLabel setBordered:NO];
	[guideLabel setDrawsBackground:NO];
	[guideLabel setFont:[NSFont systemFontOfSize:13.0]];
	[guideLabel bind:@"enabled" toObject:udc withKeyPath:@"values.showguide" options:nil];
	[view addSubview:guideLabel];

	// Guide column number field at {162, 163, 60, 22}
	NSTextField *guideColumn = [[NSTextField alloc] initWithFrame:NSMakeRect(162, 163, 60, 22)];
	[guideColumn setEditable:YES];
	[guideColumn setBezeled:YES];
	[guideColumn setDrawsBackground:YES];
	NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
	[formatter setMinimum:@1];
	[formatter setNumberStyle:NSNumberFormatterNoStyle];
	[[guideColumn cell] setFormatter:formatter];
	[guideColumn bind:@"value" toObject:udc withKeyPath:@"values.guidecolumn" options:nil];
	[guideColumn bind:@"enabled" toObject:udc withKeyPath:@"values.showguide" options:nil];
	[view addSubview:guideColumn];

	// --- Separator at {12, 152, 456, 5} ---
	NSBox *sep1 = [[NSBox alloc] initWithFrame:NSMakeRect(12, 152, 456, 5)];
	[sep1 setBoxType:NSBoxSeparator];
	[view addSubview:sep1];

	// --- Undo section ---

	// "Undo style:" label at {17, 129, 75, 17}
	NSTextField *undoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(17, 129, 75, 17)];
	[undoLabel setStringValue:@"Undo style:"];
	[undoLabel setEditable:NO];
	[undoLabel setBordered:NO];
	[undoLabel setDrawsBackground:NO];
	[undoLabel setFont:[NSFont systemFontOfSize:13.0]];
	[view addSubview:undoLabel];

	// Undo style radio group at {32, 83, 247, 38}
	NSButtonCell *prototype = [[NSButtonCell alloc] init];
	[prototype setButtonType:NSButtonTypeRadio];
	[prototype setFont:[NSFont systemFontOfSize:13.0]];
	NSMatrix *undoMatrix = [[NSMatrix alloc] initWithFrame:NSMakeRect(32, 83, 247, 38)
							  mode:NSRadioModeMatrix
						     prototype:prototype
					      numberOfRows:2
					   numberOfColumns:1];
	[undoMatrix setToolTip:@":set undostyle"];
	[undoMatrix setCellSize:NSMakeSize(247, 18)];
	[undoMatrix setIntercellSpacing:NSMakeSize(0, 2)];
	NSArray *cells = [undoMatrix cells];
	[[cells objectAtIndex:0] setTitle:@"Vim (u command keeps undoing)"];
	[[cells objectAtIndex:0] setTag:1];
	[[cells objectAtIndex:1] setTitle:@"nvi (dot command repeats undo)"];
	[[cells objectAtIndex:1] setTag:2];
	[undoMatrix bind:@"selectedTag"
		toObject:udc
	     withKeyPath:@"values.undostyle"
		 options:@{NSValueTransformerNameBindingOption: @"undoStyleTagTransformer"}];
	[view addSubview:undoMatrix];

	// --- Separator at {12, 72, 456, 5} ---
	NSBox *sep2 = [[NSBox alloc] initWithFrame:NSMakeRect(12, 72, 456, 5)];
	[sep2 setBoxType:NSBoxSeparator];
	[view addSubview:sep2];

	// --- Bottom section ---

	// "Default language syntax for new files:" label at {17, 48, 243, 17}
	NSTextField *syntaxLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(17, 48, 243, 17)];
	[syntaxLabel setStringValue:@"Default language syntax for new files:"];
	[syntaxLabel setEditable:NO];
	[syntaxLabel setBordered:NO];
	[syntaxLabel setDrawsBackground:NO];
	[syntaxLabel setFont:[NSFont systemFontOfSize:13.0]];
	[view addSubview:syntaxLabel];

	// Default syntax popup at {262, 42, 201, 26}
	defaultSyntaxButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(262, 42, 201, 26) pullsDown:NO];
	[defaultSyntaxButton bind:@"selectedObject"
			 toObject:udc
		      withKeyPath:@"values.defaultsyntax"
			  options:nil];
	[view addSubview:defaultSyntaxButton];

	// "By default, documents open in:" label at {59, 22, 201, 17}
	NSTextField *tabLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(59, 22, 201, 17)];
	[tabLabel setStringValue:@"By default, documents open in:"];
	[tabLabel setEditable:NO];
	[tabLabel setBordered:NO];
	[tabLabel setDrawsBackground:NO];
	[tabLabel setFont:[NSFont systemFontOfSize:13.0]];
	[view addSubview:tabLabel];

	// Tab preference popup at {262, 16, 201, 26}
	NSPopUpButton *tabPref = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(262, 16, 201, 26) pullsDown:NO];
	[tabPref addItemWithTitle:@"Tabs"];
	[[tabPref lastItem] setTag:1];
	[tabPref addItemWithTitle:@"Windows"];
	[[tabPref lastItem] setTag:0];
	[tabPref setToolTip:@":set prefertabs"];
	[tabPref bind:@"selectedTag" toObject:udc withKeyPath:@"values.prefertabs" options:nil];
	[view addSubview:tabPref];
}

@end
