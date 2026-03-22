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

#import "ViAppController.h"
#import <objc/message.h>
#import "ViThemeStore.h"
#import "ViBundleStore.h"
#import "ViDocument.h"
#import "ViDocumentView.h"
#import "ViDocumentController.h"
#import "ViPreferencesController.h"
#import "ViPreferencePaneGeneral.h"
#import "ViPreferencePaneEdit.h"
#import "ViPreferencePaneTheme.h"
#import "ViPreferencePaneBundles.h"
#import "ViPreferencePaneAdvanced.h"
#import "TMFileURLProtocol.h"
#import "TxmtURLProtocol.h"
#import "SBJson.h"
#import "ViError.h"
#import "ViCommandMenuItemView.h"
#import "ViEventManager.h"
#import "ViFileExplorer.h"
#import "ViMarkInspector.h"
#import "NSMenu-additions.h"
#import <Sparkle/Sparkle.h>
#import "SFBCrashReporter.h"
#import "ViXPCProtocols.h"
#import "ViXPCBackChannelProxy.h"

#import "ViFileURLHandler.h"
#import "ViSFTPURLHandler.h"
#import "ViHTTPURLHandler.h"

#include <sys/time.h>

BOOL openUntitledDocument = YES;

@interface caretBlinkModeTransformer : NSValueTransformer
{
}
@end

@implementation caretBlinkModeTransformer
+ (Class)transformedValueClass { return [NSString class]; }
+ (BOOL)allowsReverseTransformation { return YES; }
- (id)init { return [super init]; }
- (id)transformedValue:(id)value
{
	if ([value isKindOfClass:[NSNumber class]]) {
		switch ([value intValue]) {
		case ViInsertMode:
			return @"insert";
		case ViNormalMode | ViVisualMode:
			return @"normal";
		case ViInsertMode | ViNormalMode | ViVisualMode:
			return @"both";
		default:
			return @"none";
		}
	} else if ([value isKindOfClass:[NSString class]]) {
		if ([value isEqualToString:@"insert"])
			return [NSNumber numberWithInt:ViInsertMode];
		else if ([value isEqualToString:@"normal"])
			return [NSNumber numberWithInt:ViNormalMode | ViVisualMode];
		else if ([value isEqualToString:@"both"])
			return [NSNumber numberWithInt:ViInsertMode | ViNormalMode | ViVisualMode];
		else
			return [NSNumber numberWithInt:0];
	}

	return nil;
}
@end

@interface ViAppController ()

- (void)setCloseCallbackForDocument:(ViDocument *)document
                        backChannel:(ViXPCBackChannelProxy *)backChannel;

@end

@implementation ViAppController

@synthesize encodingMenu;
@synthesize original_input_source;

@synthesize statusSetupBlock = _statusSetupBlock;

- (void)getUrl:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent
{
	NSString *s = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];

	NSURL *url = [NSURL URLWithString:s];
	[[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:url
									       display:YES
								 completionHandler:^(NSDocument *doc, BOOL wasOpen, NSError *err) {
		if (err)
			[NSApp presentError:err];
	}];
}

- (id)init
{
	self = [super init];
	if (self) {
		[NSApp setDelegate:self];
		[[NSAppleEventManager sharedAppleEventManager] setEventHandler:self
								   andSelector:@selector(getUrl:withReplyEvent:)
								 forEventClass:kInternetEventClass
								    andEventID:kAEGetURL];

		[NSValueTransformer setValueTransformer:[[caretBlinkModeTransformer alloc] init]
						forName:@"caretBlinkModeTransformer"];

		_statusSetupBlock = nil;
	}
	return self;
}


// stops the application from creating an untitled document on load
- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
	BOOL ret = openUntitledDocument;
	openUntitledDocument = YES;
	return ret;
}

- (void)newBundleLoaded:(NSNotification *)notification
{
	/* Check if any open documents got a better language available. */
	ViDocument *doc;
	for (doc in [[NSDocumentController sharedDocumentController] documents])
		if ([doc respondsToSelector:@selector(configureSyntax)])
			[doc configureSyntax];
}

+ (NSString *)supportDirectory
{
	static NSString *__supportDirectory = nil;
	if (__supportDirectory == nil) {
		NSURL *url = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory
								    inDomain:NSUserDomainMask
							   appropriateForURL:nil
								      create:YES
								       error:nil];
		__supportDirectory = [[url path] stringByAppendingPathComponent:@"Vico"];
	}
	return __supportDirectory;
}

#ifdef TRIAL_VERSION
#include <CommonCrypto/CommonDigest.h>
#define MD5_CTX          CC_MD5_CTX
#define MD5_DIGEST_LENGTH CC_MD5_DIGEST_LENGTH
#define MD5_Init         CC_MD5_Init
#define MD5_Update       CC_MD5_Update
#define MD5_Final        CC_MD5_Final
int
updateMeta(void)
{
	NSUserDefaults *userDefs = [NSUserDefaults standardUserDefaults];

	int left = 0;
	time_t last = 0;
	id daysLeft = [userDefs objectForKey:@"left"];
	id lastDayUsed = [userDefs objectForKey:@"last"];
	NSData *hash = [userDefs dataForKey:@"meta"];
	time_t now = time(NULL);

	if (daysLeft == nil || lastDayUsed == nil || hash == nil) {
		if (daysLeft == nil && lastDayUsed == nil && hash == nil) {
			/*
			 * This is the first run.
			 */
			left = 16;
		}
	} else if (![daysLeft respondsToSelector:@selector(intValue)] ||
		   ![lastDayUsed respondsToSelector:@selector(integerValue)] ||
		    [hash length] != MD5_DIGEST_LENGTH) {
		/* Weird value. */
		left = 0;
	} else {
		left = [daysLeft intValue];
		last = [lastDayUsed integerValue] + 1311334235;
		if (left < 0 || left > 15 || last < 0 /*|| last + 3600*2 > now*/) {
			/* Weird value. */
			left = 0;
		} else {
			MD5_CTX ctx;
			bzero(&ctx, sizeof(ctx));
			MD5_Init(&ctx);
			MD5_Update(&ctx, &left, sizeof(left));
			MD5_Update(&ctx, &last, sizeof(last));
			uint8_t md[MD5_DIGEST_LENGTH];
			MD5_Final(md, &ctx);
			if (bcmp(md, [hash bytes], MD5_DIGEST_LENGTH) != 0) {
				/* Hash does NOT correspond to the value. */
				left = 0;
			}
		}
	}

	if (left > 0) {
		struct tm tm_last, tm_now;
		localtime_r(&last, &tm_last);
		localtime_r(&now, &tm_now);
		if (tm_last.tm_yday != tm_now.tm_yday || tm_last.tm_year != tm_now.tm_year) {
			--left;
			[userDefs setInteger:left forKey:@"left"];
			[userDefs setInteger:now - 1311334235 forKey:@"last"];
			MD5_CTX ctx;
			bzero(&ctx, sizeof(ctx));
			MD5_Init(&ctx);
			MD5_Update(&ctx, &left, sizeof(left));
			MD5_Update(&ctx, &now, sizeof(now));
			uint8_t md[MD5_DIGEST_LENGTH];
			MD5_Final(md, &ctx);
			[userDefs setObject:[NSData dataWithBytes:md length:MD5_DIGEST_LENGTH]
				     forKey:@"meta"];
		}
	}

	[[NSNotificationCenter defaultCenter] postNotificationName:ViTrialDaysChangedNotification
							    object:[NSNumber numberWithInt:left]];

	return left;
}
#endif

- (void)buildMainMenu
{
	NSMenu *mainMenu = [[NSMenu alloc] init];

	/* ====== Vico (app) menu ====== */
	NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
	NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Vico"];
	[appMenu addItemWithTitle:@"About Vico" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];

	checkForUpdatesMenuItem = [appMenu addItemWithTitle:@"Check for Updates..." action:nil keyEquivalent:@""];

	[appMenu addItem:[NSMenuItem separatorItem]];

	[appMenu addItemWithTitle:@"Preferences\u2026" action:@selector(showPreferences:) keyEquivalent:@","];
	[[appMenu itemArray].lastObject setTarget:self];

	[appMenu addItemWithTitle:@"Edit Site Script" action:@selector(editSiteScript:) keyEquivalent:@""];
	[[appMenu itemArray].lastObject setTarget:self];

	[appMenu addItem:[NSMenuItem separatorItem]];

	NSMenuItem *servicesItem = [[NSMenuItem alloc] initWithTitle:@"Services" action:nil keyEquivalent:@""];
	NSMenu *servicesMenu = [[NSMenu alloc] initWithTitle:@"Services"];
	[servicesItem setSubmenu:servicesMenu];
	[appMenu addItem:servicesItem];
	[NSApp setServicesMenu:servicesMenu];

	[appMenu addItem:[NSMenuItem separatorItem]];
	[appMenu addItemWithTitle:@"Hide Vico" action:@selector(hide:) keyEquivalent:@"h"];
	NSMenuItem *hideOthersItem = [appMenu addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
	[hideOthersItem setKeyEquivalentModifierMask:NSEventModifierFlagOption | NSEventModifierFlagCommand];
	[appMenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
	[appMenu addItem:[NSMenuItem separatorItem]];
	[appMenu addItemWithTitle:@"Quit Vico" action:@selector(terminate:) keyEquivalent:@"q"];

	[appMenuItem setSubmenu:appMenu];
	[mainMenu addItem:appMenuItem];
	((void (*)(id, SEL, id))objc_msgSend)(NSApp, NSSelectorFromString(@"setAppleMenu:"), appMenu);

	/* ====== File menu ====== */
	NSMenuItem *fileMenuItem = [[NSMenuItem alloc] init];
	NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
	[fileMenu setDelegate:self];

	[fileMenu addItemWithTitle:@"New Document" action:@selector(newDocument:) keyEquivalent:@"N"];
	[fileMenu addItemWithTitle:@"New Window" action:@selector(newProject:) keyEquivalent:@"n"];

	NSMenuItem *item;
	item = [fileMenu addItemWithTitle:@"New Split (<c-w>n)" action:nil keyEquivalent:@""];
	[item setTag:4000];
	item = [fileMenu addItemWithTitle:@"New Vertical Split (:vnew<cr>)(:<c-u>vnew<cr>)" action:nil keyEquivalent:@""];
	[item setTag:4000];

	[fileMenu addItem:[NSMenuItem separatorItem]];
	[fileMenu addItemWithTitle:@"Open\u2026" action:@selector(openDocument:) keyEquivalent:@"o"];

	NSMenuItem *openRecentItem = [[NSMenuItem alloc] initWithTitle:@"Open Recent" action:nil keyEquivalent:@""];
	NSMenu *openRecentMenu = [[NSMenu alloc] initWithTitle:@"Open Recent"];
	[openRecentMenu addItemWithTitle:@"Clear Menu" action:@selector(clearRecentDocuments:) keyEquivalent:@""];
	[openRecentItem setSubmenu:openRecentMenu];
	[fileMenu addItem:openRecentItem];

	NSMenuItem *reopenEncodingItem = [[NSMenuItem alloc] initWithTitle:@"Reopen with Encoding" action:nil keyEquivalent:@""];
	NSMenu *reopenEncodingMenu = [[NSMenu alloc] initWithTitle:@"Reopen with Encoding"];
	[reopenEncodingItem setSubmenu:reopenEncodingMenu];
	[fileMenu addItem:reopenEncodingItem];
	encodingMenu = reopenEncodingMenu;

	[fileMenu addItem:[NSMenuItem separatorItem]];

	closeWindowMenuItem = [fileMenu addItemWithTitle:@"Close Window" action:@selector(performClose:) keyEquivalent:@"W"];

	closeDocumentMenuItem = [fileMenu addItemWithTitle:@"Close Document" action:@selector(closeCurrentDocument:) keyEquivalent:@"w"];
	[closeDocumentMenuItem setKeyEquivalentModifierMask:NSEventModifierFlagControl | NSEventModifierFlagCommand];

	closeTabMenuItem = [fileMenu addItemWithTitle:@"Close" action:@selector(closeCurrent:) keyEquivalent:@"w"];

	item = [fileMenu addItemWithTitle:@"Close View (<c-w>c)" action:nil keyEquivalent:@""];
	[item setTag:4000];
	item = [fileMenu addItemWithTitle:@"Close Other Views (<c-w>o)" action:nil keyEquivalent:@""];
	[item setTag:4000];

	[fileMenu addItem:[NSMenuItem separatorItem]];
	[fileMenu addItemWithTitle:@"Save" action:@selector(saveDocument:) keyEquivalent:@"s"];

	item = [fileMenu addItemWithTitle:@"Save As\u2026" action:@selector(saveDocumentAs:) keyEquivalent:@"S"];
	[item setKeyEquivalentModifierMask:NSEventModifierFlagShift | NSEventModifierFlagCommand];

	item = [fileMenu addItemWithTitle:@"Revert to Saved (:edit!<cr>)(:<c-u>edit!<cr>)" action:@selector(revertDocumentToSaved:) keyEquivalent:@""];
	[item setTag:4000];

	item = [[NSMenuItem separatorItem] init];
	[item setHidden:YES];
	[fileMenu addItem:[NSMenuItem separatorItem]];
	[[fileMenu itemArray].lastObject setHidden:YES];

	item = [fileMenu addItemWithTitle:@"Page Setup..." action:@selector(runPageLayout:) keyEquivalent:@"P"];
	[item setKeyEquivalentModifierMask:NSEventModifierFlagShift | NSEventModifierFlagCommand];
	[item setHidden:YES];

	item = [fileMenu addItemWithTitle:@"Print\u2026" action:@selector(printDocument:) keyEquivalent:@"p"];
	[item setHidden:YES];

	[fileMenuItem setSubmenu:fileMenu];
	[mainMenu addItem:fileMenuItem];

	/* ====== Edit menu ====== */
	NSMenuItem *editMenuItem = [[NSMenuItem alloc] init];
	NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
	[editMenu setDelegate:self];

	[editMenu addItemWithTitle:@"Undo" action:NSSelectorFromString(@"undo:") keyEquivalent:@"z"];
	item = [editMenu addItemWithTitle:@"Redo" action:NSSelectorFromString(@"redo:") keyEquivalent:@"Z"];
	[item setKeyEquivalentModifierMask:NSEventModifierFlagShift | NSEventModifierFlagCommand];
	item = [editMenu addItemWithTitle:@"Repeat Last Change (.)()" action:nil keyEquivalent:@""];
	[item setTag:4000];

	[editMenu addItem:[NSMenuItem separatorItem]];
	[editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
	[editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
	[editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
	item = [editMenu addItemWithTitle:@"Delete ()(\"_x)" action:@selector(cut:) keyEquivalent:@""];
	[item setTag:4000];

	[editMenu addItem:[NSMenuItem separatorItem]];

	/* Insert Text submenu */
	NSMenuItem *insertTextItem = [[NSMenuItem alloc] initWithTitle:@"Insert Text" action:nil keyEquivalent:@""];
	NSMenu *insertTextMenu = [[NSMenu alloc] initWithTitle:@"Insert Text"];
	[insertTextMenu setDelegate:self];
	item = [insertTextMenu addItemWithTitle:@"Insert at Caret (i)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [insertTextMenu addItemWithTitle:@"Insert at Beginning of Line (I)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [insertTextMenu addItemWithTitle:@"Insert after Caret (a)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [insertTextMenu addItemWithTitle:@"Insert after End of Line (A)" action:nil keyEquivalent:@""]; [item setTag:4000];
	[insertTextMenu addItem:[NSMenuItem separatorItem]];
	item = [insertTextMenu addItemWithTitle:@"Insert Line below (o)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [insertTextMenu addItemWithTitle:@"Insert Line above (O)" action:nil keyEquivalent:@""]; [item setTag:4000];
	[insertTextMenu addItem:[NSMenuItem separatorItem]];
	item = [insertTextMenu addItemWithTitle:@"Insert at Last Insertion (gi)" action:nil keyEquivalent:@""]; [item setTag:4000];
	[insertTextItem setSubmenu:insertTextMenu];
	[editMenu addItem:insertTextItem];

	[editMenu addItem:[NSMenuItem separatorItem]];
	item = [editMenu addItemWithTitle:@"Shift Line / Selection Left (<<)(<)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [editMenu addItemWithTitle:@"Shift Line / Selection Right (>>)(>)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [editMenu addItemWithTitle:@"Indent Line / Selection (==)(=)" action:nil keyEquivalent:@""]; [item setTag:4000];
	[editMenu addItem:[NSMenuItem separatorItem]];
	item = [editMenu addItemWithTitle:@"Join Lines (J)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [editMenu addItemWithTitle:@"Reformat Paragraph / Selection (gqap)(gq)" action:nil keyEquivalent:@""]; [item setTag:4000];
	[editMenu addItem:[NSMenuItem separatorItem]];

	/* Select submenu */
	NSMenuItem *selectItem = [[NSMenuItem alloc] initWithTitle:@"Select" action:nil keyEquivalent:@""];
	NSMenu *selectMenu = [[NSMenu alloc] initWithTitle:@"Select"];
	[selectMenu setDelegate:self];
	item = [selectMenu addItemWithTitle:@"Word (viw)(iw)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [selectMenu addItemWithTitle:@"Line (V)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [selectMenu addItemWithTitle:@"Sentence (vis)(is)" action:nil keyEquivalent:@""];
	[item setTag:4000]; [item setHidden:YES]; [item setEnabled:NO];
	item = [selectMenu addItemWithTitle:@"Paragraph (vip)(ip)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [selectMenu addItemWithTitle:@"( Block ) (vib)(ib)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [selectMenu addItemWithTitle:@"{ Block } (viB)(iB)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [selectMenu addItemWithTitle:@"[ Block ] (vi[)(i[)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [selectMenu addItemWithTitle:@"< Block > (vi<)(i<)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [selectMenu addItemWithTitle:@"Scope (viS)(iS)" action:nil keyEquivalent:@""]; [item setTag:4000];
	[selectMenu addItemWithTitle:@"All" action:@selector(selectAll:) keyEquivalent:@"a"];
	[selectMenu addItem:[NSMenuItem separatorItem]];
	item = [selectMenu addItemWithTitle:@"Reselect Last Selection (gv)" action:nil keyEquivalent:@""]; [item setTag:4000];
	[selectItem setSubmenu:selectMenu];
	[editMenu addItem:selectItem];

	/* Convert submenu */
	NSMenuItem *convertItem = [[NSMenuItem alloc] initWithTitle:@"Convert" action:nil keyEquivalent:@""];
	NSMenu *convertMenu = [[NSMenu alloc] initWithTitle:@"Convert"];
	[convertMenu setDelegate:self];
	item = [convertMenu addItemWithTitle:@"Upper Case Word / Selection (gUiw)(U)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [convertMenu addItemWithTitle:@"Lower Case Word / Selection (guiw)(u)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [convertMenu addItemWithTitle:@"Toggle Case Word / Selection (g~iw)(~)" action:nil keyEquivalent:@""]; [item setTag:4000];
	[convertMenu addItem:[NSMenuItem separatorItem]];
	item = [convertMenu addItemWithTitle:@"Tabs to Spaces (:%!expand<cr>)(!expand<cr>)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [convertMenu addItemWithTitle:@"Spaces to Tabs (:%!unexpand<cr>)(!unexpand<cr>)" action:nil keyEquivalent:@""]; [item setTag:4000];
	[convertItem setSubmenu:convertMenu];
	[editMenu addItem:convertItem];

	/* Filter submenu */
	NSMenuItem *filterItem = [[NSMenuItem alloc] initWithTitle:@"Filter" action:nil keyEquivalent:@""];
	NSMenu *filterMenu = [[NSMenu alloc] initWithTitle:@"Filter"];
	[filterMenu setDelegate:self];
	item = [filterMenu addItemWithTitle:@"Filter Through Command... (gg!G )(!)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [filterMenu addItemWithTitle:@"Sort Document / Selection (:%!sort<cr>)(!sort<cr>)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [filterMenu addItemWithTitle:@"Sort and Remove Duplicates (:%!sort -u<cr>)(!sort -u<cr>)" action:nil keyEquivalent:@""]; [item setTag:4000];
	[filterItem setSubmenu:filterMenu];
	[editMenu addItem:filterItem];

	/* Find submenu */
	NSMenuItem *findItem = [[NSMenuItem alloc] initWithTitle:@"Find" action:nil keyEquivalent:@""];
	NSMenu *findMenu = [[NSMenu alloc] initWithTitle:@"Find"];
	[findMenu setDelegate:self];
	item = [findMenu addItemWithTitle:@"Find\u2026 (/)" action:@selector(performFindPanelAction:) keyEquivalent:@"f"];
	[item setTag:4000];
	item = [findMenu addItemWithTitle:@"Find Backwards\u2026 (?)" action:@selector(performFindPanelAction:) keyEquivalent:@""];
	[item setTag:4000];
	item = [findMenu addItemWithTitle:@"Find Current Word (*)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [findMenu addItemWithTitle:@"Find Current Word Backwards (#)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [findMenu addItemWithTitle:@"Find Next (n)" action:nil keyEquivalent:@"g"];
	[item setTag:4000];
	item = [findMenu addItemWithTitle:@"Find Previous (N)" action:nil keyEquivalent:@"G"];
	[item setTag:4000];
	[item setKeyEquivalentModifierMask:NSEventModifierFlagShift | NSEventModifierFlagCommand];
	[findItem setSubmenu:findMenu];
	[editMenu addItem:findItem];

	/* Spelling and Grammar submenu */
	NSMenuItem *spellingItem = [[NSMenuItem alloc] initWithTitle:@"Spelling and Grammar" action:nil keyEquivalent:@""];
	NSMenu *spellingMenu = [[NSMenu alloc] initWithTitle:@"Spelling and Grammar"];
	[spellingMenu addItemWithTitle:@"Show Spelling\u2026" action:@selector(showGuessPanel:) keyEquivalent:@":"];
	[spellingMenu addItemWithTitle:@"Check Spelling" action:@selector(checkSpelling:) keyEquivalent:@";"];
	[spellingMenu addItemWithTitle:@"Check Spelling While Typing" action:@selector(toggleContinuousSpellChecking:) keyEquivalent:@""];
	[spellingMenu addItemWithTitle:@"Check Grammar With Spelling" action:@selector(toggleGrammarChecking:) keyEquivalent:@""];
	[spellingItem setSubmenu:spellingMenu];
	[editMenu addItem:spellingItem];

	/* Speech submenu */
	NSMenuItem *speechItem = [[NSMenuItem alloc] initWithTitle:@"Speech" action:nil keyEquivalent:@""];
	NSMenu *speechMenu = [[NSMenu alloc] initWithTitle:@"Speech"];
	[speechMenu addItemWithTitle:@"Start Speaking" action:@selector(startSpeaking:) keyEquivalent:@""];
	[speechMenu addItemWithTitle:@"Stop Speaking" action:@selector(stopSpeaking:) keyEquivalent:@""];
	[speechItem setSubmenu:speechMenu];
	[editMenu addItem:speechItem];

	[editMenuItem setSubmenu:editMenu];
	[mainMenu addItem:editMenuItem];

	/* ====== Navigate menu ====== */
	NSMenuItem *navigateMenuItem = [[NSMenuItem alloc] init];
	NSMenu *navigateMenu = [[NSMenu alloc] initWithTitle:@"Navigate"];
	[navigateMenu setDelegate:self];

	[navigateMenu addItemWithTitle:@"Go to Symbol..." action:@selector(searchSymbol:) keyEquivalent:@"T"];
	[navigateMenu addItemWithTitle:@"Go to File..." action:@selector(searchFiles:) keyEquivalent:@"t"];
	item = [navigateMenu addItemWithTitle:@"Go to Previous File (<C-^>)" action:nil keyEquivalent:@""]; [item setTag:4000];

	item = [navigateMenu addItemWithTitle:@"Reveal Document in Explorer" action:@selector(revealCurrentDocument:) keyEquivalent:@"r"];
	[item setKeyEquivalentModifierMask:NSEventModifierFlagControl | NSEventModifierFlagCommand];

	[navigateMenu addItem:[NSMenuItem separatorItem]];
	item = [navigateMenu addItemWithTitle:@"Go Back in Jump List (<C-o>)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [navigateMenu addItemWithTitle:@"Go Forward in Jump List (<C-i>)" action:nil keyEquivalent:@""]; [item setTag:4000];
	[navigateMenu addItem:[NSMenuItem separatorItem]];
	item = [navigateMenu addItemWithTitle:@"Go to Definition of Tag (<C-]>)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [navigateMenu addItemWithTitle:@"Go Back (<C-t>)" action:nil keyEquivalent:@""]; [item setTag:4000];
	[navigateMenu addItem:[NSMenuItem separatorItem]];

	/* Go to submenu */
	NSMenuItem *gotoItem = [[NSMenuItem alloc] initWithTitle:@"Go to" action:nil keyEquivalent:@""];
	NSMenu *gotoMenu = [[NSMenu alloc] initWithTitle:@"Go to"];
	[gotoMenu setDelegate:self];
	item = [gotoMenu addItemWithTitle:@"Go to Beginning of Line (0)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [gotoMenu addItemWithTitle:@"Go to First Nonblank (^)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [gotoMenu addItemWithTitle:@"Go to End of Line ($)" action:nil keyEquivalent:@""]; [item setTag:4000];
	[gotoMenu addItem:[NSMenuItem separatorItem]];
	item = [gotoMenu addItemWithTitle:@"Go to First Line (gg)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [gotoMenu addItemWithTitle:@"Go to Last Line (G)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [gotoMenu addItemWithTitle:@"Go to Line Number (:)" action:nil keyEquivalent:@""]; [item setTag:4000];
	[gotoMenu addItem:[NSMenuItem separatorItem]];
	item = [gotoMenu addItemWithTitle:@"Go to Next Paragraph (})" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [gotoMenu addItemWithTitle:@"Go to Previous Paragraph ({)" action:nil keyEquivalent:@""]; [item setTag:4000];
	[gotoMenu addItem:[NSMenuItem separatorItem]];
	item = [gotoMenu addItemWithTitle:@"Go to Top of Screen (H)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [gotoMenu addItemWithTitle:@"Go to Middle of Screen (M)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [gotoMenu addItemWithTitle:@"Go to Bottom of Screen (L)" action:nil keyEquivalent:@""]; [item setTag:4000];
	[gotoMenu addItem:[NSMenuItem separatorItem]];
	item = [gotoMenu addItemWithTitle:@"Go to Last Change (`.)" action:nil keyEquivalent:@""]; [item setTag:4000];
	[gotoItem setSubmenu:gotoMenu];
	[navigateMenu addItem:gotoItem];

	/* Scroll submenu */
	NSMenuItem *scrollItem = [[NSMenuItem alloc] initWithTitle:@"Scroll" action:nil keyEquivalent:@""];
	NSMenu *scrollMenu = [[NSMenu alloc] initWithTitle:@"Scroll"];
	[scrollMenu setDelegate:self];
	item = [scrollMenu addItemWithTitle:@"Scroll Line Down (<C-e>)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [scrollMenu addItemWithTitle:@"Scroll Line Up (<C-y>)" action:nil keyEquivalent:@""]; [item setTag:4000];
	[scrollMenu addItem:[NSMenuItem separatorItem]];
	item = [scrollMenu addItemWithTitle:@"Scroll Half Page Down (<C-d>)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [scrollMenu addItemWithTitle:@"Scroll Half Page Up (<C-u>)" action:nil keyEquivalent:@""]; [item setTag:4000];
	[scrollMenu addItem:[NSMenuItem separatorItem]];
	item = [scrollMenu addItemWithTitle:@"Scroll Page Down (<C-f>)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [scrollMenu addItemWithTitle:@"Scroll Page Up (<C-b>)" action:nil keyEquivalent:@""]; [item setTag:4000];
	[scrollMenu addItem:[NSMenuItem separatorItem]];
	item = [scrollMenu addItemWithTitle:@"Position Caret at Top (zt)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [scrollMenu addItemWithTitle:@"Position Caret at Center (zz)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [scrollMenu addItemWithTitle:@"Position Caret at Bottom (zb)" action:nil keyEquivalent:@""]; [item setTag:4000];
	[scrollItem setSubmenu:scrollMenu];
	[navigateMenu addItem:scrollItem];

	[navigateMenuItem setSubmenu:navigateMenu];
	[mainMenu addItem:navigateMenuItem];

	/* ====== View menu ====== */
	NSMenuItem *viewMenuItem = [[NSMenuItem alloc] init];
	viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
	[viewMenu setDelegate:self];

	[viewMenu addItemWithTitle:@"Navigate Symbol List" action:@selector(focusSymbols:) keyEquivalent:@"y"];
	showSymbolListMenuItem = [viewMenu addItemWithTitle:@"Show Symbol List" action:@selector(toggleSymbolList:) keyEquivalent:@"Y"];
	[viewMenu addItem:[NSMenuItem separatorItem]];
	[viewMenu addItemWithTitle:@"Navigate File Explorer" action:@selector(focusExplorer:) keyEquivalent:@"e"];
	showFileExplorerMenuItem = [viewMenu addItemWithTitle:@"Show File Explorer" action:@selector(toggleExplorer:) keyEquivalent:@"E"];
	[viewMenu addItem:[NSMenuItem separatorItem]];

	item = [viewMenu addItemWithTitle:@"Split Horizontally (<c-w>s)" action:@selector(splitViewHorizontally:) keyEquivalent:@""];
	[item setTag:4000];
	item = [viewMenu addItemWithTitle:@"Split Vertically (<c-w>v)" action:@selector(splitViewVertically:) keyEquivalent:@""];
	[item setTag:4000];
	item = [viewMenu addItemWithTitle:@"Move View to New Tab (<c-w>T)" action:@selector(moveCurrentViewToNewTabAction:) keyEquivalent:@""];
	[item setTag:4000];
	item = [viewMenu addItemWithTitle:@"Move View to New Window (<c-w>D)" action:NSSelectorFromString(@"moveCurrentViewToNewWindowAction:") keyEquivalent:@""];
	[item setTag:4000];

	/* Select Split View submenu */
	NSMenuItem *selectSplitItem = [[NSMenuItem alloc] initWithTitle:@"Select Split View" action:nil keyEquivalent:@""];
	NSMenu *selectSplitMenu = [[NSMenu alloc] initWithTitle:@"Select Split View"];
	[selectSplitMenu setDelegate:self];
	item = [selectSplitMenu addItemWithTitle:@"Select Left View (<C-w>h)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [selectSplitMenu addItemWithTitle:@"Select Right View (<C-w>l)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [selectSplitMenu addItemWithTitle:@"Select View Above (<C-w>k)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [selectSplitMenu addItemWithTitle:@"Select View Below (<C-w>j)" action:nil keyEquivalent:@""]; [item setTag:4000];
	[selectSplitMenu addItem:[NSMenuItem separatorItem]];
	item = [selectSplitMenu addItemWithTitle:@"Select Last View (<C-w>p)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [selectSplitMenu addItemWithTitle:@"Select Next View (<C-w>w)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [selectSplitMenu addItemWithTitle:@"Select Previous View (<C-w>W)" action:nil keyEquivalent:@""]; [item setTag:4000];
	[selectSplitItem setSubmenu:selectSplitMenu];
	[viewMenu addItem:selectSplitItem];

	[viewMenu addItem:[NSMenuItem separatorItem]];
	[viewMenu addItemWithTitle:@"Bigger font" action:@selector(increaseFontsizeAction:) keyEquivalent:@"+"];
	[viewMenu addItemWithTitle:@"Smaller font" action:@selector(decreaseFontsizeAction:) keyEquivalent:@"-"];
	[viewMenu addItem:[NSMenuItem separatorItem]];

	item = [viewMenu addItemWithTitle:@"Show Toolbar" action:@selector(toggleToolbarShown:) keyEquivalent:@"t"];
	[item setKeyEquivalentModifierMask:NSEventModifierFlagOption | NSEventModifierFlagCommand];
	[viewMenu addItemWithTitle:@"Customize Toolbar\u2026" action:@selector(runToolbarCustomizationPalette:) keyEquivalent:@""];

	[viewMenuItem setSubmenu:viewMenu];
	[mainMenu addItem:viewMenuItem];

	/* ====== Develop menu ====== */
	NSMenuItem *developMenuItem = [[NSMenuItem alloc] initWithTitle:@"Develop" action:nil keyEquivalent:@""];
	NSMenu *developMenu = [[NSMenu alloc] initWithTitle:@"Develop"];
	[developMenu setDelegate:self];
	item = [developMenu addItemWithTitle:@"Reload Bundle (:reloadbundle<cr>)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [developMenu addItemWithTitle:@"Toggle Console (:console<cr>)" action:nil keyEquivalent:@""]; [item setTag:4000];
	item = [developMenu addItemWithTitle:@"Evaluate File / Selection (:%eval<cr>)(:eval<cr>)" action:nil keyEquivalent:@""]; [item setTag:4000];
	[developMenuItem setSubmenu:developMenu];
	[mainMenu addItem:developMenuItem];

	/* Wire ViDocumentController's developMenu outlet */
	[(ViDocumentController *)[NSDocumentController sharedDocumentController] setDevelopMenu:developMenuItem];

	/* ====== Window menu ====== */
	NSMenuItem *windowMenuItem = [[NSMenuItem alloc] init];
	NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
	[windowMenu setDelegate:self];

	[windowMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
	[windowMenu addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
	[windowMenu addItem:[NSMenuItem separatorItem]];

	item = [windowMenu addItemWithTitle:@"Select Next Tab" action:@selector(selectNextTab:) keyEquivalent:@"\t"];
	[item setKeyEquivalentModifierMask:NSEventModifierFlagControl];
	item = [windowMenu addItemWithTitle:@"Select Previous Tab" action:@selector(selectPreviousTab:) keyEquivalent:@"\t"];
	[item setKeyEquivalentModifierMask:NSEventModifierFlagShift | NSEventModifierFlagControl];

	[windowMenu addItem:[NSMenuItem separatorItem]];

	item = [windowMenu addItemWithTitle:@"Show Mark Inspector" action:@selector(showMarkInspector:) keyEquivalent:@""];
	[item setTarget:self];
	[item setHidden:YES];

	[windowMenu addItemWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) keyEquivalent:@""];

	[windowMenuItem setSubmenu:windowMenu];
	[mainMenu addItem:windowMenuItem];
	[NSApp setWindowsMenu:windowMenu];

	/* ====== Help menu ====== */
	NSMenuItem *helpMenuItem = [[NSMenuItem alloc] init];
	NSMenu *helpMenu = [[NSMenu alloc] initWithTitle:@"Help"];

	[helpMenu addItemWithTitle:@"Vico Help" action:@selector(showHelp:) keyEquivalent:@"?"];

	item = [helpMenu addItemWithTitle:@"Install Terminal Helper" action:@selector(installTerminalHelper:) keyEquivalent:@""];
	[item setTarget:self];

	[helpMenu addItem:[NSMenuItem separatorItem]];

	item = [helpMenu addItemWithTitle:@"Visit Vico Website" action:@selector(visitWebsite:) keyEquivalent:@""];
	[item setTarget:self];

	[helpMenuItem setSubmenu:helpMenu];
	[mainMenu addItem:helpMenuItem];
	[NSApp setHelpMenu:helpMenu];

	[NSApp setMainMenu:mainMenu];
}

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification
{
	[self buildMainMenu];

	/* Cache the default IBeam cursor implementation. */
	[NSCursor defaultIBeamCursorImplementation];

	[Nu loadNuFile:@"vico"   fromBundleWithIdentifier:@"se.bzero.Vico" withContext:nil];
	[Nu loadNuFile:@"keys"   fromBundleWithIdentifier:@"se.bzero.Vico" withContext:nil];
	[Nu loadNuFile:@"ex"     fromBundleWithIdentifier:@"se.bzero.Vico" withContext:nil];
	[Nu loadNuFile:@"status" fromBundleWithIdentifier:@"se.bzero.Vico" withContext:nil];

	//[SFBCrashReporter checkForNewCrashes];

	_userDriver = [[SPUStandardUserDriver alloc] initWithHostBundle:[NSBundle mainBundle] delegate:nil];
	_updater = [[SPUUpdater alloc] initWithHostBundle:[NSBundle mainBundle]
	                                applicationBundle:[NSBundle mainBundle]
	                                       userDriver:_userDriver
	                                         delegate:nil];
	NSError *updaterError = nil;
	if (![_updater startUpdater:&updaterError]) {
		NSLog(@"Failed to start Sparkle updater: %@", updaterError);
	}
	[checkForUpdatesMenuItem setAction:@selector(checkForUpdates:)];
	[checkForUpdatesMenuItem setTarget:_updater];

#if defined(DEBUG_BUILD)
	[NSApp activateIgnoringOtherApps:YES];
#endif

	original_input_source = TISCopyCurrentKeyboardInputSource();
	DEBUG(@"remembering original input: %@",
	    TISGetInputSourceProperty(original_input_source, kTISPropertyLocalizedName));
	_recently_launched = YES;

	[[NSFileManager defaultManager] createDirectoryAtPath:[ViAppController supportDirectory]
				  withIntermediateDirectories:YES
						   attributes:nil
							error:nil];
	[[NSFileManager defaultManager] createDirectoryAtPath:[ViBundleStore bundlesDirectory]
				  withIntermediateDirectories:NO
						   attributes:nil
							error:nil];
	[[NSFileManager defaultManager] createDirectoryAtPath:[[ViAppController supportDirectory] stringByAppendingPathComponent:@"Themes"]
				  withIntermediateDirectories:NO
						   attributes:nil
							error:nil];

	NSUserDefaults *userDefs = [NSUserDefaults standardUserDefaults];

	/* initialize default defaults */
	[userDefs registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
	    [NSNumber numberWithInt:4], @"shiftwidth",
	    [NSNumber numberWithInt:8], @"tabstop",
	    [NSNumber numberWithBool:YES], @"autoindent",
	    [NSNumber numberWithBool:YES], @"smartindent",
	    [NSNumber numberWithBool:YES], @"smartpair",
	    [NSNumber numberWithBool:YES], @"ignorecase",
	    [NSNumber numberWithBool:NO], @"smartcase",
	    [NSNumber numberWithBool:YES], @"expandtab",
	    [NSNumber numberWithBool:YES], @"smarttab",
	    [NSNumber numberWithBool:YES], @"number",
	    [NSNumber numberWithBool:NO], @"relativenumber",
	    [NSNumber numberWithBool:YES], @"autocollapse",
	    [NSNumber numberWithBool:YES], @"hidetab",
	    [NSNumber numberWithBool:YES], @"searchincr",
	    [NSNumber numberWithBool:NO], @"showguide",
	    [NSNumber numberWithBool:YES], @"wrap",
	    [NSNumber numberWithBool:YES], @"autocomplete",
	    [NSNumber numberWithBool:YES], @"antialias",
	    [NSNumber numberWithBool:YES], @"prefertabs",
	    [NSNumber numberWithBool:NO], @"cursorline",
	    [NSNumber numberWithBool:NO], @"gdefault",
	    [NSNumber numberWithBool:YES], @"wrapscan",
	    [NSNumber numberWithBool:NO], @"clipboard",
	    [NSNumber numberWithBool:YES], @"matchparen",
	    [NSNumber numberWithBool:NO], @"flashparen",
	    [NSNumber numberWithBool:YES], @"linebreak",
	    [NSNumber numberWithInt:80], @"guidecolumn",
	    [NSNumber numberWithFloat:12.0], @"fontsize",
	    [NSNumber numberWithFloat:0.75], @"blinktime",
	    @"none", @"blinkmode",
	    @"Monaco", @"fontname",
	    @"vim", @"undostyle",
	    @"Sunset", @"theme",
	    @"(^\\.(?!(htaccess|(git|hg|cvs)ignore)$)|^(CVS|_darcs|\\.svn|\\.git)$|~$|\\.(bak|o|pyc|gz|tgz|zip|dmg|pkg)$)", @"skipPattern",
	    [NSNumber numberWithBool:NO], @"includedevelopmenu",
	    [NSArray arrayWithObjects:@"vicoapp", @"textmate", @"kswedberg", nil], @"bundleRepoUsers",
	    [NSNumber numberWithBool:YES], @"explorecaseignore",
	    [NSNumber numberWithBool:NO], @"exploresortfolders",
	    @"text.plain", @"defaultsyntax",
	    [NSDictionary dictionaryWithObjectsAndKeys:
		@"__MyCompanyName__", @"TM_ORGANIZATION_NAME",
		@"rTbgqR B=.,?_A_a Q=#/_s>|;", @"PARINIT",
		nil], @"environment",
	    nil]];

	/* Initialize languages and themes. */
	[ViBundleStore defaultStore];
	[ViThemeStore defaultStore];

	NSArray *opts = [NSArray arrayWithObjects:
	    @"theme", @"showguide", @"guidecolumn", @"undostyle", nil];
	for (NSString *opt in opts)
		[userDefs addObserver:self
			   forKeyPath:opt
			      options:NSKeyValueObservingOptionNew
			      context:NULL];

	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(newBundleLoaded:)
	                                             name:ViBundleStoreBundleLoadedNotification
	                                           object:nil];

	const NSStringEncoding *encoding = [NSString availableStringEncodings];
	NSMutableArray *array = [NSMutableArray array];
	NSMenuItem *item;
	while (*encoding) {
		NSString *title = [NSString localizedNameOfStringEncoding:*encoding];
		item = [[NSMenuItem alloc] initWithTitle:title
						  action:NSSelectorFromString(@"setEncoding:")
					   keyEquivalent:@""];
		[item setRepresentedObject:[NSNumber numberWithUnsignedLong:*encoding]];
		[array addObject:item];
		encoding++;
	}

	[[ViURLManager defaultManager] registerHandler:[[ViFileURLHandler alloc] init]];
	[[ViURLManager defaultManager] registerHandler:[[ViSFTPURLHandler alloc] init]];
	[[ViURLManager defaultManager] registerHandler:[[ViHTTPURLHandler alloc] init]];

	NSSortDescriptor *sdesc = [[NSSortDescriptor alloc] initWithKey:@"title"
	                                                       ascending:YES];
	[array sortUsingDescriptors:[NSArray arrayWithObject:sdesc]];
	for (item in array)
		[encodingMenu addItem:item];

	[self forceUpdateMenu:[NSApp mainMenu]];

	[TMFileURLProtocol registerProtocol];
	[TxmtURLProtocol registerProtocol];

	[self installXPCLaunchdPlistIfNeeded];
	_xpcListener = [[NSXPCListener alloc] initWithMachServiceName:@"se.bzero.vico.ipc"];
	[_xpcListener setDelegate:self];
	[_xpcListener resume];

	extern struct timeval launch_start;
	struct timeval launch_done, launch_diff;
	gettimeofday(&launch_done, NULL);
	timersub(&launch_done, &launch_start, &launch_diff);
	INFO(@"launched after %fs", launch_diff.tv_sec + (float)launch_diff.tv_usec / 1000000);

#ifdef TRIAL_VERSION
	NSAlert *alert = [[NSAlert alloc] init];
	int left = updateMeta();
	if (left <= 0) {
		[alert setMessageText:@"This trial version has expired."];
		[alert addButtonWithTitle:@"OK"];
		[alert setInformativeText:@"Evaluation is now limited to 15 minutes."];
		[alert runModal];
		[NSTimer scheduledTimerWithTimeInterval:15*60
						 target:self
					       selector:@selector(m:)
					       userInfo:nil
						repeats:NO];
	} else {
		[alert setMessageText:@"This is a trial version."];
		[alert addButtonWithTitle:@"Try Vico"];
		[alert addButtonWithTitle:@"Buy Vico"];
		[alert setInformativeText:[NSString stringWithFormat:@"Vico will expire after %i day%s of use.", left, left == 1 ? "" : "s"]];
		NSUInteger ret = [alert runModal];
		if (ret == NSAlertSecondButtonReturn)
			[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://itunes.com/mac/vico"]];
		mTimer = [NSTimer scheduledTimerWithTimeInterval:1*60
							  target:self
							selector:@selector(m:)
							userInfo:nil
							 repeats:YES];
	}
#endif

	/* Register default preference panes. */
	ViPreferencesController *prefs = [ViPreferencesController sharedPreferences];
	[prefs registerPane:[[ViPreferencePaneGeneral alloc] init]];
	[prefs registerPane:[[ViPreferencePaneEdit alloc] init]];
	[prefs registerPane:[[ViPreferencePaneTheme alloc] init]];
	[prefs registerPane:[[ViPreferencePaneBundles alloc] init]];
	[prefs registerPane:[[ViPreferencePaneAdvanced alloc] init]];

	[[NSNotificationCenter defaultCenter] addObserver:self
						 selector:@selector(beginTrackingMainMenu:)
						     name:NSMenuDidBeginTrackingNotification
						   object:[NSApp mainMenu]];
	[[NSNotificationCenter defaultCenter] addObserver:self
						 selector:@selector(endTrackingMainMenu:)
						     name:NSMenuDidEndTrackingNotification
						   object:[NSApp mainMenu]];

	NSWindow *dummyWindow = [[NSWindow alloc] initWithContentRect:NSZeroRect styleMask:0 backing:0 defer:YES];
	if ([dummyWindow respondsToSelector:@selector(toggleFullScreen:)]) {
		[viewMenu addItem:[NSMenuItem separatorItem]];
		NSMenuItem *item = [viewMenu addItemWithTitle:@"Enter Full Screen" action:@selector(toggleFullScreen:) keyEquivalent:@"f"];
		[item setKeyEquivalentModifierMask:NSEventModifierFlagCommand | NSEventModifierFlagControl];
	}

	NSString *siteFile = [[ViAppController supportDirectory] stringByAppendingPathComponent:@"site.nu"];
	NSString *siteScript = [NSString stringWithContentsOfFile:siteFile
							 encoding:NSUTF8StringEncoding
							    error:nil];
	if (siteScript) {
		NSError *error = nil;
		[self eval:siteScript error:&error];
		if (error)
			INFO(@"%@: %@", siteFile, [error localizedDescription]);
	}

	[[ViEventManager defaultManager] emit:ViEventDidFinishLaunching for:nil with:nil];
}

#ifdef TRIAL_VERSION
- (void)m:(NSTimer *)timer
{
	int left = updateMeta();
	if (left <= 0) {
		NSAlert *alert = [[NSAlert alloc] init];
		[alert setMessageText:@"This trial version has expired."];
		[alert addButtonWithTitle:@"Buy Vico"];
		[alert addButtonWithTitle:@"Quit"];
		NSUInteger ret = [alert runModal];
		if (ret == NSAlertFirstButtonReturn)
			[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://itunes.com/mac/vico"]];

		[NSApp terminate:nil];
		if (mTimer == nil)
			mTimer = [NSTimer scheduledTimerWithTimeInterval:1*60
								  target:self
								selector:@selector(m:)
								userInfo:nil
								 repeats:YES];
	}
}
#endif

- (void)observeValueForKeyPath:(NSString *)keyPath
		      ofObject:(id)object
			change:(NSDictionary *)change
		       context:(void *)context
{
	ViDocument *doc;

	if ([keyPath isEqualToString:@"theme"]) {
		for (doc in [[NSDocumentController sharedDocumentController] documents])
			if ([doc respondsToSelector:@selector(changeTheme:)])
				[doc changeTheme:[[ViThemeStore defaultStore] themeWithName:[change objectForKey:NSKeyValueChangeNewKey]]];
	} else if ([keyPath isEqualToString:@"showguide"] || [keyPath isEqualToString:@"guidecolumn"]) {
		for (doc in [[NSDocumentController sharedDocumentController] documents])
			if ([doc respondsToSelector:@selector(updatePageGuide)])
				[doc updatePageGuide];
	} else if ([keyPath isEqualToString:@"undostyle"]) {
		NSString *undostyle = [change objectForKey:NSKeyValueChangeNewKey];
		if (![undostyle isEqualToString:@"vim"] && ![undostyle isEqualToString:@"nvi"])
			[[NSUserDefaults standardUserDefaults] setObject:@"vim" forKey:@"undostyle"];
	}
}

- (void)applicationWillResignActive:(NSNotification *)aNotification
{
	ViWindowController *wincon = [ViWindowController currentWindowController];
	ViViewController *viewController = [wincon currentView];
	if ([viewController isKindOfClass:[ViDocumentView class]])
		[[(ViDocumentView *)viewController textView] rememberNormalModeInputSource];

		TISSelectInputSource(original_input_source);
	DEBUG(@"selecting original input: %@",
	    TISGetInputSourceProperty(original_input_source, kTISPropertyLocalizedName));
	[[ViEventManager defaultManager] emit:ViEventWillResignActive for:nil with:nil];
}

- (void)applicationWillBecomeActive:(NSNotification *)aNotification
{
	if (!_recently_launched) {
		original_input_source = TISCopyCurrentKeyboardInputSource();
		DEBUG(@"remembering original input: %@",
		    TISGetInputSourceProperty(original_input_source, kTISPropertyLocalizedName));
	}
	_recently_launched = NO;

	ViWindowController *wincon = [ViWindowController currentWindowController];
	ViViewController *viewController = [wincon currentView];
	if ([viewController isKindOfClass:[ViDocumentView class]]) {
		[[(ViDocumentView *)viewController textView] resetInputSource];
	}

	[[ViEventManager defaultManager] emit:ViEventDidBecomeActive for:nil with:nil];
}

#pragma mark -
#pragma mark Interface actions

- (IBAction)showPreferences:(id)sender
{
	[[ViPreferencesController sharedPreferences] show];
}

- (IBAction)showMarkInspector:(id)sender
{
	[[ViMarkInspector sharedInspector] show];
}

extern BOOL __makeNewWindowInsteadOfTab;

- (IBAction)newProject:(id)sender
{
	__makeNewWindowInsteadOfTab = YES;
	[[ViDocumentController sharedDocumentController] newDocument:sender];
}

- (IBAction)installTerminalHelper:(id)sender
{
	NSString *locBookName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleHelpBookName"];
	[[NSHelpManager sharedHelpManager] openHelpAnchor:@"terminalUsage" inBook:locBookName];
}

- (IBAction)visitWebsite:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://www.vicoapp.com/"]];
}

- (IBAction)editSiteScript:(id)sender
{
	NSURL *siteURL = [NSURL fileURLWithPath:[[ViAppController supportDirectory] stringByAppendingPathComponent:@"site.nu"]];
	[[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:siteURL
									       display:YES
								 completionHandler:^(NSDocument *doc, BOOL wasOpen, NSError *err) {}];
}

#pragma mark -
#pragma mark Script evaluation

- (id)eval:(NSString *)script
withParser:(NuParser *)parser
  bindings:(NSDictionary *)bindings
     error:(NSError **)outError
{
	if (parser == nil) {
		parser = [Nu sharedParser];
	}

	DEBUG(@"additional bindings: %@", bindings);
	for (NSString *key in [bindings allKeys]) {
		if ([key isKindOfClass:[NSString class]]) {
			[parser setValue:[bindings objectForKey:key] forKey:key];
		}
	}

	DEBUG(@"evaluating script: {{{ %@ }}}", script);

	id result = nil;
	@try {
		id code = [parser parse:script];
		if (code == nil) {
			if (outError) {
				*outError = [ViError errorWithFormat:@"parse failed"];
			}
			[parser reset];
			return nil;
		}
		if ([parser incomplete]) {
			if (outError) {
				*outError = [ViError errorWithFormat:@"incomplete input"];
			}
			[parser reset];
			return nil;
		}

		DEBUG(@"context: %@", [parser context]);
		result = [parser eval:code];
	}
	@catch (NSException *exception) {
		INFO(@"%@: %@", [exception name], [exception reason]);
		if (outError) {
			*outError = [ViError errorWithFormat:@"Got exception %@: %@", [exception name], [exception reason]];
		}
		return nil;
	}

	[parser reset];
	return result;
}

- (id)eval:(NSString *)script
     error:(NSError **)outError
{
	id ret = [self eval:script withParser:nil bindings:nil error:outError];
	return ret;
}

#pragma mark -
#pragma mark Shell commands (internal)

- (void)openURL:(NSString *)pathOrURL completion:(void (^)(NSError *error))completion
{
	[self openURLInternal:pathOrURL andWait:NO backChannel:nil completion:completion];
}

- (void)openURLInternal:(NSString *)pathOrURL andWait:(BOOL)waitFlag backChannel:(ViXPCBackChannelProxy *)backChannel completion:(void (^)(NSError *error))completion
{
	ViDocumentController *docCon = [ViDocumentController sharedDocumentController];

	NSURL *url;
	if ([pathOrURL isKindOfClass:[NSURL class]])
		url = (NSURL *)pathOrURL;
	else
		url = [[ViURLManager defaultManager] normalizeURL:[[NSURL URLWithString:pathOrURL] absoluteURL]];

	[docCon openDocumentWithContentsOfURL:url display:YES completionHandler:^(NSDocument *document, BOOL wasOpen, NSError *error) {
		ViDocument *doc = (ViDocument *)document;
		[self setCloseCallbackForDocument:doc backChannel:backChannel];
		if (doc)
			[NSApp activateIgnoringOtherApps:YES];
		if (completion) completion(error);
	}];
}

- (NSError *)newDocumentWithData:(NSData *)data
{
	return [self newDocumentWithDataInternal:data andWait:NO backChannel:nil];
}

- (NSError *)newDocumentWithDataInternal:(NSData *)data andWait:(BOOL)waitFlag backChannel:(ViXPCBackChannelProxy *)backChannel
{
	NSError *error = nil;

	ViDocumentController *docCon = [ViDocumentController sharedDocumentController];

	[docCon newDocument:nil];
	ViWindowController *winCon = [ViWindowController currentWindowController];
	ViDocument *doc = [winCon currentDocument];
	[doc setData:data];

	[self setCloseCallbackForDocument:doc backChannel:backChannel];

	if (doc)
		[NSApp activateIgnoringOtherApps:YES];

	return error;
}

- (void)setCloseCallbackForDocument:(ViDocument *)document
                        backChannel:(ViXPCBackChannelProxy *)backChannel
{
	if ([document respondsToSelector:@selector(setCloseCallback:)] && backChannel) {
		[document setCloseCallback:^(int code) {
			@try {
				[backChannel exitWithError:code];
			}
			@catch (NSException *exception) {
				INFO(@"failed to notify vicotool: %@", exception);
			}
		}];
	}
}

#pragma mark XPC Listener Delegate

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection
{
	newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(ViShellCommandXPCProtocol)];
	newConnection.exportedObject = self;
	newConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(ViShellThingXPCProtocol)];
	[newConnection resume];
	return YES;
}

#pragma mark ViShellCommandXPCProtocol

- (void)pingWithReply:(void (^)(void))reply
{
	reply();
}

- (void)evalScript:(NSString *)script
 additionalBindings:(NSDictionary *)bindings
          withReply:(void (^)(NSString *result, NSString *errorString))reply
{
	dispatch_async(dispatch_get_main_queue(), ^{
		NuParser *parser = [Nu sharedParser];

		NSXPCConnection *conn = [NSXPCConnection currentConnection];
		if (conn) {
			id<ViShellThingXPCProtocol> xpcProxy = [conn remoteObjectProxy];
			ViXPCBackChannelProxy *backChannel = [[ViXPCBackChannelProxy alloc] initWithXPCProxy:xpcProxy];
			[parser setValue:backChannel forKey:@"shellCommand"];
		}

		NSError *error = nil;
		id result = [self eval:script withParser:parser bindings:bindings error:&error];
		NSString *errorString = error ? [error localizedDescription] : nil;

		NSString *resultJSON = nil;
		if (result != nil && ![result isKindOfClass:[NSNull class]]) {
			NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
			if (data)
				resultJSON = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
		}

		reply(resultJSON, errorString);
	});
}

- (void)openURL:(NSString *)pathOrURL
        andWait:(BOOL)waitFlag
      withReply:(void (^)(NSString *errorDescription))reply
{
	dispatch_async(dispatch_get_main_queue(), ^{
		ViXPCBackChannelProxy *backChannel = nil;
		if (waitFlag) {
			NSXPCConnection *conn = [NSXPCConnection currentConnection];
			if (conn) {
				id<ViShellThingXPCProtocol> xpcProxy = [conn remoteObjectProxy];
				backChannel = [[ViXPCBackChannelProxy alloc] initWithXPCProxy:xpcProxy];
			}
		}

		[self openURLInternal:pathOrURL andWait:waitFlag backChannel:backChannel completion:^(NSError *error) {
			reply(error ? [error localizedDescription] : nil);
		}];
	});
}

- (void)setStartupBasePath:(NSString *)basePath
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[[ViWindowController currentWindowController] setBaseURL:[NSURL fileURLWithPath:basePath]];
	});
}

- (void)newDocumentWithData:(NSData *)data
                    andWait:(BOOL)waitFlag
                  withReply:(void (^)(NSString *errorDescription))reply
{
	dispatch_async(dispatch_get_main_queue(), ^{
		ViXPCBackChannelProxy *backChannel = nil;
		if (waitFlag) {
			NSXPCConnection *conn = [NSXPCConnection currentConnection];
			if (conn) {
				id<ViShellThingXPCProtocol> xpcProxy = [conn remoteObjectProxy];
				backChannel = [[ViXPCBackChannelProxy alloc] initWithXPCProxy:xpcProxy];
			}
		}

		NSError *error = [self newDocumentWithDataInternal:data andWait:waitFlag backChannel:backChannel];
		reply(error ? [error localizedDescription] : nil);
	});
}

- (void)newProject
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[self newProject:nil];
	});
}

#pragma mark XPC Launchd Plist

- (void)installXPCLaunchdPlistIfNeeded
{
	NSString *launchAgentsDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents"];
	NSString *plistPath = [launchAgentsDir stringByAppendingPathComponent:@"se.bzero.vico.ipc.plist"];
	NSFileManager *fm = [NSFileManager defaultManager];

	if ([fm fileExistsAtPath:plistPath])
		return;

	[fm createDirectoryAtPath:launchAgentsDir withIntermediateDirectories:YES attributes:nil error:nil];

	NSDictionary *plist = @{
		@"Label": @"se.bzero.vico.ipc",
		@"MachServices": @{
			@"se.bzero.vico.ipc": @YES,
		},
	};

	[plist writeToURL:[NSURL fileURLWithPath:plistPath] error:nil];

	NSTask *task = [[NSTask alloc] init];
	[task setExecutableURL:[NSURL fileURLWithPath:@"/bin/launchctl"]];
	[task setArguments:@[@"bootstrap", [NSString stringWithFormat:@"gui/%u", (unsigned int)getuid()], plistPath]];
	[task setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
	[task setStandardError:[NSFileHandle fileHandleWithNullDevice]];
	[task launchAndReturnError:nil];
	[task waitUntilExit];
}

#pragma mark -
#pragma mark Updating normal mode menu items

- (void)beginTrackingMainMenu:(NSNotification *)notification
{
	_menuTrackedKeyWindow = [NSApp keyWindow];
	_trackingMainMenu = YES;
}

- (void)endTrackingMainMenu:(NSNotification *)notification
{
	_menuTrackedKeyWindow = nil;
	_trackingMainMenu = NO;
}

- (NSWindow *)keyWindowBeforeMainMenuTracking
{
	return _menuTrackedKeyWindow ?: [NSApp keyWindow];
}

- (void)menuNeedsUpdate:(NSMenu *)menu
{
	NSWindow *keyWindow = [self keyWindowBeforeMainMenuTracking];
	ViWindowController *windowController = [keyWindow windowController];
	BOOL isDocWindow = [windowController isKindOfClass:[ViWindowController class]];

	/*
	 * Revert cmd-w to its original behaviour for non-document windows.
	 */
	if (isDocWindow) {
		[closeWindowMenuItem setKeyEquivalent:@"W"];
		[closeTabMenuItem setKeyEquivalent:@"w"];
		[closeDocumentMenuItem setKeyEquivalent:@"w"];
	} else {
		[closeWindowMenuItem setKeyEquivalent:@"w"];
		[closeTabMenuItem setKeyEquivalent:@""];
		[closeDocumentMenuItem setKeyEquivalent:@""];
	}

	/*
	 * Insert the current document in the title for "Close Document".
	 */
	ViViewController *viewController = [[ViWindowController currentWindowController] currentView];
	if (viewController == nil || !isDocWindow)
		[closeDocumentMenuItem setTitle:@"Close Document"];
	else
		[closeDocumentMenuItem setTitle:[NSString stringWithFormat:@"Close \"%@\"", [viewController title]]];

	/*
	 * If we're not tracking the main menu, but got triggered by a
	 * key event, don't update displayed menu items.
	 */
	if (!_trackingMainMenu)
		return;

	/* Do we have a selection? */
	BOOL hasSelection = NO;
	NSWindow *window = [[NSApplication sharedApplication] mainWindow];
	NSResponder *target = [window firstResponder];
	if ([target respondsToSelector:@selector(selectedRange)] &&
	    [(NSText *)target selectedRange].length > 0)
		hasSelection = YES;

	for (NSMenuItem *item in [menu itemArray]) {
		if (item == closeTabMenuItem) {
			if (isDocWindow)
				[item setKeyEquivalent:@"w"];
			else
				[item setKeyEquivalent:@""];
			continue;
		} else if (item == showFileExplorerMenuItem) {
			if (isDocWindow && [[windowController explorer] explorerIsOpen])
				[item setTitle:@"Hide File Explorer"];
			else
				[item setTitle:@"Show File Explorer"];
		} else if (item == showSymbolListMenuItem) {
			if (isDocWindow && [[windowController symbolController] symbolListIsOpen])
				[item setTitle:@"Hide Symbol List"];
			else
				[item setTitle:@"Show Symbol List"];
		}
	}

	[menu updateNormalModeMenuItemsWithSelection:hasSelection];
}

- (void)forceUpdateMenu:(NSMenu *)menu
{
	_trackingMainMenu = YES;

	[self menuNeedsUpdate:menu];

	for (NSMenuItem *item in [menu itemArray]) {
		NSMenu *submenu = [item submenu];
		if (submenu)
			[self forceUpdateMenu:submenu];
	}

	_trackingMainMenu = NO;
}

#pragma mark -
#pragma mark Input of scripted ex commands

- (BOOL)ex_cancel:(ViCommand *)command
{
	if (_busy)
		[NSApp stopModalWithCode:2];
	return YES;
}

- (BOOL)ex_execute:(ViCommand *)command
{
	_exString = [[[_fieldEditor textStorage] string] copy];
	if (_busy)
		[NSApp stopModalWithCode:0];
	_busy = NO;
	return YES;
}

- (NSString *)getExStringForCommand:(ViCommand *)command prefix:(NSString *)prefix
{
	ViMacro *macro = command.macro;

	if (_busy) {
		INFO(@"%s", "can't handle nested ex commands!");
		return nil;
	}

	_busy = YES;
	_exString = nil;

	if (macro) {
		NSInteger keyCode;
		if (_fieldEditor == nil) {
			_fieldEditorStorage = [[ViTextStorage alloc] init];
			_fieldEditor = [ViTextView makeFieldEditorWithTextStorage:_fieldEditorStorage];
		}
		[_fieldEditor setInsertMode:nil];
		[_fieldEditor setCaret:0];
		[_fieldEditor setString:prefix ?: @""];
		[_fieldEditor setDelegate:self];
		while (_busy && (keyCode = [macro pop]) != -1)
			[_fieldEditor.keyManager handleKey:keyCode];
	}

	if (_busy) {
		_busy = NO;
		return nil;
	}

	return _exString;
}

- (NSString *)getExStringForCommand:(ViCommand *)command
{
	return [self getExStringForCommand:command prefix:nil];
}

@end

