# Finding tags

Read this when the mechanical rule doesn't resolve it — an event with no
`idAttribute: true`, or a command whose decision plainly needs history the rule
wouldn't fetch.

## The rule, and why it usually suffices

> Every event field with `idAttribute: true` produces a tag
> `<name without the Id suffix, in snake_case>:<value>`.

It works because the board already carries the decision. Whoever modelled the
slice marked which fields identify things, so the agent derives tags instead of
inventing them — and a made-up tag is the worst failure mode there is, since it
doesn't error, it just silently stops finding events downstream.

Other DCB stacks can't do this. Nothing in their pipeline marks it, so they ask
the agent to reason it out. We only need that reasoning when the rule runs out.

## The question to ask

For each event, and separately for each command:

> **If a different command's own decision needed to know about this, what
> field's value would it match on?**

That field is a tag. A command's decision then sees exactly the prior events
sharing at least one of its tags — never the whole history, and never
artificially narrowed to one "owning" entity either.

## The simple case, which looks like an aggregate

A bank account. `MoneyDeposited` and `MoneyWithdrawn` both carry an
`accountId`. `WithdrawMoney`'s decision — "is there enough balance" — needs
every prior deposit and withdrawal *for that account*, and nothing from any
other. One tag, `account:`, on both the events and the command's query. Here DCB
and aggregate modelling agree, and the rule gives you the answer for free.

## The case a single aggregate ID can't express

Course enrolment, with two rules that must hold at once:

- a course never takes more enrolments than its capacity;
- a student is never enrolled in more than a handful of courses.

Classic modelling puts those on two aggregates, `Course` and `Student`, and no
single transaction sees both. That's what normally forces a saga: reserve a
seat, separately check the student's count, compensate if either half fails.

DCB answers it directly. `EnrolStudentInCourse` tags on **both** `student:` and
`course:`, so `query/1` returns the union of that student's enrolment history
and that course's enrolment history, and `execute/2` checks both invariants in
one decision, atomically. No saga, no reservation, no compensation — there was
never a moment when only one of the two facts was visible.

**This is what to look for when the rule feels wrong**: a decision that needs
two histories at once. In `slice.json` it shows up as a command carrying two
`idAttribute: true` fields, and the mechanical rule already produces both tags.

## When to stop and ask

**An event with no `idAttribute: true` at all.** It can't be queried, so no read
model or TODO queue will ever find it. Don't guess a tag — invoke
`request-feedback` and put the question above to the modeller. They are the one
who knows which field another command would match on.
