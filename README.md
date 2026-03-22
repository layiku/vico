<p align="center">
  <img src="Images/vico-logo.png" alt="Vico" width="128" height="128">
</p>

<h1 align="center">Vico</h1>

<p align="center">
  A Vim-like text editor for macOS with TextMate bundle compatibility
</p>

<p align="center">
  <strong>v2.0.0-dev · Originally by Martin Hedenfalk (2008–2012) · Modernized for Xcode 16+ / macOS 13+</strong>
</p>

---

## About

Vico is a programmer's text editor with a strong focus on keyboard control. It uses vi key bindings to let you keep your fingers on the home row and work effectively with your text.

**Key features:**

- **Vi modal editing** — normal, insert, and visual modes with full vi command grammar
- **TextMate bundle support** — syntax highlighting, snippets, and commands for 21 languages
- **Split views** — horizontal and vertical splits with tab support
- **Integrated SFTP** — edit remote files directly over SSH
- **File explorer** — sidebar navigation with filtering
- **Symbol list** — jump to functions, classes, and definitions
- **Fuzzy find** — fast file navigation with fuzzy matching
- **Nu scripting** — embedded Lisp-like language for extensibility
- **ctags support** — jump to definitions, even over SFTP
- **23 color themes** — TextMate-compatible `.tmTheme` files

---

## Architecture

Vico follows a layered architecture with a **protected editor core** that must not be modified:

```
┌──────────────────────────────────────────────────────┐
│                   ViAppController                     │
│               (NSApplication delegate)                │
├──────────────────────────────────────────────────────┤
│  ViWindowController                                  │
│  ├── PSMTabBarControl (tab bar)                      │
│  ├── ViTabController (splits per tab)                │
│  ├── ViFileExplorer (sidebar)                        │
│  ├── ViSymbolController (symbol list)                │
│  └── ViStatusView (status bar)                       │
├──────────────────────────────────────────────────────┤
│  ViDocument ──── ViDocumentView (N views per doc)    │
│  ├── ViTextStorage (buffer, skip-list indexed)       │
│  ├── ViSyntaxParser (TextMate grammar highlighting)  │
│  └── ViFold (code folding tree)                      │
├──────────────────────────────────────────────────────┤
│  Editor Pipeline (protected core):                   │
│  NSEvent → ViKeyManager → ViParser → ViCommand       │
│         → ViTextView → ViTextStorage → ViLayoutManager│
└──────────────────────────────────────────────────────┘
```

### Project Structure

```
vico/
├── app/                  # Main application source (~100 .h/.m files)
│   ├── Vi*.h/m           #   Core editor classes
│   ├── Ex*.h/m           #   Ex command system
│   ├── PSM*.h/m          #   Tab bar component (PSMTabBarControl)
│   ├── SFB*.h/m          #   Crash reporter (SFBCrashReporter)
│   ├── SFTP*.h/m         #   SFTP client
│   ├── NS*-additions.h/m #   Foundation/AppKit categories
│   ├── scope_selector.*  #   Lemon-generated scope selector parser
│   └── Nu.h/m            #   Embedded Nu scripting runtime
├── Bundles/              # 21 TextMate-compatible language bundles
├── Themes/               # 23 .tmTheme color themes
├── Support/              # Runtime libraries (Ruby, Python, Shell, Nu)
├── help/                 # Built-in documentation (40+ markdown files)
├── lemon/                # Lemon parser generator (builds scope_selector.c)
├── oniguruma/            # Oniguruma 5.9.2 regex engine (25 encodings)
├── json/                 # SBJson library
├── par/                  # Par paragraph reformatter (i18n)
├── universalchardet/     # Mozilla charset detector
├── nu/                   # Nu language runtime scripts
├── CommitWindow/         # Git commit helper app
├── util/                 # vicotool CLI (XPC bridge to editor)
├── tests/                # OCUnit test suite (8 test files)
├── Images/               # UI assets (icons, tab bar graphics)
├── doc/                  # Archived vicoapp.com website
├── Sparkle.framework/    # Sparkle 2.x auto-update framework
├── Makefile              # Build orchestration
└── vico.xcodeproj/       # Xcode project (primary build system)
```

### Key Subsystems

| Subsystem | Key Classes | Description |
|-----------|-------------|-------------|
| **Editor Core** | `ViParser`, `ViCommand`, `ViTextStorage`, `ViTextView`, `ViKeyManager` | Vi state machine, command execution, buffer mutations |
| **Layout** | `ViLayoutManager`, `ViTypesetter`, `ViGlyphGenerator` | Text rendering, invisible chars, code folding display |
| **Document** | `ViDocument`, `ViDocumentView`, `ViDocumentController` | NSDocument model; one doc → N views |
| **Window** | `ViWindowController`, `ViTabController`, `ViViewController` | Tabs, splits, view lifecycle |
| **Syntax** | `ViSyntaxParser`, `ViLanguage`, `ViScope`, `ViTheme` | TextMate grammar parsing, scope matching, theming |
| **Bundles** | `ViBundleStore`, `ViBundle`, `ViBundleCommand`, `ViBundleSnippet` | TextMate bundle loading, command/snippet execution |
| **Completion** | `ViCompletionController`, `ViFileCompletion`, `ViBufferCompletion`, `ViTagsDatabase` | Multi-source completion popup |
| **Ex Commands** | `ExParser`, `ExCommand`, `ExAddress`, `ExMap` | Ex command line parsing and dispatch |
| **File I/O** | `ViURLManager`, `ViFileURLHandler`, `ViHTTPURLHandler`, `ViSFTPURLHandler` | URL scheme-based file operations |
| **Scripting** | `Nu.h`, `ViEventManager`, `vicotool` (util/) | Nu language runtime, 30+ event types, CLI↔app XPC |

For a full file-by-file reference, see [vico-architect.md](vico-architect.md).

---

## Modernization

This fork restores Vico to build and run on **Xcode 16+ / macOS 13+ (Ventura and later)**, including Apple Silicon. The modernization was completed across 15 phases, fixing ~300+ warnings without changing the editor's core behavior.

### What Was Done

| Phase | Summary |
|-------|---------|
| **1** | Raised deployment target to macOS 13.0; upgraded XIB formats; replaced OpenSSL with CommonCrypto; fixed `ffi_closure` for Apple Silicon W^X |
| **2** | Renamed 50+ deprecated AppKit/Foundation constants (`NSShiftKeyMask` → `NSEventModifierFlagShift`, etc.) across 37 files |
| **2.1–2.3** | Fixed IMP casting, K&R→ANSI C prototypes, undeclared selectors, informal→formal protocols, type mismatches, implicit self-capture |
| **3** | Migrated `NSURLConnection` → `NSURLSession` (data tasks, download tasks, chunk-streaming, cancel guards) |
| **4a** | Migrated `NSConnection` → `NSXPCConnection` for vicotool↔editor IPC with bidirectional protocol design |
| **6** | Upgraded Sparkle 1.x subproject → Sparkle 2.x prebuilt framework; rewired pbxproj |
| **7** | Eliminated `performSelector` ARC warnings with IMP casting; fixed all remaining compiler warnings |
| **8** | Committed Lemon-generated `scope_selector.c` directly (removed build-time generation dependency) |
| **9–10** | Migrated 14 XIB files to programmatic AppKit code (preferences, completion, command output, crash reporter, mark inspector, main menu, document window) |
| **11** | Converted `openDocumentWithContentsOfURL:display:error:` to async completion handler API |
| **12** | Converted `saveToURL:ofType:forSaveOperation:error:` to async completion handler API |
| **13–14** | Removed `NSMainNibFile` from Info.plist; built entire main menu and document window in code |
| **15** | Replaced `-lcrypto` linker flag with CommonCrypto (removed last OpenSSL dependency) |

For full details, see [CHANGELOG.md](CHANGELOG.md).

### Modernization Principles

- **Never suppress warnings** — always find the real fix, no `#pragma clang diagnostic ignored`
- **Migrate incrementally** — one file at a time, keep the build green after every change
- **Preserve callbacks** — new async APIs call the same delegate methods as the old sync versions
- **Respect the architecture** — UI shell changes are safe; core editor logic is not touched
- **Verify with clean build** — `xcodebuild` after every batch of changes

The lessons learned from this modernization are documented in a reusable Claude Code skill: [modernize-legacy-cocoa](https://github.com/layiku/modernize-legacy-cocoa).

---

## Building

### Prerequisites

- **Xcode 16+** (with macOS 13+ SDK)
- **macOS 13.0 (Ventura)** or later
- Apple Silicon (arm64) or Intel (x86_64)

### Build & Run

```sh
# Clone with submodules
git clone --recursive https://github.com/vicoapp/vico.git
cd vico

# Build and launch
make run

# Or build via Xcode
open vico.xcodeproj
# Select "Vico app" scheme → Build & Run
```

### Other Targets

```sh
make app          # Build only
make test         # Run test suite
make help         # Build help documentation
make distclean    # Remove build artifacts
```

---

## Contributing

Contributions from the community are encouraged.

1. Fork the `vico` repository on GitHub.
2. Clone your fork:
   ```sh
   git clone git@github.com:yourusername/vico.git
   ```
3. Create a topic branch:
   ```sh
   git checkout -b some-topic-branch
   ```
4. Make your changes and commit. Use a clear commit message with a short summary (~60 chars) on the first line, followed by a blank line and detailed explanation wrapped to ~72 chars.
5. Push and open a pull request:
   ```sh
   git push origin some-topic-branch
   ```

### Protected Modules

The following modules must not be modified without explicit approval — they form the editor pipeline:

- `ViParser`, `ViCommand`, `ViBuffer`, `ViEditor`, `ViLayoutManager`, `ViTextStorage`

Semi-protected (require careful review): `ViTextView`, `ViDocument`, `ViCommandLine`

---

## License

Vico is Copyright (c) 2008-2012, Martin Hedenfalk <martin@vicoapp.com>
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

See each individual file for their respective license.
