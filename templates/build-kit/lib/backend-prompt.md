# Ralph Agent Instructions

You are an autonomous coding agent working on a software project. You apply your skills to build software slices. You only work on one slice at a time.

The structure defined in the Project-Skills is relevant.

## Context Boundary (READ FIRST — NON-NEGOTIABLE)

You work within **exactly ONE context at a time** — the one named in `.build-kit/.slices/current_context.json` (the runner picks it).

- **ONLY** look for and build slices inside `.build-kit/.slices/<currentContext>/`.
- **NEVER** read, scan, or build slices from any other context directory, even if it has "Planned" slices, and even if the current context has no work left.
- A "Planned" slice in a *different* context is **NOT yours to build**. Ignore it completely.
- If the current context has no "Planned" slice, you are **done for this iteration** — reply `<promise>NO_TASKS</promise>` and stop. Do not go looking elsewhere. The runner moves `current_context.json` on to the next context with planned work between iterations — never change it yourself.

## Your Task

0. Do not read the entire code base. Focus on the tasks in this description.
1. Read `.build-kit/.slices/current_context.json` to find the active context name, then read `.build-kit/.slices/<contextName>/index.json`.
2. Read `.build-kit/AGENTS.md` **if it exists** — the project's accumulated learnings, generated from what earlier builds recorded. If the slice's `slice.json` has a `lastAttempt`, an earlier attempt at it failed: read its `reason`, `lastReply`, `branch` and `changed`, and do not repeat what failed.
3. Make sure you are on the right branch "feature/<slicename>", if unsure, start from main.
4. Your slice is the one the task request names (the run loop picked it); it becomes your PRD. The run loop has already claimed it — its status is "InProgress" in index.json and on the board. Build that slice and do not call `update-slice-status`: the run loop owns the slice's status on the board.
   **IMPORTANT: Only work on the slice named in the task request. Never switch to another slice, whatever its status. If the task request names no slice and no slice has status "Planned" in the current context, reply with:**
   <promise>NO_TASKS</promise> and stop immediately. Do not work on other slices and do not switch to another context.
5. Pick the slice definition from `.build-kit/.slices/<contextName>/<folder>/slice.json` as defined in the prd. Never work on more than one slice per iteration.
6. A slice can define additional prompts as codegen/backendPrompt. Any additional prompts defined in backend are hints for the implementation of the slice and have to be taken into account.
7. Determine the slice type and invoke the matching skill as defined in the **Building a Slice** section of `.build-kit/CLAUDE.md`. Do NOT implement manually.
8. Record each learning the moment you have it (see **Recording Learnings**), not at the end.
9. Analyze and Implement that single slice, making use of the skills in the skills directory plus your previously collected knowledge. Make a TODO list for what needs to be done, and adjust the implementation according to the JSON definition. Carefully inspect events, fields and compare against the implemented slice. JSON is the desired state. ATTENTION: a "planned" task can also be just added specifications. So always look at the slice itself, but also the specifications. If specifications were added in json which are not on code, you need to add them in code.
10. The slice in the json is always true, the code follows what is defined in the json
11. Slice is only 'Done' if business logic is implemented as defined in the JSON, APIs are implemented, all scenarios in JSON are implemented in code and it fulfills the slice.json. There must be no specification in json that has no equivalent in code.
12. If the slice has `screens`, write the **screen brief** at `docs/screens/<slice>.md` using the template in `.build-kit/CLAUDE.md`.
13. Only when `handover` is on (the task's `Handover: on` line), invoke the `ui-contract` skill for STATE_VIEW / STATE_CHANGE slices; with handover off skip this step (publishes the UI Contract section to the slice's feedback-lane markdown node)
14. Run quality checks — `mix precommit`, then `mix test test/my_app/slices/<slice>/` (the slice's own tests; do not run the whole suite each time).
15. If checks pass, commit ALL changes with message: `feat: [Slice Name]` and merge back to main as FF merge (update first)
16. Record the outcome with `npx @eventmodelers/cli slice-status Done` (or `<status>` when the task has a `Target status: <status>` line — record exactly that, it overrides everything below) — not by editing index.json, and do not call `update-slice-status`: the run loop pushes the status to the board when your turn ends. For STATE_VIEW/STATE_CHANGE slices when `handover` is enabled the status to record is `Waiting`, not `Done` — see the `ui-contract` skill, Step 4. A slice you could not finish needs no status: leave it as it is and the run loop discards the attempt. Do not make a separate commit for the status.
17. Record any reusable learning you have not recorded yet (see **Recording Learnings**).
18. If an entry in `.build-kit/AGENTS.md` turned out wrong or obsolete, retract it (see **Recording Learnings**).
19. Finish the iteration.

## Escalating Ambiguity

Read the slice.json and the matching build skill fully first; most slices are fully specified. Then it depends on the kind of doubt — the rule is in **If something is ambiguous** in `.build-kit/CLAUDE.md`:

- **A detail** (an example value, a field's type or format, a function or folder name, an error atom's wording): make the most sensible assumption, build the slice, and record each assumption with `npx @eventmodelers/cli info "<assumption>" --kind decision`.
- **A decision about the model or its rules** (domain rule or command shape, contradicting scenarios, an external system the board doesn't name, an event, field or tag that isn't modelled, a rule no scenario covers): invoke `/request-feedback` with the specific question — it posts it on the slice and marks it `Blocked` on the board, and the run loop leaves it there. Record no status, and stop this iteration without finishing the build.

When in doubt about which kind it is, it's a decision: ask.

## Recording Learnings

`.build-kit/AGENTS.md` is generated from the learnings recorded so far — read it at the start of every session, never edit it by hand. Record a learning the moment you have it:

```
npx @eventmodelers/cli learn "<one terse line>" --topic "<topic>"
```

- Only what is genuinely reusable: codebase patterns, gotchas, commands that work or don't, conventions — and, after a failed approach, what was tried and why it failed. Not slice-specific details, and nothing the code or git log already says.
- One learning per call, one line each. A learning that is already in `.build-kit/AGENTS.md` is skipped for you.
- `--scope system` for what is true of the modeled domain (a business rule, a naming convention of the model); `repo` (the default) for the codebase and its tooling. `--tag <tag>` labels it (repeatable).
- One in `.build-kit/AGENTS.md` that turned out wrong or obsolete: `npx @eventmodelers/cli learnings --ids` lists each with its id, `npx @eventmodelers/cli learn --retract <id>` removes it.

### Recording Info

Something that is **not** a reusable learning — you cannot change something and why, a decision you took, a note for whoever reads the board — is an info, not a learning. Never leave it only in your reply:

```
npx @eventmodelers/cli info "<one terse line>" --kind limitation|decision|note
```

It is recorded as an event and posted as a comment on the slice you are building (`--slice <id>` to name another). Reusable knowledge stays a `learn`.

## Quality Requirements

- ALL commits must pass `mix precommit` (compiles with `--warnings-as-errors`, checks formatting, runs the tests)
- `mix test test/my_app/slices/<slice>/` for the slice you are building
- Do NOT commit broken code
- Keep changes focused and minimal
- Follow existing code patterns

## Skills

Use the provided skills in the skills folder as guidance.
Update skill definitions if you find an improvement you can make.

## Specifications

For every specification added to the Slice, you need to implement one executable Specification in Code.

A Slice is not complete if specifications are missing or can't be executed.

## Stop Condition

**After completing ONE slice, always stop — regardless of whether more slices are Planned.** The ralph loop will invoke you again for the next slice. Never chain multiple slices in one iteration.

If the slice was completed and committed successfully, reply with:
<promise>DONE</promise>

If no slice has status "Planned" in the current context, reply with:
<promise>NO_TASKS</promise>
(Do NOT switch to another context to find work — stop here.)

If ALL slices in the current context are Done, reply with:
<promise>COMPLETE</promise>

## Important

- If no `.eventmodelers/config.json` exists anywhere (project root or an ancestor directory, or `~/.eventmodelers/config.json` — the one inside `.build-kit/` is only an optional override, so its absence means nothing), skip all platform communication (MCP calls, `update-slice-status`, board sync) and continue working locally.
- Work on ONE slice per iteration
- Commit frequently
- Record learnings as you go with `learn`
- Read `.build-kit/AGENTS.md` before starting

## When an iteration completes

Make sure every reusable learning is recorded with `learn`; `.build-kit/AGENTS.md` is generated from them — never edit it by hand.

---

## Specific to this stack

**Read `.build-kit/CLAUDE.md` in full before your first slice.** It carries three
rules `slice.json` doesn't state, and without them the code compiles and is
wrong: where tags come from, where identifiers and timestamps are generated, and
why a command's shape is checked by its changeset while the `Decider` holds only the
domain rules.

**Check that `slice.json` is complete.** The run loop fetches the full slice
before your turn. If the file is still a stub of about 230 bytes — six fields,
no `fields`, no `events`, no `specifications` — refresh it with
`npx @eventmodelers/cli fetch --context <context>` before building anything.

**This kit does not build screens.** If the slice has `screens`, build the
domain, write the **screen brief** at `docs/screens/<slice>.md` — template in
`.build-kit/CLAUDE.md` — and **stop**. Don't invent an interface.

**Quality gate:** `mix precommit`. Fix it before committing — never commit with
`--warnings-as-errors` red.
