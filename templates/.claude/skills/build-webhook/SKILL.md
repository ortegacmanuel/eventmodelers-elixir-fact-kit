---
name: build-webhook
description: Implements a slice whose trigger is an inbound external event — a webhook — in Elixir/Phoenix with the FACT event store, from a slice.json
---

# Build a webhook slice

> Before anything else, read the definition at
> `.build-kit/.slices/{Context}/{slice}/slice.json`. That file is the **source of
> truth**. Never invent fields that aren't there.

> And read `.build-kit/CLAUDE.md`. The three rules `slice.json` doesn't state
> apply here exactly as in any other write slice.

---

## When it's this shape and not an automation

The difference isn't "there's an external system": it's **who starts**.

| | who starts | entry point |
|---|---|---|
| **Automation** | us, polling a TODO queue | `processor.ex` (GenServer) |
| **Webhook** | the external system, whenever it likes | a **Phoenix controller** |

If the slice describes something that *arrives at us* — a payment confirmation, a
result another service computed and returns later, a status change in another
system — it's a webhook. And then **there is no processor**: there's nothing to
poll, because we aren't the ones asking.

A common mistake is standing up a GenServer for this. It's redundant: the caller
already brings the data.

---

## Step 1 — The four write files

A webhook is **a write slice with a different trigger**. Build the command, the
event, `core.ex` and `context.ex` with `/build-state-change` first, then come
back here for the web layer. This skill only covers what that one doesn't.

Everything from there applies without exception: tags come from
`idAttribute: true`, identifiers and timestamps are generated in `context.ex`,
and all validation lives in `core.ex`.

---

## Step 2 — The translation, and which way it points

Same as an automation: **our domain fact leads and the webhook body fills it
in**, not the other way round.

- **One event.** Don't emit a `WebhookReceived` alongside the business fact:
  "something arrived" isn't a domain fact, and giving it its own event drags the
  foreign shape onto the timeline.
- **The raw body travels as a technical attribute** (`rawBody`,
  `technicalAttribute: true`), for forensics and re-derivation. It is not
  projected into any view.
- **Field names are domain names**, not the provider's.
- **The translation is a pure function** in `context.ex` or its own module:
  `defp to_domain(body)`. Pull it out so it can be tested without HTTP — it's the
  only part of a webhook that really deserves a unit test.

---

## Step 3 — The controller

**File:** `lib/my_app_web/controllers/<slice>_webhook_controller.ex`

```elixir
defmodule MyAppWeb.<Slice>WebhookController do
  @moduledoc """
  Entry point for <the external system>.

  <What it sends, when, and what it expects back. If the provider retries on
  failure, say so here: it completely changes how you must respond.>
  """

  use MyAppWeb, :controller

  require Logger

  alias MyApp.Slices.<Slice>.Context, as: <Slice>

  def webhook(conn, params) do
    case <Slice>.<verb>(params) do
      {:ok, _id} ->
        send_resp(conn, 200, "OK")

      {:error, reason} ->
        # 200 on purpose: the body arrived and we understood it. That we can't
        # process it isn't the caller's fault, and returning 4xx or 5xx makes
        # the provider retry the same bad body forever.
        Logger.error("<external> webhook rejected: #{inspect(reason)}")
        send_resp(conn, 200, "OK")
    end
  end
end
```

### Which status code to return, which isn't obvious

- **200 even when the domain rejects.** The provider only knows whether it
  arrived, not whether it was useful to us. A 4xx or 5xx sets it retrying a body
  we already know is no good.
- **Answer fast and don't block.** If the work is long, write the fact and leave
  the rest to an automation — the webhook only has to record that it arrived.
- **Return 401 only when the signature fails.** That one really is the caller's
  problem.

---

## Step 4 — Verify the signature, in a plug

**Never in the controller.** Verification needs the **raw body**, and by the time
the controller sees it, `Plug.Parsers` has already decoded and discarded it.

Two plugs:

**`lib/my_app_web/plugs/cache_raw_body.ex`** — stashes the body before parsing,
via `Plug.Parsers`' `:body_reader` option in `endpoint.ex`.

**`lib/my_app_web/plugs/<external>_webhook_signature.ex`** — compares the
signature against the stashed body and **halts with 401** if it doesn't match.

```elixir
defmodule MyAppWeb.Plugs.<External>WebhookSignature do
  @moduledoc """
  Verifies <external>'s signature against the **raw** body.

  It's a plug and not the controller because `Plug.Parsers` has already consumed
  the body by the time the controller runs, and signing over re-serialised JSON
  doesn't match: key order and whitespace change.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    secret = Application.get_env(:my_app, :<external>)[:webhook_secret]

    with [signature] <- get_req_header(conn, "x-<external>-signature"),
         raw when is_binary(raw) <- conn.assigns[:raw_body],
         true <- valid?(signature, raw, secret) do
      conn
    else
      _ -> conn |> send_resp(401, "invalid signature") |> halt()
    end
  end

  # `Plug.Crypto.secure_compare/2` and not `==`: comparing strings with `==`
  # leaks information through how long it takes.
  defp valid?(signature, raw, secret) do
    expected = :crypto.mac(:hmac, :sha256, secret, raw) |> Base.encode16(case: :lower)
    Plug.Crypto.secure_compare(signature, expected)
  end
end
```

**If `slice.json` says nothing about a signature, ask.** An unverified webhook is
a public endpoint that writes to the event store: anyone can invent domain facts.
Invoke `request-feedback` before leaving it open.

---

## Step 5 — The route

In `router.ex`, **in its own scope** with its own pipeline: the `:browser`
pipeline brings `protect_from_forgery`, and a webhook sends no CSRF token.

```elixir
pipeline :webhook do
  plug :accepts, ["json"]
  plug MyAppWeb.Plugs.<External>WebhookSignature
end

scope "/webhooks", MyAppWeb do
  pipe_through :webhook
  post "/<external>", <Slice>WebhookController, :webhook
end
```

And the secret comes from `config/runtime.exs`, never from code.

---

## Step 6 — Tests

Two, and neither touches the network:

**`test/my_app/slices/<slice>/core_test.exs`** — the board's specifications
against the pure `Core`, as in any write slice.

**`test/my_app_web/controllers/<slice>_webhook_controller_test.exs`** — with
`ConnCase`, pinning down what's specific to a webhook:

- A valid body **with a valid signature** writes the event and returns 200.
- A valid body **with an invalid signature** returns **401** and **writes
  nothing**. This is the test that actually matters.
- A body the domain rejects returns **200**, not 4xx, and writes nothing.
- **The same body twice writes one event.** Providers retry; if `Core` isn't
  idempotent, every retry duplicates the fact.

---

## Step 7 — Quality gate

```
mix precommit
mix test test/my_app/slices/<slice>/ test/my_app_web/controllers/
```

---

## Final check against `slice.json`

- [ ] The four write files exist, built with `/build-state-change`.
- [ ] **There is no processor.** If you wrote a GenServer, this slice wasn't a
      webhook.
- [ ] **One domain event**, not a "webhook received" one.
- [ ] Field names are domain names, not the provider's.
- [ ] The raw body is a technical attribute and isn't projected.
- [ ] The signature is verified **in a plug**, against the raw body, with
      `secure_compare/2`.
- [ ] The scope has its own pipeline, without `protect_from_forgery`.
- [ ] The secret comes from `runtime.exs`.
- [ ] There's a test for invalid signature → 401 and no write.
- [ ] There's a test for a retry → one event.
