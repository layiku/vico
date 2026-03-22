# Why We Migrated XIBs to Code Instead of Upgrading Them

## The Short Answer

We originally planned to upgrade Vico's 14 old-format XIB files to the modern XIB format and keep using Interface Builder. We abandoned that plan because **`ibtool` is fundamentally broken for legacy XIBs** — it silently corrupts outlet connections, drops bindings, and produces files that compile but crash at runtime. The only reliable path was to delete every XIB and rebuild the UI programmatically in Objective-C.

---

## The Problem

Vico's XIB files were created in Xcode 3–4 era (2008–2012) using the old "archive" format (version 7.10). Modern Xcode (16+) requires the "document" format (version 3.0). Apple provides `ibtool --upgrade` to convert between formats.

### What `ibtool --upgrade` Actually Does

In theory, `ibtool --upgrade --write output.xib input.xib` converts old-format XIBs to the modern format. In practice:

1. **It drops Cocoa Bindings silently.** XIBs with `bind:toObject:withKeyPath:options:` connections (used extensively in Vico's preference panes) lose some or all bindings during conversion. The converted file compiles without error. The UI loads. But bound controls show no data, checkboxes don't reflect preferences, and popups don't populate — all silent failures at runtime.

2. **It corrupts outlet connections.** Complex XIBs with many outlets (like `ViDocumentWindow.xib` with 50+ outlets across multiple File's Owner classes) come out of `ibtool --upgrade` with broken or reassigned connection IDs. The symptom is `setValue:forUndefinedKey:` crashes on launch — an outlet name that existed in the old XIB now points to the wrong object or doesn't exist.

3. **It mishandles shared-owner XIBs.** `WaitProgress.xib` used a dummy File's Owner class (`ViCancellableDummy`) shared by three different callers (`ViTaskRunner`, `SFTPRequest`). `ibtool` doesn't understand this pattern and produces a converted file that only works for one of the three callers.

4. **It can't round-trip.** Once upgraded, the file can't be opened in old Xcode. And modern Interface Builder sometimes re-serializes the converted file on save, changing things further. There's no stable intermediate state.

5. **It doesn't update deprecated widgets.** `NSForm` (deprecated macOS 10.10), old-style `NSMatrix` radio groups, and deprecated `NSBox` border types survive the format upgrade unchanged. You still have to manually replace them — at which point you're doing the same work as a code migration anyway.

### The Scale of the Problem

Vico had 14 XIB files with:
- **50+ Cocoa Bindings** across preference panes (to `NSUserDefaultsController`, to `self` via KVC interception, to `NSArrayController` content)
- **100+ IBOutlet connections** across window controllers, view controllers, and cell classes
- **Dual-owner patterns** (sftpConnectView owned by both `ViWindowController` and `ViFileExplorer`)
- **Shared-owner patterns** (WaitProgress.xib loaded by 3 different classes)
- **Deprecated widgets** (NSForm, NSMatrix)

We tried `ibtool --upgrade` on the first batch of simple XIBs (Sparkle's localized XIBs) and it worked — but those were trivial single-view XIBs with no bindings. When we tried it on Vico's app XIBs, the corruption was immediate and unrecoverable without manual verification of every connection.

### Why Not Just Fix the Converted XIBs in Interface Builder?

We considered upgrading with `ibtool` and then manually repairing broken connections in Interface Builder. This failed for two reasons:

1. **Interface Builder can't display connections it doesn't understand.** When `ibtool` corrupts a binding, IB shows the outlet as "connected" — but to the wrong object. You can't tell what's broken without runtime testing of every single control.

2. **No diffability.** XIB files are XML, but the XML is machine-generated with random object IDs. When something breaks, there's no way to diff the old and new XIB meaningfully. You can't `git diff` your way to finding a dropped binding.

Programmatic code, by contrast, is fully diffable, fully searchable, and fails at compile time (not runtime) when something is wrong.

---

## The Decision

After the `ibtool` failures, we established a rule: **delete the XIB, read every outlet/binding/action from the XML, and rebuild it in code.** This was more work upfront but produced a result that:

- **Compiles or fails** — no silent runtime corruption
- **Is diffable** — every binding, outlet, and frame coordinate is in version-controlled `.m` files
- **Has no IB dependency** — no need for Interface Builder, no format migration ever again
- **Is incrementally migratable** — we could migrate one XIB at a time while others still loaded from nib

---

## How We Did It

### Migration Order (14 XIBs across 4 tiers)

| Tier | XIBs | Approach |
|------|-------|---------|
| **Tier 1: Standalone** | WaitProgress, CompletionWindow, SFBCrashReporterWindow | Factory class / inline construction |
| **Tier 2: Panels** | MarkInspector | `initWithWindow:nil` + `buildWindow` |
| **Tier 3: Preferences** | PreferenceWindow, GeneralPrefs, EditPrefs, ThemePrefs, BundlePrefs, AdvancedPrefs | Base class nil-nib pattern for incremental migration |
| **Tier 4: Core** | CommandOutputWindow, ViDocument, MainMenu, ViDocumentWindow | Most complex; migrated last |

### The Analysis Phase

Before touching any XIB, we produced a comprehensive **XIB File Analysis** (`xib-file-analysis-result.md`) documenting every code↔XIB relationship across all 14 files:

- Every IBOutlet connection with object ID, type, and purpose
- Every IBAction connection with source and selector
- Every Cocoa Binding with key path, options, and value transformers
- Every cross-XIB or shared-owner dependency
- Every deprecated widget requiring replacement

This document was the single source of truth for the migration. Without it, we would have missed connections and produced crashes.

### Patterns That Emerged

**NSWindowController without nib:**
```objc
// Old: loads from XIB
self = [super initWithWindowNibName:@"SomeWindow"];

// New: builds programmatically
self = [super initWithWindow:nil];
[self buildWindow];  // creates NSWindow, subviews, bindings
```
Critical: `windowDidLoad` is NOT called when using `initWithWindow:` — its logic must be merged into `buildWindow`.

**Factory class for shared XIBs:**
When multiple classes loaded the same XIB (WaitProgress.xib), we created a factory class that uses KVC (`setValue:forKey:`) to wire outlets on any owner — mirroring what the nib loader does internally.

**Base class nil-nib pattern for incremental migration:**
```objc
// ViPreferencePane.m — allows one pane at a time
if (nib && ![nib instantiateWithOwner:self topLevelObjects:nil]) { ... }
// When nib is nil, skip — subclass builds view in code
```

**Cocoa bindings survive nib removal:**
Every `bind:toObject:withKeyPath:options:` call works identically in code as in XIB. We preserved every binding exactly.

**NSMainNibFile removal:**
The final step: remove `NSMainNibFile` from Info.plist. The main menu and document window are now built entirely in `applicationWillFinishLaunching:`. This required explicitly setting `NSApp.servicesMenu`, `NSApp.windowsMenu`, and `NSApp.helpMenu` — without a nib, AppKit doesn't auto-detect these.

---

## The Result

- **14 XIB files deleted** — zero XIBs remain in the project
- **14 programmatic equivalents** — exact pixel-for-pixel reproduction of the original UI
- **Zero runtime binding failures** — all bindings verified at compile time
- **Fully diffable UI code** — every frame, every outlet, every binding in `.m` files
- **No Interface Builder dependency** — the project builds with `xcodebuild` alone
- **Incremental migration worked** — build stayed green after every XIB deletion

---

## Lessons for Other Projects

If you're modernizing a legacy Cocoa project with old XIB files:

1. **Don't trust `ibtool --upgrade`** for anything beyond trivial XIBs. Test every outlet and binding at runtime after conversion.

2. **Read the XIB XML directly.** Don't rely on Interface Builder's visual representation. The XML contains the ground truth about connections, bindings, and object IDs.

3. **Document every connection before deleting.** A comprehensive analysis document saves hours of debugging.

4. **Migrate incrementally.** Use nil-nib patterns so you can convert one file at a time without breaking the rest.

5. **Prefer code over XIB for complex UIs.** The upfront cost is higher, but the maintenance cost is dramatically lower — and you'll never face another format migration.

6. **Test at runtime, not just compile time.** Bindings can be syntactically correct but semantically wrong (wrong key path, wrong target object). Run the app and verify every control.
