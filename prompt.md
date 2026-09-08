# Prompt: Delphi/FMX + ML Kit en Android (RAD Studio, sin Gradle)

Este es el prompt que le daría a un LLM (o a mí mismo en una sesión nueva) para
trabajar en este proyecto — o para arrancar uno parecido — sin repetir los
errores que costó descubrir la primera vez. Está escrito como instrucciones a
seguir, no como narrativa.

## Contexto del proyecto

- App Delphi FMX (`MLKitOCRDemo`), RAD Studio 12 Athens (BDS 23.0), target
  **Android64 (arm64-v8a) exclusivamente** — nunca Android de 32 bits: varios
  módulos "dynamite" de Play Services/ML Kit no se distribuyen para procesos
  de 32 bits en dispositivos modernos, y el fallo resultante no da excepción
  clara ("Failed to init text recognizer...").
- `minSdkVersion=23`, `targetSdkVersion=34`.
- Funciones ya implementadas: OCR (ML Kit Text Recognition v2, vía Play
  Services), Translate (ML Kit Translate, con descarga de modelos), Language
  Identification, dictado por voz (STT vía intent nativo), texto a voz (TTS
  vía binding JNI propio), y una pestaña de cámara en vivo con OCR + detección
  de idioma + traducción encadenados automáticamente.
- Ficheros de referencia ya existentes en este repo — **léelos antes de tocar
  nada de librerías/manifest/cámara**: `delphikit.md` (guía prescriptiva paso
  a paso), `javabridge.md` (el problema de los `.java` y el patrón JNI),
  `sesion.md` (log cronológico de cada error real y su causa).

## Reglas no negociables (verificadas, no supuestas)

1. **RAD Studio no ejecuta Gradle ni resuelve Maven.** Su Android toolchain
   solo empaqueta `.jar`/`.aar` que tú añadas a mano al proyecto. Para saber
   qué librerías necesita realmente una dependencia de ML Kit, usa un
   proyecto Gradle auxiliar (`gradle-deps/build.gradle`, ya existe en este
   repo con tareas `collect*Libs`) solo para *resolver* el árbol de
   dependencias reales — nunca para compilar la app.
2. **Filtra duplicados contra `EnabledSysJars`** (propiedad del `.dproj`) por
   nombre base ignorando versión, incluyendo los renombrados `-jvm`
   (`collection`→`collection-jvm`, `annotation`→`annotation-jvm`,
   `okio`→`okio-jvm`). Si Gradle resuelve algo que ya está ahí, no lo añadas.
3. **`emoji2-*`, `emoji2-views-helper-*` y `lifecycle-process-*` NUNCA van al
   proyecto**, aunque Gradle los resuelva como transitivos de un `appcompat`
   más nuevo — provocan `NoClassDefFoundError: androidx.startup.R$string` al
   arrancar, porque el `appcompat` de sistema que trae RAD Studio es más
   antiguo y no los necesita.
4. **RAD Studio no compila `.java` añadidos al proyecto** (quedan como
   `<None>` en el `.dproj`). Compílalos a mano con `javac` (mismo JDK/flags
   que usa RAD Studio internamente, ver `javabridge.md` sección "Paso 3") y
   empaquétalos en un `.jar`, añadido como `JavaReference`.
5. **El dexer de RAD Studio vacía en silencio ciertos `JavaReference` grandes**
   (produce un `-dexed.jar` de 22 bytes sin error de compilación). Si pasa,
   envuelve ese `.jar` en un `.aar` mínimo y añádelo como `AarReference` en
   vez de `JavaReference` — las AAR grandes sí dexean bien.
6. **RAD Studio no extrae nada de un AAR salvo `classes.jar`** — ni `.so`
   (`jni/<abi>/`), ni `assets/`, ni `res/`. Si una librería los necesita,
   extráelos a mano y declara un `DeployClass`/`DeployFile` propio apuntando
   al destino correcto en el paquete final (`library\lib\arm64-v8a` para
   `.so`, `.\assets\` — no `.\assets\internal\`, esa es solo para los
   `.java` fuente del proyecto — para assets reales).
7. **Ciclo de build**: `msbuild .dproj /t:Build` desde CLI solo recompila el
   `.so` de Pascal — NO repaqueta/redexea/redespliega. El ciclo completo
   (dex + package + deploy) solo ocurre con **F9 en el IDE**. Usa CLI para
   detectar errores de compilación Pascal rápido; usa F9 para validar de
   verdad en el dispositivo.
8. **Si el proyecto está abierto en el IDE, ciérralo antes de editar el
   `.dproj`/`.fmx` a mano**, o el IDE lo sobrescribe con su copia en memoria
   al guardar/compilar. Cierra → edita → reabre → F9.
9. **JNI en Delphi**: cada clase Java necesita una interfaz `...Class`
   (estáticos, extiende `JObjectClass`/`IJavaClass`) y una interfaz de
   instancia (extiende `JObject`/`IJavaInstance`), unidas por
   `[JavaSignature('paquete/Clase')]`. Callbacks Java se implementan con
   `TJavaLocal`; el cuerpo del callback SIEMPRE dentro de
   `TThread.Queue(nil, ...)` (Java invoca fuera del hilo principal), y la
   instancia del callback debe vivir en un **campo** del formulario (no
   variable local) mientras la llamada async esté en vuelo, o el GC la
   recoge antes de que Java la invoque.
10. **Un `JString` no es automáticamente un `JCharSequence`** en los bindings
    de Delphi, aunque en Java sí lo sea. Conviértelo con
    `TJCharSequence.Wrap((StringToJString(S) as ILocalObject).GetObjectID)`.
11. **`TCameraComponent` (`FMX.Media`) para cámara en vivo — sin AAR, es RTL
    puro**, pero:
    - Hay un bug real en `FMX.Media.Android.pas`
      (`TAndroidVideoCaptureDevice.GetCamera/OpenCamera`): si `Camera.open()`
      lanza excepción, el `TEvent` interno nunca se marca y el hilo que llamó
      a `Active := True` se bloquea para siempre → ANR. Mitígalo lanzando
      `Active := True` desde tu propio `TThread.CreateAnonymousThread`.
    - `FocusMode`/`Quality` deben fijarse **después** de `Active := True`
      (necesitan `Camera.getParameters()`, que exige la cámara ya abierta), y
      cada uno en su propio `try/except` — `Camera.setParameters()` puede
      lanzar `setParameters failed` en dispositivos concretos, y si comparte
      `try/except` con la activación bloquea todo lo que venga después
      (incluido activar el temporizador de reconocimiento).
    - La rotación del frame según orientación del dispositivo **ya la
      gestiona FMX internamente** (`GetOutputBufferRotation` +
      `TOrientationChangedMessage`) — no hace falta código propio para eso.
    - Para/reactiva la cámara con `TApplicationEventMessage`
      (`WillBecomeInactive`/`EnteredBackground` → parar;
      `BecameActive`/`WillBecomeForeground` → reactivar si la pestaña sigue
      activa). Ojo: el campo del record es `.Event`, no `.EventType`.
12. **Diagnóstico**: `adb logcat -d -v time` capturado justo después de
    reproducir el fallo (no logs viejos), `adb shell dumpsys media.camera`
    para ver si otra app tiene la cámara, `adb shell dumpsys activity
    activities | grep mResumedActivity` para saber si la app tiene el foco
    real. Si algo falla en una API de Android que Delphi envuelve
    (`TCameraComponent`, etc.) y el mensaje de error no basta, lee el código
    fuente real en `Program Files (x86)\Embarcadero\Studio\<ver>\source\fmx\`
    antes de adivinar la causa.

## Flujo para añadir una nueva capacidad de ML Kit

1. Añade la dependencia a `gradle-deps/build.gradle` (nueva `configuration` +
   tarea `collectXxxLibs` copiando el patrón de las existentes) y ejecútala.
2. Compara la lista resuelta contra `EnabledSysJars` y lo ya añadido al
   proyecto (por nombre base). Anota qué es genuinamente nuevo.
3. `unzip -l lib.aar` en cada AAR nuevo — busca `jni/` (nativo) y `assets/`
   (modelo embebido); si hay, prepara el `DeployClass`/`DeployFile` a mano.
4. Escribe el wrapper Java (interfaz de callback + clase que envuelve la API
   real de ML Kit), cópialo a `com\<paquete>\` dentro del proyecto Delphi.
5. Compílalo con `javac` (ver regla 4/`javabridge.md`), empaquétalo en un
   `.jar`, añádelo como `JavaReference` (o `AarReference` si el dexer lo
   vacía — regla 5).
6. Escribe la unidad JNI Delphi (`Android.JNI.<Nombre>.pas`) siguiendo el
   patrón de la regla 9 — que NO dependa de paquetes de ML Kit directamente,
   solo de la forma del wrapper propio.
7. Añade las entradas al `.dproj` (`AarReference`/`JavaReference`/
   `DCCReference`/`DeployFile`) con el proyecto **cerrado** en el IDE.
8. Compila por CLI (`msbuild ... /t:Build`) para pillar errores Pascal rápido,
   luego pide F9 para el ciclo completo y prueba real en dispositivo.
9. Verifica con `adb logcat` que el fallo (si lo hay) es real y no un
   artefacto del propio flujo de RAD Studio (dexer vacío, asset no
   desplegado, etc.) antes de asumir que la librería está mal.
10. Actualiza `sesion.md`/`delphikit.md` con lo aprendido, para que la
    próxima vuelta a este patrón no repita el mismo descubrimiento desde
    cero.
