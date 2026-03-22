# How Vico Works

A deep dive into how Vico — a Vim-like macOS text editor — works from launch to keystroke to screen.

---

## 1. Launch Sequence

When you double-click Vico.app, execution starts in `app/main.m`:

```
1. Record launch time (gettimeofday)
2. Initialize Nu scripting runtime (NuInit)
3. Create NSApplication singleton
4. Create ViAppController, set as app delegate
5. Create ViDocumentController (becomes shared singleton)
6. Enter NSApplicationMain() — starts the run loop
```

The app delegate (`ViAppController`) handles global state: the Nu scripting interpreter, Sparkle auto-updater, keyboard input source tracking, and the shared field editor for ex command input.

`ViDocumentController` subclasses `NSDocumentController` and manages all open documents, maintaining a URL→document cache for fast lookup.

On first launch, `ViBundleStore` scans the `Bundles/` directory and `~/Library/Application Support/Vico/Bundles/` for TextMate-compatible `.tmbundle` directories, loading their languages, commands, snippets, and preferences.

---

## 2. Opening a Document

When you open a file (via menu, ex command `:e filename`, or `vicotool`):

```
ViDocumentController
  → checks URL cache (already open? reuse it)
  → creates ViDocument (NSDocument subclass)
  → ViDocument loads file data into ViTextStorage
  → universalchardet auto-detects encoding if unknown
  → ViBundleStore selects language by filename or first line
  → ViSyntaxParser begins highlighting
  → ViDocument creates a ViDocumentView
  → ViDocumentView is placed in the window's tab/split hierarchy
```

### ViTextStorage — The Buffer

`ViTextStorage` is a custom `NSTextStorage` subclass — the actual text buffer. It stores the document's characters and provides fast line-based access using a **skip list** data structure, giving O(log n) performance for:

- Finding the start of line N
- Finding which line a character offset belongs to
- Counting total lines

This is critical for large files where naive line scanning would be too slow.

### One Document, Many Views

A single `ViDocument` can appear in multiple splits or tabs simultaneously. Each appearance is a `ViDocumentView` containing its own `NSScrollView` and `ViTextView`. All views share the same `ViTextStorage` — edits in one view instantly appear in all others.

---

## 3. The Window Layout

Each window is managed by `ViWindowController` and organized as:

```
┌─────────────────────────────────────────────────┐
│  Toolbar                                        │
├──────┬───────────────────────────────┬──────────┤
│      │  Tab Bar (PSMTabBarControl)   │          │
│      ├───────────────────────────────┤          │
│ File │                               │ Symbol   │
│ Exp- │  Editor Area                  │ List     │
│ lorer│  (ViTabController manages     │          │
│      │   splits within each tab)     │          │
│      │                               │          │
│      │  ┌────────────┬──────────┐   │          │
│      │  │ Split A    │ Split B  │   │          │
│      │  │ (ViDoc-    │ (ViDoc-  │   │          │
│      │  │  umentView)│  umentView│  │          │
│      │  └────────────┴──────────┘   │          │
├──────┴───────────────────────────────┴──────────┤
│  Status Bar (ViStatusView) + Ex Command Line    │
└─────────────────────────────────────────────────┘
```

- **PSMTabBarControl** — third-party tab bar with drag-and-drop, overflow menu
- **ViTabController** — manages one tab's `NSSplitView` tree (nested horizontal/vertical splits)
- **ViViewController** — base class for anything that can live in a tab (documents, command output)
- **ViFileExplorer** — sidebar with `NSOutlineView` file tree, filtering, vi-style navigation
- **ViSymbolController** — sidebar listing functions/classes from the current document
- **ViStatusView** — pluggable status bar showing mode, cursor position, file info

---

## 4. The Editor Pipeline — From Keystroke to Screen

This is the heart of Vico. When you press a key:

### Step 1: Key Event → ViKeyManager

macOS delivers an `NSEvent` to the focused `ViTextView`. The text view forwards it to its `ViKeyManager`:

```objc
- (void)keyDown:(NSEvent *)event {
    [keyManager keyDown:event];
}
```

`ViKeyManager` normalizes the key event (handling modifiers, special keys via `NSEvent-keyAdditions`) and passes the key code to the parser. It also handles **macro recording** — if recording is active, the key is appended to the macro register.

### Step 2: ViKeyManager → ViParser (State Machine)

`ViParser` implements the vi command grammar as a state machine with 6 states:

```
  initial
    │
    ├─ [count] ──→ (accumulate digits)
    ├─ ["] ──→ needRegister ──→ [a-z] ──→ back to initial
    ├─ [d,c,y,>...] ──→ needMotion (operator entered)
    │                      ├─ [count]
    │                      ├─ [w,e,b,f...] ──→ COMPLETE
    │                      └─ [same operator] ──→ line mode COMPLETE
    ├─ [w,e,b,0,$...] ──→ COMPLETE (motion only)
    ├─ [f,t,r...] ──→ needChar ──→ [any] ──→ COMPLETE
    └─ [i,a,o...] ──→ switch to insert mode
```

For example, typing `"ad2w`:
1. `"` → state: needRegister
2. `a` → register set to 'a', state: initial
3. `d` → state: needMotion (operator = delete)
4. `2` → count = 2
5. `w` → motion = word → **COMPLETE**

The parser also consults `ViMap` for key mappings. Maps can be scope-aware (only active in certain syntax scopes) and recursive (one mapping can trigger another).

### Step 3: ViParser → ViCommand

When the parser recognizes a complete command, it creates a `ViCommand` object bundling:

- **action** — the selector to call (e.g., `delete:`)
- **motion** — a nested ViCommand for the motion part (e.g., `move_word_forward:`)
- **count** — repeat count
- **register** — which register to use ('a'–'z', '"', '+', etc.)
- **argument** — character argument (for `f`, `t`, `r` commands)
- **isLineMode** — whether the command operates on whole lines
- **range** — computed character range (filled in during execution)

### Step 4: ViCommand → ViTextView (Execution)

The command is executed on the `ViTextView` via Objective-C message dispatch:

```objc
[command performWithTarget:textView];
```

This calls the appropriate method in one of ViTextView's category files:

| Category File | Commands |
|---------------|----------|
| `ViTextView-vi_commands.m` | `move_left:`, `delete:`, `yank:`, `shift_right:`, `visual:`, `paste:`, ... |
| `ViTextView-ex_commands.m` | `:s`, `:g`, address resolution, line range operations |
| `ViTextView-snippets.m` | snippet insertion, tabstop navigation |
| `ViTextView-bundle_commands.m` | TextMate bundle command execution |

**Operator-motion composition:**

For operator commands like `d2w` (delete 2 words), execution works in two phases:

1. Execute the **motion** (`move_word_forward:`) to compute the affected range
2. Execute the **operator** (`delete:`) on that range

The motion sets `command.range`; the operator acts on it.

### Step 5: ViTextStorage (Buffer Mutation)

The actual text change happens through `ViTextStorage`:

```objc
[textStorage replaceCharactersInRange:range withString:replacement];
```

This triggers:
- Skip list update (line index recalculation)
- `NSTextStorageDelegate` notification to `ViDocument`
- Undo manager registration
- Syntax parser invalidation for the changed range

### Step 6: ViLayoutManager → Screen

After the text storage changes, the Cocoa text system's layout pipeline kicks in:

```
ViTextStorage (text changed notification)
  → ViLayoutManager (invalidates layout for changed range)
  → ViGlyphGenerator (produces glyphs; null glyphs for folded regions)
  → ViTypesetter (computes glyph positions; zero advancement for folds)
  → ViLayoutManager draws:
      - Normal text glyphs
      - Invisible characters (⇥ for tabs, ･ for spaces, ↩ for newlines)
      - Syntax-colored attributes from ViTheme
  → ViTextView draws:
      - Block cursor (vi-style, not I-beam)
      - Line highlight
      - Visual selection
  → ViLineNumberView redraws line numbers
  → ViFoldMarginView redraws fold indicators
```

---

## 5. Modes

Vico implements three vi modes:

### Normal Mode (default)
- Keys are interpreted as commands by `ViParser`
- Block cursor displayed
- `ViMap.normalMap` is active

### Insert Mode
- Entered via `i`, `a`, `o`, `c`, etc.
- Keys are inserted as text (except Escape → back to normal)
- `ViMap.insertMap` is active (for mapped insert-mode shortcuts)
- Thin cursor displayed

### Visual Mode
- Entered via `v` (character), `V` (line), `Ctrl-V` (block)
- Motion commands extend the selection
- Operators act on the selection
- `ViMap.visualMap` is active

Mode changes update `ViStatusView` and cursor appearance.

---

## 6. Syntax Highlighting

Vico uses TextMate-compatible grammars for syntax highlighting:

### The Pipeline

```
Source Text
  → ViSyntaxParser (regex matching against language patterns)
  → ViScope (scope stack per character range)
  → ViTheme (scope → colors/styles via scope selector ranking)
  → NSAttributedString attributes on ViTextStorage
  → Rendered by ViLayoutManager
```

### How It Works

1. **Language grammars** are plists in `.tmbundle/Syntaxes/` directories. Each grammar defines:
   - `match` patterns — single-line regex (e.g., `//.*$` for comments)
   - `begin`/`end` patterns — multi-line spans (e.g., `/*` ... `*/`)
   - `include` directives — reference other grammars or pattern groups

2. **ViSyntaxParser** processes text line by line:
   - Matches all patterns against each line
   - For `begin`/`end` patterns, tracks **continuations** across lines
   - Assigns a **scope stack** to each character range
   - Example: `source.python meta.function.python entity.name.function.python`

3. **Scope matching** determines which theme rule applies:
   - Theme rules have scope selectors like `string.quoted` or `keyword.control`
   - The selector parser (generated by Lemon from `scope_selector.lemon`) supports operators: `|` (OR), `&` (AND), `-` (except), `>` (child)
   - Matching is **ranked** — more specific matches win (depth-based scoring at 10^18 per depth level)

4. **ViTheme** caches scope→attribute mappings for performance

### Incremental Parsing

When you edit text, only the affected lines are re-parsed:

```
Edit at line 50
  → ViDocument dispatches syntax parser for affected range
  → Parser checks continuations (did a multi-line string/comment change?)
  → If continuations changed, parsing extends to subsequent lines
  → Updated scopes applied as text attributes
  → ViLayoutManager invalidates and redraws
```

---

## 7. TextMate Bundles

Bundles provide language-specific functionality beyond syntax highlighting:

### Bundle Structure
```
language.tmbundle/
├── Syntaxes/       → Language grammars (.plist)
├── Snippets/       → Text templates with tabstops
├── Commands/       → Shell scripts, Nu expressions
├── Preferences/    → Smart typing pairs, indentation rules, comment markers
├── Support/        → Helper scripts
├── main.nu         → Optional Nu plugin code
└── info.plist      → Bundle metadata
```

### Snippets

Snippets are templates with **tab triggers** and **tabstops**:

```
Trigger: "for" + Tab
Template: for (${1:i} = ${2:0}; $1 < ${3:count}; $1++) {
              $0
          }
```

`ViSnippet` manages the active snippet:
- Tracks tabstop positions and mirrors ($1 appears twice — editing one updates both)
- Supports regex transformations on tabstop values
- Supports shell command interpolation
- Tab key advances to next tabstop; Escape exits snippet mode

### Commands

Bundle commands execute shell scripts with environment variables set by `ViBundle.setupEnvironment:forTextView:`:

- `TM_CURRENT_LINE`, `TM_LINE_INDEX`, `TM_SCOPE`
- `TM_SELECTED_TEXT`, `TM_FILEPATH`, `TM_DIRECTORY`

Input can be: selection, document, line, word, or nothing.
Output can be: insert as text, insert as snippet, replace selection, show as HTML, show as tooltip, or create new document.

`ViTaskRunner` handles async execution with progress UI and cancellation.

---

## 8. Ex Commands

The ex command line (`:` in normal mode) provides a second command interface:

```
User types ":"
  → ViWindowController shows ExTextField at bottom of window
  → User types command (e.g., "1,5s/foo/bar/g")
  → ExParser parses into ExCommand:
      addresses: [1, 5]  (line range)
      command: "s"        (substitute)
      pattern: "foo"
      replacement: "bar"
      flags: "g"          (global)
  → ViTextView resolves addresses to character ranges
  → Executes substitution via ViRegexp + ViTextStorage
```

### Address Types
- Absolute: `42` (line 42)
- Current: `.` (current line)
- Last: `$` (last line)
- Search: `/pattern/` (next match), `?pattern?` (previous match)
- Mark: `'a` (line of mark a)
- Relative: `+5`, `-3`
- Combined: `.,+10` (current line to 10 lines below)

### Key Ex Commands
- `:e file` — open file
- `:w` — save
- `:s/pat/repl/flags` — substitute
- `:g/pat/cmd` — global command
- `:split`, `:vsplit` — create splits
- `:tabedit` — open in new tab
- `:set option=value` — change settings
- `:map keys action` — create key mapping

---

## 9. Completion

Vico provides context-aware completion from multiple sources:

```
Ctrl-P / Ctrl-N (or configured trigger)
  → ViCompletionController collects candidates from:
      ├── ViBufferCompletion (words from open documents)
      ├── ViSyntaxCompletion (language keywords)
      ├── ViFileCompletion (file paths)
      ├── ViWordCompletion (current buffer words)
      └── ViTagsDatabase (ctags symbols)
  → Candidates scored by fuzzy match quality
  → Displayed in popup window (ViCompletionWindow)
  → User navigates with Ctrl-N/Ctrl-P, confirms with Tab/Enter
```

The completion popup is built programmatically (no XIB) and positions itself near the cursor.

---

## 10. Remote File Editing (SFTP)

Vico can edit files over SSH:

```
:e sftp://user@host/path/to/file
  → ViURLManager dispatches to ViSFTPURLHandler
  → ViSFTPURLHandler asks SFTPConnectionPool for a connection
  → SFTPConnectionPool reuses existing SSH connection or creates new one
  → SFTPConnection implements SSH2/SFTP protocol:
      SSH handshake → auth → SFTP subsystem → file read
  → File contents loaded into ViDocument
  → :w saves back via the same SFTP connection
```

The `ViURLManager` provides a unified `ViURLHandler` protocol for all file operations (read, write, mkdir, remove, move, stat), abstracting the underlying transport. `ViFileExplorer` uses the same protocol to browse remote directories.

---

## 11. Nu Scripting

Nu is an embedded Lisp-like language providing extensibility:

```nu
; Example: bind Cmd-Shift-L to select current line
(map "<C-S-l>" (do ()
    (set view (current-view))
    (view selectLine)))
```

Nu is used for:
- **Bundle plugins** — `main.nu` files in bundles execute at load time
- **Key mappings** — map keys to Nu expressions instead of built-in commands
- **Event handlers** — `ViEventManager` dispatches 30+ event types to Nu blocks
- **Status bar** — custom status components via Nu blocks
- **vicotool** — evaluate Nu scripts from the command line (`vico -e '(expression)'`)

The Nu runtime (`Nu.h/Nu.m`) provides the bridge between Objective-C and Nu, with full access to Cocoa APIs.

---

## 12. vicotool — CLI Integration

The `util/vico.m` command-line tool communicates with the running Vico app via XPC (Mach service `se.bzero.vico.ipc`):

```sh
vico file.txt            # Open file
vico -l 42 file.txt      # Open at line 42
vico -e '(expression)'   # Evaluate Nu expression
vico -f script.nu        # Run Nu script file
vico -w file.txt         # Open and wait for close
vico -p '{"key":"val"}'  # Pass JSON parameters to script
```

The XPC communication uses two protocols:
- `ViShellCommandXPCProtocol` — Vico→vicotool (commands)
- `ViShellThingXPCProtocol` — vicotool→Vico (callbacks)

`ViXPCBackChannelProxy` enables bidirectional communication so running scripts can call back to the CLI.

---

## 13. Code Folding

Vico supports code folding with a hierarchical model:

```
ViFold tree:
  ├── Function A (lines 10-50)
  │   ├── If block (lines 15-25)
  │   └── For loop (lines 30-45)
  └── Function B (lines 55-80)
```

- `ViFold` objects form a parent-child tree
- Folding/unfolding posts notifications (`ViFoldsChangedNotification`)
- `ViGlyphGenerator` produces null glyphs for folded ranges
- `ViTypesetter` gives zero advancement to folded glyphs
- `ViFoldMarginView` draws +/− indicators in the ruler
- Click a fold indicator to toggle

---

## 14. Registers and Marks

### Registers (Yank/Paste Buffers)

`ViRegisterManager` manages named registers:

| Register | Purpose |
|----------|---------|
| `"` | Default (unnamed) — last delete/yank |
| `a`–`z` | Named registers (lowercase = replace, uppercase = append) |
| `+`, `*` | System clipboard |
| `/` | Last search pattern |
| `:` | Last ex command |
| `%` | Current filename |
| `#` | Alternate filename |
| `_` | Black hole (discard) |

Usage: `"ayw` = yank word into register 'a', `"ap` = paste from register 'a'.

### Marks (Named Positions)

`ViMarkManager` organizes marks hierarchically:

```
ViMarkManager (singleton)
  └── ViMarkStack (named collection, e.g., "bookmarks")
      └── ViMarkList (ordered list)
          └── ViMark (name + line + column + URL)
```

- `ma` = set mark 'a' at cursor
- `` `a `` = jump to mark 'a'
- `ViJumpList` tracks Ctrl-O / Ctrl-I navigation history (automatic marks)

---

## 15. Undo/Redo

Vico uses Cocoa's `NSUndoManager` with vi-aware grouping:

- `ViDocument.beginUndoGroup` / `endUndoGroup` bracket compound operations
- An entire insert mode session (from `i` to `Escape`) is one undo group
- Operator commands (`d`, `c`, `>`, etc.) are each one undo group
- `u` undoes one group, `Ctrl-R` redoes
- Supports nvi-style undo (configurable via `nviStyleUndo`)

---

## Summary: The Complete Keystroke Journey

```
You press "d2w" in normal mode:

1. macOS NSEvent → ViTextView.keyDown:
2. → ViKeyManager.keyDown: (check macros, normalize key)
3. → ViParser.pushKey:'d' (state → needMotion, operator = delete)
4. → ViParser.pushKey:'2' (count = 2)
5. → ViParser.pushKey:'w' (motion = word_forward → COMPLETE)
6. → ViCommand created: {action=delete, motion=word_forward, count=2}
7. → ViTextView.delete: called
8.   → ViTextView.move_word_forward: executed (computes range for 2 words)
9.   → Deleted text saved to register '"'
10.  → ViTextStorage.replaceCharactersInRange:withString:@""
11.  → NSUndoManager records inverse operation
12.  → ViSyntaxParser re-parses affected lines
13.  → ViLayoutManager invalidates layout
14.  → ViGlyphGenerator + ViTypesetter recompute
15.  → Screen redraws with updated text, cursor, line numbers
16. → Command saved as dot command (press '.' to repeat)
```

Every keystroke flows through this same pipeline — consistent, composable, and fast.
