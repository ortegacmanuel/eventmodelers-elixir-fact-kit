---
name: build-state-change
description: Implementa una rodaja de escritura (comando validado contra los eventos replegados, eventos nuevos emitidos) en Elixir con el event store FACT, a partir de un slice.json
---

# Construir una rodaja de escritura

> Antes de nada, lee la definición en `.build-kit/.slices/{Contexto}/{rodaja}/slice.json`.
> Ese fichero es la **fuente de verdad** de todos los campos, eventos y metadatos.
> Nunca inventes campos que no estén ahí.

> Y lee `.build-kit/CLAUDE.md`. Lleva tres reglas que `slice.json` no dice, y las
> tres aparecen aquí abajo porque sin ellas el código compila y está mal.

---

## Qué es una rodaja de escritura

Un comando que decide, contra la historia, si emite eventos. En esta pila:

```
Context.funcion(...)  →  Decide.execute(db, Core, cmd)
                              1. Lectura.leer(db, Core.query(cmd))     → eventos
                              2. Enum.reduce(…, Core.apply_event/2)    → estado
                              3. Core.execute(cmd, estado)             → {:ok, [ev]} | {:error, m}
                              4. FactEvent.to_fact/1                   → mapas
                              5. Fact.append(db, …, {append_condition, pos})
                              6. espera a que lo escrito sea visible
```

`Core` es **puro**. `Decide` pone los efectos. `Context` es la única API pública.

---

## Paso 1 — Leer el `slice.json`

Saca de ahí:

- **`title`** — el nombre de la rodaja. Da nombre a la carpeta, en `snake_case`.
- **`context`** — el contexto acotado.
- **`commands[]`** — con sus `fields[]`: `name`, `type`, `cardinality`,
  `idAttribute`, `generated`, `optional`, `mapping`.
- **`events[]`** — igual, más `dependencies` para saber quién los consume.
- **`specifications[]`** — los escenarios given/when/then **con datos de
  ejemplo**. Son los tests, casi literalmente.
- **`description`** de cada elemento — lleva los invariantes redactados en
  prosa. Es la fuente de las reglas de negocio; léela entera.

> **Comentarios**: cada elemento trae `comments: string[]`. Úsalos como pistas.
> Si un comentario plantea una **decisión abierta** en vez de una pista —«falta
> decidir el límite de uso», «¿stream propio o registro?»— no la decidas tú:
> invoca `request-feedback`. Resolver los consumidos:
> `POST <BASE_URL>/api/org/<ORG_ID>/boards/<BOARD_ID>/nodes/<nodeId>/comments/<commentId>/resolve`.

---

## Paso 2 — El struct del comando

**Fichero:** `lib/my_app/slices/<rodaja>/<rodaja>.ex`

```elixir
defmodule MyApp.Slices.<Rodaja>.<Rodaja> do
  @moduledoc """
  Comando: <lo que el actor quiere hacer, en una frase de dominio>.

  <Y por qué los campos son estos. Si hay campos generados, di aquí que viajan
  en el comando aunque el tablero no los liste — ver más abajo.>
  """

  defstruct [:campo_a, :campo_b]
end
```

**Los campos son los de `commands[].fields[]` en `snake_case`**, más los
generados del paso 3.

---

## Paso 3 — Los campos generados (regla que `slice.json` no dice)

`slice.json` marca campos con `generated: true` o
`mapping: "derived:instante del append"`. **No los generes en `Core`.**

`Core` es puro: un `DateTime.utc_now()` o un `uuid4()` dentro de `execute/2`
hace la decisión imposible de probar sin un reloj y sin sembrar aleatoriedad.

> **Identificadores e instantes se generan en `context.ex` y viajan en el struct
> del comando**, aunque `slice.json` no los liste entre los campos del comando.

Es la **única** desviación autorizada de «si no está en `slice.json`, no está en
el código». Déjala escrita en el `@moduledoc` del comando, con el porqué.

- Identificadores → `MyApp.Id.uuid4()`
- Instantes → `DateTime.utc_now() |> DateTime.to_iso8601()`

---

## Paso 4 — El struct del evento y sus etiquetas

**Fichero:** `lib/my_app/slices/<rodaja>/<evento>.ex`, en `snake_case`.

```elixir
defmodule MyApp.Slices.<Rodaja>.<Evento> do
  @moduledoc """
  Evento: <lo que pasó, en pasado y en lenguaje de dominio>.

  <Qué NO implica. La description del tablero suele decirlo, y suele ser lo más
  valioso que hay ahí.>
  """

  defstruct [:campo_a, :campo_b]

  defimpl MyApp.FactEvent do
    def to_fact(e) do
      %{
        type: "<Evento>",
        data: Map.from_struct(e),
        tags: ["<entidad>:#{e.<entidad>_id}", "<otra>:#{e.<otra>_id}"]
      }
    end
  end
end
```

### Las etiquetas (regla que `slice.json` no dice)

`slice.json` trae `tags: []` en todos los elementos. **No están vacías: están
sin derivar.**

> Cada campo del evento con `idAttribute: true` produce una etiqueta
> `<nombre sin el sufijo Id, en snake_case>:<valor>`.

`comprobacionId` → `"comprobacion:#{e.comprobacion_id}"`.
`sesionId` → `"sesion:#{e.sesion_id}"`.

**Esto importa más que ninguna otra cosa de este skill.** Las etiquetas son las
claves de consulta de todo el sistema: por ellas preguntan `query/1`, los
modelos de lectura y las colas TODO. Una etiqueta inventada no falla — deja de
encontrar eventos, en silencio, aguas abajo.

Si un evento no tiene ningún `idAttribute: true`, **para e invoca
`request-feedback`**: un evento sin etiquetas no se puede consultar.

### El tipo del evento

`type:` es el `title` del evento **tal cual**, en PascalCase y sin espacios.
Es la cadena que emparejan los `apply_event/2` de otras rodajas, así que no la
adornes.

---

## Paso 5 — `core.ex`

**Fichero:** `lib/my_app/slices/<rodaja>/core.ex`

```elixir
defmodule MyApp.Slices.<Rodaja>.Core do
  @moduledoc """
  <Qué decide, y con qué reglas. Si el tablero retiró reglas que parecían
  obvias, di cuáles y por qué: es lo que impide que vuelvan.>
  """

  use MyApp.StateChange

  alias MyApp.Slices.<Rodaja>.{<Comando>, <Evento>}

  @impl true
  def query(%<Comando>{} = cmd) do
    Fact.QueryItem.types(["<Evento>"])
    |> Fact.QueryItem.tags(["<entidad>:#{cmd.<entidad>_id}"])
  end

  @impl true
  def initial_state, do: %{ya_ocurrio: false}

  @impl true
  def apply_event(state, %{"event_type" => "<Evento>"}), do: %{state | ya_ocurrio: true}
  def apply_event(state, _), do: state

  @impl true
  def execute(_cmd, %{ya_ocurrio: true}), do: {:ok, []}

  def execute(%<Comando>{} = cmd, _state) do
    with :ok <- valida(cmd) do
      {:ok, [%<Evento>{...}]}
    end
  end
end
```

### Qué leer en `query/1`

**Sólo lo que la decisión necesita.** No es «todos los eventos de la entidad»:
es el conjunto mínimo que responde a la pregunta que hace `execute/2`.

Si el único invariante es la idempotencia, `query/1` es el propio tipo de evento
acotado por su identificador — con un id recién generado no pliega nada, y a la
vez protege contra un reintento con el mismo id.

`append_condition/1` cae en `query/1` por defecto, que es lo seguro. Sobreescríbelo
sólo si los eventos concurrentes **no pueden** invalidar la decisión.

### La validación entera aquí (regla que `slice.json` no dice)

La regla del repo manda los invariantes a `core.ex` y la validación de forma a
`context.ex`. Con las especificaciones del tablero eso no funciona: los
escenarios `SPEC_ERROR` se prueban en `core_test.exs`, que es puro y no pasa por
`Context`.

> **Toda la validación va en `core.ex`**, incluida la de forma. Decodificar JSON,
> comprobar rangos o contar elementos es puro, así que cabe.
> `context.ex` sólo limpia (`nil`, espacios) y construye el comando.

Los motivos de error son **átomos de dominio** (`:geometria_requerida`,
`:poligono_sin_superficie`), no cadenas: la pantalla los traduce.

### Los umbrales se justifican

Si necesitas una constante que `slice.json` no da, escribe en un comentario **de
dónde sale y en qué unidades**. Un umbral sin justificación es una regla de
negocio inventada.

---

## Paso 6 — `context.ex`

**Fichero:** `lib/my_app/slices/<rodaja>/context.ex`

```elixir
defmodule MyApp.Slices.<Rodaja>.Context do
  @moduledoc "API pública de <la rodaja>."

  alias MyApp.Slices.<Rodaja>.{<Comando>, Core}

  require Logger

  def <verbo>(args...) do
    id = MyApp.Id.uuid4()

    cmd = %<Comando>{
      <entidad>_id: id,
      ...,
      <instante>: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    case escribir(cmd) do
      {:ok, _eventos} -> {:ok, id}
      error -> error
    end
  end

  # `Application.fact_db/0` **lanza** si el store no está en pie, y esto se
  # llama desde manejadores de LiveView: una excepción ahí mata la sesión del
  # visitante y se lleva lo que acababa de introducir.
  defp escribir(cmd) do
    MyApp.Decide.execute(MyApp.Application.fact_db(), Core, cmd)
  rescue
    e in RuntimeError ->
      Logger.error("no se pudo escribir: #{Exception.message(e)}")
      {:error, :almacen_no_disponible}
  end
end
```

Devuelve `{:ok, <identificador>}`, no `{:ok, eventos}`: el identificador es lo
que la capa de arriba necesita para suscribirse al resultado y para enseñar la
referencia.

---

## Paso 7 — `core_test.exs`

**Fichero:** `test/my_app/slices/<rodaja>/core_test.exs`

**Un `describe` por especificación de `slice.json`, con su título literal.** Así
se ve de un vistazo qué escenario del tablero cubre cada bloque.

```elixir
defmodule MyApp.Slices.<Rodaja>.CoreTest do
  use ExUnit.Case, async: true

  alias MyApp.Slices.<Rodaja>.{<Comando>, <Evento>, Core}

  defp dado(eventos),
    do: Enum.reduce(eventos, Core.initial_state(), &Core.apply_event(&2, &1))

  defp evento_fact(tipo, datos \\ %{}),
    do: %{"event_type" => tipo, "event_data" => datos}

  defp cmd(overrides \\ %{}), do: Map.merge(%<Comando>{...}, overrides)

  describe "<título literal de la especificación>" do
    test "<lo que fija>" do
      assert {:ok, [%<Evento>{} = e]} = Core.execute(cmd(), dado([]))
      assert e.campo == "<el ejemplo del slice.json>"
    end
  end
end
```

Reglas:

- **Sólo el `Core` puro.** Sin store, sin `Context`, sin `ConnCase`.
- **Los datos salen de `specifications[].given/when/then[].fields[].example`**,
  literalmente. No inventes valores: los del tablero suelen estar medidos.
- **Prueba también `FactEvent.to_fact/1`**: tipo, datos y **las dos etiquetas**.
  Es lo único que fija la regla del paso 4.
- Los eventos del `given` se fabrican como **mapas de claves string**,
  respetando la frontera que mantiene independientes a las rodajas.
- Un escenario `SPEC_ERROR` es `assert {:error, :motivo} = Core.execute(...)`.

### Si un test falla, sospecha del test

Los ejemplos del tablero suelen venir medidos contra sistemas reales. Antes de
cambiar el código, comprueba que la aserción dice lo que el escenario dice.

---

## Paso 8 — Quality gate

```
mix precommit                          # --warnings-as-errors, format, tests
mix test test/my_app/slices/<rodaja>/    # sólo los de la rodaja
```

Nunca commitees con avisos en rojo.

---

## Verificación final contra `slice.json`

Antes de dar la rodaja por hecha:

- [ ] Cada campo de `commands[].fields[]` está en el struct del comando.
- [ ] Cada campo de `events[].fields[]` está en el struct del evento.
- [ ] Ningún campo inventado — salvo los generados del paso 3, documentados.
- [ ] Cada `idAttribute: true` produce su etiqueta.
- [ ] Cada `specifications[]` tiene su `describe` en el test.
- [ ] `Core` no tiene efectos: ni `utc_now`, ni `uuid4`, ni `Req`, ni `Fact`.
- [ ] `apply_event/2` tiene cláusula final que ignora lo que no es suyo.
- [ ] Si la rodaja tiene `screens`, **no** has escrito interfaz: has escrito el
      **encargo de pantalla** en `docs/pantallas/<rodaja>.md`, como manda
      `.build-kit/CLAUDE.md`, y lo has anotado en `progress.txt`. Incluye los
      **átomos de error** que devuelve `Core`: la pantalla los tiene que
      traducir y no los puede adivinar.
