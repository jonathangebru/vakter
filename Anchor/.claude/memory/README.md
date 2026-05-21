# Vakter team memory

Owned and edited by `vakter-memory-keeper` only. Every other agent reads from here as preamble; only memory-keeper writes.

## Purpose

Stop the team from re-discovering the same problem twice. Every durable lesson — a SwiftPM quirk, an Apple API rename, a codesign footgun, a brand voice pitfall — lives here as a short, structured note.

## Layout

```
.claude/memory/
├── INDEX.md                            ← entry point; sorted by category + severity
├── build/                              ← swift build, SPM, target structure
├── codesign/                           ← codesign, --remove-signature, entitlements
├── notarize/                           ← xcrun notarytool, staple, spctl
├── macos-api/                          ← Apple API renames, behaviour drift across versions
├── xpc/                                ← NSXPC, peer pinning, listener lifetime
├── bluetooth/                          ← CoreBluetooth quirks
├── cloudkit/                           ← CKContainer, entitlement probes, schema deploys
├── ui/                                 ← SwiftUI/AppKit hybrid gotchas
├── brand/                              ← editorial voice, palette, type-stack
├── strategy/                           ← strategic lessons (rare; most go to .claude/strategy/)
├── security/                           ← threat-modelling decisions, advisory impact notes
│   └── private/                        ← exploit details that need human-gate before public ref
├── release/                            ← end-to-end ship lessons (combine sign + notarize + swap)
└── should-fix/                         ← memory-keeper's flagged code fixes; PO files them as tickets
```

## Note format

Every note is a Markdown file matching this schema (memory-keeper enforces):

```markdown
# <Short imperative title>

**Category:** <one of the directory names>
**Severity:** critical | high | medium | low
**First seen:** YYYY-MM-DD (commit/PR if known)
**Last reinforced:** YYYY-MM-DD

## Symptom
## Root cause
## Fix
## How to detect it next time
## Related
- `path/to/file.swift:LINE`
- Ticket: #N
```

## Read order for other agents

Every agent's system prompt says: read `.claude/memory/INDEX.md` first, then read notes in any categories relevant to the current task. The index keeps the load proportional to the task, not the entire corpus.

## Pruning policy

Notes are never deleted. If a lesson is obsoleted by an API change or a refactor, memory-keeper marks it `superseded` at the top with a forward link. The historical record matters.
