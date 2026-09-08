# Sesión de depuración — MLKitOCRDemo (Delphi FMX + ML Kit OCR en Android)

Resumen de la sesión: la app arrancaba mal / se cerraba en distintos puntos del flujo
(inicio, foto, reconocer texto). Se fue diagnosticando con logcat real sobre un
dispositivo físico (Xiaomi/MIUI, `adb -s 82a124b7`) y corrigiendo un problema distinto
en cada capa: binding de eventos FMX, duplicados de librerías Android, un provider que
crasheaba al arrancar, un ANR al volver de la cámara, la compilación real del wrapper
Java, un meta-data de Play Services que faltaba, y una app compilada solo para 32 bits
en un ML Kit que ya no lo soporta. Después se añadió una segunda función completa
(ML Kit Translate con descarga de modelos), lo que sacó a la luz dos limitaciones más
de RAD Studio: un dexer que vacía en silencio ciertos `.jar` grandes, y que RAD Studio
nunca extrae librerías nativas (`.so`) de dentro de un `.aar`.

Ver también [`delphikit.md`](delphikit.md): guía prescriptiva ("cómo hacerlo bien
desde cero") que resume todo lo aprendido aquí como receta paso a paso para un
proyecto Delphi nuevo, sin repetir el proceso de prueba y error. Y
[`javabridge.md`](javabridge.md): documento centrado solo en el problema del
punto 5 de abajo — cómo se incluye código Java propio en un proyecto Delphi
Android y por qué la forma "obvia" (añadirlo al proyecto desde el IDE) no
compila nada.

Con el OCR y Translate ya funcionando, se rehizo la pantalla principal
(`TTabControl` con pestañas Foto/Texto/Voz) y se añadieron dictado por voz
(STT) y lectura en voz alta (TTS) — ninguna de las dos es ML Kit, son API
nativas de Android usadas directamente por JNI. Esta parte fue mucho más
fluida que el resto de la sesión (compiló a la primera o a la segunda en cada
paso), con solo dos incidencias, ambas menores — ver problema 11.

## Índice de problemas encontrados y solución

### 1. Botón "Reconocer texto" nunca se activaba
**Causa:** en `MainForm.fmx`, el componente `TakePhotoFromCameraAction1` no tenía
enlazado el evento `OnDidFinishTaking` al método `TakePhotoFromCameraAction1DidFinishTaking`
ya escrito en `MainForm.pas`. El método existía y compilaba, pero nunca se ejecutaba.

**Fix:** añadida la línea en el `.fmx`:
```
object TakePhotoFromCameraAction1: TTakePhotoFromCameraAction
  OnDidFinishTaking = TakePhotoFromCameraAction1DidFinishTaking
end
```

**Nota posterior (la encontró el usuario):** la firma real del evento en esta versión
de RAD Studio es `procedure(Image: TBitmap)`, no `procedure(Sender: TObject; const Image: TBitmap)`
como estaba escrito originalmente en `MainForm.pas`. Con la firma equivocada el binding
por nombre del `.fmx` no conectaba el método (sin dar error de compilación visible).
Corregido por el usuario directamente en `MainForm.pas`.

### 2. Error de compilación Java: `Classpath type already present`
Al añadir todos los `.jar`/`.aar` resueltos por `gradle-deps` (60 ficheros) al proyecto,
el dexer (R8) fallaba con errores como:

```
Error: E7432 com.android.tools.r8.internal.vc: Classpath type already present: androidx.core.content.res.TypedArrayUtils
```

**Causa:** RAD Studio 12 Athens ya trae activadas (propiedad `EnabledSysJars` en el
`.dproj`) un conjunto grande de librerías AndroidX/Play-Services/Firebase como
"system jars" globales. Muchos de los `.jar`/`.aar` bajados por Gradle duplican esas
mismas clases con otra versión.

**Proceso de diagnóstico:** se extrajo la lista `EnabledSysJars` del `.dproj` y se
comparó (por nombre base, ignorando versión) contra los 60 ficheros de `libs-android`,
para separar "duplicados de lo que ya trae RAD Studio" de "genuinamente nuevos".

**Fix:** se movieron a `libs-android\quito\` (fuera del proyecto) 47 ficheros duplicados
(`core-1.9.0`, `appcompat-1.6.1`, `collection-1.1.0`, `kotlin-stdlib-*`, `play-services-base`,
`play-services-tasks`, `firebase-*`, etc.). Se detectaron dos casos adicionales sobre la
marcha porque el error solo aparece uno a uno según el orden de dexing:
- `core-1.9.0.aar` → `androidx.core.content.res.TypedArrayUtils` duplicada.
- `collection-1.1.0.jar` → `androidx.collection.ArraySet` duplicada (RAD Studio ya trae
  `collection-jvm-1.4.2`).

Quedaron añadidas al proyecto solo 10 librerías realmente nuevas:
```
common-18.11.0.aar
emoji2-1.2.0.aar                      (luego también se quitó, ver problema 3)
emoji2-views-helper-1.2.0.aar         (luego también se quitó, ver problema 3)
image-1.0.0-beta1.aar
lifecycle-process-2.4.1.aar           (luego también se quitó, ver problema 3)
play-services-mlkit-text-recognition-19.0.1.aar
play-services-mlkit-text-recognition-common-19.1.0.aar
resourceinspection-annotation-1.0.1.jar
vision-common-17.3.0.aar
vision-interfaces-16.3.0.aar
```

### 3. Crash al arrancar: `NoClassDefFoundError: androidx.startup.R$string`
```
FATAL EXCEPTION: main
java.lang.NoClassDefFoundError: Failed resolution of: Landroidx/startup/R$string;
  at androidx.startup.AppInitializer.discoverAndInitialize
  at androidx.startup.InitializationProvider.onCreate
```

**Causa:** `emoji2-1.2.0.aar` y `lifecycle-process-2.4.1.aar` inyectan en el manifest
fusionado un `<provider android:name="androidx.startup.InitializationProvider">` que se
ejecuta automáticamente al crear el proceso. Ese provider necesita la clase de recursos
`androidx.startup.R$string`, que nunca se genera porque `androidx.startup` en este
proyecto solo existe como `.dex.jar` de sistema (sin recursos propios que `aapt2` pueda
compilar).

**Fix:** se quitaron del proyecto `emoji2-1.2.0.aar`, `emoji2-views-helper-1.2.0.aar` y
`lifecycle-process-2.4.1.aar` (ninguno lo usa el código real: ni `EmojiCompat` ni
`ProcessLifecycleOwner` se llaman desde `MlKitTextRecognizerBridge.java`). Al quitarlos
desaparece el `<provider>` del manifest fusionado y el crash.

Lista final de librerías añadidas al proyecto (7):
```
common-18.11.0.aar
image-1.0.0-beta1.aar
play-services-mlkit-text-recognition-19.0.1.aar
play-services-mlkit-text-recognition-common-19.1.0.aar
resourceinspection-annotation-1.0.1.jar
vision-common-17.3.0.aar
vision-interfaces-16.3.0.aar
```

### 4. ANR al volver de tomar la foto ("se sale del programa")
En logcat: `Input dispatching timed out ... Waited 5000ms for MotionEvent` → 
`ANR in com.example.mlkitocrdemo` → proceso matado. No había ninguna excepción Java:
era el hilo principal bloqueado, no un crash.

Se intentó primero limitar la resolución de la foto con una propiedad `Quality` en
`TTakePhotoFromCameraAction` — **esa propiedad no existe** en esta versión (el usuario
lo comprobó al dar error de compilación; se quitó de nuevo del `.fmx`).

**Causa real:** la firma incorrecta del evento `OnDidFinishTaking` (ver problema 1) — al
corregirla, el ANR desapareció sin necesidad de tocar nada de resolución de imagen.

### 5. `Java type JMlKitTextRecognizerBridge could not be found`
Al pulsar "Reconocer texto", `TJMlKitTextRecognizerBridge.JavaClass.init` fallaba porque
la clase Java `com.example.mlkitocr.MlKitTextRecognizerBridge` no existía en el `.dex`
del APK — no era un tema de descargar el modelo de OCR de Play Services, como se
sospechó al principio.

**Diagnóstico:** los ficheros `MlKitTextRecognizerBridge.java` y `OcrCallback.java`
estaban copiados dentro de `MLKitOCRDemo\com\example\mlkitocr\`, pero en el `.dproj`
aparecían como:
```xml
<None Include="com\example\mlkitocr\MlKitTextRecognizerBridge.java"/>
<None Include="com\example\mlkitocr\OcrCallback.java"/>
```
`None` es el tipo de item de MSBuild para "solo un archivo en el proyecto, no lo
proceses" — nunca se compilaban, pasara lo que pasara desde el IDE (ni desde Delphi 12
ni desde Delphi 13). Se comprobó contra `CodeGear.Common.targets` (instalación real de
RAD Studio) que el único mecanismo de RAD Studio para invocar `javac` automáticamente es
el de los "Android Services" generados por su propio wizard — **no existe un mecanismo
genérico para compilar `.java` sueltos añadidos a mano**, pese a lo que afirmaba el
README original del proyecto.

**Fix real:** compilar el wrapper Java a mano con `javac`, empaquetarlo en un `.jar`, y
añadir ese `.jar` como `JavaReference` (el mismo tipo de entrada que usan las demás
librerías ML Kit) en vez de como `.java` suelto. Ver detalle completo abajo.

### 6. `GooglePlayServicesMissingManifestValueException` y luego `GooglePlayServicesUtil: resources were not found`
Con el wrapper ya compilado y encontrado, "Reconocer texto" fallaba en dos fases
sucesivas al llamar de verdad a Play Services:

1. Primero: `GooglePlayServicesMissingManifestValueException` — falta el meta-data
   `com.google.android.gms.version` en el manifest, obligatorio en cualquier app que use
   Play Services. Se probó primero un parche rápido con el valor **literal**
   (`android:value="12451000"`, extraído a mano del `values.xml` real de
   `play-services-basement-18.4.0.aar`) en vez de la referencia a recurso — funcionó a
   medias.
2. Al añadir después las AAR "solo-recursos" de `play-services-basement`/`base` (ver
   problema 2, arriba: sus *clases* estaban excluidas por duplicado, pero sus
   *recursos* — incluido ese mismo `google_play_services_version` — nunca se habían
   generado), el manifest merger se quejó de valor duplicado
   (`tools:replace="android:value"` sugerido). Se quitó el literal y se dejó que la AAR
   de recursos aportara el valor real vía `@integer/google_play_services_version`.

**Fix final:** dos AAR "solo-recursos" (mismo truco que en el problema 3: manifest y
`res/` reales, `classes.jar` vaciado para no duplicar clases) añadidas como
`AarReference`:
```
resonly/play-services-basement-18.4.0-resonly.aar
resonly/play-services-base-18.5.0-resonly.aar
```
Construidas así:
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

### 7. `Failed to init text recognizer play-services-mlkit-text-recognition` (sin traza) → la app solo compilaba para 32 bits
Con el manifest ya arreglado, el reconocimiento seguía fallando con un mensaje genérico
sin ninguna excepción logueada. En logcat sí se veía que Play Services **resolvía
correctamente** el módulo remoto (`DynamiteModule: Selected remote version of
com.google.android.gms.vision.ocr, version >= 263234001`) pero fallaba justo después,
en silencio.

**Diagnóstico:** `adb shell dumpsys package <paquete> | grep primaryCpuAbi` →
`armeabi-v7a`. El `.dproj` solo tenía activa la plataforma **Android** (32 bits);
**Android64** existía en el proyecto (con toda su configuración ya lista, iconos, SDK,
etc.) pero desactivada (`<Platform value="Android64">False</Platform>`). Google lleva
tiempo retirando el soporte 32-bit de varios módulos "dynamite" de Play Services
(incluido el de OCR de ML Kit) en dispositivos que ya son 64-bit: el módulo se
"encuentra" (por eso resuelve la versión) pero no llega a cargarse de verdad en un
proceso de 32 bits.

**Fix:** Project Manager → Target Platforms → *Add Platform* → *Android 64-bit* →
seleccionarla como plataforma activa. Confirmado: compila y funciona sin cambios de
código. **A partir de aquí toda la sesión se compiló y probó exclusivamente en
Android64.**

---

## Segunda función: ML Kit Translate (traducir el texto reconocido, con descarga de modelos)

Con el OCR ya funcionando, se añadió un botón "Traducir" que usa el texto ya
reconocido, con selector de idioma origen/destino (poblado dinámicamente llamando a
`TranslateLanguage.getAllLanguages()` desde Java, sin mantener a mano la lista de ~59
idiomas) y descarga bajo demanda del modelo del idioma (`downloadModelIfNeeded`).

Nuevos ficheros: `MlKitTranslatorBridge.java` + `TranslateCallback.java` (wrapper),
`Android.JNI.MLKitTranslate.pas` (declaraciones JNI), más los combos/botones/memo
nuevos en `MainForm.fmx`/`.pas`.

Dependencia resuelta igual que el OCR, con una tarea Gradle nueva
(`collectTranslateLibs`) para `com.google.mlkit:translate:17.0.3`.

### 8. `NoClassDefFoundError: Lokhttp3/MediaType` — el dexer de RAD Studio vacía en silencio ciertos `.jar` grandes
`translate` necesita `com.squareup.okhttp3:okhttp` (mínimo transitivo declarado:
3.0.0, del 2016 — se forzó a 3.12.13, más moderno, sin que cambiara el problema de
fondo). Añadido como `JavaReference` normal (igual que `resourceinspection-annotation`,
que sí funciona), compilaba sin error pero la app crasheaba en tiempo de ejecución:
```
java.lang.NoClassDefFoundError: com.google.android.gms.internal.mlkit_translate.zztz
Caused by: java.lang.ClassNotFoundException: Didn't find class "okhttp3.MediaType" on path: ...base.apk...
```

**Diagnóstico:** revisando los `.jar` pre-dexados que genera RAD Studio
(`Android64\Debug\*-dexed.jar`) antes de fusionarlos en el `.dex` final:
```bash
find Android64/Debug -iname "*-dexed.jar" -exec ls -la {} \;
```
`okhttp-3.0.0-dexed.jar` pesaba **22 bytes** — un zip vacío. RAD Studio había fallado
al dexear ese `.jar` en concreto **sin dar ningún error de compilación**. Se comprobó
con `d8` de línea de comandos que el mismo `.jar` (con o sin `--lib android.jar`) sí se
dexea bien, produciendo un `classes.dex` real de ~300 KB — el bug es específico de cómo
RAD Studio invoca su dexer para `JavaReference` grandes/complejos (con muchas
advertencias de "desugaring" por interfaces con métodos por defecto). Se descartó que
fuera un duplicado de clases (comprobado contra `EnabledSysJars` y contra todas las
demás AAR ya añadidas: ninguna contiene clases `okhttp3.*`/`okio.*`).

**Fix:** envolver `okhttp-3.12.13.jar` en un `.aar` mínimo (con su propio
`AndroidManifest.xml`) y añadirlo como `AarReference` en vez de `JavaReference` — todas
las entradas `AarReference` de la sesión (incluida la propia `translate-17.0.3.aar`,
igual de grande) se dexearon bien; solo los `JavaReference` grandes fallaban.
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
cd "$WORK" && "$JARBIN" cf ".../libs-android/translate/okhttp-3.12.13-aar.aar" .
```

Nota aparte: `okio` (dependencia de `okhttp`) se descartó del proyecto por duplicado —
mismo caso que `collection`/`annotation` del problema 2, pero con nombre distinto:
RAD Studio ya trae `okio-jvm-3.4.0.dex.jar`, que aporta las mismas clases `okio.*` que
el `okio-1.6.0.jar`/`okio-1.15.0.jar` que resuelve Gradle bajo el nombre sin sufijo
`-jvm`. Confirmado con el mismo error de dexer del problema 2
(`Type okio.Sink is defined multiple times`).

### 9. Detalle del entorno: dos instalaciones de RAD Studio y nombre de paquete distinto
Al reproducir estos errores se descubrió que las compilaciones reales las hacía el
usuario con **RAD Studio 37.0 ("Delphi 13")**, no con la 23.0 usada hasta entonces para
las comprobaciones por CLI (las rutas de error mostraban
`...\Embarcadero\Studio\37.0\lib\android\Debug\...`). A partir de aquí las
comprobaciones de compilación por terminal se hicieron también contra `Studio\37.0\bin\
rsvars.bat`, para probar exactamente el mismo toolchain. La lista `EnabledSysJars` está
guardada en el propio `.dproj` (no en la instalación del IDE), así que aplica igual
para ambas versiones.

También se detectó (sin llegar a corregirlo, pendiente) que la build de **Android64**
se instala con el paquete `com.embarcadero.MLKitOCRDemo`, distinto del
`com.example.mlkitocrdemo` de la build de 32 bits — un valor de plantilla sin
personalizar en el `PropertyGroup` de `Base_Android64` del `.dproj`
(`VerInfo_Keys>package=com.embarcadero.$(MSBuildProjectName)`).

### 10. `UnsatisfiedLinkError: Couldn't load translate native code library` — RAD Studio no extrae `.so` de dentro de un AAR
Con el problema 8 resuelto, la traducción fallaba al intentar cargar el motor
TFLite embebido en `translate-17.0.3.aar` (`jni/<abi>/libtranslate_jni.so`).

**Diagnóstico:**
```bash
unzip -l Android64/Debug/MLKitOCRDemo/bin/MLKitOCRDemo.apk | grep "\.so$"
```
Solo aparecía `lib/arm64-v8a/libMLKitOCRDemo.so` (el binario propio de la app) — el
`.so` de `translate` nunca llegó al APK. Revisando qué extrae RAD Studio de una AAR
(carpeta `Android64\Debug\AndroidLibraries\translate-17.0.3\`): solo
`AndroidManifest.xml`, `classes.jar`, `res.zip` y `R-prepended.txt`. Confirmado también
contra `CodeGear.Deployment.Targets`: la tarea `ResolveAndroidLibraryFilesContents` que
procesa cada AAR solo produce manifest/recursos/símbolos como salida — **RAD Studio no
tiene ningún mecanismo para extraer librerías nativas de un AAR**, ni con la
convención moderna (`jni/<abi>/`, se probó primero) ni con la antigua
(`libs/<abi>/`, se probó después duplicando la carpeta dentro del AAR — tampoco
funcionó, RAD Studio ignora ambas).

**Primer intento fallido:** `DeployFile` manual con `Class="DependencyModule"` — no
hizo nada. Revisando la definición de esa clase en el propio `.dproj`
(`<DeployClass Name="DependencyModule">`), solo admite plataformas
iOS/macOS/Win32 y extensiones `.dylib`/`.dll`/`.bpl` — ninguna sección para Android, así
que el `DeployFile` se ignora en silencio.

**Fix real:** extraer el `.so` del AAR a mano, y declarar una `DeployClass` propia para
Android64 (RAD Studio solo trae de fábrica variantes de 32 bits heredadas:
`AndroidLibnativeArmeabiv7aFile`/`...ArmeabiFile`/`...MipsFile`, ninguna arm64):
```bash
mkdir -p libs-android/native
cd /tmp && unzip -o -q ".../translate-17.0.3.aar" "jni/arm64-v8a/libtranslate_jni.so"
cp jni/arm64-v8a/libtranslate_jni.so \
   ".../libs-android/native/libtranslate_jni-arm64-v8a.so"
```
```xml
<DeployClass Name="AndroidLibnativeArm64File">
    <Platform Name="Android64">
        <RemoteDir>library\lib\arm64-v8a</RemoteDir>
        <Operation>1</Operation>
    </Platform>
</DeployClass>
```
```xml
<DeployFile LocalName="..\libs-android\native\libtranslate_jni-arm64-v8a.so" Class="AndroidLibnativeArm64File">
    <Platform Name="Android64">
        <RemoteName>libtranslate_jni.so</RemoteName>
        <Overwrite>true</Overwrite>
    </Platform>
</DeployFile>
```
Verificado tras F9: `unzip -l ...apk | grep "\.so$"` → aparece
`lib/arm64-v8a/libtranslate_jni.so` (16 MB) junto al binario propio. Traducción
funcionando de extremo a extremo (con descarga real del modelo de idioma la primera
vez que se usa un par de idiomas nuevo).

---

## Detalle: cómo se compiló el wrapper Java (`MlKitTextRecognizerBridge.java` + `OcrCallback.java`)

### 1. Herramientas usadas
- JDK: `C:\Program Files\Eclipse Adoptium\jdk-17.0.9.9-hotspot` (ya instalado en la
  máquina; también había un JDK 21 pero se usó el 17 para que coincida con el
  `-source 17 -target 17` que usa RAD Studio internamente según `CodeGear.Common.targets`).
- `android.jar` de la plataforma Android 34 (la misma que usa el proyecto, `targetSdkVersion=34`),
  localizado en el caché de SDK de RAD Studio:
  `C:\Users\Public\Documents\Embarcadero\Studio\23.0\CatalogRepository\AndroidSDK-2525-23.0.53571.9782\platforms\android-34\android.jar`

### 2. Extraer `classes.jar` de cada AAR necesario como classpath de compilación
Los `.aar` no se pueden pasar directamente a `javac`; hay que sacar su `classes.jar`
interno (cada `.aar` es un zip). Se fueron añadiendo uno a uno, según los errores
`cannot find symbol` / `package ... does not exist` que iba dando el compilador:

```bash
SCRATCH=".../scratchpad"
mkdir -p "$SCRATCH/aar_extract/<nombre>"
unzip -o -q "libs-android/<nombre>.aar" classes.jar -d "$SCRATCH/aar_extract/<nombre>"
```

AARs de los que se extrajo `classes.jar` (algunos ya estaban añadidos al proyecto Delphi,
otros —como `play-services-tasks`, `play-services-base/basement`— solo hacían falta como
dependencia de compilación, no van al proyecto Delphi porque ya los aporta RAD Studio
como system jar):
- `vision-common-17.3.0.aar` → `InputImage`
- `vision-interfaces-16.3.0.aar`
- `play-services-mlkit-text-recognition-19.0.1.aar` → `TextRecognizerOptions` (paquete `.latin`)
- `play-services-mlkit-text-recognition-common-19.1.0.aar` → `Text`, `TextRecognition`, `TextRecognizer`
- `libs-android/quito/play-services-tasks-18.2.0.aar` → `OnSuccessListener`, `OnFailureListener`
- `common-18.11.0.aar` → `com.google.mlkit.common.sdkinternal.MLTaskInput`
- `libs-android/quito/play-services-basement-18.4.0.aar` → `OptionalModuleApi`
- `libs-android/quito/play-services-base-18.5.0.aar`
- `image-1.0.0-beta1.aar` → `com.google.android.odml.image.MlImage`
- `libs-android/quito/lifecycle-common-2.5.1.jar` → usado directamente (ya es un `.jar`, sin extraer)

### 3. Comando de compilación final (`javac`)
Ejecutado desde Git Bash, con las rutas en formato Windows nativo (`C:\...`) para evitar
que MSYS reinterpretara mal el `;` del classpath multi-ruta al llamar a un `.exe` nativo:

```bash
SCRATCH="C:\Users\TONI\AppData\Local\Temp\claude\...\scratchpad"
ANDROID_JAR="C:\Users\Public\Documents\Embarcadero\Studio\23.0\CatalogRepository\AndroidSDK-2525-23.0.53571.9782\platforms\android-34\android.jar"

CP="${ANDROID_JAR};${SCRATCH}\aar_extract\vision-common-17.3.0\classes.jar;${SCRATCH}\aar_extract\vision-interfaces-16.3.0\classes.jar;${SCRATCH}\aar_extract\play-services-mlkit-text-recognition-19.0.1\classes.jar;${SCRATCH}\aar_extract\play-services-mlkit-text-recognition-common-19.1.0\classes.jar;${SCRATCH}\aar_extract\play-services-tasks-18.2.0\classes.jar;${SCRATCH}\aar_extract\common-18.11.0\classes.jar;${SCRATCH}\aar_extract\play-services-basement-18.4.0\classes.jar;${SCRATCH}\aar_extract\play-services-base-18.5.0\classes.jar;${SCRATCH}\aar_extract\image-1.0.0-beta1\classes.jar;E:\claudecode\android\mlkit\libs-android\quito\lifecycle-common-2.5.1.jar"

"/c/Program Files/Eclipse Adoptium/jdk-17.0.9.9-hotspot/bin/javac" \
  -g -Xlint:deprecation -source 17 -target 17 -encoding UTF-8 \
  -d "${SCRATCH}\javac_out" \
  -classpath "$CP" \
  "E:\claudecode\android\mlkit\MLKitOCRDemo\com\example\mlkitocr\OcrCallback.java" \
  "E:\claudecode\android\mlkit\MLKitOCRDemo\com\example\mlkitocr\MlKitTextRecognizerBridge.java"
```

(Los flags `-g -Xlint:deprecation -source 17 -target 17 -encoding UTF-8` se copiaron
literalmente de la propiedad `JavaCCommand` que usa el propio RAD Studio en
`CodeGear.Common.targets`, para que el `.class` resultante sea equivalente al que
generaría el IDE.)

Resultado: compiló con éxito (solo un warning inofensivo por una anotación
`androidx.annotation.RestrictTo$Scope` no resuelta en tiempo de compilación, que no
afecta a la ejecución).

### 4. Empaquetar en `.jar`
```bash
cd "$SCRATCH/javac_out"
"/c/Program Files/Eclipse Adoptium/jdk-17.0.9.9-hotspot/bin/jar" cf "$SCRATCH/mlkitocr-wrapper.jar" -C "$SCRATCH/javac_out" com
mkdir -p "/e/claudecode/android/mlkit/libs-android/wrapper"
cp "$SCRATCH/mlkitocr-wrapper.jar" "/e/claudecode/android/mlkit/libs-android/wrapper/mlkitocr-wrapper.jar"
```

Resultado: `libs-android\wrapper\mlkitocr-wrapper.jar` con las 4 clases:
```
com/example/mlkitocr/OcrCallback.class
com/example/mlkitocr/MlKitTextRecognizerBridge.class
com/example/mlkitocr/MlKitTextRecognizerBridge$1.class
com/example/mlkitocr/MlKitTextRecognizerBridge$2.class
```

### 5. Registrar el `.jar` en el proyecto Delphi
En `MLKitOCRDemo.dproj`, se sustituyeron las dos entradas `<None>` por una
`<JavaReference>` (mismo esquema XML que usan el resto de librerías ML Kit añadidas
desde el IDE):

```xml
<JavaReference Include="..\libs-android\wrapper\mlkitocr-wrapper.jar">
    <ContainerId>ClassesdexFile</ContainerId>
    <Disabled/>
</JavaReference>
<None Include="com\example\mlkitocr\MlKitTextRecognizerBridge.java"/>
<None Include="com\example\mlkitocr\OcrCallback.java"/>
```
(Los `<None>` de las fuentes `.java` se dejaron solo como referencia/documentación
dentro del proyecto; no participan en el build.)

### 6. Verificación
```
cmd /c '"C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat" && msbuild MLKitOCRDemo.dproj /p:config=Debug /p:platform=Android /t:Build'
```
→ `Compilación correcta`, 0 errores.

**Importante — limitación de esta verificación:** el target `Build` de `msbuild` en
línea de comandos solo recompila el binario nativo Delphi (`.pas` → `.so`); **no**
vuelve a empaquetar el APK completo (no repite el dexing ni el `aapt2`). Por eso, en
toda la sesión, cada vez que se tocó una librería o el wrapper Java, el paso real de
comprobación en el dispositivo requirió pulsar **F9 en el IDE** (o un build/deploy
completo), no bastaba con el `msbuild` de la terminal.

### Si hay que volver a tocar el wrapper Java
Si en el futuro se edita `MlKitTextRecognizerBridge.java` u `OcrCallback.java`, hay que
repetir los pasos 3–5 (recompilar con `javac` y volver a generar `mlkitocr-wrapper.jar`)
— el `.dproj` no vuelve a compilarlos solo, apunta a un `.jar` ya construido.

---

## Tercera y cuarta función: pestañas, dictado por voz y texto a voz

Reestructurado `MainForm` con un `TTabControl` (pestañas **Foto** — flujo OCR de
siempre —, **Texto** — memo editable para escribir directamente — y **Voz**), con
la sección de traducción (idiomas, botón, resultado, y ahora "Escuchar traducción")
compartida debajo de las pestañas. `GetActiveSourceText` decide de qué memo sacar
el texto a traducir según la pestaña activa en cada momento.

### 11. Dos incidencias menores (nada comparable a la parte anterior de la sesión)

**a) `Android.JNI.MLKitTranslate.pas` había desaparecido del `.dproj`.** Al revisar
el `.dproj` para añadir la nueva unidad `Android.JNI.TTS.pas`, se encontró que la
entrada `<DCCReference Include="Android.JNI.MLKitTranslate.pas"/>` (añadida varias
sesiones atrás) ya no estaba — mismo mecanismo que hizo desaparecer las AAR
`resonly` en su momento (el IDE reescribe el `.dproj` con su copia en memoria si no
reconoce la entrada como añadida desde su propia UI). La diferencia esta vez: **el
build nunca dejó de funcionar**, porque el compilador de Delphi busca los `.pas` por
nombre en el directorio del proyecto independientemente de si aparecen como
`DCCReference` — esa entrada solo controla la visibilidad en el árbol del Project
Manager del IDE, no la compilación. Se volvieron a añadir (`Android.JNI.MLKitTranslate.pas`
y `Android.JNI.TTS.pas`) con el proyecto cerrado, solo por higiene/navegación en el IDE.

**b) `error E2010: Incompatible types: JCharSequence y JString`** al llamar a
`TextToSpeech.speak`, que pide `JCharSequence` y se le pasaba directamente el
resultado de `StringToJString`. Aunque en Java `String` implementa `CharSequence`,
las interfaces JNI de Delphi no siempre modelan esa relación de herencia. Fix:
```pascal
TJCharSequence.Wrap((StringToJString(MiTexto) as ILocalObject).GetObjectID)
```

### Dictado por voz (STT)
Sin librerías nuevas: se lanza el intent nativo `android.speech.action.
RECOGNIZE_SPEECH` con `TAndroidHelper.Activity.startActivityForResult`, y se
recoge el resultado suscribiéndose a `TMessageManager.DefaultManager` con
`TMessageResultNotification` — el mismo mecanismo interno que usa FMX para
cualquier `startActivityForResult` (p. ej. el propio `TTakePhotoFromCameraAction`
por dentro). No hace falta declarar `RecognizerIntent` como clase JNI: sus
constantes son literales `String` estables, se pasan como texto directamente
(`'android.speech.extra.LANGUAGE_MODEL'`, `'free_form'`, etc.). Compiló a la
primera pese a ser una hipótesis sin verificar de antemano (clase y unit
`Androidapi.JNI.App` correctos al primer intento).

### Texto a voz (TTS)
Nueva unidad `Android.JNI.TTS.pas` con binding JNI propio (no hay wrapper de
terceros razonable para 4 métodos) para `android.speech.tts.TextToSpeech`, sin
depender de ningún binding de `java.util.Locale` que pudiera ya existir en otra
unidad (se declaró una interfaz `JLocaleTTS` con nombre propio para evitar choque
de identificadores duplicados, apuntando igualmente a `java/util/Locale` vía
`JavaSignature`). Las constantes (`SUCCESS`, `LANG_NOT_SUPPORTED`, `QUEUE_FLUSH`...)
se declararon como `const` Pascal normales en vez de leerlas por JNI (estables
desde API 1, no vale la pena la complejidad de un acceso a campo estático).

**Confirmado:** el motor de voz por defecto de Android (Google TTS) no soporta
esperanto — `setLanguage` devuelve `LANG_NOT_SUPPORTED`. Se implementó para avisar
de esto explícitamente en vez de fallar en silencio, en lugar de intentar forzarlo.

---

## Quinta función: detección de idioma de ML Kit (Language Identification)

Misma metodología que Translate: tarea `collectLanguageIdLibs` nueva en
`gradle-deps/build.gradle` para `com.google.mlkit:language-id:17.0.6`, diferencia
por nombre base contra `EnabledSysJars` y contra lo ya añadido al proyecto. De 56
artefactos resueltos, solo dos eran realmente nuevos: `language-id-17.0.6.aar` y
`language-id-common-16.1.0.aar` — el resto ya lo cubría el mismo stack
androidx/kotlin/firebase que OCR y Translate.

**Deliberadamente NO añadidos:** `emoji2-1.2.0.aar`, `emoji2-views-helper-1.2.0.aar`
y `lifecycle-process-2.4.1.aar`, aunque Gradle los resuelve como parte del árbol
(los arrastra el `appcompat` más nuevo que resuelve Gradle). Son exactamente las
AAR que causaron el crash `NoClassDefFoundError: androidx.startup.R$string` del
problema 3 — RAD Studio usa un `appcompat` de sistema más antiguo que no las
necesita, así que se excluyen igual que la primera vez.

Wrapper Java nuevo (`LanguageIdCallback.java` + `MlKitLanguageIdBridge.java`,
método `identifyLanguage(text, callback)` sobre `LanguageIdentification.getClient()`),
compilado y empaquetado con el mismo procedimiento `javac` de siempre — pequeño, así
que `JavaReference` normal sin necesidad de envolverlo en AAR.

### 12. `Couldn't open language identification model` — RAD Studio tampoco extrae `assets/` de un AAR

Con las librerías bien añadidas y el wrapper compilando y cargando, la llamada a
`identifyLanguage` fallaba con ese mensaje. Causa: `language-id-17.0.6.aar` trae el
modelo TFLite como **asset** dentro del AAR (`assets/tflite_langid.tflite.jpg` —
la extensión `.jpg` es deliberada, para que `aapt` no intente comprimirlo al
empaquetar). Mismo problema de fondo que el `.so` de Translate (problema 10): RAD
Studio empaqueta `classes.jar` de un AAR, pero no fusiona ninguna otra carpeta
(`res/`, `jni/`, y aquí `assets/`) en el APK final.

**Fix:** igual que con el `.so`, extraer el fichero a mano y declarar un
`DeployClass`/`DeployFile` propio que lo copie a la carpeta `assets\` real de la
app (no `assets\internal\`, que es donde RAD Studio deposita por convención los
`.java` fuente del proyecto — aquí hace falta la raíz de `assets\`, que es donde
`Context.getAssets()` busca de verdad):

```xml
<DeployClass Name="AndroidMlKitAssetFile">
    <Platform Name="Android64">
        <RemoteDir>.\assets\</RemoteDir>
        <Operation>1</Operation>
    </Platform>
</DeployClass>
...
<DeployFile LocalName="..\libs-android\languageid\assets\tflite_langid.tflite.jpg" Class="AndroidMlKitAssetFile">
    <Platform Name="Android64">
        <RemoteName>tflite_langid.tflite.jpg</RemoteName>
        <Overwrite>true</Overwrite>
    </Platform>
</DeployFile>
```

El nombre de fichero remoto debe coincidir exactamente con el que trae el AAR —
es el nombre que el código interno de ML Kit espera encontrar vía `AssetManager`.

Con esto, "Detectar idioma" (botón nuevo junto a "Traducir") funciona: identifica
el idioma del texto activo (según la pestaña) y, si el código coincide con uno de
la lista de Translate, selecciona automáticamente `ComboLangSource`.

## Sexta función: pestaña "Vivo" — cámara en directo con OCR e idioma continuos

A petición explícita ("una ventanita con la imagen de la cámara... directamente
sobre la entrada de la imagen sin hacer foto"): nueva pestaña con `TCameraComponent`
(`FMX.Media`, parte del propio RTL de FireMonkey — sin AAR, sin JNI, sin
dependencias nuevas, funciona igual en cualquier plataforma que soporte cámara).

- `CameraComponentLive.OnSampleBufferReady` pinta cada frame en `ImageLiveCamera`
  vía `SampleBufferToBitmap` (dentro de `TThread.Synchronize`, por si la plataforma
  entrega el frame fuera del hilo principal).
- Un `TTimer` (`TimerLiveScan`, 1.5 s) toma una copia del frame actual y encadena
  `recognizeText` → `identifyLanguage` → (si `CheckBoxAutoTranslate` está marcado y
  el idioma detectado está en la lista) `translate`, todo sobre los mismos bridges
  Java que ya usan las otras pestañas. Un flag `FLiveBusy` cubre toda la cadena
  (no solo el primer paso) para no lanzar un nuevo frame mientras el anterior sigue
  resolviéndose en cualquiera de esos tres pasos.
- La cámara solo está activa mientras la pestaña está seleccionada
  (`TabControlMainChange` llama a `StartLiveCamera`/`StopLiveCamera`), para no
  gastar batería ni pelearse por el hardware de cámara con "Tomar foto".

### El pulso tiembla y no enfoca bien

Comentario del usuario probando en dispositivo real. Comprobado en el código
fuente de FMX (`FMX.Media.Android.pas`): si nunca se fija `FocusMode`, Android se
queda con el modo por defecto del driver de la cámara — típicamente autoenfoque
de un solo disparo, que no reenfoca si el plano del texto se mueve. Fix de una
línea, fijado **después** de `Active := True` (por debajo llama a
`Camera.getParameters()`, que necesita la cámara ya abierta):

```pascal
CameraComponentLive.FocusMode := TFocusMode.ContinuousAutoFocus;
```

Esto mapea a `Camera.Parameters.FOCUS_MODE_CONTINUOUS_PICTURE` en Android — el
mismo modo que usan los escáneres de documentos. No corrige el motion blur en sí
(borrosidad por movimiento con poca luz), que depende de estabilización óptica del
propio hardware y no es controlable desde esta API.

De paso, mismo mecanismo para bajar la resolución de captura y acelerar cada
pasada de OCR (la resolución completa del sensor es innecesaria para reconocer
texto y ralentiza cada llamada a `recognizeText`):

```pascal
CameraComponentLive.Quality := TVideoCaptureQuality.MediumQuality;
```

### 13. `EJNIException: Fail to connect to camera service` → ANR y kill de la app — bug real en `FMX.Media.Android.pas`, no en el código propio

Al entrar en la pestaña "Vivo", en un intento concreto: excepción
`java.lang.RuntimeException: Fail to connect to camera service`. Diagnóstico vía
`adb logcat` en el momento exacto:

```
W/CameraBase: An error occurred while connecting to camera 0: Status(-129, EX_TRANSACTION_FAILED): 'DEAD_OBJECT: '
W/CameraBase: Camera service died!
W/System.err: java.lang.RuntimeException: Fail to connect to camera service
...
I/CameraService: CameraService started (pid=11194)   ← el propio Android lo reinicia solo, medio segundo después
```

Causa inmediata: el propio `cameraserver` de Android murió justo en el instante
de abrir la cámara (`DEAD_OBJECT`) — un fallo puntual del sistema/HAL de cámara
del dispositivo (Xiaomi/MIUI), no algo provocado por nuestro código (no hay
denegación de permiso, ni "cámara en uso por otra app": `dumpsys media.camera`
mostraba `Active Camera Clients: []`).

Lo grave no fue el error en sí, sino la consecuencia: en el log, justo después,
aparecen ~30 segundos de `Input event dispatching timed out... (server) is not
responding`, y Android acaba matando el proceso. Causa raíz, leyendo el propio
código fuente de FMX (`FMX.Media.Android.pas`,
`TAndroidVideoCaptureDevice.GetCamera/OpenCamera`):

```pascal
Runnable := TRunnable.Create(
  procedure
  begin
    Camera := TJCamera.JavaClass.open(FCameraId);
    WaitEvent.SetEvent;    // <- nunca se alcanza si open() lanza excepción
  end);
...
WaitEvent.WaitFor;         // <- el hilo que llamó a Active := True se queda aquí para siempre
```

Si `Camera.open()` lanza, `SetEvent` nunca se ejecuta y el hilo que invocó
`Active := True` (el hilo principal de la UI, si se llama directamente desde un
evento) se bloquea **indefinidamente** — de ahí el ANR. Es un bug del propio RTL
de Embarcadero, no arreglable sin tocar `FMX.Media.Android.pas`.

**Mitigación aplicada** (no arregla la causa — un fallo del servicio de cámara del
sistema — pero evita que congele la app entera): mover la activación de la cámara
a un hilo propio, desechable, en vez de llamarla directamente desde el hilo
principal:

```pascal
TThread.CreateAnonymousThread(
  procedure
  begin
    try
      CameraComponentLive.Active := True;
      // ... FocusMode, Quality ...
      TThread.Queue(nil, procedure begin TimerLiveScan.Enabled := True; end);
    except
      on E: Exception do
        TThread.Queue(nil, procedure begin ShowError('...' + E.message); end);
    end;
  end).Start;
```

Así, si `Camera.open()` vuelve a fallar y el bug de FMX vuelve a impedir que se
señalice el evento, el hilo bloqueado es uno desechable creado por nosotros, no
el hilo principal — la app se queda sin cámara en directo pero sigue respondiendo,
en vez de acabar en ANR y kill del proceso.

**Segunda vuelta — `EJNIException: setParameters failed` y encima dejó de
reconocer texto.** Con la cámara ya abriendo bien, `FocusMode :=
ContinuousAutoFocus` (o `Quality := MediumQuality` — no se pudo determinar cuál
de los dos exactamente, algunos dispositivos rechazan uno u otro según su HAL)
lanzaba `RuntimeException: setParameters failed` desde `Camera.setParameters()`.
Como los tres ajustes (`Active`, `FocusMode`, `Quality`) estaban dentro del
**mismo** bloque `try/except`, la excepción saltaba directo al `except` sin
llegar nunca a `TimerLiveScan.Enabled := True` — de ahí que tampoco reconociera
texto: no es que el OCR fallara, es que el temporizador que lo dispara nunca
llegaba a activarse. Fix: cada ajuste (`FocusMode`, `Quality`) en su propio
`try/except` no fatal — si el dispositivo lo rechaza, se ignora y sigue con lo
que traiga por defecto, pero `TimerLiveScan.Enabled := True` se ejecuta siempre
que `Active := True` haya tenido éxito, sin depender de que esos ajustes
"cosméticos" funcionen.

### Parar/reactivar la cámara al pasar la app a segundo plano

Con la cámara ya funcionando en la pestaña "Vivo" de forma estable, quedaba un
hueco: `StartLiveCamera`/`StopLiveCamera` solo reaccionaban a cambios de
pestaña, no a que la app pasara a segundo plano (botón Home, cambiar de app)
mientras esa pestaña seguía activa — la cámara se quedaba abierta de fondo.

Se suscribió `ApplicationEventHandler` a `TApplicationEventMessage`
(`FMX.Platform`, mismo mecanismo `TMessageManager` que ya se usaba para el
resultado de voz) en `FormCreate`, parando la cámara en
`WillBecomeInactive`/`EnteredBackground` y reactivándola en
`BecameActive`/`WillBecomeForeground` solo si la pestaña activa seguía siendo
"Vivo". Primer intento fallido por dos errores de compilación:
- `Undeclared identifier: 'EventType'` — el campo del record
  `TApplicationEventData` se llama `Event`, no `EventType` (comprobado leyendo
  `FMX.Platform.pas` directamente en vez de adivinar por analogía con otras
  APIs de mensajería del proyecto).
- Un `E2250` de `Synchronize` en un método sin relación, más abajo en el mismo
  fichero — efecto cascada del error anterior (el parser se desincroniza tras
  el primer error real y reporta síntomas fantasma después); desapareció solo
  al arreglar el primero, sin tocar nada más.

## Interfaz responsive: los botones no se veían bien en el móvil

Todo el formulario se diseñó sobre un lienzo de 480pt de ancho
(`FormFactor.Width = 480`), y varias filas de controles usaban `Position.X` +
`Size.Width` fijos en vez de `Align`/`Margins` — en un móvil real más estrecho
(~360-400pt), cualquier control cuyo `X + Width` superase ese ancho quedaba
recortado o directamente fuera de pantalla. Síntoma reportado: el botón "invertir
idiomas" (`X=424, Width=48`, pensado para terminar en 472 de 480) desaparecía por
completo en pantallas más estrechas.

**Fix:** sustituir posiciones absolutas por `Align`/`Margins` en las filas
horizontales, para que FMX recalcule contra el ancho real en tiempo de ejecución:
- Fila "Tomar foto"/"Reconocer texto": `Align=Left` (ancho fijo) + `Align=Client`
  (ocupa el resto).
- Fila de idiomas: `ComboLangSource` en `Align=Left`, `ComboLangTarget` en
  `Align=Client`, y **`ButtonSwapLanguages` en `Align=Right`** — así queda siempre
  anclado al borde derecho real de la pantalla, sea cual sea su ancho, en vez de a
  una coordenada fija.
- Botones de ancho completo ("Detectar idioma", "Traducir", "Escuchar traducción"):
  `Align=Top` con márgenes de 8pt en vez de `Position.X=8, Width=464` fijos.

Los memos, labels y pestañas ya usaban `Align=Top`/`Client` desde el principio, así
que no hizo falta tocarlos — el problema estaba solo en las filas con controles en
horizontal.

---

## Herramientas de diagnóstico usadas en toda la sesión
- `adb logcat -c` / `adb logcat -d -v time` sobre un dispositivo físico Xiaomi (MIUI),
  id `82a124b7`, para capturar crashes/ANR reales en el momento exacto de cada acción.
- `adb shell am start / am force-stop / input tap / input keyevent` para automatizar el
  flujo (abrir app, tocar botones, disparar la cámara) sin depender de interacción manual.
- `adb shell dumpsys activity activities | grep mResumedActivity` para esperar de forma
  fiable a que la app recuperase el foco tras un intent externo (cámara), en vez de
  `sleep` fijo o `dumpsys window | grep mCurrentFocus` (este último podía mostrar varias
  líneas obsoletas simultáneas y dar falsos positivos).
- `adb exec-out screencap -p` para capturar el estado visual en cada paso.
- Gradle (usando una distribución 8.13 ya cacheada en `~/.gradle/wrapper/dists`, sin
  necesitar descarga) para resolver de verdad el árbol de dependencias Maven, tanto de
  `play-services-mlkit-text-recognition:19.0.1` como después de
  `com.google.mlkit:translate:17.0.3`, vía dos tareas del mismo proyecto auxiliar
  `gradle-deps` (`collectMlKitLibs` y `collectTranslateLibs`).
- Comparación por script (bash, extrayendo `EnabledSysJars` del `.dproj`) contra los
  ficheros resueltos por Gradle, para detectar duplicados antes de que fallara el dexer
  — incluyendo el caso de variantes con sufijo `-jvm` (`collection`, `annotation`,
  `okio`) que no calzan por nombre exacto pero sí comparten las mismas clases Java.
- `d8` de línea de comandos (del propio SDK de RAD Studio,
  `cmdline-tools\...\bin\d8.bat`) para verificar de forma independiente si un `.jar`
  problemático dexeaba bien fuera del pipeline de RAD Studio, y así aislar bugs propios
  del IDE (ver problema 8) de problemas reales de la librería.
- Compilación por CLI tanto con `Studio\23.0\bin\rsvars.bat` como, tras detectar que el
  usuario compilaba realmente con Delphi 13, con `Studio\37.0\bin\rsvars.bat` — la
  configuración de librerías (`EnabledSysJars`, `AarReference`, etc.) vive en el
  `.dproj` y es independiente de qué instalación de RAD Studio se use para compilar.
