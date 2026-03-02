# sqlitenote

A TUI for browsing notes stored in a SQLite database, with markdown rendering in the terminal.

Dependencies: `sqlite3`, `gum`, `glow`. Run `./install.sh` to install everything (macOS, Arch, Ubuntu).

Usage: `./notes` (looks for `notes.db` in the same directory) or `./notes /path/to/my.db`.

Modes: text search, tag filtering, selection with `gum filter`, browse with ←→ arrow keys.

Simple SQL schema: `notes`, `tags`, `note_tags` (many-to-many).

Tests: `bats test_notes.bats` (67 tests).
