# PO inbox

The product-owner's queue. Files dropped here become GitHub Project tickets on the next dispatcher cycle.

## Who drops files here

- **`vakter-product-strategist`** — most common. Drops directives after writing a strategy memo.
- **The human** — occasionally. You can manually create a directive when you want the team to file work without going through strategist.
- **`vakter-security-watcher`** — drops directives for security findings that warrant tickets.
- **`vakter-memory-keeper`** — drops `_should-fix.md` notes that need to be filed as bug tickets.

## What the file looks like

Numeric prefix + slug. Use the next available 4-digit number.

```
.claude/inbox/po/NNNN-<slug>.md
```

Example body:

```markdown
# <Directive title>

**Strategy memo:** .claude/strategy/YYYY-MM-DD-<slug>.md
**Priority:** p0 | p1 | p2
**Estimated complexity:** small | medium | large

## Epic title for the board
## Goal
## Acceptance criteria (epic-level)
## Suggested Features for PO to file
## Anti-scope
## Reading priority for PO
```

## Lifecycle

```
.claude/inbox/po/NNNN-foo.md                ← strategist or human creates
    │
    │ (dispatcher cycle picks it up)
    ▼
vakter-product-owner reads, files GitHub Issues
    │
    ▼
.claude/inbox/po/consumed/NNNN-foo.md       ← PO moves it here after processing
```

## Consumed files

`consumed/` keeps the historical record of every directive that's ever been processed. Never delete — provides audit trail. PO is the only agent that writes to `consumed/`.

## Don't put here

- Code (PO doesn't write code).
- Marketing copy (brand-keeper writes that).
- Memory notes (memory-keeper writes those).
- Strategy memos (those go in `.claude/strategy/`).
- README updates (this file is hand-written by the human; agents don't auto-edit it).
