# CLAUDE.md — MLKitOCRDemo

Instrucciones persistentes para trabajar en este proyecto. Léelas al empezar
cualquier sesión aquí, antes de tocar librerías, el `.dproj`, el manifest o
`TCameraComponent`.

## Qué es esto

App Delphi FMX Android (RAD Studio 12 Athens / BDS 23.0) que integra ML Kit:
OCR, Translate (con descarga de modelos), Language Identification, dictado
por voz (STT), texto a voz (TTS), y una pestaña "Vivo" con cámara en directo
que encadena OCR → detección de idioma → traducción automáticamente. Target
**exclusivo Android64 (arm64-v8a)** — nunca Android de 32 bits.

**Este directorio no es un repositorio git todavía.** No hay red de
seguridad de versiones — pide confirmación antes de cualquier operación
destructiva (borrar, sobrescribir sin revisar) y sugiere `git init` si toca
el tema.

## Antes de tocar nada: la documentación ya existe, léela primero

- `delphikit.md` — guía prescriptiva paso a paso para añadir/tocar
  librerías de ML Kit (Gradle auxiliar, filtrado de duplicados, AAR/JavaReference,
  `.so`/`assets/` de un AAR, checklist final).
- `javabridge.md` — por qué RAD Studio no compila los `.java` del proyecto,
  y el patrón JNI completo en el lado Delphi.
- `sesion.md` — log cronológico de cada error real encontrado y su causa raíz
  (para no repetir el mismo descubrimiento dos veces).
- `prompt.md` — versión condensada en "reglas no negociables" + flujo paso a
  paso, pensada para arrancar rápido en una sesión nueva.

## Reglas duras (verificadas, no las repitas mal)

1. Plataforma activa **siempre Android64**, nunca Android de 32 bits (varios
   módulos de Play Services/ML Kit fallan en silencio en 32 bits).
2. RAD Studio no ejecuta Gradle ni resuelve Maven. `gradle-deps/build.gradle`
   es solo para *resolver* dependencias reales, nunca para compilar la app.
3. Nunca añadas `emoji2-*`, `emoji2-views-helper-*` ni `lifecycle-process-*`
   al proyecto — provocan `NoClassDefFoundError: androidx.startup.R$string`
   al arrancar.
4. RAD Studio no compila `.java` del proyecto (quedan como `<None>`) ni
   extrae `.so`/`assets/` de dentro de un AAR — todo eso se hace a mano (ver
   `javabridge.md`/`delphikit.md`).
5. Si el proyecto está abierto en el IDE, **ciérralo antes de editar
   `.dproj`/`.fmx` a mano** — si no, el IDE lo sobrescribe con su copia en
   memoria al guardar/compilar. Cierra → edita → reabre → F9.
6. `msbuild MLKitOCRDemo.dproj /t:Build` por CLI solo compila el Pascal — NO
   repaqueta, redexea ni redespliega. El ciclo completo (dex+package+deploy)
   solo ocurre con **F9 en el IDE**. Usa CLI para detectar errores de
   compilación rápido; pide al usuario F9 para validar de verdad en el
   dispositivo antes de dar algo por arreglado.
7. Si una API de Delphi/Android es dudosa, verifícala contra el código
   fuente real (`Program Files (x86)\Embarcadero\Studio\23.0\source\fmx\`
   ya accesible como directorio de trabajo) o contra un error de compilador/
   logcat real — no la asumas de memoria.
8. Diagnóstico en dispositivo: `adb logcat -d -v time` capturado justo
   después de reproducir el fallo, no logs viejos.
9. `TCameraComponent.Active := True` puede colgar el hilo que lo llama si
   `Camera.open()` lanza (bug real de `FMX.Media.Android.pas`) — actívala
   desde un hilo propio (`TThread.CreateAnonymousThread`), y trata
   `FocusMode`/`Quality` como ajustes opcionales, cada uno en su propio
   `try/except`, nunca compartiendo bloque con `Active := True`.

## Preferencias de estilo

- Responde en español.
- Pide/usa el texto exacto de cualquier excepción o error que reporte el
  usuario — no trabajes sobre una paráfrasis del error.
- Compila por CLI como mínimo antes de decir que algo "ya está"; para
  cambios de librerías, manifest o cámara, pide explícitamente al usuario
  que pruebe con F9 en el dispositivo real antes de considerarlo resuelto.
- Actualiza `sesion.md`/`delphikit.md` cuando se descubra o arregle algo
  nuevo y no trivial, para que la próxima sesión no repita el descubrimiento.
