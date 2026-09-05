# Build kit: Elixir · Phoenix · FACT

Traduce rodajas de un tablero de [eventmodelers.ai](https://eventmodelers.ai) a
código Elixir con **event sourcing sobre [`fact`](https://hex.pm/packages/fact)**
— ficheros, sin base de datos — y arquitectura de rodajas verticales.

```
npx @eventmodelers/cli init --stack elixir-fact \
  --git https://github.com/<tu-usuario>/eventmodelers-elixir-fact-kit
```

## Qué instala

| | |
|---|---|
| `.claude/skills/build-*` | las cuatro skills: state-change, state-view, automation, webhook |
| `.build-kit/CLAUDE.md` | el blueprint — «cómo se construye aquí» |
| `.build-kit/lib/*.md` | los prompts del bucle ralph |
| `lib/my_app/` | el armazón: `decide`, `lectura`, `state_change`, `state_view`, `fact_event`, `id` |

Las skills compartidas —`connect`, `learn-eventmodelers-api`,
`update-slice-status`, `request-feedback`— las pone el propio CLI.

## Antes de instalar

**Este kit no crea la aplicación Phoenix, la equipa.** Crea el proyecto primero:

```
mix phx.new mi_app --no-ecto
```

`--no-ecto` a propósito: el dominio no usa base de datos. Si necesitas Ecto para
otra cosa (formularios vía `phoenix_ecto`, un espejo desechable de un sistema
externo), añádelo después — pero **fuera del dominio**.

## Después de instalar: renombrar el namespace

El armazón viene con el namespace `MyApp`, porque el CLI copia ficheros y no
sustituye plantillas. Renómbralo:

```bash
APP=mi_app; MOD=MiApp
grep -rl 'MyApp\|my_app' lib .claude/skills .build-kit/CLAUDE.md \
  | xargs sed -i "s/MyApp/$MOD/g; s/my_app/$APP/g"
mv lib/my_app "lib/$APP"
```

Y añade a `mix.exs`:

```elixir
{:fact, "~> 0.2.0"},
{:req, "~> 0.5"},
# `lazy_html` con versión CLAVADA: la última puede no tener binario
# precompilado para tu plataforma y cae a compilar lexbor con cmake.
{:lazy_html, "0.1.11", only: :test},
```

```elixir
defp aliases do
  [
    setup: ["deps.get", "fact.setup", "assets.setup", "assets.build"],
    test: ["fact.setup", "test"],
    "phx.server": ["fact.setup", "phx.server"],
    "fact.setup": &fact_setup/1,
    precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
  ]
end
```

**`fact.setup` en los tres.** Sin el store creado, `Application.fact_db/0`
lanza tras dos segundos y se lleva por delante lo que estuviera haciendo el
usuario. Pasa la primera vez que alguien arranca `phx.server` y cuesta un rato
diagnosticarlo.

## Las cuatro formas de rodaja

| `slice.json` dice | skill | ficheros |
|---|---|---|
| `commands` / `events` | `build-state-change` | comando, evento, `core`, `context` |
| `readmodels` / `queries` | `build-state-view` | `core`, `context` |
| `processors` no vacío | `build-automation` | los cuatro + `processor` |
| evento externo entrante | `build-webhook` | los cuatro + controlador y plug |

## Lo que este kit NO hace

**Pantallas.** `slice.json` trae la pantalla como metadatos y prosa, **no como
diseño** — el HTML del tablero no viaja en el payload. Cuando una rodaja tiene
`screens`, el agente construye el dominio, escribe un **encargo de pantalla** en
`docs/pantallas/<rodaja>.md` y para.

Ese encargo es el `ui-prompt.md` que el bucle prevé y ningún kit rellena. Su
sección más útil es **«Lo que el dominio NO da»**: es lo que impide que quien
construya la vista se invente campos.

## Las tres reglas que `slice.json` no dice

Están en `.build-kit/CLAUDE.md` y son la razón de ser de este kit. No se deducen
leyendo otros build kits — salieron de construir una rodaja a mano y chocar con
ellas:

1. **Las etiquetas salen de `idAttribute: true`.** `slice.json` trae `tags: []`
   en todos los elementos: no están vacías, están **sin derivar**. Y son las
   claves de consulta de todo el sistema.
2. **Los campos generados viajan en el comando.** Un `derived:instante del
   append` parece decir que se genera al escribir; hacerlo en `Core` rompe la
   pureza y deja la decisión imposible de probar sin reloj.
3. **La validación no se parte** entre `Core` y `Context`. Los escenarios
   `SPEC_ERROR` se prueban sobre el `Core` puro, que no pasa por `Context`.

## Trampas del bucle que conviene conocer

- **El `slice.json` que escribe el bucle es un stub.** `fetchAndPersistSlices`
  usa el endpoint resumen: seis campos, ~230 bytes, sin `fields` ni `events` ni
  `specifications`. El kit trae `.build-kit/refrescar-rodajas.py`, y el paso 0
  del `CLAUDE.md` obliga a comprobarlo.
- **Un bucle ocioso puede no enterarse** de una rodaja marcada `Planned` si el
  evento de tiempo real no llega. Refrescar el índice local lo desbloquea.
- **El nombre de carpeta canónico** conserva tildes y `·`: es `title` sin
  espacios y en minúsculas. Normalizar a ASCII crea una carpeta paralela que el
  bucle no mira.

## Procedencia

Derivado de construir el capítulo 1 de [NAMU](https://namupartner.com) —
trazabilidad EUDR para cacao y café venezolanos— rodaja a rodaja, y de los
módulos base de `traduka-servo`, `conecta_zen` y `contextovnzla`.

Licencia: MIT.
