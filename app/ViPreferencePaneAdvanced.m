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

#import "ViPreferencePaneAdvanced.h"
#include "logging.h"

@implementation environmentVariableTransformer
+ (Class)transformedValueClass { return [NSDictionary class]; }
+ (BOOL)allowsReverseTransformation { return YES; }
- (id)init { return [super init]; }
- (id)transformedValue:(id)value
{
	if ([value isKindOfClass:[NSDictionary class]]) {
		/* Create an array of dictionaries with keys "name" and "value". */
		NSMutableArray *a = [NSMutableArray array];
		NSDictionary *dict = value;
		NSArray *keys = [[dict allKeys] sortedArrayUsingComparator:^(id a, id b) {
			return [(NSString *)a compare:b];
		}];
		for (NSString *key in keys) {
			[a addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:
				[key mutableCopy], @"name",
				[[dict objectForKey:key] mutableCopy], @"value",
				nil]];
		}
		return a;
	} else if ([value isKindOfClass:[NSArray class]]) {
		NSArray *a = [(NSArray *)value sortedArrayUsingComparator:^(id a, id b) {
			return [[(NSDictionary *)a objectForKey:@"name"] compare:[(NSDictionary *)b objectForKey:@"name"]];
		}];
		NSMutableDictionary *dict = [NSMutableDictionary dictionary];
		for (NSDictionary *pair in a) {
			NSMutableString *key = [[pair objectForKey:@"name"] mutableCopy];
			NSMutableString *value = [[pair objectForKey:@"value"] mutableCopy];
			[dict setObject:value forKey:key];
		}
		return dict;
	}

	return nil;
}
@end

@implementation ViPreferencePaneAdvanced

- (id)init
{
	self = [super initWithNib:nil
			     name:@"Advanced"
			     icon:[NSImage imageNamed:NSImageNameAdvanced]];
	if (self == nil)
		return nil;

	[NSValueTransformer setValueTransformer:[[environmentVariableTransformer alloc] init]
					forName:@"environmentVariableTransformer"];

	[self buildView];

	return self;
}

- (void)buildView
{
	NSUserDefaultsController *udc = [NSUserDefaultsController sharedUserDefaultsController];

	// Root view (480×401)
	view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 401)];

	// --- Environment variables section ---

	// "Environment variables:" label at {17, 374, 155, 17}
	NSTextField *envLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(17, 374, 155, 17)];
	[envLabel setStringValue:@"Environment variables:"];
	[envLabel setEditable:NO];
	[envLabel setBordered:NO];
	[envLabel setDrawsBackground:NO];
	[envLabel setFont:[NSFont systemFontOfSize:13.0]];
	[view addSubview:envLabel];

	// NSArrayController for environment variables
	arrayController = [[NSArrayController alloc] init];
	[arrayController setObjectClass:[NSMutableDictionary class]];
	[arrayController bind:@"contentArray"
		     toObject:udc
		  withKeyPath:@"values.environment"
		      options:@{
			NSValueTransformerNameBindingOption: @"environmentVariableTransformer",
			@"NSHandlesContentAsCompoundValue": @YES
		      }];

	// NSScrollView + NSTableView at {18, 130, 444, 240}
	NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(18, 130, 444, 240)];
	[scrollView setHasVerticalScroller:YES];
	[scrollView setHasHorizontalScroller:NO];
	[scrollView setBorderType:NSBezelBorder];
	[scrollView setAutohidesScrollers:YES];

	tableView = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 444, 240)];
	[tableView setAutosaveName:@"environmentTable"];
	[tableView setAllowsColumnReordering:YES];
	[tableView setAllowsColumnResizing:YES];
	[tableView setAllowsMultipleSelection:NO];

	// "Variable Name" column (144px)
	NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
	[[nameColumn headerCell] setStringValue:@"Variable Name"];
	[nameColumn setWidth:144];
	[nameColumn setEditable:YES];
	[nameColumn bind:@"value"
		toObject:arrayController
	     withKeyPath:@"arrangedObjects.name"
		 options:nil];
	[tableView addTableColumn:nameColumn];

	// "Value" column (288px)
	NSTableColumn *valueColumn = [[NSTableColumn alloc] initWithIdentifier:@"value"];
	[[valueColumn headerCell] setStringValue:@"Value"];
	[valueColumn setWidth:288];
	[valueColumn setEditable:YES];
	[valueColumn bind:@"value"
		 toObject:arrayController
	      withKeyPath:@"arrangedObjects.value"
		  options:nil];
	[tableView addTableColumn:valueColumn];

	[scrollView setDocumentView:tableView];
	[view addSubview:scrollView];

	// Add (+) button at {18, 104, 25, 25}
	NSButton *addButton = [[NSButton alloc] initWithFrame:NSMakeRect(18, 104, 25, 25)];
	[addButton setTitle:@"+"];
	[addButton setBezelStyle:NSBezelStyleSmallSquare];
	[addButton setTarget:self];
	[addButton setAction:@selector(addVariable:)];
	[view addSubview:addButton];

	// Remove (–) button at {42, 104, 25, 25}
	NSButton *removeButton = [[NSButton alloc] initWithFrame:NSMakeRect(42, 104, 25, 25)];
	[removeButton setTitle:@"\u2013"];
	[removeButton setBezelStyle:NSBezelStyleSmallSquare];
	[removeButton setTarget:arrayController];
	[removeButton setAction:@selector(remove:)];
	[view addSubview:removeButton];

	// --- Separator at {12, 90, 456, 5} ---
	NSBox *sep = [[NSBox alloc] initWithFrame:NSMakeRect(12, 90, 456, 5)];
	[sep setBoxType:NSBoxSeparator];
	[view addSubview:sep];

	// --- Skip pattern section ---

	// "Skip pattern:" label at {17, 62, 95, 17}
	NSTextField *skipLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(17, 62, 95, 17)];
	[skipLabel setStringValue:@"Skip pattern:"];
	[skipLabel setEditable:NO];
	[skipLabel setBordered:NO];
	[skipLabel setDrawsBackground:NO];
	[skipLabel setFont:[NSFont systemFontOfSize:13.0]];
	[view addSubview:skipLabel];

	// Skip pattern text field at {114, 58, 348, 22}
	NSTextField *skipField = [[NSTextField alloc] initWithFrame:NSMakeRect(114, 58, 348, 22)];
	[skipField setEditable:YES];
	[skipField setBezeled:YES];
	[skipField setDrawsBackground:YES];
	[skipField bind:@"value" toObject:udc withKeyPath:@"values.skipPattern" options:nil];
	[view addSubview:skipField];

	// --- Separator at {12, 46, 456, 5} ---
	NSBox *sep2 = [[NSBox alloc] initWithFrame:NSMakeRect(12, 46, 456, 5)];
	[sep2 setBoxType:NSBoxSeparator];
	[view addSubview:sep2];

	// --- Develop menu section ---

	// "Include Develop menu" checkbox at {18, 18, 180, 18}
	NSButton *developMenu = [NSButton checkboxWithTitle:@"Include Develop menu" target:nil action:nil];
	[developMenu setFrame:NSMakeRect(18, 18, 180, 18)];
	[developMenu bind:@"value" toObject:udc withKeyPath:@"values.includedevelopmenu" options:nil];
	[view addSubview:developMenu];
}

- (IBAction)addVariable:(id)sender
{
	NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithObjectsAndKeys:
		[@"name" mutableCopy], @"name",
		[@"value" mutableCopy], @"value",
		nil];

	[arrayController addObject:dict];
	[arrayController setSelectedObjects:[NSArray arrayWithObject:dict]];
	[tableView editColumn:0 row:[arrayController selectionIndex] withEvent:nil select:YES];
}

@end
