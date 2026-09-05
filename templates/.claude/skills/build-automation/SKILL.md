---
name: build-automation
description: Implementa una rodaja de automatismo (un procesador que vigila una cola TODO, llama a un sistema externo y registra el resultado como hecho propio) en Elixir con el event store FACT, a partir de un slice.json
---

# Construir una rodaja de automatismo

> Antes de nada, lee la definición en `.build-kit/.slices/{Contexto}/{rodaja}/slice.json`.
> Ese fichero es la **fuente de verdad**. Nunca inventes campos que no estén ahí.

> Y lee `.build-kit/CLAUDE.md`. Esta forma de rodaja es la que más se desvía de
> lo que parece decir el tablero, así que las tres reglas de ahí importan aquí
> el doble.

---

## Qué es una rodaja de automatismo

Nadie pulsa nada. Un procesador vigila una **cola TODO** —que es un modelo de
lectura, no una tabla—, hace el trabajo y **escribe un hecho propio**.

```
Cola TODO (STATE_VIEW)  →  Processor (GenServer)
                              → Task.Supervisor.async_nolink
                                  → llamada externa
                                  → Context.<verbo>(...)  →  Decide  →  evento
```

Cinco ficheros: los cuatro de una rodaja de escritura, más `processor.ex`.
**Construye primero los cuatro con `/build-state-change`**, y vuelve aquí para
el procesador. Este skill sólo cubre lo que aquélla no.

---

## Paso 1 — La cola TODO existe y no la construyes tú

`processors[].dependencies` apunta a un READMODEL que es la cola. Suele ser una
rodaja aparte en el tablero, con su propio `slice.json`.

**Si esa rodaja no está construida, para.** Constrúyela primero con
`/build-state-view`, o invoca `request-feedback` si no está en el tablero.

Una cola TODO es «lo pedido menos lo resuelto»: pliega el evento que abre el
trabajo y el que lo cierra, y deja fuera los que ya tienen cierre. **Es una
consulta, no una resta** — no lleves un contador.

---

## Paso 2 — La capa de anticorrupción, y en qué dirección va

Cuando la rodaja llama a un sistema externo, la tentación es modelar «recibimos
esto». **No lo hagas.**

> **Nuestro hecho de dominio manda y la respuesta externa lo rellena**, no al
> revés.

La diferencia no es de estilo. Si el evento es «la respuesta de X menos cosas»,
un cambio en X se propaga por todo el sistema. Si el evento es nuestro hecho y X
es el insumo, un cambio en X sólo mueve el mapeo, en un sitio.

Consecuencias concretas:

- **Un solo evento, no dos.** No emitas un `RespuestaDeXRecibida` además del
  hecho de dominio: «recibimos esto» no es un hecho de negocio, y darle nodo
  propio mete la forma ajena en la línea de tiempo — que es justo lo que una
  capa de anticorrupción evita.
- **El cuerpo crudo viaja como atributo técnico** (`respuestaCruda`,
  `technicalAttribute: true`) para forense y para poder rederivar. No se
  proyecta a ninguna vista.
- **Los nombres de campo son de dominio**, no de la API externa. Nunca
  `risk_pcrop`: `veredicto`. Nunca `eufo2020`: `coberturaForestal2020`. Qué capa
  lo midió viaja en un campo de procedencia, no en el nombre.
- **La preposición del evento importa.** `…EvaluadaConX` dice que X calculó y
  nosotros valoramos. `…EvaluadaPorX` diría que X hizo nuestra valoración. El
  tablero ya eligió: respétalo exactamente.

### Dónde va la fuente: en el nombre o en un campo

| quién dictamina | dónde va |
|---|---|
| un tercero evalúa y devuelve un veredicto | en el **nombre del evento** |
| calculamos nosotros contra un fichero | en un campo de **procedencia** (`versionDatos`) |

En el segundo caso **no hay campo `fuente`**: sería un error de categoría, daría
a entender que hay un evaluador externo donde no lo hay. Y el campo de
procedencia se describe solo — `"Provita ANP 2023-07-29"`, no `"2023-07-29"`.

### La traducción va en línea

El tablero puede mostrar cuatro o seis rodajas para una llamada externa
(petición → evento externo → vista de respuesta → traductor → comando → evento).
**En el código es un procesador que llama y registra.** El modelo prioriza la
claridad conceptual y la visibilidad de la frontera; la implementación prioriza
no tener handlers que no hacen nada.

Si la llamada externa fuera de verdad asíncrona —webhook entrante—, el punto de
entrada es un **controlador de Phoenix**, no un procesador.

---

## Paso 3 — `processor.ex`

**Fichero:** `lib/my_app/slices/<rodaja>/processor.ex`

```elixir
defmodule MyApp.Slices.<Rodaja>.Processor do
  @moduledoc """
  Automatismo: vigila <la cola>, <hace el trabajo> y registra <el evento>.

  <Y las cifras que justifican el intervalo y los plazos. Un `@poll_interval`
  sin medición al lado es un número inventado.>
  """

  use GenServer

  require Logger

  alias MyApp.Slices.<Cola>.Context, as: Cola
  alias MyApp.Slices.<Rodaja>.Context, as: <Rodaja>

  @poll_interval :timer.seconds(5)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    if Keyword.get(opts, :arrancar?, true) do
      programar()
      {:ok, %{}}
    else
      {:ok, %{}}
    end
  end

  @impl true
  def handle_info(:poll, state) do
    procesar_pendientes()
    programar()
    {:noreply, state}
  end

  # Las tareas van con `async_nolink`: su resultado y su caída llegan como
  # mensajes, y hay que atenderlos o el GenServer se llena de correo sin leer.
  def handle_info({ref, _resultado}, state) when is_reference(ref), do: {:noreply, state}
  def handle_info({:DOWN, _ref, :process, _pid, :normal}, state), do: {:noreply, state}

  def handle_info({:DOWN, _ref, :process, _pid, motivo}, state) do
    Logger.error("tarea de <rodaja> falló: #{inspect(motivo)}")
    {:noreply, state}
  end

  def handle_info(_otro, state), do: {:noreply, state}

  defp procesar_pendientes do
    Enum.each(Cola.pendientes(), fn item ->
      Task.Supervisor.async_nolink(MyApp.TaskSupervisor, fn -> procesar(item) end)
    end)
  rescue
    e -> Logger.warning("el sondeo falló: #{Exception.message(e)}")
  end

  defp procesar(item) do
    case llamar_al_externo(item) do
      {:ok, respuesta} -> <Rodaja>.<verbo>(item.<id>, respuesta)
      {:error, motivo} -> Logger.error("<externo> falló para #{item.<id>}: #{inspect(motivo)}")
    end
  end
end
```

Reglas que no se negocian:

- **La llamada externa va dentro de la `Task`, nunca en el `GenServer`.** Un
  `Req.post` en `handle_info` bloquea el sondeo entero.
- **`arrancar?: true` por defecto, configurable.** En tests se apaga: un
  procesador vivo durante la suite hace llamadas de red reales.
- **`Req`, nunca otra cosa.** Con `receive_timeout` explícito si la llamada es
  lenta.
- **Añádelo al árbol de supervisión** en `lib/my_app/application.ex`, después de
  `Fact.Supervisor` y de `Task.Supervisor`, con
  `Application.get_env(:my_app, :<rodaja>, [])`.
- **Los secretos salen de `config/runtime.exs`**, nunca del código. Si la clave
  no está, el procesador arranca y registra el fallo; no revienta el arranque de
  la aplicación entera.

### El fallo del externo es un caso de dominio

Si `slice.json` modela un evento de fallo, emítelo. Si no lo modela, **regístralo
y deja el ítem en la cola** — no inventes un evento de fallo: es una decisión de
modelo, no de implementación, y le toca al tablero.

Y si el fallo del externo produce un resultado **tranquilizador** en vez de un
error visible, dilo en el `@moduledoc` con todas las letras. Es la clase de fallo
que nadie descubre a tiempo.

---

## Paso 4 — Tests

**El procesador no se prueba con red.** Lo que se prueba es el `Core` de su
rodaja de escritura, con `/build-state-change`, más:

- Que la cola devuelve lo pendiente y **deja de devolverlo** una vez resuelto.
- El mapeo de la respuesta externa a campos de dominio, como función pura. Sácalo
  a una función aparte (`defp a_dominio(respuesta)`) precisamente para poder
  probarlo sin red.

Con `arrancar?: false` en `config/test.exs` para esta rodaja.

---

## Paso 5 — Quality gate

```
mix precommit
mix test test/my_app/slices/<rodaja>/
```

---

## Verificación final contra `slice.json`

- [ ] Los cuatro ficheros de escritura están, hechos con `/build-state-change`.
- [ ] **Un solo evento de dominio**, no uno de «respuesta recibida».
- [ ] Los nombres de campo son de dominio, no de la API externa.
- [ ] El cuerpo crudo va como atributo técnico y **no** se proyecta.
- [ ] La preposición del nombre del evento es la del tablero (`Con…` / `Por…`).
- [ ] La llamada externa está dentro de la `Task`, no en el `GenServer`.
- [ ] Los tres `handle_info` de las tareas están (`{ref, _}`, `:DOWN` normal,
      `:DOWN` con motivo).
- [ ] El procesador está en el árbol de supervisión y apagado en tests.
- [ ] Los secretos vienen de `runtime.exs`.
- [ ] El mapeo respuesta → dominio es una función pura y tiene test.
