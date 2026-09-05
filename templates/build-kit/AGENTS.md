# Lo aprendido construyendo

Patrones y trampas reutilizables. Añade aquí lo que descubras, sin repetir lo que
ya está. Este fichero se lee **antes** de cada rodaja: es la memoria que evita
repetir errores entre iteraciones.

Viene sembrado con lo que salió de construir el primer capítulo de un sistema
real con este armazón. No son hipótesis — cada punto costó una vuelta.

## El armazón

- `lib/my_app/`: `decide.ex`, `lectura.ex`, `state_change.ex`, `state_view.ex`,
  `fact_event.ex`, `id.ex`. **No los toques** salvo que te lo pidan.
- `Decide` espera a que lo escrito sea visible antes de volver: `Fact.append/3`
  confirma entre 7 y 10 ms antes de que una lectura lo vea. Sin esa espera, una
  LiveView que escribe y repinta enseña el estado viejo.
- `Lectura.leer/2` lee por índice en vez de recorrer el ledger. Medido: consulta
  por etiqueta sobre 20.000 eventos, **235 ms escaneando contra 0,07 ms por
  índice**. Importa porque toda escritura empieza por una lectura.
- Techo conocido y **no** resuelto en el armazón base: con la condición de
  añadido anclada en 0 —lo que pasa cuando el pliegue no encuentra nada— FACT
  recorre el ledger entero. Medido: 29 ms con 531 eventos, **4,5 s con 157.711**.
  Se arregla anclando en una marca de visibilidad; la costura está documentada
  en `Decide.read_and_fold/3`.

## Sobre `slice.json`

- **`tags: []` no significa «sin etiquetas», significa «sin derivar».** Salen de
  los campos con `idAttribute: true`. Es la regla más importante del kit.
- **El `slice.json` que escribe el bucle es un stub.** `fetchAndPersistSlices`
  usa el endpoint **resumen**: seis campos, ~230 bytes, sin `fields`, sin
  `events` y sin `specifications`. Refresca con
  `python3 .build-kit/refrescar-rodajas.py` — es el paso 0 del `CLAUDE.md`.
  Pasó de verdad, y la primera vez funcionó **por azar**: para las rodajas de
  título ASCII el stub **sobrescribió** la definición completa, y sólo se
  salvaron las que llevaban tildes o `·`, porque cayeron en otra carpeta.
- El nombre de carpeta canónico es `title` sin espacios y en minúsculas,
  **conservando tildes y `·`**. Normalizarlo a ASCII crea una carpeta paralela
  que el bucle no mira.
- La pantalla llega como metadatos: `title`, `fields`, `dependencies` y prosa.
  **El diseño renderizado no viaja en el payload.**
- La `description` de cada nodo lleva los invariantes redactados, y suele
  explicar **qué reglas se retiraron y por qué**. Es lo más valioso del fichero
  y es fácil saltárselo.
- Los `examples` de los escenarios suelen estar **medidos contra sistemas
  reales**. Si un test falla, sospecha del test antes que del dato.

## Trampas de FACT y del quality gate

- **`event_data` vuelve con claves de cadena en snake_case.** Los eventos se
  serializan con `Map.from_struct/1`, así que un `comprobacionId` del tablero se
  lee `d["comprobacion_id"]`. Se comprueba mirando los ficheros de
  `data/fact_db/events/<xx>/<id>`, que son JSON planos.
- **El store tiene que existir antes de arrancar.** Si falta,
  `Application.fact_db/0` **lanza** tras dos segundos y se lleva por delante lo
  que estuviera haciendo el usuario. Por eso `fact.setup` va en los alias de
  `test`, `setup` **y** `phx.server`.
- **`mix precommit` compila con `--warnings-as-errors`.** Un `defp f(x, y \\ %{})`
  cuyo valor por defecto no se usa nunca es un aviso, y tumba el gate.

## Sobre los tests

- **Nunca compares `Map.keys/1` con una lista.** El orden no está garantizado:
  `assert Map.keys(fila) == [:a, :b, :c]` falla de forma **intermitente** — pasa
  en local y tumba el gate más tarde. Se commiteó así una vez. Usa `MapSet`.
- Un test que pasa puede estar mintiendo. Pasó uno que afirmaba que un botón
  arranca deshabilitado: cierto sólo porque en las pruebas no hay JavaScript que
  publique el estado inicial. **Cuando un test dependa de algo que el navegador
  hace solo, simúlalo explícitamente.**
- `Application.put_env` es global. Un test que la muta **no puede vivir en un
  módulo `async: true`** junto a otro que lea esa misma configuración.
- Con `nil`, HEEx **omite el atributo entero** en vez de pintarlo vacío, así que
  la aserción obvia (`data-x=''`) no encuentra nada.

## Sobre las rodajas de lectura

- **Una cola TODO no se acota por etiqueta.** Es la excepción a «la etiqueta
  acota la vista»: la consume un procesador, que no tiene sesión ni ninguna otra
  identidad por la que filtrar. La consulta va por tipos.
- **El fallo caro es un tipo que falte en `query/1`.** No revienta: deja el campo
  en `nil` para siempre y nadie se entera. Conviene un test sobre `query/1`
  —los tipos y las etiquetas— porque el resto de la suite pasa igual con la
  consulta mal puesta.
- **Una cola sin campo de estado es una decisión, no un olvido.** La pertenencia
  a la lista *es* el estado.

## Sobre cómo se reclaman las rodajas

- El bucle rechaza el cambio de estado si la rodaja ya está en el estado
  destino: **no es un error**, es que otro agente la reclamó primero. No
  reintentes la misma; pasa a la siguiente `Planned` del contexto actual.
- Dos bucles sobre el mismo directorio comparten `progress.txt`, `index.json` y
  el árbol de trabajo, y cada uno quiere su rama en el mismo checkout. Si vas a
  correrlos en paralelo, **un worktree por agente**.
- Un bucle ocioso puede no enterarse de una rodaja marcada `Planned` si el
  evento de tiempo real no llega. Refrescar el índice local lo desbloquea.

## El encargo de pantalla

- Si la rodaja trae `screens`, además del dominio se escribe
  `docs/pantallas/<rodaja>.md`. Plantilla y reglas en `.build-kit/CLAUDE.md`.
- **La sección que más vale es «Lo que el dominio NO da».** Es la que impide que
  quien construya la vista se invente campos o se los pida al dominio sin
  motivo. Escríbela aunque el resto quede corto.
- Los **átomos de error** de `Core` van siempre: la pantalla los traduce a
  mensajes y no los puede adivinar leyendo el `slice.json`.
- Va en `docs/` y no en `.build-kit/` a propósito: `.build-kit/` se regenera con
  cada fetch y el encargo tiene que sobrevivir.
