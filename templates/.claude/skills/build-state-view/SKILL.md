---
name: build-state-view
description: Implementa una rodaja de lectura (un modelo de lectura plegado de eventos, sin tablas ni proyecciones materializadas) en Elixir con el event store FACT, a partir de un slice.json
---

# Construir una rodaja de lectura

> Antes de nada, lee la definición en `.build-kit/.slices/{Contexto}/{rodaja}/slice.json`.
> Ese fichero es la **fuente de verdad** de todos los campos y metadatos.
> Nunca inventes campos que no estén ahí.

> Y lee `.build-kit/CLAUDE.md`, sobre todo la regla de las etiquetas: aquí es
> donde se cobra o se rompe.

---

## Qué es una rodaja de lectura

Una vista que se **pliega al vuelo desde los eventos**. En esta pila **no hay
migración, ni tabla, ni proyección materializada**: se lee y se reduce.

```
Context.funcion(args)  →  Lectura.leer(db, Core.query(args))
                       →  Enum.reduce(eventos, Core.initial_state(), &Core.apply_event/2)
                       →  dar forma al resultado
```

Dos ficheros, no cuatro: `core.ex` y `context.ex`. Sin comando y sin evento.

---

## Paso 1 — Leer el `slice.json`

- **`readmodels[]`** con sus `fields[]`. Fíjate en:
  - `mapping: "<Evento>.<campo>"` → **copia directa** al plegar ese evento.
  - `mapping: "derived:…"` → **cálculo al leer**. La prosa dice cuál.
  - `optional: true` → todavía no ha llegado el evento que lo trae.
  - `generated: true` → derivado, no viene de ningún evento.
  - `cardinality: "List"` con `subfields` → una lista de mapas.
- **`specifications[]`** — el `given` son los eventos, el `then` es el estado
  esperado. **Los datos de `examples` en el escenario son el estado final**, y
  son los que van al test.
- **`description` del modelo de lectura** — lleva escrito qué es cálculo y qué
  es copia, y suele justificar por qué. Léela entera antes de escribir nada.

---

## Paso 2 — `core.ex`

**Fichero:** `lib/my_app/slices/<rodaja>/core.ex`

```elixir
defmodule MyApp.Slices.<Rodaja>.Core do
  @moduledoc """
  <Qué responde esta vista, y acotada por qué. Y qué NO responde — suele haber
  otra vista parecida con otro alcance, y confundirlas es el error típico.>
  """

  @behaviour MyApp.StateView

  @impl true
  def query(<clave>) do
    Fact.QueryItem.types(["<EventoA>", "<EventoB>"])
    |> Fact.QueryItem.tags(["<entidad>:#{<clave>}"])
  end

  @impl true
  def initial_state, do: %{campo: nil, lista: []}

  @impl true
  def apply_event(state, %{"event_type" => "<EventoA>", "event_data" => d}) do
    %{state | campo: d["campo"]}
  end

  def apply_event(state, _), do: state
end
```

Ojo con `@behaviour` y no `use`: `StateView` no inyecta nada.

### La consulta lleva TODOS los tipos que la vista necesita

Es el fallo más caro de esta forma de rodaja. Si el modelo de lectura pliega
tres tipos de evento, `query/1` tiene que nombrar los tres. Uno que falte no
rompe nada: deja un campo en `nil` para siempre.

Saca la lista de los `mapping:` de los campos — cada `<Evento>.<campo>` nombra
un tipo que tiene que estar en `query/1`.

### La etiqueta acota el alcance

`Fact.QueryItem.tags(["comprobacion:#{id}"])` responde «cómo va **ésta**».
`tags(["sesion:#{id}"])` responde «qué he pedido **yo**». Son vistas distintas
aunque plieguen los mismos eventos, y el tablero suele tener las dos.

La etiqueta sale de la misma regla que en escritura: los campos con
`idAttribute: true`. Si no sabes cuál acota esta vista, mira qué campo del
modelo de lectura es el `idAttribute`.

### Lo derivado se calcula aquí, no se guarda

Un campo con `mapping: "derived:presencia de <Evento>"` es
`%{state | estado: "resuelta"}` dentro del `apply_event/2` de ese evento.
Un `derived:` que combina varios se calcula al final, en `context.ex`.

**Nunca guardes en el evento algo que se puede derivar al leer.** Si te parece
que falta un campo, casi siempre es que hay que derivarlo.

### Listas por índice

Con `cardinality: "List"` el estado lleva una lista y `apply_event/2` la
extiende. Ordénala explícitamente en `context.ex` — el orden de llegada de los
eventos es el orden del log, que puede no ser el que la pantalla quiere.

---

## Paso 3 — `context.ex`

```elixir
defmodule MyApp.Slices.<Rodaja>.Context do
  @moduledoc "API pública de <la vista>."

  alias MyApp.Slices.<Rodaja>.Core

  def <verbo>(<clave>) do
    MyApp.Application.fact_db()
    |> MyApp.Lectura.leer(Core.query(<clave>))
    |> Enum.reduce(Core.initial_state(), &Core.apply_event(&2, &1))
    |> dar_forma()
  end

  defp dar_forma(state), do: state
end
```

**Siempre `MyApp.Lectura.leer/2`, nunca `Fact.read/2`.** `Lectura` elige el
índice en vez de recorrer el ledger entero; la diferencia es de tres órdenes de
magnitud en cuanto la historia crece.

`dar_forma/1` es donde van los derivados que combinan varios eventos y el orden
de las listas. Nada de formato de presentación: cadenas con formato, textos
traducidos y decisiones de pintado son de la pantalla, no del modelo.

---

## Paso 4 — `core_test.exs`

**Fichero:** `test/my_app/slices/<rodaja>/core_test.exs`

```elixir
defmodule MyApp.Slices.<Rodaja>.CoreTest do
  use ExUnit.Case, async: true

  alias MyApp.Slices.<Rodaja>.Core

  defp plegar(eventos),
    do: Enum.reduce(eventos, Core.initial_state(), &Core.apply_event(&2, &1))

  defp ev(tipo, datos \\ %{}), do: %{"event_type" => tipo, "event_data" => datos}

  describe "<título literal de la especificación>" do
    test "<lo que fija>" do
      estado = plegar([ev("<EventoA>", %{"campo" => "valor"})])
      assert estado.campo == "valor"
    end
  end
end
```

- **Sólo el `Core` puro**, sin store y sin `Context`.
- **Los datos salen del escenario**: el `given` son los eventos, y `examples`
  del escenario es el estado esperado.
- **Prueba el estado inicial**: un modelo de lectura sin eventos tiene que ser
  legible, no reventar. La pantalla lo va a pintar mientras llega el resto.
- **Prueba el orden de llegada** si la vista pliega varios flujos que llegan sin
  orden garantizado. Dos eventos en un orden y en el otro tienen que dar lo
  mismo, o el sistema tiene una carrera.
- **Prueba que `apply_event/2` ignora lo ajeno**: un tipo que no es suyo no debe
  cambiar el estado.
- **Nunca compares `Map.keys/1` con una lista.** El orden **no está
  garantizado** y la aserción falla de forma intermitente — pasa en local y
  tumba el gate más tarde. Si quieres fijar las claves de una fila:

  ```elixir
  assert MapSet.new(Map.keys(fila)) == MapSet.new([:a, :b, :c])
  ```

  Vale para cualquier comparación de colecciones sin orden definido.

---

## Paso 5 — Quality gate

```
mix precommit
mix test test/my_app/slices/<rodaja>/
```

---

## Verificación final contra `slice.json`

- [ ] Cada campo de `readmodels[].fields[]` existe en el estado o en `dar_forma/1`.
- [ ] `query/1` nombra **todos** los tipos de evento que aparecen en los `mapping:`.
- [ ] Los `derived:` se calculan, no se guardan.
- [ ] Cada `specifications[]` tiene su `describe`.
- [ ] Hay un test del estado inicial vacío.
- [ ] Se lee con `MyApp.Lectura.leer/2`, no con `Fact.read/2`.
- [ ] Si la rodaja tiene `screens`, **no** has escrito interfaz: has escrito el
      **encargo de pantalla** en `docs/pantallas/<rodaja>.md`, como manda
      `.build-kit/CLAUDE.md`, y lo has anotado en `progress.txt`.
