---
name: start-day-vakter
description: Use when the user types /start-day-vakter, "start the Vakter day", "kick off Vakter", or anything signaling they want the Vakter AI team to begin working for the day. Verifies the dispatcher scheduled task exists and is enabled, runs one immediate dispatcher cycle so the user sees instant activity, then prints a status summary.
---

# /start-day-vakter

You are running the Vakter AI team's morning ignition. The user just opened Claude Code and wants the team to start working.

## Workflow

### Step 1 — Confirm the scheduled task exists and is enabled

Call `mcp__scheduled-tasks__list_scheduled_tasks` and look for a task with `taskId: "vakter-dispatcher"`.

- **If it exists and is enabled**: good. Continue to step 2.
- **If it exists but is disabled**: call `mcp__scheduled-tasks__update_scheduled_task` with `taskId: "vakter-dispatcher", enabled: true`. Log a one-liner to `.claude/dispatcher-log.md` that the dispatcher was re-enabled today.
- **If it doesn't exist**: this should not normally happen (the dispatcher is created during initial setup). If it's missing, surface the issue to the user explicitly — don't auto-recreate without telling them, because they may have intentionally removed it.

### Step 2 — Run one immediate dispatcher cycle inline

Read `.claude/dispatcher-prompt.md` (the canonical dispatcher behavior). Follow it as if you were the scheduled task firing right now.

You ARE the main session, so you can spawn subagents via the Agent tool. Do that as the dispatcher prompt directs.

Bound the cycle the same way the scheduled task does: at most 3 Ready tickets + 2 Review tickets + 2 memory distillations.

### Step 3 — Print a daily-standup-style summary to the user

After the cycle completes, output a clear human-facing summary in this exact shape:

```
☕ Vakter AI team — day started

📅 Today: <YYYY-MM-DD>
🔄 Dispatcher: enabled, next auto-cycle in ~15 min
📋 GitHub Project status:
  • Backlog: <N>
  • Ready: <N>
  • In Progress: <N>
  • Review: <N>
  • Done (today): <N>
  • Awaiting You: <N>   ← items that need your attention

🚀 This cycle's work:
  <bullets — what was dispatched, what was idled>

⏸  To pause everything: tell me "pause Vakter team" or run
   mcp__scheduled-tasks__update_scheduled_task with enabled: false
```

If `Awaiting You` > 0, **list each ticket** in the summary: number, title, what the team is waiting for from you.

### Step 4 — Done

The dispatcher scheduled task is now running. It will fire again automatically in 15 minutes (while Claude Code is open). The user can close the laptop / app — work resumes when they reopen.

## What this skill does NOT do

- It does **not** modify the agent files, the directive inbox, or the memory store.
- It does **not** create the scheduled task if missing (surfaces to user instead).
- It does **not** override the `needs-human` gate — Awaiting You tickets stay awaiting.
- It does **not** spawn unbounded work — the cycle is bounded the same way the scheduled task is.

## Anti-patterns

- Running this skill twice in a minute. Once per morning is enough; the scheduled task handles the rest.
- Auto-clearing `Awaiting You` tickets. Those exist specifically to pause the team for you. Surface, don't bypass.
- Sycophantic openings. The user just woke up and wants signal — give them a one-screen standup, not a thousand words.
