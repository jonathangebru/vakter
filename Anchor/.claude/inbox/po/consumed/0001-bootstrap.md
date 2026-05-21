# Bootstrap: get the AI team's working environment in place

**Strategy memo:** (none — this is the initial bootstrap, pre-strategist)
**Priority:** p0
**Estimated complexity:** medium

## Epic title for the board
Foundation: bootstrap AI team's working environment

## Goal
By the end of this Epic, the AI team is fully operational: the GitHub repo is named `vakter`, all 9 days of uncommitted work is on `origin/main` as a coherent commit series, the GitHub Project v2 board is set up with our label taxonomy, branch protection is on, `gh` has the right scopes, and `AI_TEAM.md` exists at repo root explaining the system to a fresh reader.

This Epic exists once. After it ships, the team operates on directives from strategist (or the human) for the rest of its life.

## Acceptance criteria (epic-level)
- [ ] `gh repo view jonathangebru/vakter` succeeds (rename completed).
- [ ] `git remote -v` shows the new URL.
- [ ] `git status` is clean in the working tree.
- [ ] `git log origin/main --oneline -20` shows 8 new commits representing the 9 days of work.
- [ ] `gh auth status` shows `project, read:project` in scopes.
- [ ] `gh project list --owner jonathangebru` shows the "Vakter" project.
- [ ] The project board has columns: Backlog, Ready, In Progress, Review, Done, Awaiting You.
- [ ] The repo has the full label taxonomy (see Feature 5).
- [ ] Branch protection on `main` requires PR + 1 review (release-warden satisfies the review).
- [ ] `AI_TEAM.md` exists at repo root and is committed.

## Suggested Features for PO to file

### Feature 1 — Rename GitHub repo anchor → vakter
**Agent:** vakter-mac-engineer
**Priority:** p0
**Complexity:** small

Scope:
- `gh repo rename vakter --repo jonathangebru/anchor`
- Update local git remote: `git remote set-url origin https://github.com/jonathangebru/vakter.git`
- Grep `Scripts/` and `README.md` for any hardcoded `anchor` URLs; update.
- Comment on the ticket with the new remote URL.

Acceptance:
- `gh repo view jonathangebru/vakter` returns the repo.
- `git remote -v` shows `vakter.git`.
- No remaining hardcoded references to the old `anchor.git` URL anywhere in the tree.

### Feature 2 — Rename local working directory Anchor → Vakter
**Agent:** vakter-mac-engineer
**Priority:** p0
**Complexity:** small

Scope:
- Move `/Users/jonathangebru/Desktop/security-mac/Anchor` to `/Users/jonathangebru/Desktop/security-mac/Vakter`. This requires the user to cd out first; the agent posts a comment asking the human to run `mv` themselves (the human owns paths outside the repo). Once renamed, agent updates the scheduled-task path in the dispatcher prompt via `mcp__scheduled-tasks__update_scheduled_task` so the dispatcher finds the new path.
- Verify `swift build` still works in the new location.

Acceptance:
- `pwd` from inside the working tree shows `/Users/jonathangebru/Desktop/security-mac/Vakter`.
- `swift build --configuration debug` exits 0.
- Dispatcher scheduled task prompt references the new path.

### Feature 3 — Refresh gh CLI scopes
**Agent:** vakter-mac-engineer
**Priority:** p0
**Complexity:** small

Scope:
- Run `gh auth refresh -s project,read:project`
- This will open a browser. Comment on the ticket telling the human to approve.

Acceptance:
- `gh auth status` lists `project` and `read:project` in token scopes.

### Feature 4 — Commit 9 days of uncommitted work as a coherent series
**Agent:** vakter-mac-engineer
**Priority:** p0
**Complexity:** large

Scope: group the working-tree changes into logical commits and push. Suggested grouping:

1. **rebrand: Anchor → Vakter (sources + scripts + plists)** — the bulk rename. Use `git mv` for tracked file renames.
2. **v0.9: locale phrases + sample-backed sirens + evidence-bundle builder + recipient store**
3. **v1.0-1.2: visual polish (concepts page implementations in SwiftUI — menubar last-event row, About window, Event Log redesign, Settings Modes spectrum, Defenses Pareto checklist, Onboarding polish)**
4. **v1.3: Merkle event chain + EvidenceReport PDF + audio capture**
5. **v1.4: Defenses audit (12 checks) + CloudKit publisher + EntitlementProbe**
6. **v1.4.1: BT trust-lost café-fix + first notarized release + provisioning profile embedded + build-app.sh updated**
7. **iOS + watchOS companions: source for iOS/, WatchOS/ + xcodegen project.yml**
8. **Website + docs: vakter.app landing, press kit, concepts page, STRATEGY/SECURITY/PRIVACY/BACKLOG/TESTING_PLAN/AUDIT_PLAN/SPARKLE_SETUP/REPO_SPLIT.md (the last one likely DELETE since the OSS attempt was reverted)**

Each commit message follows the style in `git log` (one-line summary, blank, body). **NEVER add a `Co-Authored-By: Claude` (or any Anthropic) trailer** — see global CLAUDE.md.

Push to `origin/main`. If branch protection blocks (Feature 6 may have run first), use a PR-per-commit-group flow with release-warden auto-merging.

Acceptance:
- `git status` clean.
- `git log origin/main --oneline -20` shows the 8 commits.
- `origin/main` is up to date.

### Feature 5 — Create GitHub Project v2 board + labels + columns
**Agent:** vakter-product-owner
**Priority:** p0
**Complexity:** medium

Scope: depends on Features 1 + 3 (rename + project scope) being done first.

- `gh project create --owner jonathangebru --title "Vakter"`
- Add the following columns (via `gh project field-create` on the Status field): `Backlog`, `Ready`, `In Progress`, `Review`, `Done`, `Awaiting You`
- Create the following labels on the `vakter` repo:
  - **Agent routing:** `agent:vakter-mac-engineer`, `agent:vakter-brand-keeper`, `agent:vakter-release-warden`, `agent:vakter-security-watcher`, `agent:vakter-product-owner`, `agent:vakter-memory-keeper`, `agent:vakter-product-strategist`
  - **Type:** `type:epic`, `type:feature`, `type:item`
  - **Priority:** `priority:p0`, `priority:p1`, `priority:p2`
  - **Severity:** `severity:regression`, `security-critical`
  - **Human-gate:** `needs-human`, `needs-human:security`
- Link the `vakter` repo to the project.
- File this bootstrap Epic itself as the first Issue on the new board, marking each of these Features as sub-items.

Acceptance:
- `gh project list --owner jonathangebru` shows "Vakter".
- `gh label list --repo jonathangebru/vakter` shows all 17 labels above.
- The bootstrap Epic + all its Features are filed and visible on the board.

### Feature 6 — Branch protection on main
**Agent:** vakter-mac-engineer
**Priority:** p1
**Complexity:** small

Scope:
- `gh api repos/jonathangebru/vakter/branches/main/protection -X PUT --input -` with a JSON payload that requires:
  - 1 review approval before merge (release-warden satisfies this — agent identity is fine, GitHub doesn't differentiate)
  - status checks pass (later wire-up; for now optional)
  - no force-push, no deletion
- Verify by attempting a direct push (should be rejected).

Acceptance:
- `gh api repos/jonathangebru/vakter/branches/main/protection` returns the configured rules.
- A test push to main from a non-PR context is rejected.

### Feature 7 — Write AI_TEAM.md playbook at repo root
**Agent:** vakter-brand-keeper
**Priority:** p1
**Complexity:** medium

Scope:
- Read all 7 agent files in `.claude/agents/`.
- Read this directive.
- Write `AI_TEAM.md` at repo root explaining:
  - The team of 7 agents + dispatcher (what each does in 2-3 sentences).
  - The daily flow: open Claude Code → `/start-day-vakter` → dispatcher runs → close Claude Code → done.
  - The `Awaiting You` column: how to know when the team needs you.
  - How to pause everything (one-liner: `update_scheduled_task` to disable).
  - The closed-loop diagram (text/ASCII or table).
- Voice: match `SECURITY.md` — calm, technical, no fluff.
- Commit it.

Acceptance:
- `AI_TEAM.md` exists, committed to `origin/main`, ~400-800 lines.
- Reading it cold gives a complete picture of how the AI team operates.

## Anti-scope

Things this Epic does NOT do (PO must NOT file these as Features):
- Wire up CI (no GitHub Actions). That's a separate future Epic.
- Deploy CloudKit schema. Separate Epic when iOS companion lands.
- Build the iOS / watchOS apps. Source is there but provisioning is out of scope here.
- Sparkle auto-update. Separate future Epic.
- Rewrite SECURITY.md / STRATEGY.md / PRIVACY.md. Those are the user's source-of-truth; only update mechanical things like dates or stale claims as part of the rebrand commit.
- Delete `REPO_SPLIT.md` and `LICENSES/` — those are abandoned OSS-attempt artifacts. **Wait — actually delete them as part of Feature 4's commit 8 ("Website + docs"), since they're abandoned and never were tracked.**

## Reading priority for PO

- `.claude/agents/vakter-*.md` (you need to know the team you're filing tickets for)
- `BACKLOG.md` (verify no duplicates)
- `STRATEGY.md` (verify alignment with north star)
- `git status` + `git log -1` (understand the current state of the tree)
