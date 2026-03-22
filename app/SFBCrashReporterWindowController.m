/*
 *  Copyright (C) 2009, 2010 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "SFBCrashReporterWindowController.h"
#import "SFBSystemInformation.h"
#import "GenerateFormData.h"

#import <AddressBook/AddressBook.h>

@interface SFBCrashReporterWindowController (Callbacks)
- (void) showSubmissionSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
@end

@interface SFBCrashReporterWindowController (Private)
- (NSString *) applicationName;
- (void) sendCrashReport;
- (void) showSubmissionSucceededSheet;
- (void) showSubmissionFailedSheet:(NSError *)error;
@end

@implementation SFBCrashReporterWindowController

@synthesize emailAddress = _emailAddress;
@synthesize crashLogPath = _crashLogPath;
@synthesize submissionURL = _submissionURL;

+ (void) initialize
{
	// Register reasonable defaults for most preferences
	NSMutableDictionary *defaultsDictionary = [NSMutableDictionary dictionary];
	
	[defaultsDictionary setObject:[NSNumber numberWithBool:YES] forKey:@"SFBCrashReporterIncludeAnonymousSystemInformation"];
	[defaultsDictionary setObject:[NSNumber numberWithBool:NO] forKey:@"SFBCrashReporterIncludeEmailAddress"];
		
	[[NSUserDefaults standardUserDefaults] registerDefaults:defaultsDictionary];
}

+ (void) showWindowForCrashLogPath:(NSString *)crashLogPath submissionURL:(NSURL *)submissionURL
{
	NSParameterAssert(nil != crashLogPath);
	NSParameterAssert(nil != submissionURL);

	SFBCrashReporterWindowController *windowController = [[self alloc] init];
	
	windowController.crashLogPath = crashLogPath;
	windowController.submissionURL = submissionURL;
	
	[[windowController window] center];
	[windowController showWindow:self];

	windowController = nil;
}

// Should not be called directly by anyone except this class
- (id) init
{
	if ((self = [super initWithWindow:nil]) != nil) {
		[self buildWindow];
	}
	return self;
}

- (void) buildWindow
{
	// Window: 453×365, titled, autosave "SFBCrashReporterWindow"
	NSWindow *win = [[NSWindow alloc] initWithContentRect:NSMakeRect(196, 145, 453, 365)
						    styleMask:NSWindowStyleMaskTitled
						      backing:NSBackingStoreBuffered
							defer:YES];
	[win setFrameAutosaveName:@"SFBCrashReporterWindow"];
	[win setAutorecalculatesKeyViewLoop:NO];
	[win setAnimationBehavior:NSWindowAnimationBehaviorDefault];
	[win setDelegate:self];

	NSView *contentView = [win contentView];

	// App icon image: {20, 281, 64, 64}
	NSImageView *iconView = [[NSImageView alloc] initWithFrame:NSMakeRect(20, 281, 64, 64)];
	[iconView setImage:[NSApp applicationIconImage]];
	[iconView setImageScaling:NSImageScaleProportionallyDown];
	[iconView setEditable:NO];
	[iconView setAutoresizingMask:(NSViewMaxXMargin | NSViewMinYMargin)];
	[contentView addSubview:iconView];

	// Crash message label: {89, 294, 344, 51} — bold system font
	// Uses displayPatternValue1 binding to show app name
	NSTextField *crashMessageLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(89, 294, 344, 51)];
	[crashMessageLabel setStringValue:@""];
	[crashMessageLabel setEditable:NO];
	[crashMessageLabel setBordered:NO];
	[crashMessageLabel setSelectable:NO];
	[crashMessageLabel setDrawsBackground:NO];
	[crashMessageLabel setFont:[NSFont boldSystemFontOfSize:13.0]];
	[crashMessageLabel setTextColor:[NSColor controlTextColor]];
	[crashMessageLabel setAutoresizingMask:(NSViewMaxXMargin | NSViewMinYMargin)];
	[crashMessageLabel bind:@"displayPatternValue1"
		       toObject:self
		    withKeyPath:@"applicationName"
			options:@{@"NSDisplayPattern": @"%{value1}@ crashed the last time it was run.  Would you like to submit a crash report to the developers?"}];
	[contentView addSubview:crashMessageLabel];

	// Progress indicator: {414, 256, 16, 16} — small spinning, hidden when stopped
	_progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(414, 256, 16, 16)];
	[_progressIndicator setStyle:NSProgressIndicatorStyleSpinning];
	[_progressIndicator setControlSize:NSControlSizeSmall];
	[_progressIndicator setIndeterminate:YES];
	[_progressIndicator setDisplayedWhenStopped:NO];
	[_progressIndicator setAutoresizingMask:(NSViewMaxXMargin | NSViewMinYMargin)];
	[contentView addSubview:_progressIndicator];

	// "What were you doing..." label: {17, 256, 281, 17}
	NSTextField *questionLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(17, 256, 281, 17)];
	[questionLabel setStringValue:@"What were you doing when the application crashed?"];
	[questionLabel setEditable:NO];
	[questionLabel setBordered:NO];
	[questionLabel setSelectable:NO];
	[questionLabel setDrawsBackground:NO];
	[questionLabel setFont:[NSFont systemFontOfSize:11.0]];
	[questionLabel setTextColor:[NSColor controlTextColor]];
	[contentView addSubview:questionLabel];

	// ScrollView with comments TextView: {20, 130, 413, 118}
	NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 130, 413, 118)];
	[scrollView setHasVerticalScroller:YES];
	[scrollView setHasHorizontalScroller:NO];
	[scrollView setBorderType:NSBezelBorder];

	NSSize contentSize = [scrollView contentSize];
	_commentsTextView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
	[_commentsTextView setMinSize:NSMakeSize(contentSize.width, contentSize.height)];
	[_commentsTextView setMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
	[_commentsTextView setVerticallyResizable:YES];
	[_commentsTextView setHorizontallyResizable:NO];
	[_commentsTextView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[[_commentsTextView textContainer] setContainerSize:NSMakeSize(contentSize.width, FLT_MAX)];
	[[_commentsTextView textContainer] setWidthTracksTextView:YES];
	[_commentsTextView setRichText:NO];
	[_commentsTextView setImportsGraphics:NO];
	[_commentsTextView setContinuousSpellCheckingEnabled:YES];
	[_commentsTextView setUsesRuler:YES];
	[_commentsTextView setUsesFontPanel:YES];
	[_commentsTextView setSmartInsertDeleteEnabled:YES];
	[_commentsTextView setDelegate:self];

	// Set default placeholder text
	NSFont *defaultFont = [NSFont fontWithName:@"LucidaGrande" size:10.0];
	if (!defaultFont)
		defaultFont = [NSFont systemFontOfSize:10.0];
	NSDictionary *attrs = @{NSFontAttributeName: defaultFont};
	NSAttributedString *defaultText = [[NSAttributedString alloc] initWithString:@"Please enter a brief description of the actions which caused the crash." attributes:attrs];
	[[_commentsTextView textStorage] setAttributedString:defaultText];

	[scrollView setDocumentView:_commentsTextView];
	[contentView addSubview:scrollView];

	// Checkbox: "Include anonymous system information" {18, 106, 272, 18}
	NSButton *sysInfoCheckbox = [NSButton checkboxWithTitle:@"Include anonymous system information" target:nil action:nil];
	[sysInfoCheckbox setFrame:NSMakeRect(18, 106, 272, 18)];
	[sysInfoCheckbox bind:@"value"
		     toObject:[NSUserDefaultsController sharedUserDefaultsController]
		  withKeyPath:@"values.SFBCrashReporterIncludeAnonymousSystemInformation"
		      options:nil];
	[contentView addSubview:sysInfoCheckbox];

	// Checkbox: "Include my e-mail address" {18, 86, 190, 18}
	NSButton *emailCheckbox = [NSButton checkboxWithTitle:@"Include my e-mail address" target:nil action:nil];
	[emailCheckbox setFrame:NSMakeRect(18, 86, 190, 18)];
	[emailCheckbox bind:@"value"
		   toObject:[NSUserDefaultsController sharedUserDefaultsController]
		withKeyPath:@"values.SFBCrashReporterIncludeEmailAddress"
		    options:nil];
	[contentView addSubview:emailCheckbox];

	// "E-mail address:" label: {29, 60, 103, 17}
	NSTextField *emailLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(29, 60, 103, 17)];
	[emailLabel setStringValue:@"E-mail address:"];
	[emailLabel setEditable:NO];
	[emailLabel setBordered:NO];
	[emailLabel setSelectable:NO];
	[emailLabel setDrawsBackground:NO];
	[emailLabel setFont:[NSFont systemFontOfSize:13.0]];
	[emailLabel setTextColor:[NSColor controlTextColor]];
	[emailLabel setAutoresizingMask:(NSViewMaxXMargin | NSViewMinYMargin)];
	[contentView addSubview:emailLabel];

	// E-mail text field: {137, 58, 211, 22} — editable, bindings
	NSTextField *emailField = [[NSTextField alloc] initWithFrame:NSMakeRect(137, 58, 211, 22)];
	[emailField setEditable:YES];
	[emailField setSelectable:YES];
	[emailField setBordered:YES];
	[emailField setBezeled:YES];
	[emailField setBezelStyle:NSTextFieldSquareBezel];
	[emailField setDrawsBackground:YES];
	[emailField setFont:[NSFont systemFontOfSize:13.0]];
	[emailField setAutoresizingMask:(NSViewMaxXMargin | NSViewMinYMargin)];
	// Bind value to File's Owner emailAddress
	[emailField bind:@"value"
		toObject:self
	     withKeyPath:@"emailAddress"
		 options:nil];
	// Bind enabled to NSUserDefaults SFBCrashReporterIncludeEmailAddress
	[emailField bind:@"enabled"
		toObject:[NSUserDefaultsController sharedUserDefaultsController]
	     withKeyPath:@"values.SFBCrashReporterIncludeEmailAddress"
		 options:nil];
	[contentView addSubview:emailField];

	// Report button: {343, 12, 96, 32} — keyEquivalent: Return
	_reportButton = [[NSButton alloc] initWithFrame:NSMakeRect(343, 12, 96, 32)];
	[_reportButton setTitle:@"Report"];
	[_reportButton setBezelStyle:NSBezelStyleRounded];
	[_reportButton setKeyEquivalent:@"\r"];
	[_reportButton setTarget:self];
	[_reportButton setAction:@selector(sendReport:)];
	[_reportButton setAutoresizingMask:(NSViewMaxXMargin | NSViewMinYMargin)];
	[contentView addSubview:_reportButton];

	// Ignore button: {247, 12, 96, 32} — keyEquivalent: Escape
	_ignoreButton = [[NSButton alloc] initWithFrame:NSMakeRect(247, 12, 96, 32)];
	[_ignoreButton setTitle:@"Ignore"];
	[_ignoreButton setBezelStyle:NSBezelStyleRounded];
	[_ignoreButton setKeyEquivalent:@"\033"];
	[_ignoreButton setTarget:self];
	[_ignoreButton setAction:@selector(ignoreReport:)];
	[_ignoreButton setAutoresizingMask:(NSViewMaxXMargin | NSViewMinYMargin)];
	[contentView addSubview:_ignoreButton];

	// Discard button: {14, 12, 96, 32} — keyEquivalent: Cmd+D
	_discardButton = [[NSButton alloc] initWithFrame:NSMakeRect(14, 12, 96, 32)];
	[_discardButton setTitle:@"Discard"];
	[_discardButton setBezelStyle:NSBezelStyleRounded];
	[_discardButton setKeyEquivalent:@"d"];
	[_discardButton setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
	[_discardButton setTarget:self];
	[_discardButton setAction:@selector(discardReport:)];
	[_discardButton setAutoresizingMask:(NSViewMaxXMargin | NSViewMinYMargin)];
	[contentView addSubview:_discardButton];

	[self setWindow:win];

	// --- windowDidLoad logic (won't be called automatically without nib) ---

	// Set the window's title
	NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
	NSString *appShortVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];

	NSString *windowTitle;
	if (!appShortVersion)
		windowTitle = [NSString stringWithFormat:NSLocalizedString(@"Crash Reporter: %@", @""), appName];
	else
		windowTitle = [NSString stringWithFormat:NSLocalizedString(@"Crash Reporter: %@ (%@)", @""), appName, appShortVersion];

	[win setTitle:windowTitle];

	// Populate the e-mail field with the user's primary e-mail address
	ABMultiValue *emailAddresses = [[[ABAddressBook sharedAddressBook] me] valueForProperty:kABEmailProperty];
	self.emailAddress = (NSString *)[emailAddresses valueForIdentifier:[emailAddresses primaryIdentifier]];

	// Set the font for the comments
	[_commentsTextView setTypingAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:10.0]}];

	// Select the comments text
	[_commentsTextView setSelectedRange:NSMakeRange(0, NSUIntegerMax)];
}

- (void) dealloc
{
	_emailAddress = nil;
	_crashLogPath = nil;
	_submissionURL = nil;

}

#pragma mark Action Methods

// Send the report off
- (IBAction) sendReport:(id)sender
{

#pragma unused(sender)

	[self sendCrashReport];
}

// Don't do anything except dismiss our window
- (IBAction) ignoreReport:(id)sender
{

#pragma unused(sender)

	[[self window] orderOut:self];
}

// Move the crash log to the trash since the user isn't interested in submitting it
- (IBAction) discardReport:(id)sender
{

#pragma unused(sender)

	NSError *error;
	[[NSFileManager defaultManager] trashItemAtURL:[NSURL fileURLWithPath:self.crashLogPath] resultingItemURL:nil error:&error];
	if (error)
		NSLog(@"SFBCrashReporter: Unable to move %@ to trash: %@", self.crashLogPath, error);

	[[self window] orderOut:self];
}

@end

@implementation SFBCrashReporterWindowController (Callbacks)

- (void) showSubmissionSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{

#pragma unused(sheet)
#pragma unused(returnCode)
#pragma unused(contextInfo)

	// Whether success or failure, all that remains is to close the window
	[[self window] orderOut:self];
}

@end

@implementation SFBCrashReporterWindowController (Private)

// Convenience method for bindings
- (NSString *) applicationName
{
	return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
}

// Do the actual work of building the HTTP POST and submitting it
- (void) sendCrashReport
{
	NSMutableDictionary *formValues = [NSMutableDictionary dictionary];
	
	// Append system information, if specified
	if([[NSUserDefaults standardUserDefaults] boolForKey:@"SFBCrashReporterIncludeAnonymousSystemInformation"]) {
		SFBSystemInformation *systemInformation = [[SFBSystemInformation alloc] init];
		
		id value = nil;
		
		if((value = [systemInformation machine]))
			[formValues setObject:value forKey:@"machine"];
		if((value = [systemInformation model]))
			[formValues setObject:value forKey:@"model"];
		if((value = [systemInformation physicalMemory]))
			[formValues setObject:value forKey:@"physicalMemory"];
		if((value = [systemInformation numberOfCPUs]))
			[formValues setObject:value forKey:@"numberOfCPUs"];
		if((value = [systemInformation busFrequency]))
			[formValues setObject:value forKey:@"busFrequency"];
		if((value = [systemInformation CPUFrequency]))
			[formValues setObject:value forKey:@"CPUFrequency"];
		if((value = [systemInformation CPUFamily]))
			[formValues setObject:value forKey:@"CPUFamily"];
		if((value = [systemInformation modelName]))
			[formValues setObject:value forKey:@"modelName"];
		if((value = [systemInformation CPUFamilyName]))
			[formValues setObject:value forKey:@"CPUFamilyName"];
		if((value = [systemInformation systemVersion]))
			[formValues setObject:value forKey:@"systemVersion"];
		if((value = [systemInformation systemBuildVersion]))
			[formValues setObject:value forKey:@"systemBuildVersion"];

		[formValues setObject:[NSNumber numberWithBool:YES] forKey:@"systemInformationIncluded"];

		systemInformation = nil;
	}
	else
		[formValues setObject:[NSNumber numberWithBool:NO] forKey:@"systemInformationIncluded"];
	
	// Include email address, if permitted
	if([[NSUserDefaults standardUserDefaults] boolForKey:@"SFBCrashReporterIncludeEmailAddress"] && self.emailAddress)
		[formValues setObject:self.emailAddress forKey:@"emailAddress"];
	
	// Optional comments
	NSRange fullRange = NSMakeRange(0, [[_commentsTextView textStorage] length]);
	NSAttributedString *attributedComments = [_commentsTextView attributedSubstringForProposedRange:fullRange actualRange:NULL];
	if([[attributedComments string] length])
		[formValues setObject:[attributedComments string] forKey:@"comments"];
	
	// The most important item of all
	[formValues setObject:[NSURL fileURLWithPath:self.crashLogPath] forKey:@"crashLog"];

	// Add the application information
	NSString *applicationName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
	if(applicationName)
		[formValues setObject:applicationName forKey:@"applicationName"];
	
	NSString *applicationIdentifier = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifier"];
	if(applicationIdentifier)
		[formValues setObject:applicationIdentifier forKey:@"applicationIdentifier"];

	NSString *applicationVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
	if(applicationVersion)
		[formValues setObject:applicationVersion forKey:@"applicationVersion"];

	NSString *applicationShortVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
	if(applicationShortVersion)
		[formValues setObject:applicationShortVersion forKey:@"applicationShortVersion"];
	
	// Create a date formatter
	[NSDateFormatter setDefaultFormatterBehavior:NSDateFormatterBehavior10_4];
	NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
	
	// Determine which locale the developer would like dates/times in
	NSString *localeName = [[NSUserDefaults standardUserDefaults] stringForKey:@"SFBCrashReporterPreferredReportingLocale"];
	if(!localeName) {
		localeName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SFBCrashReporterPreferredReportingLocale"];
		// US English is the default
		if(!localeName)
			localeName = @"en_US";
	}
	
	NSLocale *localeToUse = [[NSLocale alloc] initWithLocaleIdentifier:localeName];
	[dateFormatter setLocale:localeToUse];

	[dateFormatter setDateStyle:NSDateFormatterMediumStyle];
	[dateFormatter setTimeStyle:NSDateFormatterMediumStyle];
	
	// Include the date and time
	[formValues setObject:[dateFormatter stringFromDate:[NSDate date]] forKey:@"date"];
		
	localeToUse = nil;
	dateFormatter = nil;
	
	// Generate the form data
	NSString *boundary = @"0xKhTmLbOuNdArY";
	NSData *formData = GenerateFormData(formValues, boundary);
	
	// Set up the HTTP request
	NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:self.submissionURL];
	
	[urlRequest setHTTPMethod:@"POST"];

	NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
	[urlRequest setValue:contentType forHTTPHeaderField:@"Content-Type"];
	
	[urlRequest setValue:@"SFBCrashReporter" forHTTPHeaderField:@"User-Agent"];
	[urlRequest setValue:[NSString stringWithFormat:@"%lu", [formData length]] forHTTPHeaderField:@"Content-Length"];

	[urlRequest setHTTPBody:formData];
	
	[_progressIndicator startAnimation:self];

	[_reportButton setEnabled:NO];
	[_ignoreButton setEnabled:NO];
	[_discardButton setEnabled:NO];
	
	// Submit the URL request
	[[[NSURLSession sharedSession] dataTaskWithRequest:urlRequest
	                               completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			if (error) {
				[self showSubmissionFailedSheet:error];
				return;
			}
			NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
			if ([responseString isEqualToString:@"ok"]) {
				NSFileManager *fileManager = [[NSFileManager alloc] init];
				NSDictionary *fileAttributes = [fileManager attributesOfItemAtPath:[self.crashLogPath stringByResolvingSymlinksInPath] error:nil];
				[[NSUserDefaults standardUserDefaults] setObject:[fileAttributes fileModificationDate] forKey:@"SFBCrashReporterLastCrashReportDate"];
				NSError *removeError = nil;
				if (![fileManager removeItemAtPath:self.crashLogPath error:&removeError])
					NSLog(@"SFBCrashReporter error: Unable to delete the submitted crash log (%@): %@", [self.crashLogPath lastPathComponent], [removeError localizedDescription]);
				[self showSubmissionSucceededSheet];
			} else {
				NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"Unrecognized response from the server", @""), NSLocalizedDescriptionKey, nil];
				[self showSubmissionFailedSheet:[NSError errorWithDomain:NSPOSIXErrorDomain code:EPROTO userInfo:userInfo]];
			}
		});
	}] resume];
}

- (void) showSubmissionSucceededSheet
{
	[_progressIndicator stopAnimation:self];

	NSAlert *alert = [[NSAlert alloc] init];
	alert.messageText = NSLocalizedString(@"The crash report was successfully submitted.", @"");
	alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"Thank you for taking the time to help improve %@!", @""), [self applicationName]];
	[alert addButtonWithTitle:NSLocalizedString(@"OK", @"")];
	[alert beginSheetModalForWindow:[self window] completionHandler:^(NSModalResponse returnCode) {
		[self showSubmissionSheetDidEnd:nil returnCode:(int)returnCode contextInfo:NULL];
	}];
}

- (void) showSubmissionFailedSheet:(NSError *)error
{
	NSParameterAssert(nil != error);

	[_progressIndicator stopAnimation:self];

	NSAlert *alert = [[NSAlert alloc] init];
	alert.messageText = NSLocalizedString(@"An error occurred while submitting the crash report.", @"");
	alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"The error was: %@", @""), [error localizedDescription]];
	[alert addButtonWithTitle:NSLocalizedString(@"OK", @"")];
	[alert beginSheetModalForWindow:[self window] completionHandler:^(NSModalResponse returnCode) {
		[self showSubmissionSheetDidEnd:nil returnCode:(int)returnCode contextInfo:NULL];
	}];
}

#pragma mark NSTextView delegate methods

- (BOOL) textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector;
{
    if(commandSelector == @selector(insertTab:)) {
        [[textView window] selectNextKeyView:self];
        return YES;
    }
	else if(commandSelector == @selector(insertBacktab:)) {
        [[textView window] selectPreviousKeyView:self];
        return YES;
    }

    return NO;
}


@end
