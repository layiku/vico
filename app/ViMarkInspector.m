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

#import "ViMarkInspector.h"
#import "ViMarkManager.h"
#import "ViWindowController.h"
#import "MHTextIconCell.h"
#include "logging.h"

@implementation ViMarkInspector

+ (ViMarkInspector *)sharedInspector
{
	static ViMarkInspector *__sharedInspector = nil;
	if (__sharedInspector == nil)
		__sharedInspector = [[ViMarkInspector alloc] init];
	return __sharedInspector;
}

- (id)init
{
	if ((self = [super initWithWindow:nil]) != nil) {
		[self buildWindow];
	}
	return self;
}

- (void)buildWindow
{
	// NSPanel (283×516, titled+closable+miniaturizable+resizable, utility style)
	NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(139, 81, 283, 516)
						    styleMask:(NSWindowStyleMaskTitled |
							       NSWindowStyleMaskClosable |
							       NSWindowStyleMaskMiniaturizable |
							       NSWindowStyleMaskResizable)
						      backing:NSBackingStoreBuffered
							defer:YES];
	[panel setTitle:@"Mark Inspector"];
	[panel setFrameAutosaveName:@"MarkInspectorPanel"];
	[panel setRestorable:YES];

	NSView *contentView = [panel contentView];

	// --- Controllers (top-level nib objects) ---

	// NSArrayController — mark stacks
	markStackController = [[NSArrayController alloc] init];
	[markStackController setObjectClass:[ViMarkStack class]];
	[markStackController setAvoidsEmptySelection:YES];
	[markStackController setPreservesSelection:YES];
	[markStackController setSelectsInsertedObjects:YES];
	[markStackController setClearsFilterPredicateOnInsertion:YES];
	// Bind contentArray to ViMarkManager.sharedManager.stacks
	[markStackController bind:@"contentArray"
			 toObject:[ViMarkManager sharedManager]
		      withKeyPath:@"stacks"
			  options:nil];

	// NSTreeController — mark list (hierarchical)
	markListController = [[NSTreeController alloc] init];
	[markListController setObjectClass:[ViMark class]];
	[markListController setChildrenKeyPath:@"marks"];
	[markListController setLeafKeyPath:@"isLeaf"];
	[markListController setAvoidsEmptySelection:YES];
	[markListController setPreservesSelection:YES];
	[markListController setSelectsInsertedObjects:YES];
	// Bind contentArray to markStackController.selection.list.group_by_groupName.groups
	[markListController bind:@"contentArray"
			toObject:markStackController
		     withKeyPath:@"selection.list.group_by_groupName.groups"
			 options:nil];

	// --- PopUpButton (174×26) — mark stack selection ---
	NSPopUpButton *stackPopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(17, 11, 174, 26) pullsDown:NO];
	[stackPopUp setAutoresizingMask:(NSViewMaxXMargin | NSViewMaxYMargin)];
	[stackPopUp bind:@"content"
		toObject:markStackController
	     withKeyPath:@"arrangedObjects"
		 options:nil];
	[stackPopUp bind:@"contentValues"
		toObject:markStackController
	     withKeyPath:@"arrangedObjects.name"
		 options:nil];
	[stackPopUp bind:@"selectedIndex"
		toObject:markStackController
	     withKeyPath:@"selectionIndex"
		 options:nil];
	[contentView addSubview:stackPopUp];

	// --- NSSegmentedControl (71×24) — back/forward navigation ---
	NSSegmentedControl *segControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(194, 12, 71, 24)];
	[segControl setSegmentCount:2];
	[segControl setWidth:32 forSegment:0];
	[segControl setWidth:32 forSegment:1];
	[segControl setImage:[NSImage imageNamed:NSImageNameGoLeftTemplate] forSegment:0];
	[segControl setImage:[NSImage imageNamed:NSImageNameGoRightTemplate] forSegment:1];
	[[segControl cell] setToolTip:@"Go to older list." forSegment:0];
	[[segControl cell] setToolTip:@"Go to newer list." forSegment:1];
	[[segControl cell] setTag:0 forSegment:0];
	[[segControl cell] setTag:1 forSegment:1];
	[[segControl cell] setTrackingMode:NSSegmentSwitchTrackingMomentary];
	[segControl setSegmentStyle:NSSegmentStyleCapsule];
	[segControl setTarget:self];
	[segControl setAction:@selector(changeList:)];
	[segControl setAutoresizingMask:(NSViewMinXMargin | NSViewMaxYMargin)];
	[contentView addSubview:segControl];

	// --- NSScrollView + ViOutlineView ---
	NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(-1, 43, 285, 474)];
	[scrollView setHasVerticalScroller:YES];
	[scrollView setHasHorizontalScroller:YES];
	[scrollView setAutohidesScrollers:YES];
	[scrollView setBorderType:NSBezelBorder];
	[scrollView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];

	outlineView = [[ViOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 283, 456)];
	[outlineView setAutosaveName:@"MarkInspectorWindow"];
	[outlineView setRowHeight:20];
	[outlineView setIntercellSpacing:NSMakeSize(3, 2)];
	[outlineView setAllowsTypeSelect:YES];
	[outlineView setColumnAutoresizingStyle:NSTableViewSequentialColumnAutoresizingStyle];
	[outlineView setDraggingSourceOperationMask:NSDragOperationEvery forLocal:YES];
	[outlineView setDraggingSourceOperationMask:NSDragOperationNone forLocal:NO];
	[outlineView setAutoresizesOutlineColumn:NO];
	[outlineView setDelegate:self];

	// Title column (233.6px, MHTextIconCell)
	NSTableColumn *titleColumn = [[NSTableColumn alloc] initWithIdentifier:@"title"];
	[titleColumn setWidth:233.609375];
	[titleColumn setMinWidth:16];
	[titleColumn setMaxWidth:1000];
	[titleColumn setResizingMask:NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask];
	[[titleColumn headerCell] setStringValue:@"Title"];
	MHTextIconCell *dataCell = [[MHTextIconCell alloc] init];
	[dataCell setFont:[NSFont fontWithName:@"LucidaGrande" size:13]];
	[dataCell setLineBreakMode:NSLineBreakByTruncatingTail];
	[titleColumn setDataCell:dataCell];
	[titleColumn bind:@"value"
		 toObject:markListController
	      withKeyPath:@"arrangedObjects.title"
		  options:nil];
	[outlineView addTableColumn:titleColumn];
	[outlineView setOutlineTableColumn:titleColumn];

	// Location column (54px)
	NSTableColumn *locationColumn = [[NSTableColumn alloc] initWithIdentifier:@"location"];
	[locationColumn setWidth:54];
	[locationColumn setMinWidth:10];
	[locationColumn setResizingMask:NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask];
	[[locationColumn headerCell] setStringValue:@"Location"];
	[locationColumn bind:@"value"
		    toObject:markListController
		 withKeyPath:@"arrangedObjects.rangeString"
		     options:@{@"NSConditionallySetsEditable": @YES}];
	[outlineView addTableColumn:locationColumn];

	[scrollView setDocumentView:outlineView];
	[contentView addSubview:scrollView];

	// Set target/double-action (was in awakeFromNib)
	[outlineView setTarget:self];
	[outlineView setDoubleAction:@selector(gotoMark:)];

	[self setWindow:panel];
}

- (void)show
{
	[[self window] makeKeyAndOrderFront:self];
}

- (IBAction)changeList:(id)sender
{
	DEBUG(@"sender is %@, tag %lu", sender, [sender tag]);
	ViMarkStack *stack = [[markStackController selectedObjects] lastObject];
	if ([sender selectedSegment] == 0)
		[stack previous];
	else
		[stack next];
}

- (IBAction)gotoMark:(id)sender
{
	DEBUG(@"sender is %@", sender);
	NSArray *objects = [markListController selectedObjects];
	if ([objects count] == 1) {
		id object = [objects lastObject];
		DEBUG(@"selected object is %@ (row is %li)", object, [outlineView rowForItem:object]);
		if ([object isKindOfClass:[ViMark class]]) {
			ViMark *mark = object;
			ViWindowController *windowController = [ViWindowController currentWindowController];
			[windowController gotoMark:mark];
			[windowController showWindow:nil];
		} else {
			NSArray *nodes = [markListController selectedNodes];
			DEBUG(@"got selected nodes %@", nodes);
			id node = [nodes lastObject];
			if ([outlineView isItemExpanded:node])
				[outlineView collapseItem:node];
			else
				[outlineView expandItem:node];
		}
	}
}

@end
