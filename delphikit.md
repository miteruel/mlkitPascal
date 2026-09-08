# Guía definitiva: ML Kit (OCR + Translate) en un proyecto Delphi/FMX Android nuevo

Receta paso a paso, sin los rodeos ni los errores que se cometieron la primera vez.
Basada en RAD Studio 12 Athens / Delphi 13, toolchain Android propio (sin Gradle),
verificada compilando y ejecutando de verdad en dispositivo físico.

## 0. Requisitos previos

- RAD Studio con la plataforma **Android64 (arm64-v8a) añadida y activa** como
  destino. **No uses solo Android de 32 bits**: varios módulos "dynamite" de
  Play Services / ML Kit (el motor de OCR incluido) ya no se distribuyen para
  procesos de 32 bits en dispositivos modernos — la app compila y arranca bien,
  pero el reconocimiento falla en tiempo de ejecución con un error genérico
  ("Failed to init text recognizer...") sin excepción clara. Añádela en
  Project Manager → Target Platforms → clic derecho → *Add Platform* →
  *Android 64-bit*, y selecciónala como plataforma activa antes de compilar.
- Un JDK (11+; se usó 17) y Gradle disponibles. Si no tienes Gradle instalado,
  revisa `~/.gradle/wrapper/dists/` — si alguna vez usaste Android Studio,
  probablemente ya tengas una distribución cacheada y no haga falta descargar
  nada; usa el `gradle.bat` de ahí directamente.
- `minSdkVersion` = 23 (obligatorio para ML Kit Text Recognition v2 y Translate).

## 1. Por qué el flujo es así (arquitectura)

RAD Studio **no ejecuta Gradle ni resuelve Maven**. Su toolchain Android solo
sabe empaquetar `.jar`/`.aar` que tú le des ya resueltos, con su propio
`aapt2`, su propio dexer (basado en R8/D8) y su propio *manifest merger*. Por
eso el flujo para cualquier librería con dependencias transitivas (como ML
Kit) es siempre:

1. Resolver el árbol de dependencias real con Gradle de verdad, una vez.
2. Aplanar el resultado en ficheros `.jar`/`.aar` sueltos.
3. Añadir **solo los que hagan falta de verdad** al proyecto Delphi (RAD
   Studio ya trae de serie un catálogo grande de AndroidX/Play-Services/
   Firebase — ver paso 3).
4. Para código Java propio (wrappers JNI): compilarlo tú mismo con `javac` y
   empaquetarlo en un `.jar`, porque **RAD Studio no compila `.java` sueltos
   añadidos al proyecto** — pese a que esto es fácil de asumir por error (el
   propio equipo de este proyecto lo dio por hecho la primera vez). Solo
   compila automáticamente `.java` que él mismo genera para su asistente de
   "Android Service".

## 2. Proyecto Gradle auxiliar para resolver dependencias

Este proyecto ya trae uno en `gradle-deps/build.gradle`. Patrón general para
cualquier artefacto ML Kit nuevo:

```gradle
apply plugin: 'java'
repositories { google(); mavenCentral() }
configurations { miLibreria }
dependencies {
    miLibreria 'com.google.mlkit:XXXX:VERSION'
}
def outDir = file("${rootDir}/../libs-android-XXXX")
tasks.register('collectXXXX', Copy) {
    doFirst { outDir.deleteDir(); outDir.mkdirs() }
    from configurations.miLibreria
    into outDir
    include '*.jar'; include '*.aar'
    eachFile { fcd -> fcd.path = fcd.name }
    includeEmptyDirs = false
}
```

Ejecutar con el Gradle que tengas (ejemplo usando una distribución ya
cacheada, sin descargar nada):

```bash
"<ruta_a_gradle_cacheado>/gradle.bat" collectXXXX --console=plain
```

Esto deja todos los `.jar`/`.aar` (con sus versiones ya resueltas por Gradle
de verdad — nunca copies versiones de memoria/documentación vieja) en una
carpeta plana.

## 3. Filtrar duplicados contra lo que RAD Studio ya trae

RAD Studio activa por defecto (propiedad `EnabledSysJars` en el `.dproj`) un
catálogo grande de AndroidX/Play-Services/Firebase/Kotlin ya usado por FMX y
por otros proyectos del mismo IDE. Si añades tu propia copia de algo que ya
está ahí, el dexer falla con:

```
Type X is defined multiple times: ...\lib\Android\Debug\Y.dex.jar, ...\X-dexed.jar
```

**Antes de añadir nada**, compara por nombre base (ignorando la versión) los
ficheros que bajó Gradle contra la lista `EnabledSysJars` del `.dproj`:

```bash
grep -o "<EnabledSysJars>[^<]*" TuProyecto.dproj | head -1 \
  | sed 's/<EnabledSysJars>//' | tr ';' '\n' | sed 's/\.dex\.jar$//' | sort -u \
  > system_jars.txt
```

Luego, para cada fichero bajado, comprueba si su nombre-sin-versión (o su
variante con sufijo `-jvm`, ver aviso abajo) está en `system_jars.txt`. Si
está, **no lo añadas** — muévelo a una subcarpeta tipo `quito/` para no
confundirte.

**Aviso importante — el truco `-jvm`:** varias librerías AndroidX se
partieron en un artefacto "multiplatform" con sufijo `-jvm`
(`collection`→`collection-jvm`, `annotation`→`annotation-jvm`,
`okio`→`okio-jvm`...). El nombre no calza exacto con una comparación de texto
simple, pero **las clases Java son las mismas** — si añades la versión sin
sufijo, duplicas contra la versión `-jvm` que ya trae RAD Studio. Antes de dar
por buena una "librería nueva", comprueba también si existe una variante
`-jvm`/`-android`/similar ya en `EnabledSysJars`.

## 4. ML Kit Text Recognition v2 (OCR) — lista concreta

Artefacto: `com.google.android.gms:play-services-mlkit-text-recognition:19.0.1`
(variante *unbundled*, hospedada por Play Services — el modelo se descarga en
tiempo de ejecución, no va en el APK). Requiere Google Play Services en el
dispositivo.

De los ~60 ficheros que resuelve Gradle, **añade solo estos al proyecto**
(`AarReference`/`JavaReference` según corresponda):

```
common-18.11.0.aar
image-1.0.0-beta1.aar
play-services-mlkit-text-recognition-19.0.1.aar
play-services-mlkit-text-recognition-common-19.1.0.aar
resourceinspection-annotation-1.0.1.jar
vision-common-17.3.0.aar
vision-interfaces-16.3.0.aar
```

**No añadas** (ya cubiertos por RAD Studio, o activamente problemáticos):
`core`, `core-ktx`, `appcompat`, `appcompat-resources`, `collection`,
`annotation`, `kotlin-stdlib*`, `kotlinx-coroutines*`, `lifecycle-*` (salvo
excepción de abajo), `fragment`, `activity`, `savedstate`, `startup-runtime`,
`tracing`, `transport-*`, `firebase-*`, `vectordrawable*`,
`versionedparcelable`, `viewpager`, `play-services-base`,
`play-services-basement`, `play-services-tasks`, y sobre todo:

**`emoji2-*.aar` y `lifecycle-process-*.aar` — NUNCA los añadas.** Inyectan en
el manifest fusionado un `<provider android:name="androidx.startup.
InitializationProvider">` que crashea la app al arrancar
(`NoClassDefFoundError: androidx.startup.R$string`) porque esa librería solo
existe como `.dex.jar` de sistema sin sus propios recursos — su clase de
recursos nunca se genera. Tu código no usa `EmojiCompat` ni
`ProcessLifecycleOwner`, así que no hacen falta.

### 4.1 El meta-data de Play Services que falta

Al excluir `play-services-basement`/`play-services-base` (porque sus *clases*
ya están cubiertas por RAD Studio), pierdes también sus *recursos* — en
concreto `@integer/google_play_services_version`, obligatorio para cualquier
app que use Play Services. Sin él:

```
GooglePlayServicesMissingManifestValueException: A required meta-data tag ...
```

**Solución correcta (no un parche con valor literal):** crea versiones
"solo-recursos" de esas dos AAR — mismo `AndroidManifest.xml` y `res/`, pero
con `classes.jar` vaciado (para no duplicar sus clases) — y añádelas como
`AarReference` normal. Así el recurso real se genera y el manifest se fusiona
sin conflicto.

```bash
JARBIN="<jdk>/bin/jar"
for name in play-services-basement-18.4.0 play-services-base-18.5.0; do
  work="/tmp/${name}_work"; mkdir -p "$work"; cd "$work"
  unzip -o -q ".../${name}.aar"
  rm -f classes.jar; mkdir -p emptysrc
  "$JARBIN" cf classes.jar -C emptysrc .
  rm -rf emptysrc
  "$JARBIN" cf ".../libs-android/resonly/${name}-resonly.aar" .
done
```

Añade ambos `*-resonly.aar` como `AarReference`. (Un intento anterior de
"arreglar" esto poniendo el valor `12451000` literal en el manifest funciona
a medias, pero en cuanto añades la AAR real de recursos, el manifest merger
se queja de valor duplicado — usa directamente la AAR solo-recursos y ya no
hace falta el literal.)

## 5. ML Kit Translate — lista concreta y diferencias con OCR

Artefacto: `com.google.mlkit:translate:17.0.3`. A diferencia de OCR, **no hay
variante Play-Services-hosted** — esta librería trae su propio motor TFLite
embebido (con librerías nativas `.so`) y solo descarga los *datos* del modelo
de idioma bajo demanda vía `RemoteModelManager`/`DownloadConditions` (que ya
vienen en `common-18.11.0.aar`, reutilizado de OCR).

Fuerza una versión moderna de OkHttp al resolver (la que declara `translate`
como mínimo transitivo, 3.0.0, es de 2016 y da problemas — ver 5.1):

```gradle
translateLibs 'com.google.mlkit:translate:17.0.3'
translateLibs 'com.squareup.okhttp3:okhttp:3.12.13'
```

Añade solo:
```
common-18.11.0.aar                 (compartido con OCR, no lo dupliques si ya lo tienes)
translate-17.0.3.aar
resourceinspection-annotation-1.0.1.jar   (compartido con OCR)
```

Y el propio OkHttp, con el tratamiento especial del punto 5.1.

**No añadas** (mismas exclusiones que en OCR, más): `okio` (¡ojo, aunque
Gradle lo resuelva sin sufijo `-jvm`, sus clases SÍ chocan con
`okio-jvm-3.4.0` que ya trae RAD Studio — es el mismo caso "-jvm" del punto
3, pero con nombre distinto!).

### 5.1 Bug del dexer de RAD Studio con jars grandes/complejos (`JavaReference`)

Si añades `okhttp-*.jar` como `JavaReference` normal, **RAD Studio genera un
`.dex` vacío en silencio** (22 bytes, sin ningún error de compilación) y la
app crashea en tiempo de ejecución con `NoClassDefFoundError:
Lokhttp3/MediaType` (o cualquier otra clase de esa librería) en cuanto algo
la usa de verdad. Verificado: `d8` de línea de comandos dexa ese mismo jar sin
problema — es un bug específico de cómo RAD Studio invoca el dexer para
`JavaReference` "grandes" (con muchas clases/advertencias de desugaring),
mientras que `AarReference` (incluida la propia `translate-17.0.3.aar`, igual
de grande) sí funciona.

**Solución: envuelve el `.jar` problemático en un `.aar` mínimo** y añádelo
como `AarReference` en vez de `JavaReference`:

```bash
JARBIN="<jdk>/bin/jar"
WORK="/tmp/okhttp_aar"; mkdir -p "$WORK"
cp okhttp-3.12.13.jar "$WORK/classes.jar"
cat > "$WORK/AndroidManifest.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.squareup.okhttp3.wrapper">
    <uses-sdk android:minSdkVersion="21"/>
</manifest>
EOF
cd "$WORK"
"$JARBIN" cf ".../libs-android/translate/okhttp-3.12.13-aar.aar" .
```

Añade `okhttp-3.12.13-aar.aar` como `AarReference` normal. Si en el futuro
cualquier otra librería falla igual (jar pre-dexado de 22 bytes en
`Android64\Debug\<nombre>-dexed.jar`), aplica el mismo truco.

**Cómo detectarlo si vuelve a pasar:** tras un build completo (F9, no vale el
`msbuild /t:Build` de terminal — ver punto 7), revisa el tamaño de los jars
pre-dexados:
```bash
find Android64/Debug -iname "*-dexed.jar" -exec ls -la {} \;
```
Un tamaño de 22 bytes es un dex vacío = el jar nunca llegó al APK.

### 5.2 Librerías nativas (`.so`) dentro de un AAR — RAD Studio no las extrae

`translate-17.0.3.aar` trae `jni/<abi>/libtranslate_jni.so` (el motor TFLite).
**RAD Studio, al procesar un `AarReference`, solo extrae
`AndroidManifest.xml`, `classes.jar` y los recursos (`res/`) — nunca las
librerías nativas**, sin avisar de ello. Sin este `.so` la app crashea en
`Translator.translate()`/`downloadModelIfNeeded()` con:

```
java.lang.UnsatisfiedLinkError: Couldn't load translate native code library
```

**Solución: extrae el `.so` del AAR y decláralo a mano como fichero de
despliegue (`DeployFile`), con una `DeployClass` propia** (RAD Studio no trae
una variante arm64 de fábrica, solo `AndroidLibnativeArmeabiv7aFile`/
`...ArmeabiFile`/`...MipsFile`, heredadas de cuando solo existía 32 bits):

```bash
mkdir -p libs-android/native
JARBIN="<jdk>/bin/jar"; cd /tmp
unzip -o -q ".../translate-17.0.3.aar" "jni/arm64-v8a/libtranslate_jni.so"
cp jni/arm64-v8a/libtranslate_jni.so \
   ".../libs-android/native/libtranslate_jni-arm64-v8a.so"
```

En el `.dproj`, dentro de `<ItemGroup>` con las demás `<DeployClass>` (busca
las `AndroidLibnative*File` existentes para copiar el estilo exacto), añade:

```xml
<DeployClass Name="AndroidLibnativeArm64File">
    <Platform Name="Android64">
        <RemoteDir>library\lib\arm64-v8a</RemoteDir>
        <Operation>1</Operation>
    </Platform>
</DeployClass>
```

Y dentro del `<Deployment Version="5">` con los demás `<DeployFile>`:

```xml
<DeployFile LocalName="..\libs-android\native\libtranslate_jni-arm64-v8a.so" Class="AndroidLibnativeArm64File">
    <Platform Name="Android64">
        <RemoteName>libtranslate_jni.so</RemoteName>
        <Overwrite>true</Overwrite>
    </Platform>
</DeployFile>
```

**No uses `Class="DependencyModule"`** para esto (parece genérico pero no lo
es): esa clase solo admite extensiones `.dylib`/`.dll`/`.bpl` para
iOS/macOS/Win32 — no tiene ninguna sección `Android`/`Android64` definida, así
que un `DeployFile` con esa clase se ignora en silencio para Android, sin
error. Verifícalo tú mismo si tienes dudas:
```bash
grep -A15 'DeployClass Name="DependencyModule"' TuProyecto.dproj
```

**Verificación tras el build (F9):**
```bash
unzip -l Android64/Debug/TuProyecto/bin/TuProyecto.apk | grep "\.so$"
```
Debe aparecer `lib/arm64-v8a/libtranslate_jni.so` junto a tu propio
`lib/arm64-v8a/libTuProyecto.so`.

## 6. El wrapper Java propio (JNI) — cómo compilarlo de verdad

Resumen rápido aquí; ver [`javabridge.md`](javabridge.md) para el detalle
completo (por qué RAD Studio no lo compila solo, el patrón de declaración JNI
en Pascal, la regla de "mantener vivo" un callback, y el gotcha
`JString`/`JCharSequence`).

Escribe tu wrapper en Java plano (no Kotlin — RAD Studio no tiene integración
con `kotlinc`) en, por ejemplo, `java-wrapper/com/tuempresa/tupaquete/*.java`.
**No confíes en que añadirlo al proyecto lo compile** (ver punto 1). Cópialo
también dentro de la carpeta del proyecto Delphi, y compílalo tú mismo:

```bash
JDK="<ruta_jdk_17>"
ANDROID_JAR="<SDK>/platforms/android-34/android.jar"
# Classpath: android.jar + classes.jar de cada AAR cuyas clases uses en el wrapper
# (extrae cada uno con: unzip -o -q algo.aar classes.jar -d carpeta_destino)
"$JDK/bin/javac" -g -Xlint:deprecation -source 17 -target 17 -encoding UTF-8 \
  -d out_classes \
  -classpath "$ANDROID_JAR;ruta/a/extraido1/classes.jar;ruta/a/extraido2/classes.jar;..." \
  MiWrapper.java MiCallback.java

"$JDK/bin/jar" cf mi-wrapper.jar -C out_classes com
```

Añade `mi-wrapper.jar` como `JavaReference` (jars *pequeños* como este
funcionan bien por esa vía — el bug del punto 5.1 es solo para jars grandes
con muchas advertencias de desugaring). Si `javac` se queja de una clase que
no encuentra, casi siempre está en OTRA AAR que ya tienes descargada — busca
con `unzip -l algo.aar | grep NombreClase` en las AAR resueltas por Gradle
antes de asumir que falta algo nuevo.

Escribe también la unidad Pascal con las declaraciones JNI
(`Androidapi.JNIBridge`, `JavaSignature('com/tuempresa/tupaquete/MiWrapper')`,
etc.) — no depende de las clases reales de ML Kit, solo describe la forma de
tu propio wrapper, así que no hay que tocarla si cambias de versión de ML
Kit.

## 7. Ciclo de compilación — qué build usar para qué

- **`msbuild TuProyecto.dproj /p:config=Debug /p:platform=Android64 /t:Build`**
  (con `rsvars.bat` cargado): solo recompila el binario Delphi (`.pas` →
  `.so`). **No repackagea el APK, no vuelve a dexear, no reprocesa
  `DeployFile`.** Útil solo para verificar rápido que el Pascal/`.dproj`
  compilan sin errores de sintaxis.
- **F9 en el IDE**: el único que hace el ciclo completo (dex, `aapt2`,
  manifest merge, `DeployFile`, empaquetado, firma, instalación). Cualquier
  cambio en librerías, AARs, o ficheros de despliegue **solo se ve reflejado
  tras F9**, nunca tras el `msbuild` de terminal.
- **Si editas el `.dproj` a mano** (para añadir `AarReference`/`JavaReference`/
  `DeployFile`/`DeployClass`) **con el proyecto abierto en el IDE, ciérralo
  primero.** El IDE mantiene su propia copia en memoria y la vuelve a
  escribir al guardar/compilar, descartando silenciosamente cualquier entrada
  que no reconozca como añadida desde su propia UI. Cierra el proyecto →
  edita el XML → reábrelo → F9.
- **`<DCCReference Include="MiUnidad.pas"/>` puede desaparecer del `.dproj`
  sin que el proyecto deje de compilar.** Si añades una unidad `.pas` nueva
  (p. ej. un binding JNI propio) editando el `.dproj` a mano y luego el IDE la
  "olvida" (mismo mecanismo del punto anterior), el `uses` de tu código sigue
  funcionando igual: el compilador de Delphi busca los `.pas` por nombre en el
  directorio del proyecto independientemente de si están listados como
  `DCCReference` — esa entrada solo controla si el fichero aparece en el árbol
  del Project Manager del IDE, no si se compila. No es un error si lo notas
  desaparecido; solo vuelve a añadirlo (con el proyecto cerrado) si te importa
  verlo en el árbol del IDE.

## 8. Diagnóstico en dispositivo (adb/logcat)

Todo este proceso se depuró contra un dispositivo físico real, no un
emulador. Comandos clave:

```bash
adb devices -l
adb -s <id> logcat -c                     # limpiar buffer antes de reproducir
adb -s <id> shell am force-stop <paquete>
adb -s <id> shell am start -n <paquete>/com.embarcadero.firemonkey.FMXNativeActivity
adb -s <id> shell input tap X Y           # simula toques; cuidado con el factor
                                           # de escala si sacas coordenadas de
                                           # una captura redimensionada
adb -s <id> exec-out screencap -p > foto.png
adb -s <id> logcat -d -v time > log.txt   # volcar buffer tras reproducir
```

Para saber el nombre real del paquete instalado (puede diferir entre
configuraciones Android/Android64 si el `.dproj` tiene valores de plantilla
sin personalizar — revísalo, `VerInfo_Keys` en cada `PropertyGroup` del
`.dproj`):
```bash
adb shell pm list packages | grep -i <parte_del_nombre>
adb shell dumpsys package <paquete> | grep -i "android.intent.action.MAIN" -A2
```

Para esperar de forma fiable a que tu app recupere el foco tras un intent
externo (cámara, etc.) en vez de usar `sleep` fijo:
```bash
adb shell dumpsys activity activities | grep mResumedActivity
```
(más fiable que `dumpsys window | grep mCurrentFocus`, que puede mostrar
varias líneas obsoletas simultáneas).

## 9. Extras que no son ML Kit pero acompañan bien al proyecto: voz

Ni el dictado por voz (STT) ni la lectura en voz alta (TTS) son ML Kit — son
API nativas de Android — pero encajan de forma natural en una app de
OCR+Translate y no necesitan ninguna librería nueva ni AAR: es JNI directo
contra `android.jar`, que ya tienes.

### 10.1 Dictado por voz (Speech-to-Text)

Se lanza el reconocedor de voz nativo del sistema como una app externa (igual
que `TTakePhotoFromCameraAction` lanza la cámara), y se recoge el resultado
con el mismo mecanismo interno de mensajes que usa FMX para *cualquier*
`startActivityForResult` — no hace falta escribir tu propio manejador de
`onActivityResult`, ni tocar la `Activity` nativa:

```pascal
uses
  ..., Androidapi.JNI.App, Androidapi.Helpers, System.Messaging;

const
  VoiceRecognitionRequestCode = 4321;

// en FormCreate:
TMessageManager.DefaultManager.SubscribeToMessage(TMessageResultNotification,
  HandleActivityResult);

procedure TFormMain.ButtonStartVoiceClick(Sender: TObject);
var
  VoiceIntent: JIntent;
begin
  VoiceIntent := TJIntent.JavaClass.init(
    StringToJString('android.speech.action.RECOGNIZE_SPEECH'));
  VoiceIntent.putExtra(StringToJString('android.speech.extra.LANGUAGE_MODEL'),
    StringToJString('free_form'));
  TAndroidHelper.Activity.startActivityForResult(VoiceIntent,
    VoiceRecognitionRequestCode);
end;

procedure TFormMain.HandleActivityResult(const Sender: TObject; const M: TMessage);
var
  Notification: TMessageResultNotification;
  ResultsList: JArrayList;
begin
  if not (M is TMessageResultNotification) then Exit;
  Notification := TMessageResultNotification(M);
  if Notification.RequestCode <> VoiceRecognitionRequestCode then Exit;
  if Notification.ResultCode <> TJActivity.JavaClass.RESULT_OK then Exit;
  ResultsList := Notification.Value.getStringArrayListExtra(
    StringToJString('android.speech.extra.RESULTS'));
  if (ResultsList <> nil) and (ResultsList.size > 0) then
    // ResultsList.get(0) es el texto reconocido (String java, ver 10.3)
end;
```

No hace falta declarar `RecognizerIntent` como clase JNI propia: sus
constantes (`ACTION_RECOGNIZE_SPEECH`, `EXTRA_LANGUAGE_MODEL`, `EXTRA_RESULTS`,
etc.) son simples literales `String` estables desde hace más de una década —
basta con pasarlos como texto (`android.speech.action.RECOGNIZE_SPEECH`,
`android.speech.extra.LANGUAGE_MODEL`, `free_form`,
`android.speech.extra.RESULTS`). Con un intent tan simple **no hace falta
pedir permiso `RECORD_AUDIO`**: la app externa que abre el reconocedor es la
que graba, no la tuya.

### 10.2 Texto a voz (Text-to-Speech)

`android.speech.tts.TextToSpeech` sí conviene declararlo como binding JNI
propio (no hay wrapper de terceros que valga la pena para 4 métodos), en su
propio fichero (`Android.JNI.TTS.pas` en este proyecto). Puntos a los que
prestar atención:

- **La inicialización del motor es asíncrona.** El constructor
  `TextToSpeech(Context, OnInitListener)` devuelve el objeto al momento, pero
  no está listo para hablar hasta que `OnInitListener.onInit(status)` se
  dispara (puede tardar un momento la primera vez). Guarda el texto pendiente
  y díctalo dentro del callback `onInit`, no justo después de crear el motor.
- **Comprueba el idioma antes de hablar** con
  `setLanguage(TJLocaleTTS.JavaClass.init(StringToJString(codigoIdioma)))` —
  devuelve `LANG_MISSING_DATA` (-1) o `LANG_NOT_SUPPORTED` (-2) si el motor
  activo en el dispositivo no cubre ese idioma. **El motor de Google TTS que
  trae Android por defecto no soporta esperanto** (ni varios idiomas
  minoritarios/construidos) — si lo necesitas de verdad, la única vía es que
  el usuario instale y active otro motor TTS que sí lo soporte (p. ej.
  eSpeak-NG, desde Play Store, activado en Ajustes → Accesibilidad →
  Conversión de texto a voz) — tu código no cambia, usa automáticamente el
  motor activo del sistema.
- Las constantes de `TextToSpeech` (`SUCCESS`, `LANG_NOT_SUPPORTED`,
  `QUEUE_FLUSH`, etc.) son enteros estables desde API 1 — decláralas como
  `const` Pascal normales en vez de leerlas por JNI, es mucho más simple.

### 10.3 Un `JString` no es automáticamente un `JCharSequence`

Gotcha genérico de JNI en Delphi, no específico de voz: muchos métodos de la
API de Android (`TextToSpeech.speak`, `TextView.setText`, etc.) piden un
parámetro `JCharSequence`, no `JString` — aunque en Java `String` implementa
`CharSequence`. Si le pasas directamente el resultado de `StringToJString(...)`
donde se espera `JCharSequence`, el compilador de Delphi da
`error E2010: Incompatible types` (las interfaces JNI de Delphi no siempre
modelan esa relación de herencia). Conviértelo explícitamente:

```pascal
TJCharSequence.Wrap((StringToJString(MiTexto) as ILocalObject).GetObjectID)
```

Este patrón (`Wrap` + `as ILocalObject).GetObjectID`) sirve en general para
reinterpretar una referencia JNI como otra interfaz Delphi que apunta al
mismo objeto Java real, cuando las dos interfaces Pascal no tienen una
relación de herencia declarada entre sí.

### 10.4 Detección de idioma (ML Kit Language Identification)

Mismo procedimiento que Translate (sección 5): tarea Gradle propia
(`collectLanguageIdLibs`) para `com.google.mlkit:language-id:X.Y.Z`, filtrar
contra `EnabledSysJars` y lo ya añadido. En la práctica, de decenas de
artefactos resueltos solo 1-2 son realmente nuevos (`language-id-*.aar`) — el
resto ya lo aporta el mismo stack androidx/kotlin/firebase que cualquier otra
librería de ML Kit ya añadida.

**Importante:** Gradle resolverá `emoji2-*`, `emoji2-views-helper-*` y
`lifecycle-process-*` como parte del árbol (los arrastra la versión de
`appcompat` que Gradle elige). **No los añadas** — son exactamente las AAR
que causan el crash `androidx.startup.R$string` de la sección 3; el
`appcompat` de sistema que ya trae RAD Studio es más antiguo y no los
necesita.

**Si el modelo se sirve como asset dentro del AAR** (habitual en los modelos
"bundled" de ML Kit, no solo en Language ID): además de `classes.jar`, revisa
si el AAR trae una carpeta `assets/` —

```bash
unzip -l libs-android/mi-modelo.aar | grep assets/
```

RAD Studio tampoco fusiona esa carpeta en el APK (mismo problema de fondo que
los `.so` de la sección 5.2). Extrae el fichero a mano y declara un
`DeployClass`/`DeployFile` apuntando a la **raíz** `assets\` de la app (no
`assets\internal\`, que es donde RAD Studio deposita los `.java` fuente del
proyecto — aquí hace falta la carpeta real que `Context.getAssets()` consulta):

```xml
<DeployClass Name="AndroidMlKitAssetFile">
    <Platform Name="Android64">
        <RemoteDir>.\assets\</RemoteDir>
        <Operation>1</Operation>
    </Platform>
</DeployClass>
<DeployFile LocalName="..\libs-android\mi-modelo\assets\modelo.tflite.jpg" Class="AndroidMlKitAssetFile">
    <Platform Name="Android64">
        <RemoteName>modelo.tflite.jpg</RemoteName>
        <Overwrite>true</Overwrite>
    </Platform>
</DeployFile>
```

El `RemoteName` debe coincidir exactamente con el nombre de fichero que trae
el AAR — es el nombre que el código interno de ML Kit espera abrir vía
`AssetManager`. Sin esto, el error típico es algo como
`Couldn't open <nombre> model` sin más detalle.

### 10.5 Cámara en vivo (preview continuo, sin "tomar foto")

Para un flujo tipo "apunta con la cámara y reconoce en continuo" (a diferencia
de `TTakePhotoFromCameraAction`, que delega en la app de Cámara externa y
requiere una captura explícita), usa `TCameraComponent` de `FMX.Media` — es
parte del propio RTL de FireMonkey, no un AAR ni un binding JNI propio:

```pascal
// .fmx: TCameraComponent no visual + TTimer para throttling
object CameraComponentLive: TCameraComponent
  OnSampleBufferReady = CameraComponentLiveSampleBufferReady
end
object TimerLiveScan: TTimer
  Interval = 1500
  OnTimer = TimerLiveScanTimer
end
```

```pascal
procedure TFormMain.CameraComponentLiveSampleBufferReady(Sender: TObject;
  const ATime: TMediaTime);
begin
  // la plataforma puede entregar el frame fuera del hilo principal
  TThread.Synchronize(nil,
    procedure
    begin
      CameraComponentLive.SampleBufferToBitmap(ImageLiveCamera.Bitmap, True);
    end);
end;
```

Puntos clave:
- **No proceses cada frame.** `OnSampleBufferReady` dispara a la cadencia del
  sensor (~30 fps); usa un `TTimer` con un intervalo razonable (1-2 s) para
  tomar una copia del frame actual y lanzar el reconocimiento, con un flag
  tipo `FBusy` para no encadenar una nueva pasada mientras la anterior sigue
  resolviéndose de forma asíncrona.
- **Arranca/para la cámara según la pestaña/pantalla activa**, no la dejes
  encendida de fondo — gasta batería y compite por el hardware con cualquier
  otro uso de cámara de la app.
- **`FocusMode` por defecto es de un solo disparo** (enfoca una vez y se
  queda ahí) — si el usuario mueve la cámara o le tiembla el pulso, el enfoque
  no se corrige solo. Actívalo explícitamente **después** de `Active := True`
  (internamente llama a `Camera.getParameters()`, que necesita la cámara ya
  abierta):
  ```pascal
  CameraComponentLive.FocusMode := TFocusMode.ContinuousAutoFocus;
  ```
  En Android esto mapea a `FOCUS_MODE_CONTINUOUS_PICTURE` — el mismo modo que
  usan los escáneres de documentos. No corrige el motion blur por movimiento
  con poca luz (eso depende de estabilización óptica del hardware, fuera del
  alcance de esta API).
- **Baja la calidad de captura** si vas a mandar el frame a un reconocedor de
  texto/objetos — la resolución completa del sensor es innecesaria y ralentiza
  cada pasada:
  ```pascal
  CameraComponentLive.Quality := TVideoCaptureQuality.MediumQuality;
  ```
  (Mismo requisito: fijarlo después de `Active := True`.)
- **Nunca llames a `CameraComponentLive.Active := True` directamente desde el
  hilo principal sin protección.** Hay un bug real en el propio RTL
  (`FMX.Media.Android.pas`, `TAndroidVideoCaptureDevice.GetCamera/OpenCamera`):
  `Camera.open()` se ejecuta en un hilo interno de FMX y el hilo llamante
  espera de forma síncrona un `TEvent` que solo se marca *después* de
  `Camera.open()` — si esa llamada lanza una excepción (p. ej. un fallo
  puntual del propio servicio de cámara de Android, `Camera service died!` /
  `DEAD_OBJECT`, visto en un dispositivo Xiaomi/MIUI real), el evento nunca se
  marca y el hilo llamante se queda bloqueado **para siempre** — si es el hilo
  principal, eso es un ANR seguro y Android acaba matando el proceso. Envuelve
  la activación en tu propio hilo desechable:
  ```pascal
  TThread.CreateAnonymousThread(
    procedure
    begin
      try
        CameraComponentLive.Active := True;
        CameraComponentLive.FocusMode := TFocusMode.ContinuousAutoFocus;
        CameraComponentLive.Quality := TVideoCaptureQuality.MediumQuality;
        TThread.Queue(nil, procedure begin TimerLiveScan.Enabled := True; end);
      except
        on E: Exception do
          TThread.Queue(nil, procedure begin ShowError('No se pudo abrir la cámara: ' + E.message); end);
      end;
    end).Start;
  ```
  Esto no arregla la causa (un fallo del servicio de cámara del sistema, fuera
  de tu control) pero contiene el daño: si vuelve a pasar, se bloquea un hilo
  desechable en vez del hilo de la UI, y la app sigue respondiendo.
- **`FocusMode` y `Quality` necesitan CADA UNO su propio `try/except`, separado
  del de `Active := True` y entre sí.** `Camera.setParameters()` puede lanzar
  `RuntimeException: setParameters failed` en dispositivos concretos si
  rechaza el modo de enfoque o el tamaño de preview elegido — visto en la
  práctica. Si los tres ajustes comparten un único `try/except`, esa excepción
  salta directa al `except` **sin llegar nunca a activar el temporizador de
  reconocimiento** (`TimerLiveScan.Enabled := True` quedaría sin ejecutarse) —
  síntoma confuso: parece que "no reconoce texto" cuando en realidad el
  temporizador nunca se encendió. Trátalos como ajustes opcionales,
  best-effort, cada uno con su propio `try/except` que simplemente ignora el
  fallo y sigue con el valor por defecto del dispositivo:
  ```pascal
  try
    CameraComponentLive.FocusMode := TFocusMode.ContinuousAutoFocus;
  except
    // ignorar - se queda con el modo de enfoque por defecto del dispositivo
  end;
  try
    CameraComponentLive.Quality := TVideoCaptureQuality.MediumQuality;
  except
    // ignorar - se queda con el tamaño de captura por defecto del dispositivo
  end;
  // Esto SIEMPRE debe ejecutarse si Active := True tuvo éxito, sin depender
  // de que FocusMode/Quality funcionen:
  TThread.Queue(nil, procedure begin TimerLiveScan.Enabled := True; end);
  ```
- **Para/reactiva la cámara cuando la app pasa a segundo plano.** Nada de esto
  se dispara solo por cambiar de pestaña dentro de la app — si el usuario pulsa
  Home o cambia a otra app mientras la pestaña con cámara está activa, tu
  `TCameraComponent` se queda abierto de fondo (gasta batería, compite con
  otras apps por el hardware, y en algunos dispositivos el sistema reclama la
  cámara mientras está en background, lo que da otro error de cámara al
  volver). Suscríbete a `TApplicationEventMessage` (`FMX.Platform` +
  `System.Messaging`, ya usado en el proyecto para `TMessageResultNotification`
  de voz) en `FormCreate`:
  ```pascal
  TMessageManager.DefaultManager.SubscribeToMessage(TApplicationEventMessage,
    ApplicationEventHandler);
  ```
  ```pascal
  procedure TFormMain.ApplicationEventHandler(const Sender: TObject;
    const M: TMessage);
  begin
    case TApplicationEventMessage(M).Value.Event of        // ojo: el campo se
      TApplicationEvent.WillBecomeInactive,                // llama "Event",
      TApplicationEvent.EnteredBackground:                 // no "EventType"
        StopLiveCamera;
      TApplicationEvent.BecameActive,
      TApplicationEvent.WillBecomeForeground:
        if TabControlMain.ActiveTab = TabItemVivo then      // solo si seguías
          StartLiveCamera;                                  // en esa pestaña
    end;
  end;
  ```

### 10.6 Interfaz responsive en Android: `Align`/`Margins`, no posiciones fijas

El diseñador FMX trabaja sobre un lienzo de tamaño fijo (`FormFactor.Width`),
y es fácil posicionar controles con `Position.X` + `Size.Width` absolutos que
"encajan" en ese lienzo — pero un móvil real puede ser bastante más estrecho.
Cualquier control cuyo `X + Width` supere el ancho real de pantalla queda
recortado o directamente invisible (síntoma típico: un botón que "desaparece"
en un móvil pero se ve bien en el emulador/diseñador a 480pt).

Los contenedores con `Align = Top`/`Client` ya se redimensionan solos al ancho
real en tiempo de ejecución — el problema aparece en los **hijos** de esos
contenedores cuando van varios controles en una misma fila con posiciones
absolutas. Solución: usar `Align`/`Margins` también ahí, dejando que FMX
calcule las posiciones reales:
- Un control de ancho fijo + otro que ocupe el resto → `Align = Left` +
  `Align = Client`.
- Un control que deba quedar siempre visible en el borde, pase lo que pase
  con el ancho de pantalla (p. ej. un botón de icono al final de una fila) →
  `Align = Right`. Con `Align`, `Left`/`Right`/`Client` se resuelven
  correctamente sin importar el orden en que los controles aparezcan en el
  `.fmx` (FMX procesa primero `Top`/`Bottom`/`Left`/`Right` y `Client` al
  final, con el hueco que quede).
- Un botón de ancho completo → `Align = Top` con `Margins.Left`/`Right` en vez
  de `Position.X` + `Size.Width` fijos.

## 10. Checklist final antes de dar por bueno un build

- [ ] Plataforma activa = Android64 (no Android 32-bit).
- [ ] Ningún `AarReference`/`JavaReference` duplica algo de `EnabledSysJars`
      (incluye variantes `-jvm`).
- [ ] `emoji2-*` y `lifecycle-process-*` NO están en el proyecto.
- [ ] Si excluiste `play-services-base`/`basement`, están las versiones
      "solo-recursos" (`*-resonly.aar`) añadidas.
- [ ] Los `.java` propios están compilados a un `.jar` real y añadidos como
      `JavaReference` — no como `<None>` sueltos.
- [ ] Tras F9, `Android64\Debug\*-dexed.jar` no tiene ningún fichero de 22
      bytes (dex vacío).
- [ ] Si alguna librería trae `.so` dentro del AAR, hay un `DeployFile`
      manual para ella y `unzip -l ....apk | grep .so$` lo confirma en el
      APK final.
- [ ] El evento de cualquier `TAction`/componente que uses (p. ej.
      `TTakePhotoFromCameraAction.OnDidFinishTaking`) está realmente
      enlazado en el `.fmx` (`OnDidFinishTaking = MiMetodo`) y la firma del
      método en el `.pas` coincide exactamente con la del evento — un
      desajuste de firma no da error de compilación, simplemente el método
      nunca se llama.
- [ ] Si usas `startActivityForResult` a mano (voz u otro intent externo), la
      suscripción a `TMessageManager.DefaultManager.SubscribeToMessage(
      TMessageResultNotification, ...)` está hecha antes de lanzar el intent
      (normalmente en `FormCreate`), no después.
- [ ] Cualquier `JString` que pases a un método JNI que pida `JCharSequence`
      está envuelto con `TJCharSequence.Wrap((MiJString as
      ILocalObject).GetObjectID)` — si no, error de compilación E2010.
- [ ] Si alguna librería trae un modelo/recurso como **asset** dentro del AAR
      (`unzip -l lib.aar | grep assets/`), hay un `DeployFile` apuntando a la
      raíz `assets\` real de la app — no solo el `classes.jar`/`.so`.
- [ ] Si usas `TCameraComponent` para preview en directo, `FocusMode` y
      `Quality` se fijan explícitamente **después** de `Active := True` (antes,
      `Device`/`Camera` puede no estar abierto todavía y la llamada no hace
      nada o falla).
- [ ] Ninguna fila con varios controles en horizontal usa `Position.X` +
      `Size.Width` fijos pensados para el ancho del lienzo del diseñador —
      usa `Align = Left/Client/Right` para que se recalculen contra el ancho
      real de la pantalla del dispositivo.
