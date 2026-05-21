# Vakter strategy memos

Owned by `vakter-product-strategist`. Other agents read but don't write here (with one exception: `vakter-product-owner` writes weekly board audits, and `vakter-security-watcher` writes advisory notes + defenses-verification reports).

## Purpose

Capture *decisions* — what we're doing, what we're not doing, why, and what changed. Distinct from `BACKLOG.md` (running queue of items) and `.claude/memory/` (durable footgun knowledge). This directory is where the team's strategic arc lives in writing.

## Layout

```
.claude/strategy/
├── README.md                           ← this file
├── idle-log.md                         ← strategist's autonomous-mode "nothing pressing" notes
├── YYYY-MM-DD-<slug>.md                ← strategy memos (one per decision)
├── apple-advisory-<CVE>.md             ← security-watcher's Apple advisory triage
├── defenses-verification-YYYY-MM-DD.md ← security-watcher's probe verification reports
├── board-audit-YYYY-MM-DD.md           ← product-owner's weekly board health checks
├── disclosure-<date>.md                ← security-watcher's response drafts to disclosure intake
└── launch/
    ├── product-hunt-<date>.md          ← brand-keeper's Product Hunt launch draft
    ├── show-hn-<date>.md               ← brand-keeper's HN launch draft
    ├── twitter-thread-<date>.md
    └── press-pitch-<date>.md
```

## Memo format (strategist)

```markdown
# <Headline: the move>

**Date:** YYYY-MM-DD
**Mode:** directed | autonomous
**Confidence:** high | medium | low
**Estimated effort:** <hours or t-shirt size>
**Estimated leverage:** <causal chain to 10K units by Q3>

## Context
## Recommendation
## Risks
## Out of scope
## Directive (if action)
Linked file: .claude/inbox/po/NNNN-<slug>.md
```

## Idle log format (strategist autonomous mode)

A single running file `idle-log.md` appended-to each idle invocation:

```markdown
YYYY-MM-DD HH:MM — idle. Reason: <one line>. Backlog depth: N. Board: M open tickets.
```

## Read order for other agents

Agents touching strategy read in this priority:
1. `STRATEGY.md` at repo root (north star)
2. `.claude/strategy/` last 4 memos
3. `BACKLOG.md`
4. `.claude/memory/INDEX.md`

## What does NOT live here

- Decisions to ship a specific PR — those go on the GitHub ticket.
- Implementation details — those go in code or commit messages.
- Brand voice rules — those go in `.claude/memory/brand/`.
- Day-to-day footgun notes — those go in `.claude/memory/`.
