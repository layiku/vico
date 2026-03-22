# Changelog

All changes from the Vico modernization project, organized by phase.

---

## Phase 1 — Build Compatibility Fixes

Restored buildability on modern Xcode 16+ / macOS 13+.

### Changed
- Raised deployment target from macOS 10.7/10.8 to **macOS 13.0** across all targets (`vico.xcodeproj/project.pbxproj`, Sparkle xcconfig files)
- Upgraded all XIB files from old archive format (v7.10) to modern document format (v3.0) with deployment version 1300 — `sparkle/SUStatus.xib`, `app/en.lproj/MainMenu.xib`, `app/en.lproj/CommandOutputWindow.xib`, `app/en.lproj/SFBCrashReporterWindow.xib`, 79 Sparkle localized XIBs
- Replaced OpenSSL (`-lcrypto`) with CommonCrypto for MD5 hashing in `ViAppController.m` — no external dependency needed
- Replaced `ffi_prep_closure` + `mmap`/`mprotect` with `ffi_closure_alloc` + `ffi_prep_closure_loc` in `Nu.m` — critical fix for Apple Silicon W^X memory protection
- Changed Sparkle `ARCHS = ppc i386 x86_64` to `ARCHS = $(ARCHS_STANDARD)` (arm64 + x86_64)
- Added missing source files (`SUBinaryDeltaApply.m`, `SUBinaryDeltaCommon.m`) to BinaryDelta target

### Removed
- `-Werror` from Sparkle's `WARNING_CFLAGS` (replaced with `-Wno-deprecated-declarations`)
- CPU family constants (`CPUFAMILY_INTEL_6_14`, `CPUFAMILY_INTEL_6_15`) from `SFBSystemInformation.m`
- `-lresolv` from all targets (unused)
- `_DARWIN_NO_64_BIT_INODE` from `SUBinaryDeltaTool.m`
- `NSAppKitVersionNumber10_4/10_5/10_6` macro shims from `Sparkle.pch`
- Duplicate output path from BinaryDelta "Fix Install Name" script phase

### Files
`vico.xcodeproj/project.pbxproj`, `sparkle/Configurations/ConfigCommon.xcconfig`, `sparkle/Configurations/ConfigBinaryDelta.xcconfig`, `sparkle/Sparkle.pch`, `sparkle/SUBinaryDeltaTool.m`, `sparkle/Sparkle.xcodeproj/project.pbxproj`, `sparkle/SUStatus.xib`, 79 Sparkle localized XIBs, `app/en.lproj/MainMenu.xib`, `app/en.lproj/CommandOutputWindow.xib`, `app/en.lproj/SFBCrashReporterWindow.xib`, `app/SFBSystemInformation.m`, `app/ViAppController.m`

---

## Phase 2 — Deprecation Warning Fixes

Eliminated deprecation warnings from `app/` sources (37 files touched).

### Changed
- **Modifier key masks** (7 files): `NSShiftKeyMask` → `NSEventModifierFlagShift`, `NSControlKeyMask` → `NSEventModifierFlagControl`, `NSAlternateKeyMask` → `NSEventModifierFlagOption`, `NSCommandKeyMask` → `NSEventModifierFlagCommand`, `NSNumericPadKeyMask` → `NSEventModifierFlagNumericPad`, `NSDeviceIndependentModifierFlagsMask` → `NSEventModifierFlagDeviceIndependentFlagsMask`
- **UI constants** (23 files): `NSOffState`/`NSOnState` → `NSControlStateValueOff`/`NSControlStateValueOn`, `NSCompositeSourceOver` → `NSCompositingOperationSourceOver`, `NSCompositeSourceAtop` → `NSCompositingOperationSourceAtop`, `NSWarningAlertStyle` → `NSAlertStyleWarning`, `NSCriticalAlertStyle` → `NSAlertStyleCritical`, `NSSmallControlSize` → `NSControlSizeSmall`, `NSCenterTextAlignment` → `NSTextAlignmentCenter`, `NSProgressIndicatorSpinningStyle` → `NSProgressIndicatorStyleSpinning`, `NSMomentaryChangeButton` → `NSButtonTypeMomentaryChange`, `NSRegularSquareBezelStyle` → `NSBezelStyleRegularSquare`, `NSShadowlessSquareBezelStyle` → `NSBezelStyleShadowlessSquare`, `NSFullScreenWindowMask` → `NSWindowStyleMaskFullScreen`, `NSStringPboardType` → `NSPasteboardTypeString`, `NSDragPboard` → `NSPasteboardNameDrag`, `NSLeftMouseDown` → `NSEventTypeLeftMouseDown`, `NSRightMouseDown` → `NSEventTypeRightMouseDown`
- **Percent encoding** (6 files): `stringByAddingPercentEscapesUsingEncoding:` → `stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]`, `stringByReplacingPercentEscapesUsingEncoding:` → `stringByRemovingPercentEncoding`
- **Icon API** (2 files): `[NSWorkspace iconForFileType:]` → `[NSWorkspace iconForContentType:]` using UTType API — added `UniformTypeIdentifiers.framework` to project
- **attributedSubstringFromRange:** → `attributedSubstringForProposedRange:actualRange:` in `SFBCrashReporterWindowController.m`
- **selectedMenuItemColor** → `selectedContentBackgroundColor` in `ViCommandMenuItemView.m`
- **setFlipped:** → `drawInRect:fromRect:operation:fraction:respectFlipped:hints:` in `ViToolbarPopUpButtonCell.m`
- **lockFocus/unlockFocus/initWithFocusedViewRect:** → `imageWithSize:flipped:drawingHandler:` and `bitmapImageRepForCachingDisplayInRect:` in `ViLayoutManager.m`, `ViLineNumberView.m`, `ViFile.m`, `ViTextView-cursor.m`, `PSMTabBarCell.m`
- **FSEvents RunLoop** → `FSEventStreamSetDispatchQueue` with `dispatch_get_main_queue()` in `ViURLManager.m`
- **NSBeginAlertSheet** → `NSAlert` + `beginSheetModalForWindow:completionHandler:` in `SFBCrashReporterWindowController.m`
- **mktemp** → `mkstemp` in `Nu.m` (TOCTOU race fix)
- **ffi_prep_closure** → `ffi_prep_closure_loc` in `Nu.m` (Apple Silicon W^X fix)

### Removed
- `NSGarbageCollector` calls from `Nu.m` (dead GC code)

### Files
`NSEvent-keyAdditions.m`, `NSScanner-additions.m`, `NSString-additions.m`, `ViAppController.m`, `ViBundleItem.m`, `ViFileExplorer.m`, `ViSymbolController.m`, `MHTextIconCell.m`, `NSWindow-additions.m`, `PSMMetalTabStyle.m`, `PSMOverflowPopUpButton.m`, `PSMTabBarCell.m`, `PSMTabBarControl.m`, `PSMTabDragAssistant.m`, `ViBundle.m`, `ViDocument.m`, `ViPathControl.m`, `ViRegexp.m`, `ViRegisterManager.m`, `ViTextView-bundle_commands.m`, `ViTextView-snippets.m`, `ViTextView.m`, `ViWindowController.m`, `ViFoldMarginView.m`, `NSURL-additions.m`, `SFTPConnection.m`, `TxmtURLProtocol.m`, `ViDocumentController.m`, `ViFileCompletion.m`, `ViFile.m`, `ViPathCell.m`, `SFBCrashReporterWindowController.m`, `ViCommandMenuItemView.m`, `ViToolbarPopUpButtonCell.m`, `Nu.m`, `ViLayoutManager.m`, `ViLineNumberView.m`, `ViTextView-cursor.m`, `ViURLManager.m`, `vico.xcodeproj/project.pbxproj`

---

## Phase 2.1 — Remaining Warning Fixes (Groups A–E)

### Changed
- **Sheet modal callbacks** (15 call sites, 6 files): `beginSheet:modalForWindow:modalDelegate:didEndSelector:contextInfo:` → `beginSheet:completionHandler:` and `beginSheetModalForWindow:completionHandler:` — existing delegate methods preserved and called from within completion blocks
- **Async document open** (2 sites in `ViAppController.m`): `openDocumentWithContentsOfURL:display:error:` → `openDocumentWithContentsOfURL:display:completionHandler:` for `getUrl:` and `editSiteScript:`
- **Precedence bug** in `ViFileCompletion.m`: `![isCaseSensitive intValue] == 1` → `[isCaseSensitive intValue] != 1`
- **nonnull fix** in `ViDocument.m`: `ofType:nil` → `ofType:[self fileType]` for `saveToURL:` call
- **Synthetic notification** in `ViCompletionController.m`: `nil` → proper `NSNotification` for `tableViewSelectionDidChange:`
- **Pointer-to-bool cast** in `ViCommand.m`: `(BOOL)[target performSelector:]` → `(BOOL)(intptr_t)[target performSelector:]`
- **LSMinimumSystemVersion** in `Vico-Info.plist`: `10.8.0` → `13.0`
- **PRODUCT_BUNDLE_IDENTIFIER** added to all 3 Vico build configurations (`se.bzero.Vico`)
- **initWithScheme:host:path:** → `NSURLComponents` in `ViPreferencePaneBundles.m`

### Files
`ViWindowController.m`, `ViDocument.m`, `ViFileExplorer.m`, `ViPreferencePaneEdit.m`, `ViPreferencePaneBundles.m`, `ViTaskRunner.m`, `ViAppController.m`, `ViFileCompletion.m`, `ViCompletionController.m`, `ViCommand.m`, `Vico-Info.plist`, `vico.xcodeproj/project.pbxproj`

---

## Phase 2.2 — Newly-Visible Warning Fixes (Groups F, L, M, O, P, Q)

Warnings revealed by clean build after Phase 2.1.

### Changed
- **NSURLConnection → NSURLSession** in `ViPreferencePaneBundles.m`: 3 connections (user JSON, repo list, tarball download) → `NSURLSessionDataTask` + `NSURLSessionDownloadTask` with completion handlers and download progress delegate. Tar changed from stdin pipe to file argument (`-f`). Added `NSURLErrorCancelled` guard in all completion handlers. Session created with `delegateQueue:[NSOperationQueue mainQueue]` for UI safety.
- **NSURLConnection → NSURLSession** in `SFBCrashReporterWindowController.m`: crash report POST → `[NSURLSession sharedSession] dataTaskWithRequest:completionHandler:` with `dispatch_async(dispatch_get_main_queue(), ...)` for UI updates
- **NSURLConnection → NSURLSession** in `ViHTTPURLHandler.m`: chunk-streaming HTTP deferred → `NSURLSessionDataDelegate` to preserve incremental data delivery for `ViDocument`. Uses `delegateQueue:[NSOperationQueue mainQueue]` to preserve `wait` run loop spin behavior.
- **MHTextIconCell atomic mismatch** in `MHTextIconCell.h`: `nonatomic` → `atomic` to match `NSCell` superclass
- **setNeedsDisplay** (4 sites in 2 files): zero-argument deprecated form → `self.needsDisplay = YES`
- **NSApplicationDelegate conformance**: added to `ViAppController.h`

### Removed
- `_urlConnection` and `_responseData` ivars from `SFBCrashReporterWindowController.h`

### Files
`ViPreferencePaneBundles.h`, `ViPreferencePaneBundles.m`, `MHTextIconCell.h`, `PSMRolloverButton.m`, `PSMTabBarCell.m`, `SFBCrashReporterWindowController.h`, `SFBCrashReporterWindowController.m`, `ViHTTPURLHandler.h`, `ViHTTPURLHandler.m`, `ViAppController.h`

---

## Phase 2.3 — Pre-Phase-3 Warning Audit

No code changes. Clean build audit established the warning baseline before Phase 3. Confirmed zero fixable warnings remain in `app/`. All remaining warnings are deferred by design (NSConnection IPC, sync document APIs, WebView, NSForm, drag API) or third-party (Sparkle).

---

## Phase 3 — Tier 1 XIB-to-Code Migration

Migrated 3 standalone XIB files to programmatic AppKit code.

### Added
- `app/ViWaitProgressUI.h/.m` — factory class replacing `WaitProgress.xib`, uses KVC (`setValue:forKey:`) outlet wiring to match generic File's Owner pattern. Window: 329x85, indeterminate progress bar, cancel button with Escape key equivalent.

### Changed
- `ViCompletionController.m` — replaced `CompletionWindow.xib` with programmatic `NSPanel` (borderless, `becomesKeyOnlyIfNeeded`) + `ViCompletionView` (NSTableView subclass, single column, no header). ScrollView: 150x287, label: 150x14.
- `SFBCrashReporterWindowController.m/.h` — replaced `SFBCrashReporterWindow.xib` with `initWithWindow:nil` + `buildWindow`. Window: 453x365. 12 subviews, 5 Cocoa bindings (including `displayPatternValue1` with `NSDisplayPattern`). Added `<NSWindowDelegate, NSTextViewDelegate>` protocol conformance. Merged `windowDidLoad` into `buildWindow`.
- `ViTaskRunner.m` — replaced `loadNibNamed:@"WaitProgress"` with `[ViWaitProgressUI createWaitProgressWindowWithOwner:self]`
- `SFTPConnection.m` — same nib replacement for `SFTPRequest`'s lazy init

### Removed
- `app/en.lproj/WaitProgress.xib`
- `app/en.lproj/CompletionWindow.xib`
- `app/en.lproj/SFBCrashReporterWindow.xib`

### Files
`ViWaitProgressUI.h`, `ViWaitProgressUI.m`, `ViCompletionController.m`, `SFBCrashReporterWindowController.h`, `SFBCrashReporterWindowController.m`, `ViTaskRunner.m`, `SFTPConnection.m`, `vico.xcodeproj/project.pbxproj`

---

## Phase 4 — Tier 2 + Tier 3 XIB-to-Code Migration

Migrated 7 XIB files: 1 inspector panel (Tier 2) + 6 preference system XIBs (Tier 3).

### Changed
- `ViMarkInspector.m/.h` — replaced `MarkInspector.xib` with `initWithWindow:nil` + `buildWindow`. NSPanel: 283x516, utility style. NSPopUpButton bound to `NSArrayController` (`markStackController`), NSSegmentedControl for back/forward, ViOutlineView with two columns. NSTreeController with `childrenKeyPath=marks`, `leafKeyPath=isLeaf`. Added `<NSOutlineViewDelegate>` protocol.
- `ViPreferencesController.m/.h` — replaced `PreferenceWindow.xib` with `initWithWindow:nil` + `buildWindow`. NSPanel: 480x180, NSToolbar for pane switching. Added `<NSWindowDelegate>` protocol.
- `ViPreferencePaneTheme.m` — replaced `ThemePrefs.xib` with `initWithNib:nil` + `buildView`. Root view: 480x209. Theme popup bound to `values.theme`, font display + "Select..." button, 4 checkboxes, blink mode popup with `caretBlinkModeTransformer`.
- `ViPreferencePaneGeneral.m` — replaced `GeneralPrefs.xib`. Root view: 480x326. All bindings to `NSUserDefaultsController.values.*`. Conditional enables (smartcase/ignorecase, relativenumber/number, etc.). NSMatrix radio group for undo style, default syntax popup, tab preference popup.
- `ViPreferencePaneAdvanced.m` — replaced `AdvancedPrefs.xib`. Root view: 480x401. NSArrayController bound to `values.environment` with `environmentVariableTransformer` and `NSHandlesContentAsCompoundValue`. Two-column environment table. Skip pattern field, develop menu checkbox.
- `ViPreferencePaneEdit.m/.h` — replaced `EditPrefs.xib`. Root view: 480x346. All bindings to `self` (not NSUserDefaultsController) — uses `valueForUndefinedKey:`/`setValue:forUndefinedKey:` for scope-aware preferences. 7 checkboxes, tabs/spaces popup, tab/indent width fields with NSNumberFormatter. Scope selector popup + new scope sheet (334x158). Added `<NSTextFieldDelegate>` protocol.
- `ViPreferencePaneBundles.m` — replaced `BundlePrefs.xib`. Root view: 480x461. 2 NSArrayControllers, 12 outlets. Bundles table with 4 columns (status icon, name, user, description). Action popup, search field, install/uninstall buttons. Select repo sheet (441x201) with editable username table. Progress sheet (441x93).
- `ViPreferencePane.m` — added nil check for nib parameter to allow incremental migration: `if (nib && ...)` skips instantiation when nib is nil.

### Removed
- `app/en.lproj/MarkInspector.xib`
- `app/en.lproj/PreferenceWindow.xib`
- `app/en.lproj/ThemePrefs.xib`
- `app/en.lproj/GeneralPrefs.xib`
- `app/en.lproj/AdvancedPrefs.xib`
- `app/en.lproj/EditPrefs.xib`
- `app/en.lproj/BundlePrefs.xib`

### Files
`ViMarkInspector.h`, `ViMarkInspector.m`, `ViPreferencesController.h`, `ViPreferencesController.m`, `ViPreferencePaneTheme.m`, `ViPreferencePaneGeneral.m`, `ViPreferencePaneAdvanced.m`, `ViPreferencePaneEdit.h`, `ViPreferencePaneEdit.m`, `ViPreferencePaneBundles.m`, `ViPreferencePane.m`, `vico.xcodeproj/project.pbxproj`

---

## Phase 6 — Final 3 XIB Migrations (ViDocument, MainMenu, ViDocumentWindow)

Completed full XIB elimination. All 14 original XIBs are now programmatic code.

### Changed
- `ViDocumentView.m` — replaced `ViDocument.xib` with `loadView` override. Creates NSView(600x400) → NSScrollView(600x400) → placeholder NSTextView(600x14). Placeholder swapped by `replaceTextView:` during document load.
- `ViAppController.m/.h` — replaced `MainMenu.xib` with `buildMainMenu` (~280 lines) called from `applicationWillFinishLaunching:`. Constructs 8 top-level menus: Vico (app), File, Edit, Navigate, View, Develop, Window, Help. Wired 8 IBOutlet connections. Set NSApp special menus (`setServicesMenu:`, `setWindowsMenu:`, `setHelpMenu:`, `setAppleMenu:`). Added `NSMenuDelegate` to protocol list.
- `Vico-Info.plist` — removed `NSMainNibFile`/`MainMenu` key-value pair
- `main.m` — explicit creation of `ViAppController` and `ViDocumentController` before `NSApplicationMain` (previously instantiated by main nib). `ViDocumentController` must be created first to become the shared instance.
- `ViWindowController.m` — replaced `ViDocumentWindow.xib` with `initWithWindow:nil` + `buildWindow` + 4 helper methods (`buildExplorerActionMenu`, `buildExplorerView`, `buildSymbolsView`, `buildSFTPSheet`). 18+ IBOutlets, 6 top-level nib objects created programmatically. NSToolbarDelegate with 6 identifiers. PSMTabBarControl setup. 3-pane NSSplitView (explorer|main|symbols). Status bar with `caretLabel` and `modeLabel` via `setStatusComponents:`. All `windowDidLoad` logic merged into `buildWindow`. Explicit `awakeFromNib` calls on `ViFileExplorer` and `ViSymbolController` after KVC outlet wiring.

### Removed
- `app/en.lproj/ViDocument.xib`
- `app/en.lproj/MainMenu.xib`
- `app/en.lproj/ViDocumentWindow.xib`

### Files
`ViDocumentView.m`, `ViAppController.h`, `ViAppController.m`, `Vico-Info.plist`, `main.m`, `ViWindowController.m`, `vico.xcodeproj/project.pbxproj`

---

## Phase 7 — Sparkle 1.5b6 → Sparkle 2.9.0 Upgrade

Replaced dead vendored Sparkle subproject with prebuilt framework. Resolved the long-standing linker error.

### Added
- `Sparkle.framework` — prebuilt Sparkle 2.9.0 at project root (downloaded from GitHub releases)
- SPUUpdater + SPUStandardUserDriver initialization in `ViAppController.m` with `startUpdater:` call
- `FRAMEWORK_SEARCH_PATHS = "$(inherited)", "$(SRCROOT)"` in all 3 build configurations

### Changed
- `ViAppController.h` — added `@class SPUUpdater`, `@class SPUStandardUserDriver` forward declarations, added `_updater` and `_userDriver` ivars
- `ViAppController.m` — `#import <SUUpdater.h>` → `#import <Sparkle/Sparkle.h>`. Replaced commented-out `[SUUpdater sharedUpdater]` with fully wired SPUUpdater. Menu item `checkForUpdates:` action targets `_updater`.
- `Vico-Info.plist` — removed `SUPublicDSAKeyFile`/`sparkle_pub.pem` (DSA deprecated in Sparkle 2; EdDSA `SUPublicEDKey` to be added when distribution resumes). Kept `SUFeedURL`.
- `vico.xcodeproj/project.pbxproj` — reused existing file reference ID `17E8AB43` (was `Sparkle.xcodeproj`, now `Sparkle.framework`). Removed 5 PBXContainerItemProxy, 5 PBXReferenceProxy, Products group, projectReferences, `HEADER_SEARCH_PATHS "Sparkle"`. Changed PBXBuildFile fileRefs for Frameworks and Copy Frameworks phases.

### Removed
- `sparkle/` — entire vendored Sparkle 1.5b6 source tree (60+ source files, 40+ localized XIBs)
- `sparkle_pub.pem` — DSA public key

### Files
`Sparkle.framework` (added), `ViAppController.h`, `ViAppController.m`, `Vico-Info.plist`, `vico.xcodeproj/project.pbxproj`

---

## Phase 8 — Build Script Fixes and Lemon Parser

Fixed all build errors when building from Xcode GUI.

### Added
- `help/Markdown.pl` — Gruber's Markdown.pl 1.0.1 for help bundle generation

### Changed
- **"Download bundle repo from GitHub"** script → `echo "Skipping..." && exit 0` (GitHub API v2 defunct since 2012, bundles already vendored in `Bundles/`). Added `alwaysOutOfDate = 1`.
- **"Checkout bundles from GitHub"** script → fixed to use `$SOURCE_ROOT/Bundles/` instead of undefined `$BUNDLES` env variable. Removed Debug-only early exit. Added `alwaysOutOfDate = 1`.
- **"Build help bundle"** script → `help/md2html` updated to find `Markdown.pl` relative to itself (`$SCRIPT_DIR/Markdown.pl`) instead of `$HOME/bin/Markdown.pl`. Fixed stdout bug: added `> "$html"` redirect to write `.html` files. Removed Debug/Snapshot early exit. Added `set -e` and `alwaysOutOfDate = 1`.
- **Lemon parser** — removed `*.lemon` build rule from project. Added pre-generated `scope_selector.c` as regular PBXFileReference. Replaced `scope_selector.lemon in Sources` with `scope_selector.c in Sources`. Removed lemon target dependency from Vico target. (Fixes Xcode GUI builds where `BUILT_PRODUCTS_DIR` differs from CLI builds.)

### Files
`help/Markdown.pl` (added), `help/md2html`, `vico.xcodeproj/project.pbxproj`

---

## Phase 9 — NSConnection → NSXPCConnection Migration

Migrated IPC between `vicotool` CLI and Vico app from deprecated Distributed Objects to NSXPCConnection. Eliminates all 5 `NSConnection is deprecated` warnings.

### Added
- `app/ViXPCProtocols.h` — shared XPC protocol definitions. `ViShellCommandXPCProtocol`: `pingWithReply:`, `evalScript:additionalBindings:withReply:`, `openURL:andWait:withReply:`, `setStartupBasePath:`, `newDocumentWithData:andWait:withReply:`, `newProject`. `ViShellThingXPCProtocol`: `exitWithCode:`, `exitWithJSONString:`, `log:`. Key adaptations: return values → reply blocks, `NSError **` → error string in reply, `backChannel:` string eliminated, `exitWithObject:(id)` → `exitWithJSONString:(NSString *)`.
- `app/ViXPCBackChannelProxy.h/.m` — Nu-facing wrapper bridging `id` parameters to XPC-safe JSON strings via `NSJSONSerialization`. Preserves `exitWithObject:` method name that Nu scripts expect.
- Launchd agent plist auto-installation (`installXPCLaunchdPlistIfNeeded`) at `~/Library/LaunchAgents/se.bzero.vico.ipc.plist` for Mach service registration.

### Changed
- `ViAppController.h` — removed `ViShellThingProtocol` and `ViShellCommandProtocol` definitions. Removed `ViShellCommandProtocol` from class conformance. Added `NSXPCListenerDelegate`. Replaced `NSConnection *shellConn` with `NSXPCListener *_xpcListener`.
- `ViAppController.m` — NSConnection setup → `NSXPCListener(machServiceName:@"se.bzero.vico.ipc")`. Added `listener:shouldAcceptNewConnection:` delegate. All XPC protocol method implementations dispatch to main thread via `dispatch_async(dispatch_get_main_queue(), ...)`. Bidirectional XPC for back-channel (no second named service). `backChannel:` parameter changed from `NSString *` name to `ViXPCBackChannelProxy *`. Replaced `SBJsonWriter` with `NSJSONSerialization`.
- `util/vico.m` — full IPC rewrite. `ShellThing` conforms to `ViShellThingXPCProtocol`. Connection via `NSXPCConnection(machServiceName:)` with ping-based 2-second timeout liveness check. Back-channel uses `exportedObject`/`exportedInterface` on same connection. All proxy calls use async reply blocks with `dispatch_semaphore` synchronization. Replaced `SBJsonParser`/`SBJsonWriter` with `NSJSONSerialization`. Added `CFRunLoopStop` for prompt exit.

### Removed
- `ViShellThingProtocol` and `ViShellCommandProtocol` from `ViAppController.h`
- All `NSConnection`, `NSDistantObject`, `SBJsonParser`/`SBJsonWriter` references from `app/` and `util/`

### Files
`ViXPCProtocols.h` (added), `ViXPCBackChannelProxy.h` (added), `ViXPCBackChannelProxy.m` (added), `ViAppController.h`, `ViAppController.m`, `util/vico.m`, `vico.xcodeproj/project.pbxproj`

---

## Phase 10 — Fix Deprecation & Type Warnings (Safe Steps)

Fixed 22 low/medium-risk deprecation and type mismatch warnings. All changes mechanical — no control flow modifications.

### Changed
- `ViAppController.m` — fixed stale `setCloseCallbackForDocument:toNotifyBackChannel:` forward declaration to match Phase 9's `setCloseCallbackForDocument:backChannel:` signature
- `ViFileExplorer.h` — replaced `IBOutlet NSForm *sftpConnectForm` with 3 individual `NSTextField` ivars (`sftpHostField`, `sftpUserField`, `sftpPathField`). Added `NSSearchFieldDelegate` to protocol list.
- `ViFileExplorer.m` — updated all `sftpConnectForm` cell-based access (`cellAtIndex:`, `selectTextAtIndex:`) to direct field references
- `ViWindowController.m` — replaced `NSForm` with 3 label+field pairs wired via KVC for SFTP sheet. Replaced 12 `setMinSize:`/`setMaxSize:` calls with Auto Layout `widthAnchor`/`heightAnchor` constraints on toolbar item views. Removed 2 deprecated toolbar identifiers (`NSToolbarSeparatorItemIdentifier`, `NSToolbarCustomizeToolbarItemIdentifier`).
- `ViWindowController.h` — added `NSSplitViewDelegate` protocol conformance
- `PSMTabBarControl.h` — added `NSTabViewDelegate` protocol conformance
- `ViSymbolController.h` — added `NSSearchFieldDelegate` protocol conformance

### Removed
- `[box setBorderType:NSBezelBorder]` from `ViPreferencePaneEdit.m` (no-op on `NSBoxPrimary`)

### Files
`ViAppController.m`, `ViPreferencePaneEdit.m`, `ViFileExplorer.h`, `ViFileExplorer.m`, `ViWindowController.h`, `ViWindowController.m`, `PSMTabBarControl.h`, `ViSymbolController.h`

---

## Phase 11 — Async Document Open Migration

Eliminated all 6 `openDocumentWithContentsOfURL:display:error:` deprecation warnings.

### Changed
- `ViDocumentController.m` — replaced sync override with async `openDocumentWithContentsOfURL:display:completionHandler:`. Same custom logic (URL normalization, document reuse, TxmtURL parsing, scheme validation) with early-return paths calling `completionHandler(doc, YES/NO, error)` directly.
- `ViAppController.m` — converted `openURLInternal:andWait:backChannel:` from returning `NSError *` to taking a `completion:` block. XPC handler `openURL:andWait:withReply:` replies from within the block.
- `ViWindowController.m` — 4 call sites converted:
  - `gotoMark:positioned:recordJump:` — async open when `mark.document == nil && mark.url != nil`, returns `YES` optimistically
  - `splitVertically:andOpen:orSwitchToDocument:allowReusedView:` — async open, returns `nil` for async path. Ex-command callers simplified to always return `nil`.
  - `ex_edit:` — early return for `:e!` revert, then async open with display + `+command` evaluation in completion block
  - `ex_tabedit:` — split into sync (untitled) and async (URL) paths
- `ViProject.m` — async open inside `makeSplit:selectedDocumentURL:topLevel:` enumeration block

### Files
`ViDocumentController.m`, `ViAppController.m`, `ViWindowController.m`, `ViProject.m`

---

## Phase 12 — Async Save Migration

Eliminated the last 2 deprecation warnings in the codebase.

### Changed
- `ViDocument.m` — converted 2 `saveToURL:ofType:forSaveOperation:error:` calls to async `completionHandler:` version:
  - **`continueSavingAfterError:`** (line 624) — extracted new `finishSaveWithError:didSave:` helper for post-save logic (error presentation + delegate NSInvocation callback + ivar cleanup). Called from both early-error path and completion handler path.
  - **`ex_write:`** (line 2400) — `:w filename` save-as. Returns `nil` immediately, errors displayed via `[command message:]` in completion handler.

### Files
`ViDocument.m`

---

## Phase 13 — Fix Post-Xcode-Settings-Update Warnings

Fixed ~117 compiler warnings surfaced by updated Xcode recommended settings, across 8 rounds.

### Changed
- `ViTextView-cursor.m` — cast IMP to typed function pointer `((NSCursor *(*)(id, SEL))...)` for modern SDK compatibility
- `oniguruma/st.h` — converted all function declarations from K&R to ANSI C. Added typedefs `st_compare_func`, `st_hash_func`, `st_foreach_func`. Removed `ANYARGS` and `_()` compatibility macros.
- `oniguruma/st.c` — converted all ~15 K&R function definitions to ANSI prototypes. Added casts for `type_numhash` and `type_strhash` struct initializers.
- `oniguruma/regparse.c` — added `(st_compare_func)`, `(st_hash_func)`, `(st_foreach_func)` casts at 8 sites
- `oniguruma/enc/unicode.c` — added casts for `type_code2_hash` and `type_code3_hash` struct initializers
- `json/SBJsonStreamTokeniser.m` — removed unreachable `@throw @"FUT FUT FUT"` after infinite `while(1)` loop
- `ViTaskRunner.m` — captured `waitWindow` ivar into local `NSWindow *sheet` before block to fix implicit self-capture
- `ViWaitProgressUI.m` — added `#import "ViTaskRunner.h"` for `cancelTask:` selector visibility
- `ViSymbolController.h` — removed duplicate declarations of `closeSymbolListAndFocusEditor:` and `symbolListIsOpen`
- `ViCompletionController.h` — removed duplicate `accept_or_complete_partially:` declaration
- `par/par.c`, `par/reformat.c` — replaced ~14 comma operators with semicolons, added braces where needed
- `ViWindowController.h` — added `NSMenuItemValidation` protocol
- `ViWindowController.m` — fixed implicit self-capture in 9 blocks (captured ivars into locals or used `self->` prefix). Removed deprecated `shouldCollapseSubview:forDoubleClickOnDividerAtIndex:`.
- `ViTextView.h` — added 17 method declarations across cursor and vi_commands categories (`windowBecameKey:`, `windowResignedKey:`, `scroll_down_by_line:`, `scroll_up_by_line:`, `move_down_soft:`, `move_up_soft:`, `vi_undo:`, `visual:`, `visual_other:`, `visual_line:`, `shift_right:`, `shift_left:`, `subst_lines:`, `move_to_char:`, `move_til_char:`, `move_back_to_char:`, `move_back_til_char:`)
- `ViTextView.m` — `NSSelectorFromString(@"getMoreBundles:")` for cross-class menu action; comma → semicolon
- `ViSnippet.m` — 12 `return NO` → `return nil` in pointer-returning methods (`parseString:` returns `NSMutableString *`, `initWithString:` returns `ViSnippet *`)
- `ViSyntaxParser.m` — `reachedEOL:NO` → `reachedEOL:NULL` (BOOL* parameter)
- `ViDocument.m` — converted sync `saveToURL:` override to async `completionHandler:`; converted `textStorageDidProcessEditing:` to modern `textStorage:didProcessEditing:range:changeInLength:` (NSTextStorageDelegate protocol method); 4× `options:NULL` → `options:0`
- `ViParser.m` — added `#import "ViTextView.h"` for selector visibility
- `ViAppController.m` — added `#import <objc/message.h>`. 5 `NSSelectorFromString` for responder-chain menu actions (`setAppleMenu:`, `undo:`, `redo:`, `moveCurrentViewToNewWindowAction:`, `setEncoding:`). Typed `objc_msgSend` cast for `setAppleMenu:`: `((void (*)(id, SEL, id))objc_msgSend)(NSApp, sel, appMenu)`.
- `Nu.m` — 3 function prototypes with `void` parameter (`NuInit(void)`, `_nunull(void)`, `nu_swizzleContainerClasses(void)`). Fixed array-address always-true warning with `#ifdef` guard. Removed deprecated `finalize` method (dead GC code).
- `NSMenu-additions.m` — added `#import "ViTextView.h"` for `performNormalModeMenuItem:` selector
- `ViPreferencePaneTheme.h` — added `NSFontChanging` protocol
- `ViCommand.m` — added `#import "ViTextView.h"` for `vi_undo:`. `NSSelectorFromString(@"dot:")` for Nu-registered runtime-only selector.
- `ViFileExplorer.h` — added `NSMenuItemValidation` protocol
- `PSMTabBarControl.m` — removed 3 deprecated drag source methods (`draggingSourceOperationMaskForLocal:`, `ignoreModifierKeysWhileDragging`, `draggedImage:endedAt:operation:`) — modern replacements already existed in the same file
- `ViLineNumberView.m` — `options:NULL` → `options:0`

### Files
`ViTextView-cursor.m`, `oniguruma/st.h`, `oniguruma/st.c`, `oniguruma/regparse.c`, `oniguruma/enc/unicode.c`, `json/SBJsonStreamTokeniser.m`, `ViTaskRunner.m`, `ViWaitProgressUI.m`, `ViSymbolController.h`, `ViCompletionController.h`, `par/par.c`, `par/reformat.c`, `ViWindowController.h`, `ViWindowController.m`, `ViTextView.h`, `ViTextView.m`, `ViSnippet.m`, `ViSyntaxParser.m`, `ViDocument.m`, `ViParser.m`, `ViAppController.m`, `Nu.m`, `NSMenu-additions.m`, `ViPreferencePaneTheme.h`, `ViCommand.m`, `ViFileExplorer.h`, `PSMTabBarControl.m`, `ViLineNumberView.m`

---

## Phase 14 — Fix Build-Phase Sandbox Errors

### Changed
- `vico.xcodeproj/project.pbxproj` — set `ENABLE_USER_SCRIPT_SANDBOXING = NO` in all 3 build configurations (Debug, Release, Snapshot). Required by "Build help bundle" script which needs read access to `$SOURCE_ROOT/help/` and write access to `$TARGET_BUILD_DIR/`.

### Removed
- "Checkout bundles from GitHub" shell script build phase — redundant with "Copy Bundle Resources" which already handles `Bundles/` directory and auto-excludes `.git` via Xcode's `builtin-copy`

### Files
`vico.xcodeproj/project.pbxproj`

---

## Phase 15 — Remove Stale libcrypto Reference

### Removed
- `libcrypto.0.9.8.dylib` PBXFileReference and group membership from `vico.xcodeproj/project.pbxproj` — stale reference to OpenSSL dylib that Apple removed from the macOS SDK. Was never in any `PBXFrameworksBuildPhase` (never linked into any target). Navigator-only cleanup.

### Files
`vico.xcodeproj/project.pbxproj`

---

## Final Build State

- **Compilation**: Succeeds for all targets
- **Code warnings**: Zero
- **Build-system warnings**: 3 (pre-existing: manual target order, ONLY_ACTIVE_ARCH ×2)
- **XIB files**: All 14 migrated to programmatic AppKit code (`app/en.lproj/` contains only `Credits.rtf` and `InfoPlist.strings`)
- **Deprecated APIs**: All eliminated
- **IPC**: Migrated from NSConnection/Distributed Objects to NSXPCConnection
- **Sparkle**: Upgraded from 1.5b6 to 2.9.0
- **Total warnings fixed**: ~300+ across all phases
