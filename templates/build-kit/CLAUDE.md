# Blueprint: Elixir + Phoenix + FACT (event sourcing sin base de datos)

Esto es «cómo se construye aquí». No es una guía de estilo: es el contrato que
permite que un agente implemente una rodaja sin que nadie tenga que revisar
dónde va cada fichero ni cómo se llama cada cosa.

Los eventos de dominio viven en `lib/my_app/slices/<rodaja>/`, uno por fichero.
El armazón está en `lib/my_app/` — léelo antes de la primera rodaja:
`decide.ex`, `lectura.ex`, `state_change.ex`, `state_view.ex`, `fact_event.ex`,
`id.ex`.

## Restricciones de ficheros

- **Ruta estricta:** trabaja dentro de `lib/my_app/slices/<rodaja>/*` y
  `test/my_app/slices/<rodaja>/*`. Nada más, salvo lo que diga explícitamente el
  skill que estés ejecutando.
- **Una rodaja, una carpeta.** Nunca ficheros de dos rodajas mezclados.
- **No toques `lib/my_app/` (el armazón)** ni `lib/my_app_web/` sin que te lo pidan.
  Las pantallas no las construye este kit — ver «Lo que este kit NO hace».

## Estándares

- **Lenguaje:** Elixir. **Framework:** Phoenix 1.8+. **Almacén:** `fact` 0.2.0,
  ficheros, sin base de datos.
- **Nombres de dominio en castellano** (`Comprobacion`, `veredicto`,
  `geometria`). Los módulos del armazón conservan sus nombres en inglés
  (`Decide`, `StateChange`, `StateView`, `FactEvent`) porque vienen copiados de
  `traduka-servo` y se comparten entre proyectos.
- **Sin Ecto en el dominio.** Está en `deps` sólo por `phoenix_ecto`. Para
  identificadores, `MyApp.Id.uuid4/0`.
- **HTTP:** `Req`. Nunca `httpoison`, `tesla` ni `httpc`.
- **Nunca anides módulos en el mismo fichero**: provoca dependencias cíclicas.

## Reglas de arquitectura

- **Todos los invariantes van en `core.ex`, que es puro.** Sin efectos, sin
  llamadas de red, sin acceso al almacén. `execute/2` devuelve `{:ok, [eventos]}`
  o `{:error, atom}`.
- **Toda escritura pasa por `MyApp.Decide.execute/4`.** Nunca llames a
  `Fact.append` directamente: `Decide` es quien reintenta ante conflictos de
  concurrencia y quien espera a que lo escrito sea visible.
- **Toda lectura pasa por `MyApp.Lectura.leer/2`**, no por `Fact.read`
  directamente: elige el índice en vez de recorrer el ledger.
- **Las rodajas no se acoplan.** Sólo comparten las *cadenas* de los tipos de
  evento. Nunca structs compartidos: los `apply_event/2` emparejan mapas crudos
  (`%{"event_type" => ..., "event_data" => ...}`).
- **`append` puro por defecto.** Reevaluar tiene que ser gratis; gana el último
  evento en orden de log.

## Construir una rodaja

**Usa siempre el skill que corresponda. Nunca implementes una rodaja a mano.**
**Todos los campos, nombres de evento, de comando y reglas de negocio salen
EXCLUSIVAMENTE de `slice.json`.** No inventes ninguno que no esté ahí.

0. **Comprueba que el `slice.json` está completo antes de nada.** El bucle
   puebla `.slices/` con el endpoint **resumen**, que devuelve seis campos
   (`id`, `title`, `status`, `sliceType`, `contextId`, `contextName`) y **ni
   `fields`, ni `events`, ni `specifications`**. Un fichero de ~230 bytes es un
   stub y no se puede construir con él.

   Si lo es, refresca: `python3 .build-kit/refrescar-rodajas.py`. Usa
   `/slicedata?contextName=` —la definición entera— y nombra las carpetas con
   la misma regla que el bucle, así que no deja duplicados.

1. Lee `.build-kit/.slices/<contexto>/<rodaja>/slice.json`.
2. Determina el tipo y llama al skill:
   - `sliceType == "TRANSLATION"` → lee `description` y `notes`; por defecto
     `/build-automation`. En este proyecto la traducción va **en línea** dentro
     del procesador, nunca como rodaja aparte.
   - **evento externo entrante** (el sistema de fuera empieza: una confirmación
     que llega, un resultado que otro servicio devuelve más tarde) →
     `/build-webhook`. La `description` lo dice; si dudas entre esto y un
     automatismo, la pregunta es **quién empieza**.
   - `processors` no vacío → `/build-automation`
   - `readmodels` o `queries` no vacíos → `/build-state-view`
   - por defecto (tiene `commands` / `events`) → `/build-state-change`
3. Sigue el skill entero. No te desvíes.
4. **Verifica contra `slice.json`**: cada campo de comando, cada campo de
   evento y cada especificación tiene que estar en el código. Si no está en
   `slice.json`, no puede estar en el código — con **una excepción**, la de los
   campos generados, explicada abajo.
5. `mix precommit` (compila con `--warnings-as-errors`, formatea y corre los
   tests). Luego los tests de la rodaja.
6. Si pasa: `git commit -m "feat: <Nombre de la rodaja>"` y estado `Done`.

## Las tres reglas que `slice.json` no dice

Salieron de construir la primera rodaja **a mano**, antes de que existiera este
kit. Sin ellas un agente produce código que compila y está mal. Los ejemplos son
de esa rodaja; la regla es general.

### 1. Las etiquetas salen de `idAttribute: true`

`slice.json` trae `tags: []` en todos los elementos. **Las etiquetas no están
vacías: están sin derivar.** La regla es mecánica:

> Cada campo del evento con `idAttribute: true` produce una etiqueta
> `<nombre sin el sufijo Id, en snake_case>:<valor>`.

`comprobacionId` y `sesionId` → `["comprobacion:#{e.comprobacion_id}",
"sesion:#{e.sesion_id}"]`.

Importa porque **las etiquetas son las claves de consulta de todo el sistema**:
por ellas preguntan `query/1`, los modelos de lectura y las colas TODO.
Inventarlas rompe en silencio todo lo de aguas abajo.

### 2. Los campos generados viajan en el comando

`slice.json` marca campos como `generated: true` o con
`mapping: "derived:..."`. Un `derived:instante del append` en el evento parece
decir que se genera al escribir — **no lo hagas en `Core`**. `Core` es puro y un
`DateTime.utc_now()` dentro de `execute/2` hace la decisión imposible de probar
sin un reloj.

> Identificadores e instantes se generan en `context.ex` y viajan en el struct
> del comando, aunque `slice.json` no los liste entre los campos del comando.

Es la única desviación autorizada de la regla «si no está en `slice.json`, no
está en el código». Documéntala en el `@moduledoc` del comando.

### 3. La validación no se parte

La regla del repo dice que la validación de forma va en `context.ex` y los
invariantes en `core.ex`. Con las especificaciones del tablero eso no funciona:
los escenarios de rechazo (`SPEC_ERROR`) se prueban en el `core_test.exs`, que
es puro y no pasa por `Context`.

> Toda la validación va en `core.ex`, incluida la de forma. Decodificar JSON o
> comprobar rangos es puro, así que cabe. `context.ex` sólo limpia la entrada
> (`nil`, espacios) y construye el comando.

## Lo que este kit NO hace: pantallas

`slice.json` trae la pantalla como metadatos —`title`, `fields`, `dependencies`
y la prosa de `description`— pero **no trae el diseño**. El HTML que haya en el
tablero no viaja en el payload. Las LiveViews se escriben a mano.

Si la rodaja tiene `screens`: **construye el dominio, escribe el encargo de
pantalla, y para.** No inventes una interfaz.

### El encargo de pantalla

Es el `ui-prompt.md` del paso 12 del bucle. En este proyecto se llama
`docs/pantallas/<rodaja-en-kebab-case>.md`, va **versionado** —a diferencia de
`.build-kit/`, que se regenera— y es el contrato entre el dominio y quien
construya la vista.

**Ejemplo hecho**: `docs/pantallas/EJEMPLO-comprobar-una-parcela.md`, que el kit
deja en el proyecto. Es un encargo real de otro sistema, para que se vea el
nivel de detalle que merece la pena. Bórralo cuando tengas los tuyos.

No es un diseño ni una propuesta de interfaz. Es **qué hay disponible y qué no**,
para que quien la construya no tenga que leerse la rodaja entera ni inventarse
lo que falta. Plantilla:

```markdown
# Pantalla: <título de la pantalla en el tablero>

Rodaja `<título>` · nodo `<id de la pantalla>` · escrito por el bucle el <fecha>.

## Por dónde entra

<Función pública del Context, con su firma y qué devuelve. Literal.>

## Qué devuelve

| campo | tipo | | qué es |
|---|---|---|---|
| `campo` | `String` | | <de la description del tablero, no inventado> |

<Marca `opcional` los que pueden no estar todavía, y di **por qué** — casi
siempre «el evento que lo trae aún no ha llegado».>

## Qué manda de vuelta

<Sólo si la rodaja tiene comando. La función, sus argumentos, y **los átomos de
error que puede devolver**, que la pantalla tiene que traducir a mensajes.>

## Estados que hay que pintar

<Vacío, parcial, completo, error. Un modelo de lectura sin eventos tiene que ser
pintable: di qué se ve entonces.>

## Lo que el tablero dice de esta pantalla

<La `description` del nodo de pantalla, citada. Es la intención de diseño y es
lo único que sobrevive del tablero, porque el HTML no viaja.>

## Lo que el dominio NO da

<Lo más importante del documento. Campos que la pantalla podría querer y no
existen, y si es a propósito. Evita que quien la construya se los invente o
los pida al dominio sin motivo.>
```

Regla al escribirlo: **todo sale de `slice.json` y del código que acabas de
escribir.** Si no sabes qué significa un campo, cita la `description` del
tablero en vez de parafrasear. No propongas disposición, ni copy, ni colores.

## Forma de una rodaja

```
lib/my_app/slices/<rodaja>/
├── <rodaja>.ex        # struct del comando        (sólo escritura)
├── <evento>.ex        # struct del evento + defimpl FactEvent
├── core.ex            # use MyApp.StateChange — todos los invariantes, puro
├── context.ex         # API pública: genera, construye, Decide.execute
└── processor.ex       # sólo automatismos: GenServer que sondea la cola TODO

test/my_app/slices/<rodaja>/
└── core_test.exs      # las especificaciones del tablero, sobre el Core puro
```

Una rodaja de lectura son dos ficheros: `core.ex` y `context.ex`.

**Cuando lleves una rodaja construida, léela antes de la siguiente.** El código
que ya existe manda sobre estas plantillas: si divergen, la plantilla está
vieja.

## Antes de empezar

Lee `.build-kit/AGENTS.md` si existe, para cargar lo aprendido en iteraciones
anteriores. Y al empezar una rodaja, invoca `update-slice-status` con
`InProgress` antes que nada.

## Si algo es ambiguo

Si `slice.json` es genuinamente ambiguo, contradictorio, o le falta una decisión
que necesitas — **no adivines y no construyas igual**. Invoca `request-feedback`
con la pregunta concreta: publica un comentario en la rodaja y la marca
`Blocked`. Luego para.

Es una vía de escape, no un paso rutinario: lee `slice.json` y el skill enteros
primero. La mayoría de las rodajas están completamente especificadas.
