# Pantalla: Comprobador de Parcelas

> **Ejemplo, no plantilla vacía.** Es un encargo real de otro proyecto —una
> herramienta de trazabilidad EUDR— para que se vea el nivel de detalle que
> merece la pena. Bórralo cuando tengas los tuyos. La plantilla está en
> `.build-kit/CLAUDE.md`.
>
> Lo que más se copia de aquí es la última sección, **«Lo que el dominio NO
> da»**: es la que impide que quien construya la vista se invente campos.

Rodaja `Comprobar una parcela` · nodo `dfa96352-008e-4cb0-9fc5-60ba64cdbba5`.

**Escrito a mano el 05·09·2026, después de construir la pantalla**, como ejemplo
del formato. Los que escriba el bucle irán antes de que exista la vista, que es
para lo que sirve el documento. La pantalla ya está en
`lib/my_app_web/live/comprobador_live.ex`.

## Por dónde entra

```elixir
MyApp.Slices.ComprobarParcela.Context.comprobar(geometria, sesion_id)
# → {:ok, comprobacion_id} | {:error, motivo}
```

`geometria` es una cadena de GeoJSON. `sesion_id` sale de la cookie, que pone
`MyAppWeb.Plugs.Sesion` — la LiveView lo lee de `session` en `mount/3`, no lo
genera: una LiveView monta dos veces y la sesión sólo se escribe en la primera.

Devuelve el identificador y no los eventos porque es lo que la vista necesita:
para suscribirse al resultado, y para enseñar la referencia — **los ocho primeros
caracteres**, que es lo que se le pide a soporte.

## Qué manda de vuelta

Un solo comando. Los átomos de error que puede devolver, **todos**, y la pantalla
los tiene que traducir porque no los puede adivinar:

| átomo | cuándo |
|---|---|
| `:geometria_requerida` | vacía o ausente |
| `:geometria_invalida` | no es GeoJSON, o no es `Point` ni `Polygon` |
| `:coordenadas_fuera_de_rango` | longitud fuera de ±180 o latitud fuera de ±90 |
| `:poligono_sin_superficie` | el anillo cierra pero no encierra nada |
| `:almacen_no_disponible` | FACT no está en pie — **no es culpa del visitante** |

El último merece un mensaje distinto de los otros cuatro: los cuatro primeros
son cosas que el visitante puede corregir, y el quinto no.

Y hay una función pública para validar **antes** de enviar, que es lo que
permite habilitar o deshabilitar el botón sin ida y vuelta al comando:

```elixir
MyApp.Slices.ComprobarParcela.Core.valida_geometria(blob)  # → :ok | {:error, motivo}
```

## Estados que hay que pintar

- **Sin geometría** — no se puede comprobar. Con el patrón de mira fija esto casi
  no ocurre: el centro del mapa siempre es un punto válido.
- **Geometría válida** — se puede comprobar.
- **Geometría rechazada** — mensaje del átomo, y no se puede comprobar.
- **Enviando** — el comando tarda unos 240 ms en la primera escritura del
  proceso, porque `Application.fact_db/0` resuelve con reintentos.
- **Enviada** — hay `comprobacion_id`; se enseña la referencia.

## Lo que el tablero dice de esta pantalla

> El input real. Se entra pulsando «Comprobar una parcela» en `/trace/eudr` y
> **lo primero que aparece es el mapa** — sin registro y sin preguntas previas.
>
> **Punto por defecto: dos pasos, no tres.** Se retiró el paso que preguntaba
> «¿cabe en el cuadro de 4 ha?». Esa pregunta pedía al visitante *declarar* la
> superficie de su parcela, y era una declaración que no podemos verificar: con
> un punto no hay área que medir.
>
> **Y el motivo honesto para dibujar está medido.** El 04·09·2026 se lanzaron
> cinco pines dentro de un mismo polígono de 5,02 ha en Chuao: cuatro dieron
> `riesgo bajo` y uno `información insuficiente`. Con `Area = 0` el umbral del
> 10 % de Whisp **colapsa a cero**, así que un pin es un muestreo de un píxel con
> tolerancia cero.
>
> Dibujar sigue disponible y nunca se exige. Y hay una razón específica del
> rubro: el cacao y el café de sombra **no se distinguen del bosque en la imagen
> satelital**, así que puede que el productor no reconozca sus propios linderos
> desde arriba. El punto pregunta «¿dónde está?», que sí sabe responder.

## Lo que el dominio NO da

Lo más importante de este documento.

- **No hay validación de país.** Una geometría fuera de Venezuela se acepta y se
  escribe. El país lo trae Whisp en la columna 3, y **la pantalla de resultado**
  es la que tiene que bloquear el veredicto cuando no es `VEN`. Ojo: con
  coordenadas invertidas Whisp contesta `Country: Unknown` **y `risk_pcrop:
  low`** — el fallo produce la pantalla más tranquilizadora.
- **No hay validación de zoom ni de superficie.** El zoom mínimo de 15 es una
  regla **de interfaz**, no de dominio: vive en la LiveView. Y las 4 ha del
  art. 2(28) no se comprueban en ningún sitio, porque con un pin no sabemos el
  área — el productor sí.
- **No hay `tipoGeometria`, ni `centroide`, ni `areaHa`, ni `decimales`.** Los
  cuatro son funciones puras de `geometria` y se retiraron a propósito: un campo
  derivado almacenado acaba contradiciendo a su origen. El blob **ya dice**
  `"type":"Point"`; derívalo al pintar.
- **Los seis decimales del art. 2(28) no se validan**: se cumplen por
  construcción, porque la geometría sale de un toque en el mapa. **Es
  responsabilidad de la pantalla** emitirlos — el hook redondea a seis exactos.
- **No hay estado ni progreso.** Esta rodaja escribe y devuelve. «Cómo va la
  comprobación» es otra rodaja (`Estado de la Comprobación`), y todavía no
  existe: por eso la pantalla se cierra hoy con la referencia en vez de navegar
  a un seguimiento.
