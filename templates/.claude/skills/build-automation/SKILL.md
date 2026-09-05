---
name: build-automation
description: Implements an automation slice (a processor that watches a TODO queue, calls an external system and records the result as our own fact) in Elixir with the FACT event store, from a slice.json
---

# Build an automation slice

> Before anything else, read the definition at
> `.build-kit/.slices/{Context}/{slice}/slice.json`. That file is the **source of
> truth**. Never invent fields that aren't there.

> And read `.build-kit/CLAUDE.md`. This slice shape deviates most from what the
> board appears to say, so those three rules matter double here.

---

## What an automation slice is

Nobody clicks anything. A processor watches a **TODO queue** — which is a read
model, not a table — does the work, and **writes a fact of our own**.

```
TODO queue (STATE_VIEW)  →  Processor (GenServer)
                              → Task.Supervisor.async_nolink
                                  → external call
                                  → Context.<verb>(...)  →  Decide  →  event
```

Five files: the four of a write slice, plus `processor.ex`.
**Build the four first with `/build-state-change`**, then come back here for the
processor. This skill only covers what that one doesn't.

---

## Step 1 — The TODO queue exists and you don't build it

`processors[].dependencies` points at a READMODEL that is the queue. It's usually
a separate slice on the board, with its own `slice.json`.

**If that slice isn't built, stop.** Build it first with `/build-state-view`, or
invoke `request-feedback` if it isn't on the board at all.

A TODO queue is "what was asked minus what was resolved": it folds the event that
opens the work and the one that closes it, and leaves out the ones already
closed. **It's a query, not a subtraction** — don't keep a counter.

---

## Step 2 — The anti-corruption layer, and which way it points

When the slice calls an external system, the temptation is to model "we received
this". **Don't.**

> **Our domain fact leads and the external response fills it in**, not the other
> way round.

This isn't a style preference. If the event is "X's response minus some fields",
a change in X propagates through the whole system. If the event is our fact and X
is the input, a change in X only moves the mapping, in one place.

Concrete consequences:

- **One event, not two.** Don't emit an `XResponseReceived` alongside the domain
  fact: "we received this" isn't a business fact, and giving it its own node
  drags the foreign shape onto the timeline — which is exactly what an
  anti-corruption layer prevents.
- **The raw body travels as a technical attribute** (`rawResponse`,
  `technicalAttribute: true`) for forensics and for re-derivation. It is not
  projected into any view.
- **Field names are domain names**, not the external API's. Never `risk_pcrop`:
  `verdict`. Which layer measured it travels in a provenance field, not in the
  name.
- **The event name's preposition matters.** `…EvaluatedWithX` says X computed and
  we judged. `…EvaluatedByX` would say X made our judgement. The board already
  chose: match it exactly.

### Where the source goes: in the name or in a field

| who judges | where it goes |
|---|---|
| a third party evaluates and returns a verdict | in the **event name** |
| we compute it ourselves against a file | in a **provenance field** (`dataVersion`) |

In the second case there is **no `source` field**: it would be a category error,
implying an external evaluator where there is none. And the provenance field is
self-describing — `"Provita ANP 2023-07-29"`, not `"2023-07-29"`.

#### If you compute against a file, the file is an interface

A data file you read at runtime is as much an external system as an HTTP API —
it has a shape you don't control, and it can drift from what your code expects.
The difference is that HTTP gives you a status code and a file gives you
`nil`.

**Never hand-write the fixture for a reader of a deployed artefact.** Derive it
from the artefact, and add a test that compares the two:

```elixir
test "the fixture's keys are the real file's keys" do
  path = Application.get_env(:my_app, :layer, [])[:path]

  if File.exists?(path) do
    keys = path |> File.read!() |> Jason.decode!() |> ... |> MapSet.new()

    assert MapSet.new(@keys_from_the_file) == keys,
           "the deployed file changed vocabulary: #{inspect(MapSet.to_list(keys))}"
  else
    # A large artefact often lives outside the repo. Absent is not a failure.
    assert true
  end
end
```

The failure this prevents is worth spelling out, because it is quiet and it
passes review. A hand-written fixture asserts the reader against *itself*: both
sides of the test share the author's belief about the file's shape, so the test
proves the reader is self-consistent and proves nothing about the file. If the
belief is wrong, every test is green and every field comes back `""`.

Then watch where those empty fields go. If the write command validates required
fields — and it should — the command rejects, the item stays in the queue, and
**the automation silently never produces a result**. Worse, it usually splits:
the empty path (nothing found, no fields to fill) keeps working while the
populated path (something found) hangs. The half that works is the half nobody
was worried about.

And write the guard so it **skips** when the artefact is absent rather than
failing. A clean clone that doesn't ship a 30 MB layer is not a broken build.

### Translation happens inline

The board may show four or six slices for one external call (request → external
event → response view → translator → internal command → internal event). **In
code it's one processor that calls and records.** The model prioritises
conceptual clarity and making the system boundary visible; the implementation
prioritises not having handlers that do nothing.

If the external call were genuinely asynchronous — an inbound webhook — the entry
point is a **Phoenix controller**, not a processor. Use `/build-webhook`.

---

## Step 3 — `processor.ex`

**File:** `lib/my_app/slices/<slice>/processor.ex`

```elixir
defmodule MyApp.Slices.<Slice>.Processor do
  @moduledoc """
  Automation: watches <the queue>, <does the work> and records <the event>.

  <And the numbers that justify the interval and the timeouts. A `@poll_interval`
  with no measurement beside it is an invented number.>
  """

  use GenServer

  require Logger

  alias MyApp.Slices.<Queue>.Context, as: Queue
  alias MyApp.Slices.<Slice>.Context, as: <Slice>

  @poll_interval :timer.seconds(5)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    if Keyword.get(opts, :start?, true) do
      schedule()
      {:ok, %{}}
    else
      {:ok, %{}}
    end
  end

  @impl true
  def handle_info(:poll, state) do
    process_pending()
    schedule()
    {:noreply, state}
  end

  # Tasks use `async_nolink`: their result and their crash arrive as messages,
  # and you have to handle them or the GenServer fills up with unread mail.
  def handle_info({ref, _result}, state) when is_reference(ref), do: {:noreply, state}
  def handle_info({:DOWN, _ref, :process, _pid, :normal}, state), do: {:noreply, state}

  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    Logger.error("<slice> task failed: #{inspect(reason)}")
    {:noreply, state}
  end

  def handle_info(_other, state), do: {:noreply, state}

  defp process_pending do
    Enum.each(Queue.pending(), fn item ->
      Task.Supervisor.async_nolink(MyApp.TaskSupervisor, fn -> process(item) end)
    end)
  rescue
    e -> Logger.warning("poll failed: #{Exception.message(e)}")
  end

  defp process(item) do
    case call_external(item) do
      {:ok, response} -> <Slice>.<verb>(item.<id>, response)
      {:error, reason} -> Logger.error("<external> failed for #{item.<id>}: #{inspect(reason)}")
    end
  end
end
```

Non-negotiable rules:

- **The external call goes inside the `Task`, never in the `GenServer`.** A
  `Req.post` in `handle_info` blocks the whole poll.
- **`start?: true` by default, configurable.** Switch it off in tests: a live
  processor during the suite makes real network calls.
- **`Req`, never anything else.** With an explicit `receive_timeout` if the call
  is slow.
- **Add it to the supervision tree** in `lib/my_app/application.ex`, after
  `Fact.Supervisor` and `Task.Supervisor`, with
  `Application.get_env(:my_app, :<slice>, [])`.
- **Secrets come from `config/runtime.exs`**, never from code. If the key is
  missing, the processor should start and log the failure — not take down the
  whole application's boot.
- **Decide how many calls may be in flight, and write the number down.** See
  below. There is no safe default here: "as many as the queue holds" is a
  decision, and it is usually the wrong one.

### How many at a time

A processor that sweeps its queue on boot will fire **every pending item at
once**. That is the moment the limit of the external system shows up, and it
shows up in production, on a restart, when the queue happens to be deep.

Assume the service has a concurrency or rate limit **and that it is not
documented**. Most aren't. You find them by hitting them: a burst comes back
`429`, and the same call made alone succeeds — which is exactly the shape that
makes it look like the service is broken rather than that you are being rude.

So pick a ceiling and make it a module attribute with a comment saying where the
number came from (measured? documented? guessed?):

```elixir
# One at a time: a burst of four returned 429 while a single call succeeded.
@in_flight 1
```

Then keep the rule in a **pure function**, so it can be tested without the
network:

```elixir
def room_for?(in_flight, item_id) do
  map_size(in_flight) < @in_flight and item_id not in Map.values(in_flight)
end
```

Two things follow, and both matter more than the ceiling itself:

- **Don't build a second queue in memory.** You already have a durable one — the
  TODO read model. An item you decline to launch stays pending there, so a
  restart loses nothing and doesn't replay the burst. An in-memory backlog gives
  up both properties.
- **On success, pull the next item immediately; on failure, don't.** Waiting for
  the next poll after every success leaves the queue idle most of the time. But
  chaining after a *failure* turns a rejected call into a tight loop against
  someone else's API — let the poll interval be the backoff. This means
  `process/1` has to return something that distinguishes the two; `:ok` for both
  is a bug you won't see until you're the one being rate-limited.

### The external system failing is a domain case

If `slice.json` models a failure event, emit it. If it doesn't, **log it and
leave the item in the queue** — don't invent a failure event: that's a modelling
decision, not an implementation one, and it belongs to the board.

And if the external system failing produces a **reassuring** result rather than a
visible error, say so in the `@moduledoc` in plain words. That's the class of
failure nobody discovers in time.

---

## Step 4 — Tests

**The processor isn't tested with the network.** What gets tested is its write
slice's `Core`, via `/build-state-change`, plus:

- That the queue returns what's pending and **stops returning it** once resolved.
- The mapping from external response to domain fields, as a pure function. Pull
  it out into its own function (`defp to_domain(response)`) precisely so it can
  be tested without the network.
- **The decision of when to launch** — `room_for?/2` from Step 3. This is the one
  people skip, because it is neither the mapping nor the write, so it falls
  through the gap between them and ends up as the only untested logic in the
  slice. It is also the logic that fails in production rather than in the suite.
  Four assertions cover it: nothing in flight launches; something in flight
  doesn't; the same item already in flight doesn't; releasing one makes room
  again.

"Not tested with the network" means the *call* isn't tested. It does not mean
the processor is exempt. If a rule inside the `GenServer` can't be reached
without the network, that's a sign it should be a pure function, not a sign it
shouldn't be tested.

With `start?: false` in `config/test.exs` for this slice.

---

## Step 5 — Quality gate

```
mix precommit
mix test test/my_app/slices/<slice>/
```

---

## Final check against `slice.json`

- [ ] The four write files exist, built with `/build-state-change`.
- [ ] **One domain event**, not a "response received" one.
- [ ] Field names are domain names, not the external API's.
- [ ] The raw body is a technical attribute and is **not** projected.
- [ ] The event name's preposition matches the board (`With…` / `By…`).
- [ ] The external call is inside the `Task`, not in the `GenServer`.
- [ ] All three task `handle_info` clauses are present (`{ref, _}`, `:DOWN`
      normal, `:DOWN` with a reason).
- [ ] The processor is in the supervision tree and switched off in tests.
- [ ] Secrets come from `runtime.exs`.
- [ ] The response → domain mapping is a pure function and has a test.
- [ ] If the slice reads a deployed file: the fixture is derived from it, and a
      guard test compares their vocabulary (skipping when the file is absent).
- [ ] The in-flight ceiling is a module attribute, with a comment saying where
      the number came from.
- [ ] The launch decision is a pure function and has a test.
- [ ] Declining to launch leaves the item in the durable queue — there is no
      second queue in memory.
- [ ] `process/1` distinguishes success from failure, and only success chains
      into the next item.
