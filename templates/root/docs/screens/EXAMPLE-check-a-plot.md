# Screen: Plot Checker

Slice `Check a plot` · node `dfa96352-…`.

> **An example, not an empty template.** This is a real brief from another
> system — an EUDR traceability tool for Venezuelan cocoa and coffee — so you
> can see how much detail is worth writing. Delete it once you have your own.
> The template lives in `.build-kit/CLAUDE.md`.
>
> The part most worth copying is the last section, **"What the domain does NOT
> give you"**: it's what stops whoever builds the view from inventing fields.

## How it's entered

```elixir
MyApp.Slices.CheckAPlot.Context.check(geometry, session_id)
# → {:ok, check_id} | {:error, reason}
```

`geometry` is a GeoJSON string. `session_id` comes from the cookie, set by
`MyAppWeb.Plugs.Session` — the LiveView reads it from `session` in `mount/3`, it
doesn't generate it: a LiveView mounts twice and the session can only be written
on the first pass.

It returns the identifier rather than the events because that's what the view
needs: to subscribe to the result, and to show the reference — **the first eight
characters**, which is what support asks for.

## What it sends back

One command. Every error atom it can return, and the screen has to translate them
because it can't guess them:

| atom | when |
|---|---|
| `:geometry_required` | empty or absent |
| `:geometry_invalid` | not GeoJSON, or neither `Point` nor `Polygon` |
| `:coordinates_out_of_range` | longitude outside ±180 or latitude outside ±90 |
| `:polygon_encloses_no_area` | the ring closes but encloses nothing |
| `:store_unavailable` | the event store isn't up — **not the visitor's fault** |

That last one deserves a different message from the other four: the first four
are things the visitor can fix, the fifth isn't.

There's also a public function to validate **before** submitting, which is what
lets the button enable or disable without a round trip through the command:

```elixir
MyApp.Slices.CheckAPlot.Core.validate_geometry(blob)  # → :ok | {:error, reason}
```

## States to render

- **No geometry** — can't check.
- **Valid geometry** — can check.
- **Rejected geometry** — the atom's message, and can't check.
- **Submitting** — the command takes ~240 ms on a process's first write, because
  `Application.fact_db/0` resolves with retries.
- **Submitted** — there's a `check_id`; show the reference.

## What the board says about this screen

> The real input. You get here by pressing "Check a plot", and **the first thing
> that appears is the map** — no sign-up and no questions first.
>
> **Point by default: two steps, not three.** The step asking "does it fit in the
> 4-hectare box?" was removed. That question asked the visitor to *declare* their
> plot's area, and it was a declaration we can't verify: with a point there's no
> area to measure.
>
> **And the honest reason to draw is measured.** Five pins dropped inside the
> same 5.02 ha plot: four returned `low risk` and one `insufficient information`.
> With `Area = 0` the provider's 10 % threshold **collapses to zero**, so a pin is
> a one-pixel sample with zero tolerance.
>
> Drawing stays available and is never required. And there's a crop-specific
> reason not to require it: shade-grown cocoa and coffee **are indistinguishable
> from forest in satellite imagery**, so the grower may not recognise their own
> boundaries from above. A point asks "where is it?", which they can answer.

## What the domain does NOT give you

The most important part of this document.

- **There is no country validation.** A geometry outside the country is accepted
  and written. The country arrives later, from the external evaluation, and
  **the result screen** is what must withhold the verdict when it isn't the
  expected one. Watch out: with swapped coordinates the provider answers
  `Country: Unknown` **and `risk: low`** — the failure produces the most
  reassuring screen there is.
- **There is no zoom or area validation.** The minimum zoom is a **UI** rule, not
  a domain one: it lives in the LiveView. And the 4-hectare threshold isn't
  checked anywhere, because with a pin we don't know the area — the grower does.
- **There is no `geometryType`, `centroid`, `areaHa` or `decimals`.** All four
  are pure functions of `geometry` and were removed on purpose: a stored derived
  field ends up contradicting its source. The blob **already says**
  `"type":"Point"`; derive it when rendering.
- **The six-decimal precision requirement isn't validated**: it's satisfied by
  construction, because the geometry comes from a tap on the map. **It is the
  screen's responsibility** to emit them.
- **There is no status or progress.** This slice writes and returns. "How is the
  check going" is another slice, and it may not exist yet — which is why this
  screen closes with the reference instead of navigating to a tracker.
