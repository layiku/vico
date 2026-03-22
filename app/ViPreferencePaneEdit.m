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

#import "ViPreferencePaneEdit.h"
#import "ViBundleStore.h"
#import "NSString-additions.h"
#import "NSString-scopeSelector.h"
#include "logging.h"

@implementation ViPreferencePaneEdit

- (NSMenuItem *)addScope:(NSString *)scope
{
	DEBUG(@"adding scope %@", scope);
	NSMenu *menu = [scopeButton menu];
	if ([menu numberOfItems] == 3)
		[menu insertItem:[NSMenuItem separatorItem] atIndex:1];

	[scopeButton insertItemWithTitle:scope atIndex:2];
	NSMenuItem *item = [scopeButton itemAtIndex:2];
	[item setAction:@selector(selectScope:)];
	[item setTarget:self];
	return item;
}

- (id)init
{
	_preferences = [[NSMutableSet alloc] init];

	self = [super initWithNib:nil
			     name:@"Editing"
			     icon:[NSImage imageNamed:NSImageNameMultipleDocuments]];
	if (self == nil)
		return nil;

	[self buildView];
	[self buildNewScopeSheet];

	NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
	NSDictionary *prefs = [defs dictionaryForKey:@"scopedPreferences"];
	for (NSString *scope in [prefs allKeys])
		[self addScope:scope];

	[scopeButton selectItemAtIndex:0];

	return self;
}

- (void)buildView
{
	// Root view (480×346)
	view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 346)];

	// Scope selector popup at {33, 310, 188, 26}
	scopeButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(33, 310, 188, 26) pullsDown:NO];
	NSMenu *scopeMenu = [scopeButton menu];
	NSMenuItem *defaultsItem = [[NSMenuItem alloc] initWithTitle:@"Defaults" action:@selector(selectScope:) keyEquivalent:@""];
	[defaultsItem setTag:-2];
	[defaultsItem setTarget:self];
	[scopeMenu addItem:defaultsItem];
	[scopeMenu addItem:[NSMenuItem separatorItem]];
	NSMenuItem *newScopeItem = [[NSMenuItem alloc] initWithTitle:@"New scope" action:@selector(selectNewPreferenceScope:) keyEquivalent:@""];
	[newScopeItem setTag:-1];
	[newScopeItem setTarget:self];
	[scopeMenu addItem:newScopeItem];
	[view addSubview:scopeButton];

	// Box container at {17, 16, 446, 310}
	NSBox *box = [[NSBox alloc] initWithFrame:NSMakeRect(17, 16, 446, 310)];
	[box setBoxType:NSBoxPrimary];
	[box setTitlePosition:NSNoTitle];
	NSView *content = [box contentView];
	[view addSubview:box];

	// --- Controls inside the box (coordinates relative to box content view) ---

	// "Automatically indent new lines" at {20, 263, 216, 18}
	NSButton *autoIndent = [NSButton checkboxWithTitle:@"Automatically indent new lines" target:nil action:nil];
	[autoIndent setFrame:NSMakeRect(20, 263, 216, 18)];
	[autoIndent bind:@"value" toObject:self withKeyPath:@"autoindent" options:nil];
	[content addSubview:autoIndent];

	// "Use language-specific indentation rules" at {32, 243, 273, 18}
	NSButton *smartIndent = [NSButton checkboxWithTitle:@"Use language-specific indentation rules" target:nil action:nil];
	[smartIndent setFrame:NSMakeRect(32, 243, 273, 18)];
	[smartIndent bind:@"value" toObject:self withKeyPath:@"smartindent" options:nil];
	[content addSubview:smartIndent];

	// "Tab/backspace in leading whitespace changes indentation" at {20, 223, 408, 18}
	NSButton *smartTab = [NSButton checkboxWithTitle:@"Tab/backspace in leading whitespace changes indentation" target:nil action:nil];
	[smartTab setFrame:NSMakeRect(20, 223, 408, 18)];
	[smartTab bind:@"value" toObject:self withKeyPath:@"smarttab" options:nil];
	[content addSubview:smartTab];

	// "Automatically balance paired characters" at {20, 203, 274, 18}
	NSButton *smartPair = [NSButton checkboxWithTitle:@"Automatically balance paired characters" target:nil action:nil];
	[smartPair setFrame:NSMakeRect(20, 203, 274, 18)];
	[smartPair bind:@"value" toObject:self withKeyPath:@"smartpair" options:nil];
	[content addSubview:smartPair];

	// "Wrap long lines" at {20, 183, 120, 18}
	NSButton *wrapLines = [NSButton checkboxWithTitle:@"Wrap long lines" target:nil action:nil];
	[wrapLines setFrame:NSMakeRect(20, 183, 120, 18)];
	[wrapLines bind:@"value" toObject:self withKeyPath:@"wrap" options:nil];
	[content addSubview:wrapLines];

	// "Wrap lines by words" at {32, 163, 149, 18}
	NSButton *lineBreak = [NSButton checkboxWithTitle:@"Wrap lines by words" target:nil action:nil];
	[lineBreak setFrame:NSMakeRect(32, 163, 149, 18)];
	[lineBreak bind:@"value" toObject:self withKeyPath:@"linebreak" options:nil];
	[lineBreak bind:@"enabled" toObject:self withKeyPath:@"wrap" options:nil];
	[content addSubview:lineBreak];

	// "Complete as you type" at {20, 142, 159, 18}
	NSButton *autoComplete = [NSButton checkboxWithTitle:@"Complete as you type" target:nil action:nil];
	[autoComplete setFrame:NSMakeRect(20, 142, 159, 18)];
	[autoComplete bind:@"value" toObject:self withKeyPath:@"autocomplete" options:nil];
	[content addSubview:autoComplete];

	// Separator at {18, 133, 412, 5}
	NSBox *sep = [[NSBox alloc] initWithFrame:NSMakeRect(18, 133, 412, 5)];
	[sep setBoxType:NSBoxSeparator];
	[content addSubview:sep];

	// "Prefer indent using:" label at {19, 110, 129, 17}
	NSTextField *indentLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(19, 110, 129, 17)];
	[indentLabel setStringValue:@"Prefer indent using:"];
	[indentLabel setEditable:NO];
	[indentLabel setBordered:NO];
	[indentLabel setDrawsBackground:NO];
	[indentLabel setFont:[NSFont systemFontOfSize:13.0]];
	[content addSubview:indentLabel];

	// Tabs/Spaces popup at {150, 103, 100, 26}
	NSPopUpButton *expandTab = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(150, 103, 100, 26) pullsDown:NO];
	[expandTab addItemWithTitle:@"Tabs"];
	[[expandTab lastItem] setTag:0];
	[expandTab addItemWithTitle:@"Spaces"];
	[[expandTab lastItem] setTag:1];
	[expandTab bind:@"selectedTag" toObject:self withKeyPath:@"expandtab" options:nil];
	[content addSubview:expandTab];

	// "Tab width:" label at {77, 78, 71, 17}
	NSTextField *tabLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(77, 78, 71, 17)];
	[tabLabel setStringValue:@"Tab width:"];
	[tabLabel setEditable:NO];
	[tabLabel setBordered:NO];
	[tabLabel setDrawsBackground:NO];
	[tabLabel setFont:[NSFont systemFontOfSize:13.0]];
	[content addSubview:tabLabel];

	// Tab width field at {153, 75, 45, 22}
	NSTextField *tabField = [[NSTextField alloc] initWithFrame:NSMakeRect(153, 75, 45, 22)];
	[tabField setEditable:YES];
	[tabField setBezeled:YES];
	[tabField setDrawsBackground:YES];
	NSNumberFormatter *tabFormatter = [[NSNumberFormatter alloc] init];
	[tabFormatter setMinimum:@1];
	[tabFormatter setNumberStyle:NSNumberFormatterDecimalStyle];
	[[tabField cell] setFormatter:tabFormatter];
	[tabField bind:@"value" toObject:self withKeyPath:@"tabstop" options:nil];
	[content addSubview:tabField];

	// "Indent width:" label at {60, 46, 88, 17}
	NSTextField *shiftLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(60, 46, 88, 17)];
	[shiftLabel setStringValue:@"Indent width:"];
	[shiftLabel setEditable:NO];
	[shiftLabel setBordered:NO];
	[shiftLabel setDrawsBackground:NO];
	[shiftLabel setFont:[NSFont systemFontOfSize:13.0]];
	[content addSubview:shiftLabel];

	// Indent width field at {153, 43, 45, 22}
	NSTextField *shiftField = [[NSTextField alloc] initWithFrame:NSMakeRect(153, 43, 45, 22)];
	[shiftField setEditable:YES];
	[shiftField setBezeled:YES];
	[shiftField setDrawsBackground:YES];
	NSNumberFormatter *shiftFormatter = [[NSNumberFormatter alloc] init];
	[shiftFormatter setMinimum:@1];
	[shiftFormatter setNumberStyle:NSNumberFormatterDecimalStyle];
	[[shiftField cell] setFormatter:shiftFormatter];
	[shiftField bind:@"value" toObject:self withKeyPath:@"shiftwidth" options:nil];
	[content addSubview:shiftField];

	// "Revert to Defaults" button at {280, 7, 153, 32}
	revertButton = [[NSButton alloc] initWithFrame:NSMakeRect(280, 7, 153, 32)];
	[revertButton setTitle:@"Revert to Defaults"];
	[revertButton setBezelStyle:NSBezelStyleRounded];
	[revertButton setTarget:self];
	[revertButton setAction:@selector(revertPreferenceScope:)];
	[revertButton setEnabled:NO];
	[content addSubview:revertButton];
}

- (void)buildNewScopeSheet
{
	// Sheet window (334×158)
	newPrefScopeSheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 334, 158)
							styleMask:NSWindowStyleMaskTitled
							  backing:NSBackingStoreBuffered
							    defer:YES];
	NSView *sheetContent = [newPrefScopeSheet contentView];

	// "Specify a language or a custom scope..." label at {17, 104, 300, 34}
	NSTextField *descLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(17, 104, 300, 34)];
	[descLabel setStringValue:@"Specify a language or a custom scope for the new preferences."];
	[descLabel setEditable:NO];
	[descLabel setBordered:NO];
	[descLabel setDrawsBackground:NO];
	[descLabel setFont:[NSFont systemFontOfSize:13.0]];
	[sheetContent addSubview:descLabel];

	// "Language:" label at {17, 78, 69, 17}
	NSTextField *langLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(17, 78, 69, 17)];
	[langLabel setStringValue:@"Language:"];
	[langLabel setEditable:NO];
	[langLabel setBordered:NO];
	[langLabel setDrawsBackground:NO];
	[langLabel setFont:[NSFont systemFontOfSize:13.0]];
	[sheetContent addSubview:langLabel];

	// Language popup at {88, 72, 229, 26}
	prefLanguage = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(88, 72, 229, 26) pullsDown:NO];
	[[prefLanguage menu] addItem:[NSMenuItem separatorItem]];
	NSMenuItem *customItem = [[NSMenuItem alloc] initWithTitle:@"Custom scope" action:@selector(selectPrefLanguage:) keyEquivalent:@""];
	[customItem setTag:-1];
	[customItem setTarget:self];
	[[prefLanguage menu] addItem:customItem];
	[sheetContent addSubview:prefLanguage];

	// "Scope:" label at {40, 51, 46, 17}
	NSTextField *scopeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(40, 51, 46, 17)];
	[scopeLabel setStringValue:@"Scope:"];
	[scopeLabel setEditable:NO];
	[scopeLabel setBordered:NO];
	[scopeLabel setDrawsBackground:NO];
	[scopeLabel setFont:[NSFont systemFontOfSize:13.0]];
	[sheetContent addSubview:scopeLabel];

	// Scope text field at {91, 48, 223, 22}
	prefScope = [[NSTextField alloc] initWithFrame:NSMakeRect(91, 48, 223, 22)];
	[prefScope setEditable:YES];
	[prefScope setBezeled:YES];
	[prefScope setDrawsBackground:YES];
	[prefScope setDelegate:self];
	[sheetContent addSubview:prefScope];

	// OK button at {224, 12, 96, 32}
	newScopeButton = [[NSButton alloc] initWithFrame:NSMakeRect(224, 12, 96, 32)];
	[newScopeButton setTitle:@"OK"];
	[newScopeButton setBezelStyle:NSBezelStyleRounded];
	[newScopeButton setTarget:self];
	[newScopeButton setAction:@selector(acceptNewPreferenceScope:)];
	[newScopeButton setKeyEquivalent:@"\r"];
	[newScopeButton setEnabled:NO];
	[sheetContent addSubview:newScopeButton];

	// Cancel button at {128, 12, 96, 32}
	NSButton *cancelButton = [[NSButton alloc] initWithFrame:NSMakeRect(128, 12, 96, 32)];
	[cancelButton setTitle:@"Cancel"];
	[cancelButton setBezelStyle:NSBezelStyleRounded];
	[cancelButton setTarget:self];
	[cancelButton setAction:@selector(cancelNewPreferenceScope:)];
	[cancelButton setKeyEquivalent:@"\033"];
	[sheetContent addSubview:cancelButton];
}


- (IBAction)selectScope:(id)aSender
{
	NSMenuItem *sender = (NSMenuItem *)aSender;
	[scopeButton selectItem:sender];
	[revertButton setEnabled:[sender tag] != -2];

	DEBUG(@"refreshing preferences %@", _preferences);
	for (NSString *key in _preferences) {
		[self willChangeValueForKey:key];
		[self didChangeValueForKey:key];
	}
}

- (void)notifyPreferencesChanged
{
	[[NSNotificationCenter defaultCenter] postNotificationName:ViEditPreferenceChangedNotification
							    object:nil
							  userInfo:nil];
}

- (void)initPreferenceScope:(NSString *)scope
{
	if ([scope length] == 0)
		return;

	NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
	NSMutableDictionary *prefs = [[defs dictionaryForKey:@"scopedPreferences"] mutableCopy];
	if (prefs == nil)
		prefs = [NSMutableDictionary dictionary];

	NSMutableDictionary *scopedPrefs = [NSMutableDictionary dictionary];
	for (NSString *key in _preferences)
		[scopedPrefs setObject:[defs objectForKey:key] forKey:key];
	[prefs setObject:scopedPrefs forKey:scope];
	[defs setObject:prefs forKey:@"scopedPreferences"];

	[self notifyPreferencesChanged];
}

- (void)deletePreferenceScope:(NSString *)scope
{
	NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
	NSMutableDictionary *prefs = [[defs dictionaryForKey:@"scopedPreferences"] mutableCopy];
	if (prefs == nil)
		return;
	[prefs removeObjectForKey:scope];
	[defs setObject:prefs forKey:@"scopedPreferences"];

	[self notifyPreferencesChanged];
}

- (void)revertSheetDidEnd:(NSAlert *)alert
               returnCode:(int)returnCode
              contextInfo:(void *)contextInfo
{
	if (returnCode == NSAlertFirstButtonReturn) {
		/* Copy preferences from defaults. */
		[self initPreferenceScope:[scopeButton titleOfSelectedItem]];
		[self selectScope:[scopeButton selectedItem]];
	} else if (returnCode == NSAlertSecondButtonReturn) {
		/* Delete preference scope. */
		[self deletePreferenceScope:[scopeButton titleOfSelectedItem]];
		[scopeButton removeItemAtIndex:[scopeButton indexOfSelectedItem]];
		if ([[scopeButton itemAtIndex:1] isSeparatorItem] &&
		    [[scopeButton itemAtIndex:2] isSeparatorItem])
			[scopeButton removeItemAtIndex:1];
		[self selectScope:[scopeButton itemAtIndex:0]];
	}
}

- (IBAction)revertPreferenceScope:(id)sender
{
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:@"Do you want to delete this scope or copy from defaults?"];
	[alert addButtonWithTitle:@"Copy"];
	[alert addButtonWithTitle:@"Delete"];
	[alert addButtonWithTitle:@"Cancel"];
	[alert setInformativeText:[NSString stringWithFormat:@"If you delete the preferences for this scope (%@), the defaults will be used instead.", [scopeButton titleOfSelectedItem]]];
	[alert beginSheetModalForWindow:[view window] completionHandler:^(NSModalResponse returnCode) {
		[self revertSheetDidEnd:alert returnCode:(int)returnCode contextInfo:NULL];
	}];
}

- (IBAction)acceptNewPreferenceScope:(id)sender
{
	NSString *scope = [prefScope stringValue];
	[self initPreferenceScope:scope];
	[self selectScope:[self addScope:scope]];
	[NSApp endSheet:newPrefScopeSheet];
}

- (IBAction)cancelNewPreferenceScope:(id)sender
{
	[self selectScope:[scopeButton itemAtIndex:0]];
	[NSApp endSheet:newPrefScopeSheet];
}

- (IBAction)selectPrefLanguage:(id)sender
{
	ViLanguage *lang = [sender representedObject];
	NSString *scope = @"";
	if (lang)
		scope = [lang name];
	[prefScope setStringValue:scope];
	[newScopeButton setEnabled:[scope length] > 0];
}

- (void)sheetDidEnd:(NSWindow *)sheet
         returnCode:(int)returnCode
        contextInfo:(void *)contextInfo
{
	[sheet orderOut:self];
}

- (void)updatePrefScope
{
	NSString *scope = [prefScope stringValue];
	[newScopeButton setEnabled:[scope length] > 0];
	ViLanguage *lang = [[ViBundleStore defaultStore] languageWithScope:scope];
	if (lang)
		[prefLanguage selectItemAtIndex:[[prefLanguage menu] indexOfItemWithRepresentedObject:lang]];
	else
		[prefLanguage selectItemWithTag:-1]; /* Select the "Custom" item. */
}

- (void)controlTextDidChange:(NSNotification *)aNotification
{
	if ([aNotification object] != prefScope)
		return;
	[self updatePrefScope];
}

- (IBAction)selectNewPreferenceScope:(id)sender
{
	NSMenu *menu = [prefLanguage menu];
	while ([[menu itemAtIndex:0] tag] == 0)
		[menu removeItemAtIndex:0];

	NSArray *sortedLanguages = [[ViBundleStore defaultStore] sortedLanguages];

	/* FIXME: This is the same code as in the ViTextView action menu. */
	int i = 0;
	for (ViLanguage *lang in sortedLanguages) {
		NSMenuItem *item;
		item = [menu insertItemWithTitle:[lang displayName]
					  action:@selector(selectPrefLanguage:)
				   keyEquivalent:@""
					 atIndex:i++];
		[item setRepresentedObject:lang];
		[item setTarget:self];
	}

	//[prefLanguage setStringValue:@""];
	[self updatePrefScope];

	[[view window] beginSheet:newPrefScopeSheet completionHandler:^(NSModalResponse returnCode) {
        [self sheetDidEnd:self->newPrefScopeSheet returnCode:(int)returnCode contextInfo:nil];
	}];
}

#pragma mark -
#pragma mark Responding to preference keys

- (id)valueForUndefinedKey:(NSString *)key
{
	if (![_preferences containsObject:key])
		[_preferences addObject:key];

	if ([[scopeButton selectedItem] tag] == -2) {
		DEBUG(@"getting default preference %@", key);
		return [[NSUserDefaults standardUserDefaults] valueForKey:key];
	}

	NSString *scope = [scopeButton titleOfSelectedItem];
	DEBUG(@"getting preference %@ in scope %@", key, scope);
	NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
	NSDictionary *prefs = [defs dictionaryForKey:@"scopedPreferences"];
	NSDictionary *scopedPrefs = [prefs objectForKey:scope];
	return [scopedPrefs valueForKey:key];
}

- (void)setValue:(id)value forUndefinedKey:(NSString *)key
{
	if ([[scopeButton selectedItem] tag] == -2) {
		DEBUG(@"setting preference %@ to %@", key, value);
		[[NSUserDefaults standardUserDefaults] setObject:value forKey:key];
		return;
	}

	NSString *scope = [scopeButton titleOfSelectedItem];
	DEBUG(@"setting preference %@ to %@ in scope %@", key, value, scope);
	NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
	NSMutableDictionary *prefs = [[defs dictionaryForKey:@"scopedPreferences"] mutableCopy];
	NSMutableDictionary *scopedPrefs = [[prefs objectForKey:scope] mutableCopy];
	[scopedPrefs setObject:value forKey:key];
	[prefs setObject:scopedPrefs forKey:scope];
	[defs setObject:prefs forKey:@"scopedPreferences"];

	[self notifyPreferencesChanged];
}

+ (id)valueForKey:(NSString *)key inScope:(ViScope *)scope
{
	NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];

	if (scope) {
		NSDictionary *prefs = [defs dictionaryForKey:@"scopedPreferences"];
		NSString *selector = [scope bestMatch:[prefs allKeys]];
		if (selector) {
			NSDictionary *scopedPrefs = [prefs objectForKey:selector];
			return [scopedPrefs objectForKey:key];
		}
	}

	/* No scopes matched. Return default setting. */
	return [defs objectForKey:key];
}

@end
