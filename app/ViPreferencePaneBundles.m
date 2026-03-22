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

#import "ViPreferencePaneBundles.h"
#import "ViBundleStore.h"
#import "SBJson.h"
#include "logging.h"

@implementation repoUserTransformer
+ (Class)transformedValueClass { return [NSDictionary class]; }
+ (BOOL)allowsReverseTransformation { return YES; }
- (id)init { return [super init]; }
- (id)transformedValue:(id)value
{
	if (![value isKindOfClass:[NSArray class]])
		return nil;

	NSArray *array = value;
	if ([array count] == 0)
		return value;

	if ([[array objectAtIndex:0] isKindOfClass:[NSString class]]) {
		/* Convert an array of strings to an array of dictionaries with "username" key. */
		NSMutableArray *a = [NSMutableArray array];
		NSArray *usernames = [array sortedArrayUsingSelector:@selector(compare:)];
		for (NSString *username in usernames)
			[a addObject:[NSMutableDictionary dictionaryWithObject:[username mutableCopy] forKey:@"username"]];
		return a;
	} else if ([[array objectAtIndex:0] isKindOfClass:[NSDictionary class]]) {
		/* Convert an array of dictionaries with "username" keys to an array of strings. */
		NSMutableArray *a = [NSMutableArray array];
		for (NSDictionary *dict in array)
			[a addObject:[[dict objectForKey:@"username"] mutableCopy]];
		[a sortUsingSelector:@selector(compare:)];
		return a;
	}

	return nil;
}
@end

@implementation statusIconTransformer
+ (Class)transformedValueClass { return [NSImage class]; }
+ (BOOL)allowsReverseTransformation { return NO; }
- (id)init {
	self = [super init];
	_installedIcon = [NSImage imageNamed:NSImageNameStatusAvailable];
	return self;
}
- (id)transformedValue:(id)value
{
	if ([value isEqualToString:@"Installed"])
		return _installedIcon;
	return nil;
}
@end

@implementation ViPreferencePaneBundles

@synthesize filteredRepositories = _filteredRepositories;

- (id)init
{
	self = [super initWithNib:nil
			     name:@"Bundles"
			     icon:[NSImage imageNamed:NSImageNameNetwork]];
	if (self == nil)
		return nil;

	_repositories = [[NSMutableArray alloc] init];
	_repoNameRx = [[ViRegexp alloc] initWithString:@"(\\W*(tm|textmate|vico)\\W*bundle)$"
					       options:ONIG_OPTION_IGNORECASE];

	_session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
	                                         delegate:self
	                                    delegateQueue:[NSOperationQueue mainQueue]];

	/* Show an icon in the status column of the repository table. */
	[NSValueTransformer setValueTransformer:[[statusIconTransformer alloc] init]
					forName:@"statusIconTransformer"];

	[NSValueTransformer setValueTransformer:[[repoUserTransformer alloc] init]
					forName:@"repoUserTransformer"];

	[self buildView];
	[self buildSelectRepoSheet];
	[self buildProgressSheet];

	/* Sort repositories by installed status, then by name. */
	NSSortDescriptor *statusSort = [[NSSortDescriptor alloc] initWithKey:@"status"
								    ascending:NO];
	NSSortDescriptor *nameSort = [[NSSortDescriptor alloc] initWithKey:@"name"
								  ascending:YES];
	[bundlesController setSortDescriptors:[NSArray arrayWithObjects:statusSort, nameSort, nil]];

	NSArray *repoUsers = [[NSUserDefaults standardUserDefaults] arrayForKey:@"bundleRepoUsers"];
	for (NSString *username in repoUsers)
		[self loadBundlesFromRepo:username];

	[bundlesTable setDoubleAction:@selector(installBundles:)];
	[bundlesTable setTarget:self];

	return self;
}

- (void)buildView
{
	NSUserDefaultsController *udc = [NSUserDefaultsController sharedUserDefaultsController];

	// Root view (480×461)
	view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 461)];

	// Info text at top {17, 407, 446, 34}
	NSTextField *infoText = [[NSTextField alloc] initWithFrame:NSMakeRect(17, 407, 446, 34)];
	[infoText setStringValue:@"You can extend Vico with support for new languages, snippets and commands by installing bundles directly from GitHub."];
	[infoText setEditable:NO];
	[infoText setBordered:NO];
	[infoText setDrawsBackground:NO];
	[infoText setFont:[NSFont systemFontOfSize:13.0]];
	[view addSubview:infoText];

	// --- NSArrayController for bundles ---
	bundlesController = [[NSArrayController alloc] init];
	[bundlesController setPreservesSelection:YES];
	[bundlesController setSelectsInsertedObjects:YES];
	[bundlesController setClearsFilterPredicateOnInsertion:YES];
	[bundlesController bind:@"contentArray"
		       toObject:self
		    withKeyPath:@"filteredRepositories"
			options:nil];

	// --- NSArrayController for repo users ---
	repoUsersController = [[NSArrayController alloc] init];
	[repoUsersController setPreservesSelection:YES];
	[repoUsersController setSelectsInsertedObjects:YES];
	[repoUsersController setClearsFilterPredicateOnInsertion:YES];
	[repoUsersController bind:@"contentArray"
			 toObject:udc
		      withKeyPath:@"values.bundleRepoUsers"
			  options:@{
				NSValueTransformerNameBindingOption: @"repoUserTransformer",
				@"NSHandlesContentAsCompoundValue": @YES
			  }];

	// --- Bundles table in scroll view at {20, 72, 440, 322} ---
	NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 72, 440, 322)];
	[scrollView setHasVerticalScroller:YES];
	[scrollView setHasHorizontalScroller:NO];
	[scrollView setBorderType:NSBezelBorder];
	[scrollView setAutohidesScrollers:YES];
	bundlesTable = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 438, 304)];
	[bundlesTable setAutosaveName:@"BundlesTable"];
	[bundlesTable setRowHeight:14];
	[bundlesTable setIntercellSpacing:NSMakeSize(3, 2)];
	[bundlesTable setAllowsColumnReordering:YES];
	[bundlesTable setAllowsColumnResizing:YES];
	[bundlesTable setAllowsMultipleSelection:YES];

	// Status column (16px, image cell)
	NSTableColumn *statusCol = [[NSTableColumn alloc] initWithIdentifier:@"StatusColumn"];
	[statusCol setWidth:16];
	[statusCol setMinWidth:16];
	[statusCol setMaxWidth:16];
	[[statusCol headerCell] setStringValue:@""];
	NSImageCell *statusCell = [[NSImageCell alloc] init];
	[statusCol setDataCell:statusCell];
	[statusCol bind:@"value"
		toObject:bundlesController
	     withKeyPath:@"arrangedObjects.status"
		 options:@{NSValueTransformerNameBindingOption: @"statusIconTransformer"}];
	[statusCol setSortDescriptorPrototype:[[NSSortDescriptor alloc] initWithKey:@"status" ascending:YES selector:@selector(compare:)]];
	[bundlesTable addTableColumn:statusCol];

	// Name column (134px)
	NSTableColumn *nameCol = [[NSTableColumn alloc] initWithIdentifier:@"NameColumn"];
	[nameCol setWidth:134];
	[nameCol setMinWidth:40];
	[[nameCol headerCell] setStringValue:@"Name"];
	[nameCol bind:@"value"
		toObject:bundlesController
	     withKeyPath:@"arrangedObjects.displayName"
		 options:nil];
	[nameCol setSortDescriptorPrototype:[[NSSortDescriptor alloc] initWithKey:@"displayName" ascending:YES selector:@selector(compare:)]];
	[bundlesTable addTableColumn:nameCol];

	// User column (78px)
	NSTableColumn *userCol = [[NSTableColumn alloc] initWithIdentifier:@"UserColumn"];
	[userCol setWidth:78];
	[userCol setMinWidth:10];
	[[userCol headerCell] setStringValue:@"User"];
	[userCol bind:@"value"
		toObject:bundlesController
	     withKeyPath:@"arrangedObjects.owner.login"
		 options:nil];
	[bundlesTable addTableColumn:userCol];

	// Description column (198px)
	NSTableColumn *descCol = [[NSTableColumn alloc] initWithIdentifier:@"DescriptionColumn"];
	[descCol setWidth:198];
	[descCol setMinWidth:10];
	[[descCol headerCell] setStringValue:@"Description"];
	[descCol bind:@"value"
		toObject:bundlesController
	     withKeyPath:@"arrangedObjects.description"
		 options:nil];
	[bundlesTable addTableColumn:descCol];

	[scrollView setDocumentView:bundlesTable];
	[view addSubview:scrollView];

	// --- Bottom controls ---

	// Bundles info label at {17, 50, 446, 14}
	bundlesInfo = [[NSTextField alloc] initWithFrame:NSMakeRect(17, 50, 446, 14)];
	[bundlesInfo setEditable:NO];
	[bundlesInfo setBordered:NO];
	[bundlesInfo setDrawsBackground:NO];
	[bundlesInfo setFont:[NSFont systemFontOfSize:11.0]];
	[view addSubview:bundlesInfo];

	// Install (+) button at {20, 20, 23, 23}
	NSButton *installButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, 20, 23, 23)];
	[installButton setImage:[NSImage imageNamed:NSImageNameAddTemplate]];
	[installButton setBezelStyle:NSBezelStyleSmallSquare];
	[installButton setBordered:YES];
	[installButton setTarget:self];
	[installButton setAction:@selector(installBundles:)];
	[view addSubview:installButton];

	// Uninstall (-) button at {42, 20, 23, 23}
	NSButton *uninstallButton = [[NSButton alloc] initWithFrame:NSMakeRect(42, 20, 23, 23)];
	[uninstallButton setImage:[NSImage imageNamed:NSImageNameRemoveTemplate]];
	[uninstallButton setBezelStyle:NSBezelStyleSmallSquare];
	[uninstallButton setBordered:YES];
	[uninstallButton setTarget:self];
	[uninstallButton setAction:@selector(uninstallBundles:)];
	[view addSubview:uninstallButton];

	// Action popup at {70, 20, 37, 23}
	NSPopUpButton *actionPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(70, 20, 37, 23) pullsDown:YES];
	[actionPopup setBezelStyle:NSBezelStyleSmallSquare];
	[actionPopup setBordered:YES];
	[[actionPopup cell] setArrowPosition:NSPopUpArrowAtCenter];
	[actionPopup addItemWithTitle:@""];
	[actionPopup addItemWithTitle:@"Reload from GitHub"];
	[[actionPopup lastItem] setTarget:self];
	[[actionPopup lastItem] setAction:@selector(reloadRepositories:)];
	[actionPopup addItemWithTitle:@"Select repositories..."];
	[[actionPopup lastItem] setTarget:self];
	[[actionPopup lastItem] setAction:@selector(selectRepositories:)];
	[view addSubview:actionPopup];

	// Filter search field at {115, 20, 164, 22}
	repoFilterField = [[NSSearchField alloc] initWithFrame:NSMakeRect(115, 20, 164, 22)];
	[repoFilterField setTarget:self];
	[repoFilterField setAction:@selector(filterRepositories:)];
	[[repoFilterField cell] setPlaceholderString:@"Filter"];
	[view addSubview:repoFilterField];
}

- (void)buildSelectRepoSheet
{
	// Sheet window (441×201)
	selectRepoSheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 441, 201)
						      styleMask:NSWindowStyleMaskTitled
							backing:NSBackingStoreBuffered
							  defer:YES];
	NSView *sheetContent = [selectRepoSheet contentView];

	// Info text at {17, 153, 407, 28}
	NSTextField *infoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(17, 153, 407, 28)];
	[infoLabel setStringValue:@"You can manage what bundles are listed by selecting GitHub users. Only repositories with the string 'tmbundle' in the name are available."];
	[infoLabel setEditable:NO];
	[infoLabel setBordered:NO];
	[infoLabel setDrawsBackground:NO];
	[infoLabel setFont:[NSFont systemFontOfSize:11.0]];
	[sheetContent addSubview:infoLabel];

	// Repo users table in scroll view at {20, 47, 401, 98}
	NSScrollView *repoScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 47, 401, 98)];
	[repoScroll setHasVerticalScroller:YES];
	[repoScroll setHasHorizontalScroller:NO];
	[repoScroll setBorderType:NSBezelBorder];
	[repoScroll setAutohidesScrollers:YES];

	repoUsersTable = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 399, 96)];
	[repoUsersTable setRowHeight:14];
	[repoUsersTable setIntercellSpacing:NSMakeSize(3, 2)];

	NSTableColumn *usernameCol = [[NSTableColumn alloc] initWithIdentifier:@"username"];
	[usernameCol setWidth:396];
	[usernameCol setMinWidth:40];
	[usernameCol setEditable:YES];
	[[usernameCol headerCell] setStringValue:@""];
	[usernameCol bind:@"value"
		 toObject:repoUsersController
	      withKeyPath:@"arrangedObjects.username"
		  options:nil];
	[repoUsersTable addTableColumn:usernameCol];
	[repoScroll setDocumentView:repoUsersTable];
	[sheetContent addSubview:repoScroll];

	// Add (+) button at {20, 19, 21, 21}
	NSButton *addButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, 19, 21, 21)];
	[addButton setImage:[NSImage imageNamed:NSImageNameAddTemplate]];
	[addButton setBezelStyle:NSBezelStyleSmallSquare];
	[addButton setBordered:YES];
	[addButton setTarget:self];
	[addButton setAction:@selector(addRepoUser:)];
	[sheetContent addSubview:addButton];

	// Remove (-) button at {40, 19, 21, 21}
	NSButton *removeButton = [[NSButton alloc] initWithFrame:NSMakeRect(40, 19, 21, 21)];
	[removeButton setImage:[NSImage imageNamed:NSImageNameRemoveTemplate]];
	[removeButton setBezelStyle:NSBezelStyleSmallSquare];
	[removeButton setBordered:YES];
	[removeButton setTarget:repoUsersController];
	[removeButton setAction:@selector(remove:)];
	[removeButton bind:@"enabled"
		  toObject:repoUsersController
	       withKeyPath:@"selection"
		   options:@{NSValueTransformerNameBindingOption: NSIsNotNilTransformerName}];
	[sheetContent addSubview:removeButton];

	// Done button at {355, 14, 71, 28}
	NSButton *doneButton = [[NSButton alloc] initWithFrame:NSMakeRect(355, 14, 71, 28)];
	[doneButton setTitle:@"Done"];
	[doneButton setBezelStyle:NSBezelStyleRounded];
	[doneButton setTarget:self];
	[doneButton setAction:@selector(acceptSelectRepoSheet:)];
	[doneButton setKeyEquivalent:@"\r"];
	[sheetContent addSubview:doneButton];
}

- (void)buildProgressSheet
{
	// Progress sheet window (441×93)
	progressSheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 441, 93)
						    styleMask:NSWindowStyleMaskTitled
						      backing:NSBackingStoreBuffered
							defer:YES];
	NSView *sheetContent = [progressSheet contentView];

	// Status description at {17, 45, 407, 28}
	progressDescription = [[NSTextField alloc] initWithFrame:NSMakeRect(17, 45, 407, 28)];
	[progressDescription setEditable:NO];
	[progressDescription setBordered:NO];
	[progressDescription setDrawsBackground:NO];
	[progressDescription setFont:[NSFont systemFontOfSize:11.0]];
	[sheetContent addSubview:progressDescription];

	// Progress indicator at {19, 22, 309, 12}
	progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(19, 22, 309, 12)];
	[progressIndicator setIndeterminate:YES];
	[progressIndicator setMaxValue:100];
	[sheetContent addSubview:progressIndicator];

	// Cancel button at {330, 13, 96, 28}
	progressButton = [[NSButton alloc] initWithFrame:NSMakeRect(330, 13, 96, 28)];
	[progressButton setTitle:@"Cancel"];
	[progressButton setBezelStyle:NSBezelStyleRounded];
	[progressButton setTarget:self];
	[progressButton setAction:@selector(cancelProgressSheet:)];
	[sheetContent addSubview:progressButton];
}


- (NSString *)repoPathForUser:(NSString *)username readonly:(BOOL)readonly
{
	NSString *path = [[NSString stringWithFormat:@"%@/%@-bundles.json",
	    [ViBundleStore bundlesDirectory], username]
	    stringByExpandingTildeInPath];

	if (!readonly)
		return path;

	if ([[NSFileManager defaultManager] fileExistsAtPath:path])
		return path;

	NSString *bundlePath = [[NSString stringWithFormat:@"%@/Contents/Resources/%@-bundles.json",
	    [[NSBundle mainBundle] bundlePath], username]
	    stringByExpandingTildeInPath];

	if ([[NSFileManager defaultManager] fileExistsAtPath:bundlePath])
		return bundlePath;

	return nil;
}

- (void)updateBundleStatus
{
	NSDate *date = [[NSUserDefaults standardUserDefaults] objectForKey:@"LastBundleRepoReload"];
	if (date) {
		NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
		[dateFormatter setDateStyle:NSDateFormatterMediumStyle];
		[dateFormatter setTimeStyle:NSDateFormatterMediumStyle];
		[bundlesInfo setStringValue:[NSString stringWithFormat:@"%u installed, %lu available. Last updated %@.",
		    (unsigned)[[[ViBundleStore defaultStore] allBundles] count],
		    [_repositories count], [dateFormatter stringFromDate:date]]];
	} else {
		[bundlesInfo setStringValue:[NSString stringWithFormat:@"%u installed, %lu available.",
		    (unsigned)[[[ViBundleStore defaultStore] allBundles] count], [_repositories count]]];
	}
}

- (void)loadBundlesFromRepo:(NSString *)username
{
	/* Remove any existing repositories owned by this user. */
	[_repositories filterUsingPredicate:[NSPredicate predicateWithFormat:@"NOT owner.login == %@", username]];

	if (!_repoJson) {
		NSString *path = [self repoPathForUser:username readonly:YES];
		if (path == nil)
			return;
		NSData *jsonData = [NSData dataWithContentsOfFile:path];
		NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
		
		SBJsonParser *parser = [[SBJsonParser alloc] init];
		NSArray *arry = [parser objectWithString:jsonString];
		if (![arry isKindOfClass:[NSArray class]]) {
			INFO(@"%s: %@", "failed to parse JSON, error was ", parser.error);
			return;
		}
		[_repositories addObjectsFromArray: arry];
	} else {
		NSString *path = [self repoPathForUser:username readonly:NO];
		
		SBJsonWriter *writer = [[SBJsonWriter alloc] init];
		NSString *json =[writer stringWithObject:_repoJson];
		[json writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
		[_repositories addObjectsFromArray:_repoJson];
	}

	for (NSUInteger i = 0; i < [_repositories count];) {
		NSMutableDictionary *bundle = [_repositories objectAtIndex:i];

		/* Set displayName based on name, but trim any trailing .tmbundle. */
		NSString *displayName = [bundle objectForKey:@"name"];
		ViRegexpMatch *m = [_repoNameRx matchInString:displayName];
		if (m == nil) {
			/* Remove any non-bundle repositories. */
			[_repositories removeObjectAtIndex:i];
			continue;
		}
		++i;

		NSString *name = [bundle objectForKey:@"name"];
		NSString *owner = [[bundle objectForKey:@"owner"] objectForKey:@"login"];
		NSString *status = @"";
		if ([[ViBundleStore defaultStore] isBundleLoaded:[NSString stringWithFormat:@"%@-%@", owner, name]])
			status = @"Installed";
		[bundle setObject:status forKey:@"status"];

		displayName = [displayName stringByReplacingCharactersInRange:[m rangeOfSubstringAtIndex:1] withString:@""];
		[bundle setObject:[displayName capitalizedString] forKey:@"displayName"];
	}

	[self filterRepositories:repoFilterField];
	[self updateBundleStatus];
}

#pragma mark -
#pragma mark Filtering GitHub bundle repositories

- (IBAction)filterRepositories:(id)sender
{
	NSString *filter = [sender stringValue];
	if ([filter length] == 0) {
		[self setFilteredRepositories:_repositories];
		return;
	}

	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"(owner.login CONTAINS[cd] %@) OR (name CONTAINS[cd] %@) OR (description CONTAINS[cd] %@)",
		filter, filter, filter];
	[self setFilteredRepositories:[_repositories filteredArrayUsingPredicate:predicate]];
}

#pragma mark -
#pragma mark Managing GitHub repository users

- (void)selectRepoSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	[sheet orderOut:self];
}

- (IBAction)acceptSelectRepoSheet:(id)sender
{
	[NSApp endSheet:selectRepoSheet];

	/* Remove repositories for any deleted users. */
	for (NSDictionary *prevUser in _previousRepoUsers) {
		NSString *prevOwner = [prevUser objectForKey:@"username"];
		BOOL found = NO;
		for (NSDictionary *repoUser in [repoUsersController arrangedObjects]) {
			if ([[repoUser objectForKey:@"username"] isEqualToString:prevOwner]) {
				found = YES;
				break;
			}
		}
		if (!found) {
			[_repositories filterUsingPredicate:[NSPredicate predicateWithFormat:@"NOT owner.login == %@", prevOwner]];
			[self filterRepositories:repoFilterField];
		}
	}

	/* Reload repositories for any added users. */
	NSMutableArray *newUsers = [NSMutableArray array];
	for (NSDictionary *repoUser in [repoUsersController arrangedObjects]) {
		BOOL found = NO;
		for (NSDictionary *prevUser in _previousRepoUsers) {
			if ([[repoUser objectForKey:@"username"] isEqualToString:[prevUser objectForKey:@"username"]]) {
				found = YES;
				break;
			}
		}
		if (!found)
			[newUsers addObject:repoUser];
	}
	[self reloadRepositoriesFromUsers:newUsers];
}

- (IBAction)selectRepositories:(id)sender
{
	_previousRepoUsers = [[repoUsersController arrangedObjects] copy];

	[[view window] beginSheet:selectRepoSheet completionHandler:^(NSModalResponse returnCode) {
        [self selectRepoSheetDidEnd:self->selectRepoSheet returnCode:(int)returnCode contextInfo:nil];
	}];
}

- (IBAction)addRepoUser:(id)sender
{
	NSMutableDictionary *item = [NSMutableDictionary dictionaryWithObject:[NSMutableString string] forKey:@"username"];
	[repoUsersController addObject:item];
	[repoUsersController setSelectedObjects:[NSArray arrayWithObject:item]];
	[repoUsersTable editColumn:0 row:[repoUsersController selectionIndex] withEvent:nil select:YES];
}

#pragma mark -
#pragma mark Downloading GitHub repositories

- (void)progressSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	[sheet orderOut:self];
	_progressCancelled = NO;
}

- (void)setExpectedContentLengthFromResponse:(NSURLResponse *)response
{
	long long expectedContentLength = [response expectedContentLength];
	if (expectedContentLength != NSURLResponseUnknownLength && expectedContentLength > 0) {
		[progressIndicator setIndeterminate:NO];
		[progressIndicator setMaxValue:expectedContentLength];
		[progressIndicator setDoubleValue:_receivedContentLength];
	}
}

- (void)resetProgressIndicator
{
	_receivedContentLength = 0;
	[progressButton setTitle:@"Cancel"];
	[progressButton setKeyEquivalent:@""];
	[progressIndicator setIndeterminate:YES];
	[progressIndicator startAnimation:self];

	_downloadTask = nil;

	_repoTask = nil;
}

- (IBAction)cancelProgressSheet:(id)sender
{
	if (_progressCancelled) {
		[NSApp endSheet:progressSheet];
		return;
	}

	/* This action is connected to both repo downloads and bundle installation. */
	if (_downloadTask) {
		[_downloadTask cancel];
		[_installTask terminate];
		_downloadTask = nil;
		_installTask = nil;
	} else if (_userTask) {
		[_userTask cancel];
		_userTask = nil;
	} else {
		[_repoTask cancel];
		_repoTask = nil;
	}

	_progressCancelled = YES;
	[progressButton setTitle:@"OK"];
	[progressButton setKeyEquivalent:@"\r"];
	[progressIndicator stopAnimation:self];
	[progressDescription setStringValue:@"Cancelled download from GitHub"];
}

- (void)reloadNextUser
{
	NSDictionary *repo = [_processQueue lastObject];
	NSString *username = [repo objectForKey:@"username"];
	if ([username length] == 0) {
		[_processQueue removeLastObject];
		if ([_processQueue count] == 0)
			[NSApp endSheet:progressSheet];
		else
			[self reloadNextUser];
	}

	[self resetProgressIndicator];
	[progressDescription setStringValue:[NSString stringWithFormat:@"Loading user %@...", username]];
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://api.github.com/users/%@", username]];

	_userTask = [_session dataTaskWithRequest:[NSURLRequest requestWithURL:url]
	                       completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		if (error) {
			if (error.code == NSURLErrorCancelled) return;
			NSMutableDictionary *repo = [self->_processQueue lastObject];
			[self->progressDescription setStringValue:[NSString stringWithFormat:@"Download of %@ failed: %@",
			    [repo objectForKey:@"username"], [error localizedDescription]]];
			[self cancelProgressSheet:nil];
			return;
		}
		NSMutableDictionary *repo = [self->_processQueue lastObject];
		NSString *username = [repo objectForKey:@"username"];
		NSString *jsonString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
		SBJsonParser *parser = [[SBJsonParser alloc] init];
		NSDictionary *dict = [parser objectWithString:jsonString];
		if (![dict isKindOfClass:[NSDictionary class]]) {
			[self cancelProgressSheet:nil];
			[self->progressDescription setStringValue:[NSString stringWithFormat:@"Failed to parse data for user %@.", username]];
			return;
		}
		DEBUG(@"got user %@: %@", username, dict);
		[self->progressDescription setStringValue:[NSString stringWithFormat:@"Loading repositories from %@...", username]];
		NSString *type = [dict objectForKey:@"type"];
		if ([type isEqualToString:@"User"])
			self->_repoURL = [NSURL URLWithString:[NSString stringWithFormat:@"https://api.github.com/users/%@/repos", username]];
		else if ([type isEqualToString:@"Organization"])
			self->_repoURL = [NSURL URLWithString:[NSString stringWithFormat:@"https://api.github.com/orgs/%@/repos", username]];
		else {
			[self cancelProgressSheet:nil];
			[self->progressDescription setStringValue:[NSString stringWithFormat:@"Unknown type %@ of user %@", type, username]];
			return;
		}
		self->_repoPage = 1;
		self->_repoJson = [NSMutableArray new];
		[self startRepoTask];
	}];
	[_userTask resume];
}

- (void)reloadRepositoriesFromUsers:(NSArray *)users
{
	if ([users count] == 0)
		return;

	[progressDescription setStringValue:@"Loading bundle repositories from GitHub..."];
	[[view window] beginSheet:progressSheet completionHandler:^(NSModalResponse returnCode) {
        [self progressSheetDidEnd:self->progressSheet returnCode:(int)returnCode contextInfo:nil];
	}];

	_processQueue = [[NSMutableArray alloc] initWithArray:users];
	[self reloadNextUser];
}

- (IBAction)reloadRepositories:(id)sender
{
	[self reloadRepositoriesFromUsers:[repoUsersController arrangedObjects]];
}

#pragma mark -
#pragma mark Installing bundles from GitHub

- (void)startRepoTask
{
	_repoTask = [_session dataTaskWithRequest:[NSURLRequest requestWithURL:_repoURL]
	                       completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		if (error) {
			if (error.code == NSURLErrorCancelled) return;
			NSDictionary *repoUser = [self->_processQueue lastObject];
			[self cancelProgressSheet:nil];
			[self->progressDescription setStringValue:[NSString stringWithFormat:@"Failed to load %@'s repository: %@",
			    [repoUser objectForKey:@"username"], [error localizedDescription]]];
			return;
		}
		NSString *jsonString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
		SBJsonParser *parser = [[SBJsonParser alloc] init];
		NSArray *repoJson = [parser objectWithString:jsonString];
		[self->_repoJson addObjectsFromArray:repoJson];

		NSDictionary *repoUser = [self->_processQueue lastObject];
		[self loadBundlesFromRepo:[repoUser objectForKey:@"username"]];
		[[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:@"LastBundleRepoReload"];

		if (repoJson.count == 0) {
			[self->_processQueue removeLastObject];
			if ([self->_processQueue count] == 0) {
				[NSApp endSheet:self->progressSheet];
			} else {
				[self reloadNextUser];
			}
		} else {
			NSURLComponents *noQueryComps = [[NSURLComponents alloc] init];
			noQueryComps.scheme = self->_repoURL.scheme;
			noQueryComps.host   = self->_repoURL.host;
			noQueryComps.path   = self->_repoURL.path;
			NSURL *noQueryURL = noQueryComps.URL;
			self->_repoPage++;
			self->_repoURL = [NSURL URLWithString:
			    [NSString stringWithFormat:@"%@?page=%d", noQueryURL.absoluteString, self->_repoPage]];
			DEBUG(@"Loading next page of repositories: %@", self->_repoURL);
			[self startRepoTask];
		}
	}];
	[_repoTask resume];
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location
{
	/* Download completion is handled via the per-task completion block. */
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
	if (downloadTask != _downloadTask)
		return;
	_receivedContentLength = totalBytesWritten;
	if (totalBytesExpectedToWrite > 0) {
		[progressIndicator setIndeterminate:NO];
		[progressIndicator setMaxValue:totalBytesExpectedToWrite];
		[progressIndicator setDoubleValue:totalBytesWritten];
	}
}

- (void)installNextBundle
{
	NSMutableDictionary *repo = [_processQueue lastObject];
	NSString *owner = [[repo objectForKey:@"owner"] objectForKey:@"login"];
	NSString *name = [repo objectForKey:@"name"];
	NSString *displayName = [repo objectForKey:@"displayName"];

	[self resetProgressIndicator];
	[progressDescription setStringValue:[NSString stringWithFormat:@"Downloading and installing %@ (by %@)...",
	    name, owner]];

	/*
	 * Move away any existing (temporary) bundle directory.
	 */
	NSError *error = nil;
	NSString *downloadDirectory = [[ViBundleStore bundlesDirectory] stringByAppendingPathComponent:@"download"];
	if (![[NSFileManager defaultManager] removeItemAtPath:downloadDirectory error:&error] && [error code] != NSFileNoSuchFileError) {
		[self cancelProgressSheet:nil];
		[progressDescription setStringValue:[NSString stringWithFormat:@"Installation of %@ failed: %@",
		    displayName, [error localizedDescription]]];
		return;
	}

	if (![[NSFileManager defaultManager] createDirectoryAtPath:downloadDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
		[self cancelProgressSheet:nil];
		[progressDescription setStringValue:[NSString stringWithFormat:@"Installation of %@ failed: %@",
		    displayName, [error localizedDescription]]];
		return;
	}

	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/tarball/master", [repo objectForKey:@"url"]]];

	_downloadTask = [_session downloadTaskWithRequest:[NSURLRequest requestWithURL:url]
	                               completionHandler:^(NSURL *location, NSURLResponse *response, NSError *dlError) {
		if (dlError) {
			if (dlError.code == NSURLErrorCancelled) return;
			[self cancelProgressSheet:nil];
			[self->progressDescription setStringValue:[NSString stringWithFormat:@"Download of %@ failed: %@",
			    displayName, [dlError localizedDescription]]];
			return;
		}

		/* Move temp file to a persistent path before NSURLSession deletes it. */
		NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
		    [NSString stringWithFormat:@"vico-bundle-%u.tar.gz", arc4random()]];
		NSError *moveError = nil;
		if (![[NSFileManager defaultManager] moveItemAtURL:location
		                                             toURL:[NSURL fileURLWithPath:tempPath]
		                                             error:&moveError]) {
			[self cancelProgressSheet:nil];
			[self->progressDescription setStringValue:[NSString stringWithFormat:@"Installation of %@ failed: %@",
			    displayName, [moveError localizedDescription]]];
			return;
		}

		[self->progressIndicator setIndeterminate:YES];
		self->_installTask = [[NSTask alloc] init];
		[self->_installTask setLaunchPath:@"/usr/bin/tar"];
		[self->_installTask setArguments:@[@"-x", @"-C", downloadDirectory, @"-f", tempPath]];

		@try {
			[self->_installTask launch];
		}
		@catch (NSException *exception) {
			[[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
			[self cancelProgressSheet:nil];
			[self->progressDescription setStringValue:[NSString stringWithFormat:@"Installation of %@ failed: %@",
			    displayName, [exception reason]]];
			return;
		}

		[self->_installTask waitUntilExit];
		int status = [self->_installTask terminationStatus];
		self->_installTask = nil;
		[[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];

		if (status != 0) {
			[self cancelProgressSheet:nil];
			[self->progressDescription setStringValue:[NSString stringWithFormat:
			    @"Installation of %@ failed when unpacking (status %d).", displayName, status]];
			return;
		}

		NSError *installError = nil;
		NSString *prefix = [NSString stringWithFormat:@"%@-%@", owner, name];
		NSString *bundleDirectory = nil;
		NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:downloadDirectory error:NULL];
		for (NSString *filename in contents) {
			if ([filename hasPrefix:prefix]) {
				bundleDirectory = filename;
				break;
			}
		}

		if (bundleDirectory == nil) {
			[self cancelProgressSheet:nil];
			[self->progressDescription setStringValue:[NSString stringWithFormat:
			    @"Installation of %@ failed: downloaded bundle not found", displayName]];
			return;
		}

		contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[ViBundleStore bundlesDirectory] error:NULL];
		for (NSString *filename in contents) {
			if ([filename hasPrefix:prefix]) {
				NSString *path = [[ViBundleStore bundlesDirectory] stringByAppendingPathComponent:filename];
				if (![[NSFileManager defaultManager] removeItemAtPath:path error:&installError]) {
					[self cancelProgressSheet:nil];
					[self->progressDescription setStringValue:[NSString stringWithFormat:
					    @"Installation of %@ failed: %@ (%li)",
					    displayName, [installError localizedDescription], [installError code]]];
					return;
				}
				break;
			}
		}

		/*
		 * Move the bundle from the download directory to the bundles directory.
		 */
		NSString *src = [downloadDirectory stringByAppendingPathComponent:bundleDirectory];
		NSString *dst = [[ViBundleStore bundlesDirectory] stringByAppendingPathComponent:
		    [NSString stringWithFormat:@"%@-%@", owner, name]];
		if (![[NSFileManager defaultManager] moveItemAtPath:src toPath:dst error:&installError]) {
			[self cancelProgressSheet:nil];
			[self->progressDescription setStringValue:[NSString stringWithFormat:@"Installation of %@ failed: %@",
			    displayName, [installError localizedDescription]]];
			return;
		}

		NSMutableDictionary *currentRepo = [self->_processQueue lastObject];
		if ([[ViBundleStore defaultStore] loadBundleFromDirectory:dst])
			[currentRepo setObject:@"Installed" forKey:@"status"];
		[self updateBundleStatus];

		[self->_processQueue removeLastObject];
		if ([self->_processQueue count] == 0)
			[NSApp endSheet:self->progressSheet];
		else
			[self installNextBundle];
	}];
	[_downloadTask resume];
}

- (IBAction)installBundles:(id)sender
{
	NSArray *selectedBundles = [bundlesController selectedObjects];
	if ([selectedBundles count] == 0)
		return;

	[[view window] beginSheet:progressSheet completionHandler:^(NSModalResponse returnCode) {
        [self progressSheetDidEnd:self->progressSheet returnCode:(int)returnCode contextInfo:nil];
	}];

	_processQueue = [[NSMutableArray alloc] initWithArray:selectedBundles];
	[self installNextBundle];
}

- (IBAction)uninstallBundles:(id)sender
{
}

@end
