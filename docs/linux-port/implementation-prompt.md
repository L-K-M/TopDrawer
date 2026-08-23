# Executor prompt — Linux port implementation

*This is the prompt to hand the executing model, verbatim. It assumes a Claude Code
session with GitHub access to `L-K-M/TopDrawer` and `L-K-M/Pict`.*

---

You are implementing the Ubuntu/Linux port of Top Drawer and Pict, end-to-end,
following a written plan. Work autonomously; I am not watching in real time.

**Read these first, in this order** (in the TopDrawer repo):

1. `docs/linux-port/implementation-plan.md` — your execution plan. Part 0 is your
   contract: ground rules, PR lifecycle, steady-state and merge rules,
   resumability. The LP-numbered items are your work queue, in order.
2. `docs/linux-port/README.md` — the research summary. Skim now; deep-read the
   research doc each LP item links before implementing that item.
3. Each repo's `CLAUDE.md` — the PR-babysitting policy you must follow.
4. The Pict repo's `docs/linux-port.md` when you reach Pict items.

**Your loop:**

1. Determine the next item: list merged PRs titled `[LP-` in both repos; the next
   item is the lowest LP number not yet merged. If an open `[LP-…]` PR exists,
   resume babysitting it instead of starting anything new.
2. Implement that one item exactly as specified (branch naming, file lists,
   acceptance criteria are in the plan). Do not work ahead. Do not batch items.
3. Open the PR, subscribe to its activity, and arm a self check-in one hour out —
   check-ins are one-shot, so **re-arm the next one as the first action of every
   check-in**. The repos have an automated reviewer that posts rounds on its own;
   additionally request a review if a request mechanism is available, after
   opening and after every substantive push. React to every review round per the
   repo's `CLAUDE.md` triage policy (apply / decline with recorded reasons /
   refute with evidence; verify claims before acting; keep CI green on BOTH the
   Linux job and the macOS job at all times).
4. Declare steady state when (a) two consecutive review rounds produce no valid,
   actionable findings, OR (b) two consecutive hourly check-ins pass with no new
   review activity at all, OR (c) the reviewer only re-raises already-declined
   items / contradicts itself, OR (d) everything left is out of scope. Human
   reviewers are exempt from all of this: always address them, never merge over an
   unresolved human "changes requested" — ask me instead.
5. At steady state, merge — with two preconditions: both platform CI jobs are
   completed green on the current head commit (pending checks defer the merge to
   the next check-in; a check red for established infrastructure reasons across
   3+ check-ins → ask me), and you re-fetch the PR's comments immediately before
   merging (a new human comment cancels the merge and re-enters babysitting).
   Then: post a short scorecard in chat, **merge the PR yourself** (merge commit,
   matching repo history), delete the branch, unsubscribe, delete that PR's
   pending check-in trigger. You have my standing authorization to merge PRs that
   have reached steady state as defined above — you do not need to ask each time.
6. Announce the merge in one line and start the next item.

**Hard rules:**

- Never push to `main` directly. Never force-push. One PR in flight at a time.
- macOS must stay green: you are on Linux and cannot build macOS code — the
  repos' macOS CI is your macOS compiler. Never merge with a red required check.
- Never change macOS behavior; refactors of shared code are pure moves with
  additive `#if` guards (plan §0.3–0.4).
- Keep each PR under roughly 600 changed lines excluding tests, lockfiles, and
  mechanical data files the plan exempts; split when bigger (plan §0.6.2).
- If the plan's assumption fails (missing package, moved API), follow plan §0.5:
  smallest deviation, consult the research docs, record a "Deviation from plan"
  section in the PR body.
- Ask me only for: merge/branch-protection failures, unresolved human reviews, a
  collapsed plan assumption the plan doesn't cover, or anything destructive or
  outward-facing beyond these PRs. Otherwise decide, record, proceed.

**Reporting:** one short chat note per event that matters (PR opened, review round
handled with the scorecard deltas, merged, item started). No narration beyond that.

Start now: read the plan, announce which LP item is next and why, and begin.
