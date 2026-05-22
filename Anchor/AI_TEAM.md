# Vakter — the AI team

> _The cast of agents that builds, ships, and watches over this product. Calm in normal use, fierce against any threat — same posture as Vakter itself._

This file exists so a fresh reader (a future contributor, an auditor, or future-you in six weeks) can understand how Vakter is operated by an AI team in roughly five minutes. It's the playbook. The agents are the cast.

## The cast

Seven agents, project-scoped, defined as Markdown files in `.claude/agents/`. Each one has a focused job, a short list of tools, and a hard constraint on what it must **not** do.

| Agent | Color | Role in one line | Does | Does NOT |
|---|---|---|---|---|
| `vakter-memory-keeper` | purple | The hippocampus | Distills lessons to `.claude/memory/` after every closed ticket so the team doesn't re-discover the same footguns. | Touch product code, post anywhere, delete old notes. |
| `vakter-mac-engineer` | blue | The implementer | Writes every line of code that ships — macOS app, helper, daemon, iOS / Watch companions, build scripts. | Sign, notarize, ship, merge. Edit `.claude/`. |
| `vakter-release-warden` | orange | The ship gate | Adversarial to the engineer. Runs the full ship cycle (test → build → sign → notarize → staple → swap into `/Applications` → publish to GitHub Releases) and rejects regressions. | Edit product code, bypass tests, ship if red. |
| `vakter-brand-keeper` | yellow | The editorial voice | Owns `Website/` end-to-end (landing, press, concepts, blog), drafts launch posts, refreshes screenshots, maintains the brand palette + type stack. | Post externally, claim unapproved pricing, touch product code. |
| `vakter-product-strategist` | green | The weekly zoom-out | Writes strategy memos to `.claude/strategy/`, commissions tickets directly to PO, prunes `BACKLOG.md`. Two modes: directed (you ask) and autonomous (the dispatcher invokes when idle). | Edit code, make financial commitments, publish anything. |
| `vakter-product-owner` | pink | The board | Translates strategy memos and human directives into well-scoped GitHub Issues on the Vakter project board. Owns labels, columns, board health. | Decide strategy, write code, ship. |
| `vakter-security-watcher` | red | The threat-modeller | Watches Apple security advisories, threat-models new features, verifies the Defenses-audit probes still match current macOS string formats, drafts responsible-disclosure responses. | Patch security issues directly (files tickets instead), publish advisories without human sign-off. |

## The eighth thing — the dispatcher

The dispatcher is **not an agent**. It's a scheduled task (`vakter-dispatcher`) that runs every 15 minutes while Claude Code is open. Its prompt is canonical at `.claude/dispatcher-prompt.md` and is also embedded in the scheduled-task definition.

Each cycle it does, in order:

1. Process new directives from `.claude/inbox/po/`.
2. Dispatch tickets in `Ready` status to their `agent:<name>`-labelled worker.
3. Run `vakter-release-warden` on tickets in `Review` status.
4. Skip `needs-human` tickets.
5. If everything above was empty, invoke `vakter-product-strategist` in autonomous mode. Strategist either files a single high-leverage directive or idles.
6. Distil closed tickets via `vakter-memory-keeper`.
7. Log the cycle to `.claude/dispatcher-log.md`.

It's the main session — it can spawn subagents. Subagents cannot spawn subagents. That's why the dispatcher exists.

## The daily flow

```
You open Claude Code in this repo
   │
   ▼  Type `/start-day-vakter` once
   ▼
Dispatcher runs immediately, then every 15 min
   │
   ▼  Picks up directives + Ready/Review tickets
   ▼
Agents do the work (code, copy, ship, threat-model, distil)
   │
   ▼  Comment on tickets, move state, write memory notes
   ▼
You glance at the GitHub Project's "Awaiting You" column
   when you feel like it. Approve, respond, close.
   │
   ▼  Close laptop / quit Claude Code = team is off the clock
   ▼
Tomorrow: open Claude Code, `/start-day-vakter`, repeat.
```

You're in the loop for exactly four things:
- **Touch ID prompts** during signing or daemon install.
- **External posts**: Product Hunt, Hacker News, Twitter, Mastodon, IndieHackers, podcast email replies. Agents draft; you click Submit.
- **Pricing, legal, financial decisions**: any ticket with the `needs-human` label.
- **Security disclosure responses**: any ticket with `needs-human:security`. The team drafts; you respond.

Everything else — code, tests, builds, signing, notarization, GitHub merges, ticket movement, BACKLOG sync, blog drafts, release notes, lesson distillation — happens without you.

## How to know when the team needs you

The GitHub Project has a column called **Awaiting You**. Tickets in that column have an `needs-human` (or `needs-human:security`) label. The dispatcher will not touch them. They sit there until you act.

On any given morning, the column should have 0–5 items. If it has 20, something is wrong — the team has been blocked on you for a while and probably needs you to either approve or correct course.

## How to pause everything

Three options, increasing finality:

| Want | Do |
|---|---|
| Pause the dispatcher (work pauses, agents stay defined) | Tell the assistant "pause Vakter team" — it sets the scheduled task to `enabled: false`. |
| Stop the dispatcher AND keep Claude Code closed | Just close the app. The cron only fires when Claude Code is open. |
| Take an agent offline temporarily | Move its `.md` file out of `.claude/agents/` (e.g. to `.claude/agents/_disabled/`) and restart Claude Code. |
| Tear it all down | Delete `~/.claude/scheduled-tasks/vakter-dispatcher/`, delete `.claude/agents/vakter-*.md`. The team stops existing. |

## How to edit an agent's behavior

Edit its `.md` file in `.claude/agents/`. Restart Claude Code. The new system prompt is live on the next dispatcher cycle.

Editing the dispatcher's behavior: edit `.claude/dispatcher-prompt.md`. The scheduled task reads it fresh every cycle so the change is live immediately — no restart needed.

## The directory layout

```
.claude/
├── agents/                            7 agent system prompts
│   ├── vakter-memory-keeper.md
│   ├── vakter-mac-engineer.md
│   ├── vakter-release-warden.md
│   ├── vakter-brand-keeper.md
│   ├── vakter-product-strategist.md
│   ├── vakter-product-owner.md
│   └── vakter-security-watcher.md
├── skills/
│   └── start-day-vakter/SKILL.md      morning ignition slash command
├── memory/                            distilled lessons (owned by memory-keeper)
│   ├── INDEX.md
│   └── <category>/<slug>.md
├── strategy/                          strategy memos, audit reports, launch drafts
│   ├── <YYYY-MM-DD>-<slug>.md
│   ├── idle-log.md
│   └── launch/
├── inbox/po/                          directives queued for product-owner
│   ├── NNNN-<slug>.md                 a directive
│   └── consumed/                      processed directives, kept as audit trail
├── dispatcher-prompt.md               canonical dispatcher behavior
└── dispatcher-log.md                  per-machine cycle history (gitignored)
```

## Hard rules the team lives by

- **No `Co-Authored-By: Claude` trailer on any commit.** Vakter is shipped by Jonathan Gebru. The team writes the diff; the human owns the signature.
- **Closed-source by intent.** The repo is private. No agent publishes source. `SECURITY.md` explains how trust is earned without OSS.
- **Touch ID stays in your hands.** No agent automates fingerprint prompts. Apple's hardware boundary is the team's boundary.
- **`release-warden` veto is absolute.** If they flag a regression, the team's priorities pause until it's fixed.
- **One agent edits one zone.** Memory-keeper edits memory; brand-keeper edits website; engineer edits code; PO edits tickets. No cross-zone writes.
- **All product code goes through PRs and the ship gate.** No direct `main` pushes from the team.

## When something goes wrong

The dispatcher fails open. Any cycle that errors logs the error and continues. Look at `.claude/dispatcher-log.md` first.

If the team appears stuck (no progress over multiple cycles), check:
1. `.claude/dispatcher-log.md` — is the dispatcher actually firing? Look at `nextRunAt` via `mcp__scheduled-tasks__list_scheduled_tasks`.
2. The GitHub Project's `Awaiting You` column — is everyone waiting on you?
3. `.claude/inbox/po/` — are directives piling up unprocessed?
4. `gh auth status` — has the token expired?

The right escalation is almost always: pause the dispatcher, investigate manually, fix, resume.

## Why this exists

Jonathan is solo. The product is Vakter — your Mac's bodyguard against physical and digital threats. The goal is 10,000 units sold by end Q3 2026, a v1.6 clipboard shield that earns Vakter a second category of coverage (ClickFix paste attacks), and a reputation worth carrying into the next thing. An AI team can't replace human judgment on price, voice, or trust — but it can absorb every other moving part. That's what the cast above does.

The proof of concept is that you, reading this for the first time, can run `/start-day-vakter` tomorrow morning and watch the team do real work.
