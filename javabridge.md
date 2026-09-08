# Puente Java ↔ Delphi en RAD Studio Android: el problema y cómo hacerlo bien

Documento centrado específicamente en un punto que causó un fallo real en este
proyecto y que es fácil de dar por hecho mal: **cómo se incluye código Java
propio (un "wrapper" JNI) en un proyecto Delphi/FMX para Android**, y qué pasa
si se hace del modo "obvio" pero incorrecto.

## El problema real que hubo

Este proyecto necesitaba un wrapper Java propio (`MlKitTextRecognizerBridge.java`
+ `OcrCallback.java`) para llamar a ML Kit desde Delphi vía JNI. Los ficheros
se escribieron, se copiaron dentro de la carpeta del proyecto Delphi
(`MLKitOCRDemo\com\example\mlkitocr\*.java`), y se añadieron al proyecto desde
el IDE (Project Manager → *Add To Project…*).

Resultado: **compilaba sin ningún error o aviso**, se desplegaba sin problema,
pero al ejecutar la app y llamar al wrapper:

```
java.lang.EJNIException: java.lang.NoClassDefFoundError: Failed resolution of:
Lcom/example/mlkitocr/MlKitTextRecognizerBridge;
```

La clase Java simplemente **no existía dentro del `.dex` del APK**. El
`README.md` original del proyecto afirmaba (incorrectamente, sin haberlo
verificado de verdad) que *"RAD Studio's Android build pipeline compiles .java
files added to the project with its own javac invocation"*. Es falso.

### Por qué es fácil creerlo (y por qué no es cierto)

Es una suposición razonable porque RAD Studio **sí** sabe hacer cosas con
Java: dexea `.jar`/`.aar`, fusiona manifests, extrae recursos de una AAR... da
la impresión de tener un pipeline Android completo. Pero comprobado contra los
ficheros `.targets` reales de la instalación (`CodeGear.Common.targets`,
`CodeGear.Delphi.Targets`), el único sitio donde RAD Studio invoca `javac`
automáticamente es para los `.java` que **él mismo genera** al usar su
asistente de "Android Service" (`BuildAndroidServiceJarFile`,
`_GenerateJavaSourceFiles` — targets específicos para ese flujo, con nombres
de fichero fijos `$(MSBuildProjectName).java`).

**No existe ningún target genérico que compile un `.java` añadido a mano.**
Si lo añades al proyecto (desde el IDE o editando el `.dproj`), sea cual sea
la carpeta o la plataforma donde lo pongas, por defecto queda registrado en
el `.dproj` como:

```xml
<None Include="com\example\mlkitocr\MlKitTextRecognizerBridge.java"/>
```

`None` es el tipo de ítem de MSBuild que significa literalmente *"este
fichero pertenece al proyecto pero no lo proceses de ninguna forma"*. Ni
`javac`, ni el dexer, ni nada lo tocan. El fichero puede incluso terminar
copiado sin compilar dentro del APK como un asset inerte (en este proyecto
apareció, sin buscarlo, como `assets/internal/MiArchivo.java` — texto plano
dentro del paquete, sin ningún efecto funcional).

## Qué SÍ hace falta: compilarlo tú mismo y añadir el `.jar` resultante

RAD Studio solo sabe empaquetar `.jar`/`.aar` **ya compilados** (`JavaReference`
para un `.jar` suelto, `AarReference` para una `.aar`). El wrapper Java hay
que compilarlo fuera del IDE, exactamente como si RAD Studio no existiera, y
darle el `.jar` resultante como si fuera cualquier otra librería de terceros.

### Paso 1 — Escribe el wrapper en Java plano (no Kotlin)

RAD Studio no tiene integración con `kotlinc` de ninguna forma — ni para
compilar `.java` sueltos (como hemos visto) ni mucho menos `.kt`. Si el
wrapper estuviera en Kotlin, habría que compilarlo con Android
Studio/Gradle aparte y añadir el `.jar` resultante iguialmente — más pasos
para el mismo resultado. Java plano es la opción más simple.

Ejemplo real de este proyecto (`OcrCallback.java`, la interfaz de callback):
```java
package com.example.mlkitocr;

public interface OcrCallback {
    void onSuccess(String text);
    void onError(String message);
}
```

Y el wrapper que la usa (`MlKitTextRecognizerBridge.java`, resumido):
```java
package com.example.mlkitocr;

import com.google.mlkit.vision.text.TextRecognition;
import com.google.mlkit.vision.text.latin.TextRecognizerOptions;
// ...

public class MlKitTextRecognizerBridge {
    private final TextRecognizer recognizer =
            TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS);

    public void recognizeText(final Bitmap bitmap, final OcrCallback callback) {
        InputImage image = InputImage.fromBitmap(bitmap, 0);
        recognizer.process(image)
                .addOnSuccessListener(result -> callback.onSuccess(result.getText()))
                .addOnFailureListener(e -> callback.onError(describe(e)));
    }
}
```

Copia estos ficheros dentro de la carpeta del proyecto Delphi
(`MLKitOCRDemo\com\example\mlkitocr\...`) — así el `.dproj` puede seguir
teniendo la entrada `<None>` apuntando a ellos, útil solo como referencia
visible en el árbol del proyecto (no participa en el build).

### Paso 2 — Prepara el classpath: extrae `classes.jar` de cada AAR que necesites

`javac` no entiende `.aar` directamente — cada `.aar` es un zip con un
`classes.jar` dentro. Extráelo:

```bash
mkdir -p aar_extract/nombre-libreria
unzip -o -q libs-android/nombre-libreria.aar classes.jar -d aar_extract/nombre-libreria
```

Repite por cada AAR cuyas clases use tu wrapper — **incluidas AAR que no
vayan finalmente al proyecto Delphi** porque ya las aporta RAD Studio como
"system jar" (ver `delphikit.md` puntos 2-3): para *compilar* sí hace falta
verlas, aunque para *empaquetar* no haga falta añadirlas.

No adivines qué AAR hace falta: compila, mira el error `cannot find symbol` /
`package ... does not exist` de `javac`, y busca esa clase en las AAR ya
descargadas antes de asumir que falta algo nuevo:
```bash
unzip -l libs-android/candidata.aar | grep NombreDeClaseQueFalta
```

### Paso 3 — Compila con `javac`

```bash
JDK="<ruta a un JDK 17>"
ANDROID_JAR="<SDK>/platforms/android-34/android.jar"   # misma API que usa el proyecto

"$JDK/bin/javac" -g -Xlint:deprecation -source 17 -target 17 -encoding UTF-8 \
  -d out_classes \
  -classpath "$ANDROID_JAR;aar_extract/lib1/classes.jar;aar_extract/lib2/classes.jar;..." \
  MiWrapper.java MiCallback.java
```

Los flags `-g -Xlint:deprecation -source 17 -target 17 -encoding UTF-8` están
copiados literalmente de la propiedad `JavaCCommand` que usa RAD Studio
internamente (en `CodeGear.Common.targets`) para su propio flujo de "Android
Service" — así el `.class` resultante es equivalente en formato al que
generaría el IDE si pudiera.

**Nota de entorno (Windows/Git Bash):** si compilas desde Git Bash, escribe
las rutas del `-classpath` en formato Windows nativo (`C:\...` con `;` como
separador) en vez de rutas POSIX (`/c/...`) — MSYS puede reinterpretar mal el
`;` de un classpath multi-ruta al invocar un `.exe` nativo como `javac.exe`, y
"trocear" el classpath de forma silenciosa.

### Paso 4 — Empaqueta en un `.jar`

```bash
cd out_classes
"$JDK/bin/jar" cf mi-wrapper.jar -C out_classes com
```

### Paso 5 — Añádelo al proyecto Delphi como `JavaReference`

En el `.dproj`, sustituye las entradas `<None>` de los `.java` (o añádelo si
no existían) por una `<JavaReference>` apuntando al `.jar` compilado:

```xml
<JavaReference Include="..\libs-android\wrapper\mi-wrapper.jar">
    <ContainerId>ClassesdexFile</ContainerId>
    <Disabled/>
</JavaReference>
<None Include="com\example\mlkitocr\MiWrapper.java"/>
<None Include="com\example\mlkitocr\MiCallback.java"/>
```

(Los `<None>` de las fuentes `.java` se pueden dejar, solo como referencia
visual en el árbol del proyecto; no hacen nada en el build.)

**Si el proyecto está abierto en el IDE, ciérralo antes de editar el
`.dproj` a mano** — si no, el IDE puede sobrescribir tu cambio con su propia
copia en memoria al guardar/compilar. Cierra → edita → reabre → F9.

### Paso 6 — Verifica que de verdad entró en el `.dex`

```bash
grep -i "mlkitocr\|MiWrapper" Android64\Debug\DexList.txt
```
y, más fiable (`DexList.txt` es solo la lista de *entradas*, no prueba que el
dexeo tuviera éxito — ver el bug de la siguiente sección):
```bash
find Android64\Debug -iname "mi-wrapper-dexed.jar" -exec ls -la {} \;
```
Si el `-dexed.jar` pesa unos pocos KB con contenido real, bien. Si pesa
**22 bytes**, es un dex vacío — sigue leyendo.

### Si hay que tocar el wrapper Java más adelante

Repite los pasos 3–5 (recompilar y regenerar el `.jar`). El `.dproj` apunta a
un `.jar` ya construido — no vuelve a compilar el `.java` solo por sí mismo,
nunca.

## Bug de RAD Studio: `JavaReference` grandes/complejos generan un `.dex` vacío en silencio

Esto no le pasó al wrapper propio de este proyecto (pequeño, pocas clases),
pero sí a una librería de terceros añadida igual como `JavaReference`
(`okhttp-3.0.0.jar`, necesaria para ML Kit Translate). Sin ningún error de
compilación, en tiempo de ejecución:

```
java.lang.NoClassDefFoundError: Failed resolution of: Lokhttp3/MediaType;
```

**Diagnóstico:** el `okhttp-3.0.0-dexed.jar` en `Android64\Debug\` pesaba 22
bytes — un zip vacío. Comprobado con `d8` de línea de comandos (del propio SDK
de RAD Studio) que el mismo `.jar` sí se dexea bien fuera del pipeline del
IDE — es un bug específico de cómo RAD Studio invoca su dexer para
`JavaReference` grandes (muchas clases, muchas advertencias de
"desugaring" por interfaces con métodos por defecto), no un problema de la
librería.

**Regla práctica:** si tu wrapper es pequeño (unas pocas clases, sin
dependencias externas complejas) `JavaReference` normal funciona bien — así
salieron `mlkitocr-wrapper.jar` y `mlkittranslate-wrapper.jar` en este mismo
proyecto. Si el `.jar` es grande o de una librería de terceros con muchas
clases, **empaquétalo como `.aar` mínimo** en vez de `JavaReference` — todas
las `AarReference` de esta sesión (incluidas las grandes) se dexearon bien:

```bash
JARBIN="<jdk>/bin/jar"
WORK="/tmp/mi_lib_aar"; mkdir -p "$WORK"
cp mi-libreria.jar "$WORK/classes.jar"
cat > "$WORK/AndroidManifest.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.ejemplo.wrapper">
    <uses-sdk android:minSdkVersion="21"/>
</manifest>
EOF
cd "$WORK" && "$JARBIN" cf ".../libs-android/mi-libreria-aar.aar" .
```
Y añádelo como `AarReference` normal en vez de `JavaReference`.

## El lado Delphi: cómo se declara y se llama desde Pascal

Compilar y empaquetar el `.jar` es solo la mitad — Delphi necesita saber la
"forma" de esas clases Java para poder llamarlas. Esto se hace con
`Androidapi.JNIBridge`, en una unidad Pascal propia que **no depende de
ninguna librería de ML Kit ni de terceros** — solo describe la forma de tu
propio wrapper, así que no cambia aunque cambies de versión de la librería
subyacente.

### Patrón para una clase Java normal con un método asíncrono

Ejemplo real (`Android.JNI.MLKitOCR.pas`), para el wrapper de arriba:

```pascal
unit Android.JNI.MLKitOCR;

interface

{$IFDEF ANDROID}

uses
  Androidapi.JNIBridge, Androidapi.JNI.JavaTypes,
  Androidapi.JNI.GraphicsContentViewText;

type
  JOcrCallback = interface;
  JMlKitTextRecognizerBridge = interface;

  { com.example.mlkitocr.OcrCallback }
  JOcrCallbackClass = interface(IJavaClass)
    ['{7B2E1A10-7F0A-4C1E-9C2A-0000000000A1}']
  end;

  [JavaSignature('com/example/mlkitocr/OcrCallback')]
  JOcrCallback = interface(IJavaInstance)
    ['{7B2E1A10-7F0A-4C1E-9C2A-0000000000A2}']
    procedure onSuccess(text: JString); cdecl;
    procedure onError(message: JString); cdecl;
  end;
  TJOcrCallback = class(TJavaGenericImport<JOcrCallbackClass, JOcrCallback>) end;

  { com.example.mlkitocr.MlKitTextRecognizerBridge }
  JMlKitTextRecognizerBridgeClass = interface(JObjectClass)
    ['{7B2E1A10-7F0A-4C1E-9C2A-0000000000B1}']
    {class} function init: JMlKitTextRecognizerBridge; cdecl;
  end;

  [JavaSignature('com/example/mlkitocr/MlKitTextRecognizerBridge')]
  JMlKitTextRecognizerBridge = interface(JObject)
    ['{7B2E1A10-7F0A-4C1E-9C2A-0000000000B2}']
    procedure recognizeText(bitmap: JBitmap; callback: JOcrCallback); cdecl;
  end;
  TJMlKitTextRecognizerBridge = class(TJavaGenericImport<JMlKitTextRecognizerBridgeClass, JMlKitTextRecognizerBridge>) end;

{$ENDIF}

implementation

end.
```

Puntos a los que prestar atención:

- **Cada clase Java necesita DOS interfaces Pascal**: una `...Class` (para los
  miembros `static`/el constructor, heredando de `JObjectClass` o
  `IJavaClass`) y una de instancia (para los métodos normales, heredando de
  `JObject` o `IJavaInstance`). El GUID de cada `interface` es arbitrario
  (basta con que sea único dentro del proyecto) — no tiene que coincidir con
  nada del lado Java.
- `[JavaSignature('paquete/completo/NombreClase')]` es lo único que conecta
  la interfaz Pascal con la clase Java real — usa `/` como separador (ruta
  JNI), no `.`.
- `TJXxx = class(TJavaGenericImport<JXxxClass, JXxx>) end;` es la "fábrica" —
  es lo que usas desde el código para llamar a miembros estáticos:
  `TJMlKitTextRecognizerBridge.JavaClass.init`.
- Para una interfaz de **callback** (que Delphi implementa y Java invoca, no
  al revés), hereda de `IJavaInstance` en vez de `JObject` en la versión de
  instancia, y de `IJavaClass` en vez de `JObjectClass` en la de clase — no
  necesitan cuerpo, son solo la "forma" que Java espera poder invocar.

### Implementar un callback en Delphi (`TJavaLocal`) y la regla de "mantenerlo vivo"

Un callback Java→Delphi se implementa como una clase Delphi normal que
declara que implementa la interfaz Java:

```pascal
type
  TOcrResultProc = reference to procedure(const AResult: string);

  TOcrCallbackImpl = class(TJavaLocal, JOcrCallback)
  private
    FOnSuccess: TOcrResultProc;
    FOnError: TOcrResultProc;
  public
    constructor Create(const AOnSuccess, AOnError: TOcrResultProc);
    procedure onSuccess(text: JString); cdecl;
    procedure onError(message: JString); cdecl;
  end;

procedure TOcrCallbackImpl.onSuccess(text: JString);
var
  RecognizedText: string;
begin
  RecognizedText := JStringToString(text);
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(FOnSuccess) then
        FOnSuccess(RecognizedText);
    end);
end;
```

Dos reglas importantes, ambas responsables de bugs reales si se saltan:

1. **`TThread.Queue(nil, ...)` es obligatorio** dentro de `onXxx`: ML Kit (o
   cualquier `Task` de Play Services) invoca el callback en el hilo donde
   termine la tarea asíncrona, que casi nunca es el hilo principal de la UI.
   Tocar controles FMX fuera del hilo principal crashea o corrompe estado.
2. **Guarda la instancia del callback en un campo del formulario, nunca en
   una variable local**:
   ```pascal
   FOcrCallback := TOcrCallbackImpl.Create(OnSuccessProc, OnErrorProc);
   FBridge.recognizeText(ToJBitmap(FCapturedBitmap), FOcrCallback);
   ```
   Si solo viviera en una variable local, su refcount llegaría a cero en
   cuanto el método termine — y como la llamada es asíncrona, ML Kit
   fallaría al intentar invocar el callback más tarde (objeto ya liberado).

### `JString` no es automáticamente un `JCharSequence`

Gotcha genérico que apareció al añadir Text-to-Speech: varios métodos de la
API de Android (`TextToSpeech.speak`, `TextView.setText`...) piden
`JCharSequence`, no `JString` — aunque en Java `String` implementa
`CharSequence`, las interfaces JNI de Delphi no siempre modelan esa relación
de herencia entre sí. Pasar directamente el resultado de `StringToJString`
donde se espera `JCharSequence` da:
```
error E2010: Incompatible types: '...JCharSequence' and '...JString'
```
Conviértelo explícitamente:
```pascal
TJCharSequence.Wrap((StringToJString(MiTexto) as ILocalObject).GetObjectID)
```
Este patrón (`Wrap` + `(... as ILocalObject).GetObjectID`) sirve en general
para reinterpretar una referencia JNI como otra interfaz Delphi que apunta al
mismo objeto Java real, cuando las dos interfaces Pascal no declaran ninguna
relación de herencia entre sí.

### Cuando la clase Java ya es del SDK de Android (no un wrapper propio)

Si lo que necesitas ya es una clase estándar de `android.jar` (por ejemplo
`android.speech.tts.TextToSpeech`, usada para el texto-a-voz de este mismo
proyecto), **no hace falta compilar ni empaquetar nada** — ni `javac` ni
`JavaReference`. Solo escribes la unidad Pascal de declaraciones JNI (mismo
patrón de arriba) apuntando con `JavaSignature` a la clase real del SDK, y
listo: la clase ya existe en el propio `android.jar`/en el runtime del
dispositivo.

```pascal
[JavaSignature('android/speech/tts/TextToSpeech')]
JTextToSpeech = interface(JObject)
  ['{...}']
  function setLanguage(loc: JLocaleTTS): Integer; cdecl;
  function speak(text: JCharSequence; queueMode: Integer; params: JBundle;
    utteranceId: JString): Integer; cdecl;
  // ...
end;
```

Si necesitas una clase auxiliar (como `java.util.Locale` para `setLanguage`)
que sospechas que ya podría estar declarada en otra unidad de Delphi
(`Androidapi.JNI.JavaTypes` y compañía), pero no estás seguro de su forma
exacta, es más seguro declarar tu propia interfaz con un **nombre Pascal
distinto** apuntando al mismo `JavaSignature` real (p. ej. `JLocaleTTS` en vez
de `JLocale`) — evita cualquier choque de identificador duplicado si la otra
declaración sí existe y no coincide exactamente con lo que necesitas.

## Checklist rápido

- [ ] El `.java` propio está compilado con `javac` a `.class` reales y
      empaquetado en un `.jar` — nunca depende de que RAD Studio lo compile
      solo.
- [ ] Ese `.jar` está añadido como `JavaReference` (o como `AarReference` si
      es grande/complejo — ver el bug del dexer) — nunca como `<None>` suelto.
- [ ] Tras F9, el `-dexed.jar` correspondiente en `Android64\Debug\` no pesa
      22 bytes.
- [ ] Cada clase Java usada desde Delphi tiene su interfaz `...Class` (JNI
      estático/constructor) y su interfaz de instancia, con `JavaSignature`
      correcto (con `/`, no `.`).
- [ ] Cualquier callback Java→Delphi (`TJavaLocal`) se guarda en un campo del
      formulario, no en una variable local, y hace `TThread.Queue` antes de
      tocar la UI.
- [ ] Si un método JNI pide `JCharSequence` y tienes un `JString`, está
      convertido con `TJCharSequence.Wrap(...)`.
