---
name: build-webhook
description: Implementa una rodaja cuyo disparador es un evento externo entrante — un webhook — en Elixir/Phoenix con el event store FACT, a partir de un slice.json
---

# Construir una rodaja de webhook

> Antes de nada, lee la definición en `.build-kit/.slices/{Contexto}/{rodaja}/slice.json`.
> Ese fichero es la **fuente de verdad**. Nunca inventes campos que no estén ahí.

> Y lee `.build-kit/CLAUDE.md`. Las tres reglas que `slice.json` no dice aplican
> aquí igual que en cualquier otra rodaja de escritura.

---

## Cuándo es esta forma y no un automatismo

La diferencia no es «hay un sistema externo»: es **quién empieza**.

| | quién empieza | punto de entrada |
|---|---|---|
| **Automatismo** | nosotros, sondeando una cola TODO | `processor.ex` (GenServer) |
| **Webhook** | el sistema externo, cuando le parece | un **controlador de Phoenix** |

Si la rodaja describe algo que *nos llega* —una confirmación de pago, un
resultado que un servicio calculó y devuelve más tarde, un cambio de estado en
otro sistema— es un webhook. Y entonces **no hay procesador**: no hay nada que
sondear, porque no somos nosotros los que preguntamos.

Un error típico es montar un GenServer para esto. Sobra: el que llama ya trae el
dato.

---

## Paso 1 — Los cuatro ficheros de escritura

Un webhook es **una rodaja de escritura con otro disparador**. Construye primero
comando, evento, `core.ex` y `context.ex` con `/build-state-change`, y vuelve
aquí para la capa web. Este skill sólo cubre lo que aquélla no.

Aplica todo lo de allí sin excepción: las etiquetas salen de `idAttribute: true`,
los identificadores e instantes se generan en `context.ex`, y la validación va
entera en `core.ex`.

---

## Paso 2 — La traducción, y en qué dirección va

Igual que en un automatismo: **nuestro hecho de dominio manda y el cuerpo del
webhook lo rellena**, no al revés.

- **Un solo evento.** No emitas un `WebhookRecibido` además del hecho de
  negocio: «nos llegó algo» no es un hecho de dominio, y darle evento propio
  mete la forma ajena en la línea de tiempo.
- **El cuerpo crudo va como atributo técnico** (`respuestaCruda`,
  `technicalAttribute: true`), para forense y para poder rederivar. No se
  proyecta a ninguna vista.
- **Los nombres de campo son de dominio**, no los del proveedor.
- **La traducción es una función pura** en `context.ex` o en un módulo aparte:
  `defp a_dominio(cuerpo)`. Sácala para poder probarla sin HTTP — es la única
  parte de un webhook que merece test unitario de verdad.

---

## Paso 3 — El controlador

**Fichero:** `lib/my_app_web/controllers/<rodaja>_webhook_controller.ex`

```elixir
defmodule MyAppWeb.<Rodaja>WebhookController do
  @moduledoc """
  Punto de entrada de <el sistema externo>.

  <Qué manda, cuándo, y qué espera de vuelta. Si el proveedor reintenta ante un
  fallo, dilo aquí: cambia por completo cómo hay que responder.>
  """

  use MyAppWeb, :controller

  require Logger

  alias MyApp.Slices.<Rodaja>.Context, as: <Rodaja>

  def webhook(conn, params) do
    case <Rodaja>.<verbo>(params) do
      {:ok, _id} ->
        send_resp(conn, 200, "OK")

      {:error, motivo} ->
        # 200 a propósito: el cuerpo llegó y lo hemos entendido; que nosotros no
        # podamos procesarlo no es culpa de quien llama, y devolver 4xx o 5xx
        # hace que el proveedor reintente para siempre el mismo cuerpo malo.
        Logger.error("webhook de <externo> rechazado: #{inspect(motivo)}")
        send_resp(conn, 200, "OK")
    end
  end
end
```

### Qué código devolver, que no es obvio

- **200 aunque el dominio rechace.** El proveedor sólo sabe si le llegó, no si
  nos sirvió. Un 4xx o 5xx lo pone a reintentar el mismo cuerpo que ya sabemos
  que no vale.
- **Responde rápido y no bloquees.** Si el trabajo es largo, escribe el hecho y
  deja lo demás a un automatismo — el webhook sólo tiene que registrar que llegó.
- **Devuelve 401 sólo cuando la firma no valida.** Ese sí es un problema del que
  llama.

---

## Paso 4 — Verificar la firma, en un plug

**Nunca en el controlador.** La verificación necesita el **cuerpo crudo**, y
para cuando el controlador lo ve, `Plug.Parsers` ya lo ha decodificado y
tirado.

Dos plugs:

**`lib/my_app_web/plugs/cache_raw_body.ex`** — guarda el cuerpo antes de
parsearlo, vía la opción `:body_reader` de `Plug.Parsers` en `endpoint.ex`.

**`lib/my_app_web/plugs/<externo>_webhook_signature.ex`** — compara la firma con
el cuerpo guardado y **corta con 401** si no cuadra.

```elixir
defmodule MyAppWeb.Plugs.<Externo>WebhookSignature do
  @moduledoc """
  Verifica la firma de <externo> contra el cuerpo **crudo**.

  Va en un plug y no en el controlador porque `Plug.Parsers` ya ha consumido el
  cuerpo cuando el controlador entra, y firmar sobre el JSON re-serializado no
  coincide: el orden de las claves y los espacios cambian.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    secreto = Application.get_env(:my_app, :<externo>)[:webhook_secret]

    with [firma] <- get_req_header(conn, "x-<externo>-signature"),
         crudo when is_binary(crudo) <- conn.assigns[:raw_body],
         true <- valida?(firma, crudo, secreto) do
      conn
    else
      _ -> conn |> send_resp(401, "firma inválida") |> halt()
    end
  end

  # `Plug.Crypto.secure_compare/2` y no `==`: comparar cadenas con `==` filtra
  # información por el tiempo que tarda.
  defp valida?(firma, crudo, secreto) do
    esperada = :crypto.mac(:hmac, :sha256, secreto, crudo) |> Base.encode16(case: :lower)
    Plug.Crypto.secure_compare(firma, esperada)
  end
end
```

**Si `slice.json` no dice nada de firma, pregunta.** Un webhook sin verificar es
un endpoint público que escribe en el event store: cualquiera puede inventarse
hechos de dominio. Invoca `request-feedback` antes de dejarlo abierto.

---

## Paso 5 — La ruta

En `router.ex`, **en un scope aparte** con su propio pipeline: el pipeline
`:browser` trae `protect_from_forgery`, y un webhook no manda token CSRF.

```elixir
pipeline :webhook do
  plug :accepts, ["json"]
  plug MyAppWeb.Plugs.<Externo>WebhookSignature
end

scope "/webhooks", MyAppWeb do
  pipe_through :webhook
  post "/<externo>", <Rodaja>WebhookController, :webhook
end
```

Y el secreto sale de `config/runtime.exs`, nunca del código.

---

## Paso 6 — Tests

Dos, y ninguno hace red:

**`test/my_app/slices/<rodaja>/core_test.exs`** — las especificaciones del
tablero sobre el `Core` puro, como en cualquier rodaja de escritura.

**`test/my_app_web/controllers/<rodaja>_webhook_controller_test.exs`** — con
`ConnCase`, y fija lo que es propio del webhook:

- Un cuerpo válido **con firma válida** escribe el evento y devuelve 200.
- Un cuerpo válido **con firma inválida** devuelve **401** y **no escribe nada**.
  Es el test que de verdad importa.
- Un cuerpo que el dominio rechaza devuelve **200**, no 4xx, y no escribe.
- **El mismo cuerpo dos veces escribe un solo evento.** Los proveedores
  reintentan; si `Core` no es idempotente, cada reintento duplica el hecho.

---

## Paso 7 — Quality gate

```
mix precommit
mix test test/my_app/slices/<rodaja>/ test/my_app_web/controllers/
```

---

## Verificación final contra `slice.json`

- [ ] Los cuatro ficheros de escritura están, hechos con `/build-state-change`.
- [ ] **No hay procesador.** Si has escrito un GenServer, esta rodaja no era un
      webhook.
- [ ] **Un solo evento de dominio**, no uno de «webhook recibido».
- [ ] Los nombres de campo son de dominio, no del proveedor.
- [ ] El cuerpo crudo va como atributo técnico y no se proyecta.
- [ ] La firma se verifica **en un plug**, contra el cuerpo crudo, con
      `secure_compare/2`.
- [ ] El scope tiene pipeline propio, sin `protect_from_forgery`.
- [ ] El secreto viene de `runtime.exs`.
- [ ] Hay test de firma inválida → 401 y sin escritura.
- [ ] Hay test de reintento → un solo evento.
