# Vico Architecture Document

Vico is a Vim-like macOS text editor written in Objective-C using AppKit. Originally developed by Martin Hedenfalk (2008–2012), it combines vi modal editing with TextMate-compatible syntax highlighting, bundles, themes, and snippets. The editor supports local and remote (SFTP) file editing, Nu scripting, and a split/tab window model.

---

## Table of Contents

1. [High-Level Architecture](#high-level-architecture)
2. [Editor Pipeline (Protected Core)](#editor-pipeline)
3. [Document & Window Layer](#document--window-layer)
4. [Syntax Highlighting & Bundles](#syntax-highlighting--bundles)
5. [Ex Command System](#ex-command-system)
6. [Completion System](#completion-system)
7. [File & URL Handling](#file--url-handling)
8. [Preferences](#preferences)
9. [Vendored Libraries](#vendored-libraries)
10. [Build System](#build-system)
11. [Auxiliary Targets](#auxiliary-targets)
12. [Resource Directories](#resource-directories)
13. [File Reference (All Source Files)](#file-reference)

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        ViAppController                      │
│                    (NSApplication delegate)                 │
├──────────┬──────────────────────────────────┬───────────────┤
│          │                                  │               │
│  ViDocumentController          ViPreferencesController      │
│  (shared singleton)            (settings UI)                │
│          │                                                  │
│    ViDocument (N)                                           │
│    ├─ ViTextStorage (buffer)                                │
│    ├─ ViSyntaxParser (highlighting)                         │
│    ├─ ViFold (code folding)                                 │
│    └─ ViDocumentView (N per doc)                            │
│          │                                                  │
│    ViWindowController                                       │
│    ├─ PSMTabBarControl (tab bar)                            │
│    ├─ ViTabController (per tab, manages splits)             │
│    │   └─ ViViewController → ViDocumentView                 │
│    ├─ ViFileExplorer (sidebar)                              │
│    ├─ ViSymbolController (symbol list)                      │
│    ├─ ViStatusView (status bar)                             │
│    └─ ViParser (command parser)                             │
│                                                             │
│  Key Input Flow:                                            │
│  NSEvent → ViKeyManager → ViParser → ViCommand → ViTextView │
│        → ViTextStorage (mutation) → ViLayoutManager (render)│
└─────────────────────────────────────────────────────────────┘
```

### Architectural Layers

| Layer | Description | Modifiable? |
|-------|-------------|-------------|
| **Editor Core** | Parser, commands, text storage, layout | Protected — do not modify |
| **Document Model** | NSDocument subclass, views, syntax | Semi-protected |
| **Window Shell** | Tabs, splits, explorer, status bar | Freely modifiable |
| **Bundles/Themes** | TextMate-compatible grammar & styling | Freely modifiable |
| **File I/O** | URL handlers for file://, sftp://, http:// | Freely modifiable |
| **Utilities** | Categories, helpers, crash reporter | Freely modifiable |
| **Vendored Libs** | Oniguruma, lemon, par, SBJson, universalchardet | External — update only |

---

## Editor Pipeline

The editor pipeline is the **protected core** — changes require explicit developer approval.

```
Keyboard Event
  → ViKeyManager.keyDown:        (bridges NSEvent to parser)
  → ViParser.pushKey:            (state machine: initial → command → motion)
  → ViCommand                    (action + operator + motion + count + register)
  → ViTextView command methods   (vi_commands, ex_commands, snippets)
  → ViTextStorage mutations      (insert, delete, replace)
  → ViLayoutManager render       (glyphs, invisibles, folding)
```

### `app/ViParser.h` / `app/ViParser.m` — Vi Command Parser
- **Class:** `ViParser`
- **Purpose:** State machine that parses key sequences into vi commands
- **States:** initial → needRegister → partialCommand → needMotion → partialMotion → needChar
- **Key methods:** `-pushKey:allowMacros:scope:timeout:excessKeys:error:`, `-reset`, `-setVisualMap`, `-setInsertMap`
- **Depends on:** ViMap, ViCommand, ViScope, ViMacro

### `app/ViCommand.h` / `app/ViCommand.m` — Command Representation
- **Class:** `ViCommand`
- **Purpose:** Encapsulates a parsed command with metadata (action, operator, motion, count, register, argument)
- **Composition:** Operators compose with motion commands (e.g., `d` + `w` = delete word)
- **Key methods:** `+commandWithMapping:count:`, `-performWithTarget:`
- **Depends on:** ViMap, ViMacro

### `app/ViKeyManager.h` / `app/ViKeyManager.m` — Key Input Bridge
- **Class:** `ViKeyManager`
- **Purpose:** Bridges keyboard events to parser; handles macro recording/playback
- **Key methods:** `-keyDown:`, `-handleKey:inScope:`, `-runAsMacro:`, `-startRecordingMacro:`
- **Depends on:** ViParser, ViScope, ViMacro, ViRegisterManager

### `app/ViMap.h` / `app/ViMap.m` — Key Mappings
- **Classes:** `ViMap`, `ViMapping`
- **Purpose:** Maps key sequences to actions; supports scope-aware, recursive mappings with Nu expressions
- **Standard maps:** normalMap, insertMap, visualMap, operatorMap, explorerMap, completionMap
- **Flags:** ViMapSetsDot, ViMapNeedMotion, ViMapIsMotion, ViMapLineMode, ViMapNeedArgument
- **Depends on:** ViScope, Nu

### `app/ViMacro.h` / `app/ViMacro.m` — Macro Recording
- **Class:** `ViMacro`
- **Purpose:** Key sequence queue with instruction pointer for playback
- **Key methods:** `-push:`, `-pop`
- **Depends on:** ViMap (for ViMapping)

### `app/ViTextStorage.h` / `app/ViTextStorage.m` — Text Buffer
- **Class:** `ViTextStorage` (NSTextStorage subclass)
- **Purpose:** Document text storage with optimized line indexing via skip lists
- **Key methods:** `-locationForStartOfLine:`, `-lineAtLocation:`, `-rangeOfLine:`, `-lineCount`, `-wordAtLocation:range:`, `-columnAtLocation:`
- **Performance:** Skip list data structure for O(log n) line lookup
- **Depends on:** NSTextStorage, sys_queue.h (BSD queue macros)

### `app/ViTextView.h` / `app/ViTextView.m` — Main Editor View
- **Class:** `ViTextView` (NSTextView subclass)
- **Purpose:** Central editor UI — modes (normal/insert/visual), undo, caret, command execution
- **Categories:** Split across 5 files for organization
- **Key methods:** `-setCaret:`, `-gotoLine:column:`, `-insertString:atLocation:`, `-deleteRange:`, `-setNormalMode`, `-setInsertMode:`
- **Depends on:** ViParser, ViDocument, ViKeyManager, ViLayoutManager, ViRegisterManager, ViTaskRunner

### `app/ViTextView-vi_commands.m` — Vi Normal Mode Commands
- **Purpose:** Implements movement, deletion, yanking, shifting, visual selection, completion
- **Key methods:** `-move_left:`, `-delete:`, `-yank:`, `-shift_right:`, `-visual:`, `-complete_keyword:`

### `app/ViTextView-ex_commands.m` — Ex Command Execution
- **Purpose:** Resolves ex addresses and line ranges; executes ex commands
- **Key methods:** `-resolveExAddress:relativeTo:error:`, `-resolveExAddresses:intoLineRange:error:`

### `app/ViTextView-cursor.m` — Cursor Management
- **Purpose:** Block cursor rendering, blinking, line highlight
- **Key methods:** `-updateCaret`, `-invalidateCaretRect`, `-setCursorColor`

### `app/ViTextView-bundle_commands.m` — Bundle Command Execution
- **Purpose:** Runs TextMate-style bundle commands (shell scripts, Nu expressions)
- **Key methods:** `-performBundleCommand:`, `-performBundleItem:`
- **Depends on:** ViBundle, ViTaskRunner

### `app/ViTextView-snippets.m` — Snippet Expansion
- **Purpose:** Inserts and manages snippets with tabstop navigation
- **Key methods:** `-insertSnippet:`, `-insertSnippet:inRange:`, `-cancelSnippet`
- **Depends on:** ViSnippet

### `app/ViLayoutManager.h` / `app/ViLayoutManager.m` — Text Layout
- **Class:** `ViLayoutManager` (NSLayoutManager subclass)
- **Purpose:** Handles invisible character display (tabs ⇥, spaces ･, newlines ↩)
- **Key methods:** `-setShowsInvisibleCharacters:`, `-setInvisiblesAttributes:`
- **Depends on:** ViGlyphGenerator, ViTypesetter, ViThemeStore

### `app/ViTypesetter.h` — Typesetter
- **Class:** `ViTypesetter` (NSATSTypesetter subclass)
- **Purpose:** Zero-advancement glyph spacing for folded code regions

### `app/ViGlyphGenerator.h` — Glyph Generator
- **Class:** `ViGlyphGenerator` (NSGlyphGenerator subclass)
- **Purpose:** Produces null glyphs for folded regions (ViFoldedAttributeName)

### `app/ViSnippet.h` / `app/ViSnippet.m` — Snippet Model
- **Classes:** `ViSnippet`, `ViTabstop`
- **Purpose:** TextMate snippet with tabstops, mirrors, regex transformations, shell commands
- **Key methods:** `-advance`, `-replaceRange:withString:`, `-updateTabstopsError:`
- **Depends on:** ViRegexp, ViTaskRunner

### `app/ViRegexp.h` / `app/ViRegexp.m` — Regexp Wrapper
- **Classes:** `ViRegexp`, `ViRegexpMatch`
- **Purpose:** Wraps Oniguruma regex engine for vi search patterns
- **Key methods:** `-matchInString:range:`, `-allMatchesInString:options:range:`

### `app/ViRegisterManager.h` / `app/ViRegisterManager.m` — Vi Registers
- **Class:** `ViRegisterManager` (singleton)
- **Purpose:** Named registers ("a–z, ", +/*, /, :, %, #, _) for yank/paste
- **Special:** Uppercase A–Z append; +/* use system clipboard; % = current file; / = last search

### `app/ViMark.h` / `app/ViMark.m` — Vi Marks
- **Class:** `ViMark`
- **Purpose:** Named position (line:column or range) with optional persistence
- **Key methods:** `+markWithURL:line:column:`, `+markWithDocument:name:range:`

### `app/ViMarkManager.h` / `app/ViMarkManager.m` — Mark Management
- **Classes:** `ViMarkManager`, `ViMarkStack`, `ViMarkList`, `ViMarkGroup`
- **Purpose:** Hierarchical mark collections — stacks of named mark lists

### `app/ViJumpList.h` / `app/ViJumpList.m` — Jump List
- **Class:** `ViJumpList`
- **Purpose:** Ctrl-O (back) and Ctrl-I (forward) navigation history
- **Key methods:** `-push:`, `-forward`, `-backwardFrom:`

---

## Document & Window Layer

### `app/ViDocument.h` / `app/ViDocument.m` — Document Model (Semi-protected)
- **Class:** `ViDocument` (NSDocument subclass)
- **Purpose:** Core document managing text storage, views, syntax, marks, folds, undo
- **Key properties:** `_textStorage`, `_views` (NSMutableSet of ViDocumentView), `_bundle`, `_language`, `_theme`, `_syntaxParser`, `_symbols`
- **Key methods:** `-makeView`, `-cloneView:`, `-dispatchSyntaxParserWithRange:`, `-scopeAtLocation:`
- **Multiple views:** One document can appear in multiple splits/tabs

### `app/ViDocumentView.h` / `app/ViDocumentView.m` — Document View
- **Class:** `ViDocumentView` (ViViewController subclass)
- **Purpose:** Single visible representation of a document in a split/tab
- **Contains:** NSScrollView wrapping a ViTextView

### `app/ViDocumentController.h` / `app/ViDocumentController.m` — Document Controller
- **Class:** `ViDocumentController` (NSDocumentController subclass)
- **Purpose:** Manages all open documents; URL→document cache; path normalization

### `app/ViWindowController.h` / `app/ViWindowController.m` — Window Controller
- **Class:** `ViWindowController` (NSWindowController subclass)
- **Purpose:** Main window management — tabs, splits, explorer, symbol list, status bar, ex command line
- **Key outlets:** `tabBar`, `tabView`, `splitView`, `explorerView`, `symbolController`, `messageView`, `statusbar`
- **Key properties:** `_documents`, `_currentView`, `_parser`, `_project`, `_jumpList`, `_baseURL`
- **100+ methods** covering tab/view management, navigation, splits, document lifecycle, ex commands, UI

### `app/ViWindow.h` / `app/ViWindow.m` — Custom Window
- **Class:** `ViWindow` (NSWindow subclass)
- **Purpose:** Posts `ViFirstResponderChangedNotification` on first responder changes

### `app/ViTabController.h` — Tab Controller
- **Class:** `ViTabController`
- **Purpose:** Manages one tab's NSSplitView hierarchy of view controllers
- **Key methods:** `-addView:`, `-splitView:withView:vertically:`, `-detachView:`, `-closeView:`

### `app/ViViewController.h` — View Controller Base
- **Class:** `ViViewController` (NSViewController subclass)
- **Purpose:** Base for any focusable view in a tab (documents, command output)
- **Key properties:** `_tabController`, `_modified`, `_processing`, `innerView`

### `app/ViAppController.h` / `app/ViAppController.m` — App Delegate
- **Class:** `ViAppController`
- **Purpose:** Application delegate; Nu scripting; global field editor; Sparkle updater
- **Key methods:** `-eval:withParser:bindings:error:` (Nu eval), `-showPreferences:`, `-getExStringForCommand:`
- **Depends on:** Nu.h, Sparkle, ViTextView

### `app/main.m` — Entry Point
- **Flow:** `gettimeofday` → `NuInit()` → `NSApplication` → set `ViAppController` as delegate → create `ViDocumentController` → `NSApplicationMain()`

### `app/ViProject.h` / `app/ViProject.m` — Project Model
- **Class:** `ViProject` (NSDocument subclass)
- **Purpose:** Session state (open files, tabs, splits, working directory)

### `app/ViStatusView.h` — Status Bar
- **Classes:** `ViStatusView`, `ViStatusComponent`, `ViStatusLabel`, etc.
- **Purpose:** Pluggable status bar with mode, cursor position, file info components

### `app/ViBgView.h` — Background View
- **Class:** `ViBgView` (NSView subclass)
- **Purpose:** Simple view with configurable background color (used by explorer panel)

### `app/ViRulerView.h` — Ruler View
- **Class:** `ViRulerView` (NSRulerView subclass)
- **Purpose:** Container for line numbers and fold margin
- **Contains:** ViLineNumberView + ViFoldMarginView

### `app/ViLineNumberView.h` / `app/ViLineNumberView.m` — Line Numbers
- **Class:** `ViLineNumberView`
- **Purpose:** Draws line numbers; supports relative numbering; click-to-select lines

### `app/ViFold.h` / `app/ViFold.m` — Code Folding Model
- **Class:** `ViFold`
- **Purpose:** Hierarchical fold tree (parent/child, open/closed state)
- **Notifications:** `ViFoldsChangedNotification`, `ViFoldOpenedNotification`, `ViFoldClosedNotification`

### `app/ViFoldMarginView.h` / `app/ViFoldMarginView.m` — Fold Margin
- **Class:** `ViFoldMarginView`
- **Purpose:** Draws fold +/− indicators; handles click to toggle

### `app/ViCommandOutputController.h` / `app/ViCommandOutputController.m` — Command Output
- **Class:** `ViCommandOutputController` (ViViewController subclass)
- **Purpose:** Displays HTML/text output from ex/bundle commands via ViWebView

### `app/ViWaitProgressUI.h` / `app/ViWaitProgressUI.m` — Progress UI
- **Class:** `ViWaitProgressUI`
- **Purpose:** Programmatic replacement for WaitProgress.xib; creates progress window with cancel button

### `app/ViPathCell.h` / `app/ViPathControl.h` / `app/ViPathComponentCell.h` — Path Bar
- **Purpose:** NSPathControl/NSPathCell subclasses for breadcrumb navigation

### `app/ViToolbarPopUpButtonCell.h` / `app/ViToolbarPopUpButtonCell.m` — Toolbar Button
- **Class:** `ViToolbarPopUpButtonCell`
- **Purpose:** Custom popup button cell for toolbar with image support

---

## Syntax Highlighting & Bundles

### Syntax Highlighting Pipeline

```
Language Grammar (.plist in .tmbundle/Syntaxes/)
  → ViLanguage (load & compile patterns)
  → ViSyntaxParser (match patterns against text)
  → ViSyntaxMatch (individual regex matches)
  → ViScope (scope assignment per character range)
  → scope_selector matching (rank best theme rule)
  → ViTheme (scope → NSAttributedString attributes)
  → NSTextView rendering
```

### `app/ViBundle.h` / `app/ViBundle.m` — Bundle Container
- **Class:** `ViBundle`
- **Purpose:** Manages languages, preferences, commands, snippets from a .tmbundle directory
- **Key methods:** `-initWithDirectory:`, `-loadPluginCode` (Nu), `-setupEnvironment:forTextView:`, `-menuForScope:hasSelection:font:`

### `app/ViBundleItem.h` / `app/ViBundleItem.m` — Bundle Item Base
- **Class:** `ViBundleItem`
- **Purpose:** Base class with UUID, name, scope selector, mode, key equivalent, tab trigger

### `app/ViBundleCommand.h` / `app/ViBundleCommand.m` — Bundle Command
- **Class:** `ViBundleCommand` (ViBundleItem subclass)
- **Purpose:** Executable command with input/output/fallback configuration

### `app/ViBundleSnippet.h` / `app/ViBundleSnippet.m` — Bundle Snippet
- **Class:** `ViBundleSnippet` (ViBundleItem subclass)
- **Purpose:** Text snippet/template with content string

### `app/ViBundleStore.h` / `app/ViBundleStore.m` — Bundle Registry
- **Class:** `ViBundleStore` (singleton)
- **Purpose:** Loads and manages all bundles; language detection by filename/first-line; item lookup by tab trigger or key code
- **Key methods:** `-languageForFilename:`, `-itemsWithTabTrigger:matchingScope:inMode:`

### `app/ViLanguage.h` / `app/ViLanguage.m` — Language Grammar
- **Class:** `ViLanguage`
- **Purpose:** Represents a TextMate syntax grammar with patterns, includes, backreference expansion
- **Key methods:** `-patterns`, `-expandedPatternsForPattern:`, `-compileRegexp:withBackreferencesToRegexp:matchText:`

### `app/ViSyntaxParser.h` / `app/ViSyntaxParser.m` — Syntax Parser
- **Class:** `ViSyntaxParser`
- **Purpose:** Parses text against language grammar; manages multi-line state via continuations
- **Key methods:** `-parseContext:`, `-setContinuation:forLine:`, `-scopesFromMatches:`

### `app/ViSyntaxContext.h` / `app/ViSyntaxContext.m` — Parse Context
- **Class:** `ViSyntaxContext`
- **Purpose:** Container for a single parsing operation (characters, range, line offset)

### `app/ViSyntaxMatch.h` / `app/ViSyntaxMatch.m` — Syntax Match
- **Class:** `ViSyntaxMatch`
- **Purpose:** One pattern match result (begin/end positions, scope, pattern reference)

### `app/ViScope.h` / `app/ViScope.m` — Scope Model
- **Class:** `ViScope`
- **Purpose:** Character range with scope stack (e.g., `source.python string.quoted.double`)
- **Key methods:** `-match:` (test selector, return rank), `-bestMatch:` (highest-ranked selector)

### `app/scope_selector.lemon` / `app/scope_selector.c` / `app/scope_selector.h` — Scope Selector Parser
- **Purpose:** Lemon-generated LALR(1) parser for TextMate scope selector syntax
- **Operators:** `|` (OR), `&` (AND), `-` (except), `,` (composite), `>` (child), `$` (end anchor)
- **Example:** `source.python & meta.function - string`

### `app/NSString-scopeSelector.h` / `app/NSString-scopeSelector.m` — Scope Matching Category
- **Purpose:** `-matchesScopes:` method on NSString; depth-ranked matching (10^18 per depth level)

### `app/ViTheme.h` / `app/ViTheme.m` — Theme Definition
- **Class:** `ViTheme`
- **Purpose:** Loads .tmTheme plists; maps scopes to colors/styles with caching
- **Key methods:** `-attributesForScope:inBundle:`, `-backgroundColor`, `-caretColor`

### `app/ViThemeStore.h` / `app/ViThemeStore.m` — Theme Registry
- **Class:** `ViThemeStore` (singleton)
- **Purpose:** Manages available themes; default theme is "Sunset"
- **Key methods:** `-defaultTheme`, `-themeWithName:`, `-availableThemes`

### `app/ViSymbolController.h` / `app/ViSymbolController.m` — Symbol List
- **Class:** `ViSymbolController`
- **Purpose:** Outline view of language symbols (functions, classes); filter field; auto-highlight current symbol

### `app/ViSymbolTransform.h` / `app/ViSymbolTransform.m` — Symbol Transform
- **Class:** `ViSymbolTransform` (ViTransformer subclass)
- **Purpose:** Sed-like `s/pattern/replacement/flags` transformations on symbol display names

---

## Ex Command System

### `app/ExParser.h` / `app/ExParser.m` — Ex Command Parser
- **Class:** `ExParser` (singleton)
- **Purpose:** Parses ex command strings into ExCommand objects; metacharacter expansion (%, #)

### `app/ExCommand.h` / `app/ExCommand.m` — Ex Command Model
- **Class:** `ExCommand`
- **Purpose:** Parsed ex command with addresses, arguments, flags, patterns, registers, line ranges
- **Flags/Constants:** Derived from nvi (E_C_*, EX_ADDR_*)

### `app/ExAddress.h` / `app/ExAddress.m` — Ex Address
- **Class:** `ExAddress`
- **Purpose:** Line address model (absolute, search pattern, mark, current line, relative offset)

### `app/ExMap.h` / `app/ExMap.m` — Ex Command Registry
- **Purpose:** Maps ex command names to handler definitions with address modes and flags

### `app/ExTextField.h` / `app/ExTextField.m` — Ex Input Field
- **Class:** `ExTextField` (NSTextField subclass)
- **Purpose:** Command-line input at bottom of window for `:` commands

### `app/ExCommandCompletion.h` / `app/ExCommandCompletion.m` — Ex Completion
- **Purpose:** Tab completion for ex commands and their arguments

---

## Completion System

### `app/ViCompletion.h` / `app/ViCompletion.m` — Completion Item
- **Class:** `ViCompletion`
- **Purpose:** Single completion candidate with content, fuzzy match info, score

### `app/ViCompletionController.h` / `app/ViCompletionController.m` — Completion UI
- **Class:** `ViCompletionController` (singleton)
- **Purpose:** Manages completion popup window with filtered table view and keyboard navigation
- **Note:** Programmatically built (replaced CompletionWindow.xib)

### `app/ViCompletionView.h` / `app/ViCompletionView.m` — Completion View
- **Class:** `ViCompletionView`
- **Purpose:** Custom table cell view for completion items

### `app/ViCompletionWindow.h` / `app/ViCompletionWindow.m` — Completion Window
- **Class:** `ViCompletionWindow`
- **Purpose:** Borderless window hosting completion popup

### Completion Providers

| File | Class | Source |
|------|-------|--------|
| `app/ViFileCompletion.h/m` | `ViFileCompletion` | File path completion |
| `app/ViBufferCompletion.h/m` | `ViBufferCompletion` | Words from open buffers |
| `app/ViSyntaxCompletion.h/m` | `ViSyntaxCompletion` | Language keywords |
| `app/ViWordCompletion.h/m` | `ViWordCompletion` | Word completion |
| `app/ViTagsDatabase.h/m` | `ViTagsDatabase` | ctags symbol lookup |

---

## File & URL Handling

### `app/ViURLManager.h` / `app/ViURLManager.m` — URL Handler Registry
- **Class:** `ViURLManager`
- **Purpose:** Central dispatch for URL schemes; FSEvents directory watching
- **Protocol:** `ViURLHandler` (read, write, mkdir, remove, move, stat)

### `app/ViFile.h` / `app/ViFile.m` — File Model
- **Class:** `ViFile`
- **Purpose:** File system object with metadata caching; handles symlinks and aliases

### `app/ViFileExplorer.h` / `app/ViFileExplorer.m` — File Browser
- **Class:** `ViFileExplorer`
- **Purpose:** NSOutlineView file browser with filtering, drag-drop, tree state management

### URL Handlers

| File | Class | Scheme |
|------|-------|--------|
| `app/ViFileURLHandler.h/m` | `ViFileURLHandler` | `file://` |
| `app/ViHTTPURLHandler.h/m` | `ViHTTPURLHandler` | `http://`, `https://` (NSURLSession) |
| `app/ViSFTPURLHandler.h/m` | `ViSFTPURLHandler` | `sftp://` |

### `app/SFTPConnection.h` / `app/SFTPConnection.m` — SFTP Client
- **Class:** `SFTPConnection`
- **Purpose:** SSH2/SFTP protocol implementation for remote file access

### `app/SFTPConnectionPool.h` / `app/SFTPConnectionPool.m` — Connection Pool
- **Class:** `SFTPConnectionPool`
- **Purpose:** Reuses SSH connections to the same host

### `app/TMFileURLProtocol.h` / `app/TMFileURLProtocol.m` — TextMate File Protocol
- **Class:** `TMFileURLProtocol` (NSURLProtocol subclass)
- **Purpose:** Handles `tm-file://` URLs for TextMate bundle resources

### `app/TxmtURLProtocol.h` / `app/TxmtURLProtocol.m` — txmt/vico URL Protocol
- **Class:** `TxmtURLProtocol` (NSURLProtocol subclass)
- **Purpose:** Handles `txmt://` and `vico://` URLs (open file at line)

---

## Preferences

### `app/ViPreferencesController.h` / `app/ViPreferencesController.m` — Preferences Window
- **Class:** `ViPreferencesController` (singleton)
- **Purpose:** Toolbar-based pane switching; manages preference pane registration

### `app/ViPreferencePane.h` / `app/ViPreferencePane.m` — Pane Base Class
- **Class:** `ViPreferencePane`
- **Purpose:** Base class implementing `ViPreferencePane` protocol

### Preference Panes

| File | Class | Purpose |
|------|-------|---------|
| `app/ViPreferencePaneGeneral.h/m` | `ViPreferencePaneGeneral` | General app settings |
| `app/ViPreferencePaneEdit.h/m` | `ViPreferencePaneEdit` | Editor settings, scope-based prefs |
| `app/ViPreferencePaneBundles.h/m` | `ViPreferencePaneBundles` | Bundle management, GitHub download |
| `app/ViPreferencePaneTheme.h/m` | `ViPreferencePaneTheme` | Theme and font selection |
| `app/ViPreferencePaneAdvanced.h/m` | `ViPreferencePaneAdvanced` | Advanced/environment settings |

---

## Vendored Libraries

### `lemon/` — Lemon Parser Generator
- **Files:** `lemon.c`, `lempar.c`
- **Purpose:** LALR(1) parser generator (SQLite-derived); generates `scope_selector.c` from `scope_selector.lemon`
- **Used by:** Scope selector matching system

### `oniguruma/` — Oniguruma Regex Engine
- **Version:** 5.9.2
- **Author:** K. Kosako (2002–2009)
- **Files:** Core engine (`reg*.c`) + 25 character encoding modules (`enc/*.c`)
- **Purpose:** Unicode-aware regex with named captures, lookahead/lookbehind, multi-encoding
- **Used by:** ViRegexp → syntax highlighting, search/replace, snippet transforms

### `json/` — SBJson Library
- **Author:** Stig Brautaset (2009–2011)
- **Files:** `SBJsonParser.h/m`, `SBJsonWriter.h/m`, `SBJsonStream*.h/m`, `SBJsonTokeniser.h/m`, `SBJsonUTF8Stream.h/m`
- **Purpose:** JSON parsing/serialization with streaming support
- **Used by:** Bundle config, vicotool parameter passing, preferences

### `par/` — Par Paragraph Reformatter
- **Version:** 1.52-i18n.3
- **Author:** Adam M. Costello (2001), modified by Jérôme Pouiller
- **Files:** `par.c`, `buffer.c/h`, `charset.c/h`, `reformat.c/h`, `errmsg.c/h`
- **Purpose:** Paragraph wrapping/reformatting with i18n support
- **Used by:** Text formatting commands

### `universalchardet/` — Mozilla Charset Detector
- **License:** MPL 1.1 / GPL 2.0 / LGPL 2.1
- **Files:** `nsUniversalDetector.h`, language models, charset probers
- **Purpose:** Automatic file encoding detection (CJK, Latin, Cyrillic, etc.)
- **Used by:** File open — detects encoding of unknown files

### `nu/` — Nu Language Runtime Scripts
- **Files:** 17 `.nu` files (`nu.nu`, `cocoa.nu`, `coredata.nu`, `console.nu`, `help.nu`, `match.nu`, `menu.nu`, `test.nu`, `template.nu`, etc.)
- **Purpose:** Runtime support for Nu scripting language (Lisp-like, embedded in app)
- **Used by:** Bundle commands, event handlers, key mappings, custom scripting

### `app/Nu.h` / `app/Nu.m` — Nu Language Bridge
- **Key classes:** `NuSymbol`, `NuSymbolTable`, `NuBlock`, `NuParser`
- **Purpose:** Embedded Lisp-like scripting runtime for automation, bundle execution, and extensibility

---

## Build System

### `Makefile`
- **Primary target:** `app` — builds via `xcodebuild -scheme "Vico app"`
- **Test target:** `test` — runs OCUnit tests via xcodebuild
- **Help target:** `help` — converts markdown to HTML via `md2html`, builds help bundle with `hiutil`
- **Debug targets:** `run`, `gdb`, `leaks`, `zombie`
- **Clean targets:** `clean` (broken — undefined vars), `distclean` (removes `build/`)

### `vico.xcodeproj/project.pbxproj`
- **Main target:** "Vico app" — builds Vico.app
- **Test target:** "Tests" — OCUnit test suite
- **CommitWindow target:** Separate helper app
- **Framework deps:** Cocoa, WebKit, AddressBook, Sparkle.framework
- **Deployment target:** macOS 13.0 (Ventura)

### `app/Vico-Info.plist`
- **Bundle ID:** `se.bzero.Vico`
- **Version:** 1.4-alpha
- **Supported file types:** C, ObjC, Python, Ruby, JavaScript, HTML, CSS, JSON, Lua, Perl, PHP, LaTeX, Shell, Markdown, and more
- **URL schemes:** `file://`, `sftp://`, `vico://`

### `Sparkle.framework/` — Auto-Update Framework
- **Version:** Sparkle 2.x (SPU* API)
- **Purpose:** Automatic app updates via appcast.xml feed with DSS1 signature validation

### `appcast.xml.in` — Update Feed Template
- **Purpose:** Template for generating Sparkle update feed (substitution variables for version, URL, signature)

---

## Auxiliary Targets

### `CommitWindow/` — Git Commit Helper App
- **Files:** `CommitWindowController.h/m`, `CWTextView.h/m`, `CommitWindowCommandLine.h/m`, `CXMenuButton.h/m`, `CXShading.h/m`, `CXTextWithButtonStripCell.h/m`, `NSString+StatusString.h/m`, `NSTask+CXAdditions.h/m`, `main.m`
- **Purpose:** Auxiliary app for composing git commit messages from within Vico

### `util/vico.m` — vicotool Command-Line Interface
- **Purpose:** Opens files in Vico from shell; evaluates Nu scripts; passes JSON parameters
- **Flags:** `-e` (eval), `-f` (script file), `-p` (JSON params), `-n` (new window), `-w` (wait), `-r` (runloop)
- **IPC:** Mach service `se.bzero.vico.ipc` via NSXPCConnection
- **Protocols:** `ViShellCommandXPCProtocol`, `ViShellThingXPCProtocol`

### `app/ViXPCProtocols.h` — XPC Protocol Definitions
- **Purpose:** Defines protocols for vicotool ↔ Vico IPC

### `app/ViXPCBackChannelProxy.h` / `app/ViXPCBackChannelProxy.m` — XPC Back Channel
- **Purpose:** Bidirectional communication proxy for vicotool callbacks

### `tests/` — Test Suite
| File | Purpose |
|------|---------|
| `TestExCommand.h/m` | Ex command parser tests |
| `TestKeyCodes.h/m` | Key event handling tests |
| `TestScopeSelectors.h/m` | Scope selector matching tests |
| `TestViMap.h/m` | Key mapping tests |
| `TestViParser.h/m` | Core vi parser tests (19KB, extensive) |
| `TestViSnippet.h/m` | Snippet expansion tests (22KB) |
| `TestViTextStorage.h/m` | Text buffer tests (14KB) |
| `TestViTextView.h/m` | Editor view tests (17KB) |

---

## Resource Directories

### `Bundles/` — Language Bundles (21 .tmbundle directories)
TextMate-compatible bundles providing syntax highlighting, snippets, commands, and preferences:

`vicoapp-ack`, `vicoapp-c`, `vicoapp-css`, `vicoapp-diff`, `vicoapp-html`, `vicoapp-java`, `vicoapp-javascript`, `vicoapp-json`, `vicoapp-lua`, `vicoapp-objective-c`, `vicoapp-perl`, `vicoapp-php`, `vicoapp-python`, `vicoapp-ruby`, `vicoapp-ruby-on-rails`, `vicoapp-shellscript`, `vicoapp-source`, `vicoapp-sql`, `vicoapp-text`, `vicoapp-xml`, `vicoapp-yaml`

Each bundle contains: `Commands/`, `Preferences/`, `Snippets/`, `Syntaxes/`, `Support/`, `info.plist`, optional `main.nu`

### `Themes/` — 23 TextMate Themes (.tmTheme)
Active4D, All Hallow's Eve, Amy, Blackboard, Brilliance Black, Brilliance Dull, Cobalt, Dawn, Eiffel, Espresso Libre, IDLE, iPlastic, LAZY, Mac Classic, MagicWB (Amiga), Pastels on Dark, Slush & Poppies, SpaceCadet, Sunburst, **Sunset** (default), Twilight, Zenburnesque

### `Support/` — Runtime Support
- `bin/` — 11 executables (helper tools)
- `lib/` — 26 libraries (Ruby, Python, Shell, Nu, JSON helpers)
- `css/` — Web preview stylesheets
- `images/` — Support images
- `nibs/` — Legacy NIB files
- `script/` — Build/utility scripts
- `themes/` — HTML output themes (bright, dark, default, halloween, night, shiny)

### `help/` — Built-in Documentation (40+ markdown files)
Topics: basics, movement, delete, change, insert, visual mode, ex commands, searching, scrolling, splits, explorer, symbols, remote files, terminal, and more. Built to HTML via `md2html` script.

### `Images/` — UI Assets
Tab bar icons (Metal theme), code browser icons (class/function/define/module/tag SVGs), action icons, badge icons

### `doc/` — Archived Website
Scraped copy of www.vicoapp.com from Way Back Machine. Contains API docs, help pages, CSS, images.

---

## File Reference

### Objective-C Categories (Foundation/AppKit Extensions)

| File | Category | Purpose |
|------|----------|---------|
| `app/NSArray-patterns.h/m` | `NSArray (patterns)` | Pattern matching on arrays |
| `app/NSCollection-enumeration.h/m` | `NSCollection (enumeration)` | Collection enumeration helpers |
| `app/NSEvent-keyAdditions.h/m` | `NSEvent (keyAdditions)` | Normalized key code from events |
| `app/NSMenu-additions.h/m` | `NSMenu (additions)` | Menu utility methods |
| `app/NSObject+SPInvocationGrabbing.h/m` | `NSObject (SPInvocationGrabbing)` | Invocation forwarding (Spotify-style) |
| `app/NSOutlineView-vimotions.h/m` | `NSOutlineView (vimotions)` | Vi-style navigation in outline views |
| `app/NSScanner-additions.h/m` | `NSScanner (additions)` | Peek, escaped chars, key code parsing |
| `app/NSString-additions.h/m` | `NSString (additions)` | Line counting, key codes, case checks |
| `app/NSString-scopeSelector.h/m` | `NSString (scopeSelector)` | Scope selector matching |
| `app/NSTableView-vimotions.h/m` | `NSTableView (vimotions)` | Vi-style navigation in table views |
| `app/NSTask-streaming.h/m` | `NSTask (streaming)` | Streaming subprocess output |
| `app/NSURL-additions.h/m` | `NSURL (equality)` | URL comparison, prefix matching, symlink resolution |
| `app/NSView-additions.h/m` | `NSView (additions)` | Action targeting, command execution |
| `app/NSWindow-additions.h/m` | `NSWindow (additions)` | Full-screen detection, responder queries |

### Utility Classes

| File | Class | Purpose |
|------|-------|---------|
| `app/ViCommon.h` | (constants) | Editor modes, notifications, attributes, macros |
| `app/logging.h` | (macros) | DEBUG/MEMDEBUG conditional logging |
| `app/ViError.h/m` | `ViError` | NSError factory with domain constants |
| `app/ViEventManager.h/m` | `ViEventManager` | 30+ event types; Nu scripting integration |
| `app/ViTransformer.h/m` | `ViTransformer` | Regex-based text transformation with stats |
| `app/ViTaskRunner.h/m` | `ViTaskRunner` | Async subprocess execution with progress UI |
| `app/ViBufferedStream.h/m` | `ViBufferedStream` | Buffered I/O for network/file streams |
| `app/ViWebView.h/m` | `ViWebView` | WKWebView with Vi key manager integration |
| `app/ViMarkInspector.h/m` | `ViMarkInspector` | Window for browsing/navigating marks |
| `app/ViCharsetDetector.h` | `ViCharsetDetector` | ObjC wrapper for universalchardet |
| `app/GenerateFormData.h/m` | `GenerateFormData` | HTTP multipart form data builder |
| `app/MHTextIconCell.h/m` | `MHTextIconCell` | NSTextFieldCell with icon + modification indicator |
| `app/ViSeparatorCell.h/m` | `ViSeparatorCell` | Separator line cell for outline views |

### Third-Party UI Components

| File | Class | Purpose |
|------|-------|---------|
| `app/PSMTabBarControl.h/m` | `PSMTabBarControl` | Tabbed interface (Positive Spin Media, hacked by Hedenfalk) |
| `app/PSMTabBarCell.h/m` | `PSMTabBarCell` | Individual tab cell |
| `app/PSMMetalTabStyle.h/m` | `PSMMetalTabStyle` | Metal tab appearance |
| `app/PSMTabStyle.h` | `PSMTabStyle` (protocol) | Tab style protocol |
| `app/PSMOverflowPopUpButton.h/m` | `PSMOverflowPopUpButton` | Tab overflow menu |
| `app/PSMRolloverButton.h/m` | `PSMRolloverButton` | Close button with hover |
| `app/PSMTabDragAssistant.h/m` | `PSMTabDragAssistant` | Tab drag-and-drop |
| `app/PSMProgressIndicator.h/m` | `PSMProgressIndicator` | In-tab progress indicator |
| `app/SFBCrashReporter.h/m` | `SFBCrashReporter` | Crash report submission (Stephen F. Booth) |
| `app/SFBCrashReporterWindowController.h/m` | `SFBCrashReporterWindowController` | Crash reporter UI |
| `app/SFBSystemInformation.h/m` | `SFBSystemInformation` | System info for crash reports |

### System Headers

| File | Purpose |
|------|---------|
| `app/sys_queue.h` | BSD queue macros (singly/doubly linked lists, tail queues) |
| `app/sys_tree.h` | BSD tree macros (splay trees, red-black trees) |
| `version.h` | Version string: `1.3.2` |

---

## Key Design Patterns

1. **Singleton pattern** — ViBundleStore, ViThemeStore, ViRegisterManager, ViMarkManager, ViCompletionController, ViPreferencesController, ExParser, ViDocumentController
2. **Document-view separation** — One ViDocument can have N ViDocumentViews across tabs/splits
3. **Protocol-based URL handling** — ViURLHandler protocol with scheme-specific implementations
4. **Scope-based dispatch** — Bundle items, key mappings, and preferences filtered by TextMate scope selectors
5. **Category-heavy extension** — Foundation/AppKit classes extended via Objective-C categories
6. **Nu scripting integration** — Event handlers, bundle commands, and key mappings can be Nu expressions
7. **Deferred/async pattern** — ViDeferred protocol for async operations (file I/O, network)
8. **Hierarchical marks** — ViMarkManager → ViMarkStack → ViMarkList → ViMark
