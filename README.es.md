# MLKitOCRDemo — Delphi FMX + Google ML Kit en Android (JNI nativo, sin wrappers de terceros)

*[Read in English](README.md)*

App Delphi FireMonkey (RAD Studio 12 Athens / BDS 23.0) para Android que
integra varias capacidades de Google ML Kit / plataforma Android directamente
mediante un puente JNI propio (`Androidapi.JNIBridge`) — **sin Kastri, sin
ninguna librería wrapper de terceros**. La plataforma de destino es
**exclusivamente Android64 (arm64-v8a)**; el proyecto no soporta Android de
32 bits a propósito (varios módulos de Play Services/ML Kit fallan en
silencio ahí).

## Qué hace la app

Cuatro pestañas en un `TTabControl`:

| Pestaña | Qué hace |
|---|---|
| **Foto** | Toma una foto (`TTakePhotoFromCameraAction`) y la pasa por **ML Kit Text Recognition v2** (OCR en el dispositivo). |
| **Texto** | Escribe o pega texto, detecta su idioma con **ML Kit Language Identification** y tradúcelo con **ML Kit Translate** (los modelos por idioma se descargan bajo demanda vía `RemoteModelManager`). |
| **Voz** | Dictado por voz mediante el intent nativo de Android `RECOGNIZE_SPEECH` (`android.speech.action.RECOGNIZE_SPEECH`) — sin dependencia de ML Kit, solo el reconocedor de voz de la plataforma. El texto reconocido es editable y alimenta los controles de traducción. |
| **Vivo** | Vista previa de cámara en directo (`TCameraComponent`) que encadena **OCR → detección de idioma → traducción automáticamente** en cada frame muestreado, con un interruptor opcional de "traducir automáticamente". |

Un botón compartido **"Escuchar traducción"** lee en voz alta el texto
traducido usando la API nativa `TextToSpeech` de Android.

## Por qué está hecho así

- **El OCR usa la variante "unbundled" de Play Services**
  (`com.google.android.gms:play-services-mlkit-text-recognition`), no
  `com.google.mlkit:text-recognition`. El toolchain de Android de RAD Studio
  no ejecuta Gradle ni resuelve dependencias Maven — solo empaqueta ficheros
  `.jar`/`.aar` que añades a mano al proyecto. La variante "unbundled" tiene
  un árbol de dependencias transitivas mucho más pequeño (el modelo en el
  dispositivo lo descarga Play Services en tiempo de ejecución en vez de ir
  empaquetado), lo que hace viable añadirla "a mano". La contrapartida: el
  dispositivo necesita Google Play Services.
- **Translate no tiene variante alojada en Play Services** —
  `com.google.mlkit:translate` es el único artefacto, y empaqueta el motor
  de inferencia TFLite directamente (solo los *datos* del modelo por idioma
  se descargan bajo demanda). Esto trae AAR de TFLite que el OCR por sí solo
  no necesita.
- **Language Identification** trae su propio modelo pequeño en el
  dispositivo como asset dentro del AAR — nada que descargar en tiempo de
  ejecución, funciona sin conexión desde la primera llamada.
- **El dictado por voz y la síntesis de voz usan clases planas del SDK de
  Android** (intent `android.speech.action.RECOGNIZE_SPEECH`,
  `android.speech.tts.TextToSpeech`), declaradas directamente contra el SDK
  estable de Android — no hace falta ningún AAR de ML Kit para ninguna de
  las dos.
- **El wrapper Java es Java plano, no Kotlin.** RAD Studio compila ficheros
  `.java` sueltos añadidos a un proyecto Android con su propio `javac` como
  parte del build; no tiene integración con `kotlinc`. Escribir el wrapper
  en Kotlin habría exigido compilarlo aparte y añadir el `.jar`/`.aar`
  resultante — más pasos para el mismo resultado.
- **La cámara en vivo usa `TCameraComponent`**, activada desde su propio
  hilo (`TThread.CreateAnonymousThread`) en vez del hilo principal — hay un
  bug real en `FMX.Media.Android.pas` por el que `Camera.open()` puede
  colgar el hilo que lo llama si lanza una excepción. `FocusMode`/`Quality`
  se tratan como ajustes opcionales, cada uno en su propio `try/except`,
  nunca compartiendo bloque con `Active := True`.
- **Callbacks Java → Delphi** siguen el patrón estándar de JNIBridge:
  descendientes de `TJavaLocal` (`TOcrCallbackImpl`, `TTranslateCallbackImpl`,
  `TLanguageIdCallbackImpl`) implementan las interfaces Java de callback y se
  mantienen vivos como campos del formulario (no variables locales), porque
  ML Kit los invoca de forma asíncrona después de que el método que los
  disparó ya haya terminado. Las actualizaciones de UI desde esos callbacks
  pasan por `TThread.Queue`.

## Estructura del proyecto

```
mlkit/
├── MLKitOCRDemo/                       Proyecto Delphi (ábrelo con RAD Studio 12 Athens)
│   ├── MLKitOCRDemo.dproj
│   ├── MLKitOCRDemo.dpr
│   ├── MainForm.pas / MainForm.fmx     UI + lógica de la app (las 4 pestañas)
│   ├── Android.JNI.MLKitOCR.pas        Declaraciones JNI — wrapper de OCR
│   ├── Android.JNI.MLKitTranslate.pas  Declaraciones JNI — wrapper de Translate
│   ├── Android.JNI.MLKitLanguageId.pas Declaraciones JNI — wrapper de Language ID
│   ├── Android.JNI.TTS.pas             Declaraciones JNI — TextToSpeech nativo de Android
│   └── AndroidManifest.template.xml    Manifest personalizado (meta-data de ML Kit)
├── java-wrapper/
│   └── com/example/mlkitocr/           Wrappers Java finos (OCR, Translate, Language ID + callbacks)
├── gradle-deps/                        Proyecto Gradle auxiliar — resuelve dependencias Maven, NUNCA se ejecuta desde Delphi
│   └── build.gradle                    3 tareas: collectMlKitLibs / collectTranslateLibs / collectLanguageIdLibs
├── libs-android*/                      Generado por gradle-deps — no está versionado, ver abajo
├── delphikit.md                        Guía paso a paso para añadir/tocar librerías de ML Kit
├── javabridge.md                       Por qué RAD Studio no compila los .java del proyecto, y el patrón JNI usado
└── sesion.md                           Log cronológico de cada error real encontrado y su causa raíz
```

`libs-android/`, `libs-android-translate/`, `libs-android-languageid/` y
`lib/` **no están versionados** (ver `.gitignore`) — son ficheros binarios
`.jar`/`.aar` que regenera `gradle-deps` (ver abajo). Lo mismo para las
carpetas de salida de compilación `Android/`/`Android64/` bajo
`MLKitOCRDemo/` y las carpetas de respaldo de RAD Studio
`__history/`/`__recovery/`.

## Configurar las dependencias de ML Kit (paso a paso)

RAD Studio 12 Athens no ejecuta Gradle ni resuelve Maven — solo empaqueta
ficheros `.jar`/`.aar` que tú añades al proyecto. Por eso:

1. **Resuelve las dependencias transitivas reales con Gradle de verdad**
   (una vez, o cada vez que cambies de versión):
   ```
   cd gradle-deps
   gradle collectMlKitLibs
   gradle collectTranslateLibs
   gradle collectLanguageIdLibs
   ```
   Requiere un JDK y Gradle (no forman parte de RAD Studio). Esto aplana
   cada `.jar`/`.aar` en `../libs-android/`, `../libs-android-translate/` y
   `../libs-android-languageid/`. No copies a mano números de versión de
   documentación vieja — vuelve a ejecutar el script, porque las versiones
   de Play Services cambian con frecuencia.
2. **Añade cada `.jar`/`.aar` de esas carpetas al proyecto Delphi.** Con el
   proyecto abierto en RAD Studio: Project Manager → Target Platforms → nodo
   **Android64** → *Add To Project…* → selecciona todos los ficheros
   generados. RAD Studio extrae clases, recursos y fragmentos de manifest de
   cada `.aar` automáticamente y los fusiona en el manifest final.
3. **Añade el wrapper Java al proyecto.** Copia `java-wrapper/com` dentro de
   `MLKitOCRDemo/` (para que quede
   `MLKitOCRDemo/com/example/mlkitocr/*.java`) y usa *Add To Project…* con
   cada fichero `.java` — RAD Studio los compila con su propio `javac` como
   parte del build de Android.
4. **`AndroidManifest.template.xml`** ya incluye la entrada de meta-data
   `com.google.mlkit.vision.DEPENDENCIES` (para que Play Services empiece a
   descargar el modelo de OCR nada más instalar la app). Si tu proyecto ya
   tiene otra plantilla, no la sobrescribas a ciegas: fusiona solo ese
   bloque.
5. **⚠️ Nunca añadas** `emoji2-*`, `emoji2-views-helper-*` ni
   `lifecycle-process-*` — provocan `NoClassDefFoundError:
   androidx.startup.R$string` al arrancar.

Consulta `delphikit.md` para el recorrido completo y detallado (filtrado de
duplicados, extracción de `.so`/`assets/` de un AAR, checklist final).

## Configurar el proyecto en RAD Studio

1. Abre `MLKitOCRDemo/MLKitOCRDemo.dproj` con RAD Studio 12 Athens.
2. **Plataforma de destino: solo Android64.** El proyecto se compila y
   verifica exclusivamente contra **Android de 64 bits (arm64-v8a)** — no
   apuntes a Android de 32 bits, varios módulos de Play Services/ML Kit
   fallan en silencio ahí.
3. **minSdkVersion 23 / targetSdkVersion 35** — verificado contra la
   documentación oficial de ML Kit y configurado en la info de versión del
   proyecto.
4. **Permisos**: se necesitan `CAMERA` (foto y pestaña Vivo) e `INTERNET`
   (descarga de modelos de Translate/OCR). El `.dproj` también activa
   `ACCESS_COARSE_LOCATION`/`ACCESS_FINE_LOCATION`, que el conjunto actual de
   4 pestañas no usa realmente — resto de la plantilla por defecto de RAD
   Studio para Android; revisa *Project Options > Application > Uses
   Permissions* y recórtalo si no lo necesitas.
5. El nombre de paquete se configura en *Project Options > Application >
   Version Info* — cámbialo ahí para tu propia build.
6. Sigue la sección anterior para añadir las AAR/JAR de ML Kit y el wrapper
   Java.

## Claves de firma

Este repositorio **no incluye ningún keystore**. `MLKitOCRDemo.dproj`
todavía referencia nombres de fichero de un keystore de debug local
(`PF_KeyStoreDebug`) de la máquina donde se desarrolló — esos ficheros nunca
salieron de esa máquina y están excluidos del control de versiones. Genera
tu propio keystore de debug/release (`keytool -genkeypair …` o desde la UI
de firma de RAD Studio en *Project Options > Application > Security*) y
apunta las propiedades `PF_KeyStore*` correspondientes a él en tu máquina;
no subas el `.keystore`/`.jks` resultante (ya cubierto por `.gitignore`).

## Compilar y desplegar

1. Conecta un dispositivo Android64 físico con depuración USB activada, o
   arranca un emulador **con Google Play Services** (una imagen de emulador
   sin Google APIs no funciona con la variante de OCR vía Play Services
   usada aquí).
2. Selecciona la plataforma **Android64** y el dispositivo de destino en RAD
   Studio.
3. *Run > Run* (F9). RAD Studio compila, empaqueta el APK (con las AAR/JAR y
   el manifest ya configurados) y lo despliega.
4. En el dispositivo: concede los permisos de cámara/micrófono cuando se
   soliciten, prueba cada pestaña.

Compilación por línea de comandos (solo compila el Pascal — **no** dexea,
empaqueta ni despliega; usa F9 en el IDE para un build completo real):
```
"C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat"
msbuild MLKitOCRDemo.dproj /p:config=Debug /p:platform=Android64 /t:Build
```

## Limitaciones conocidas

- **Requiere Google Play Services** en el dispositivo/emulador (la variante
  de OCR vía Play Services + ML Kit Translate/Language ID dependen de que
  esté presente y actualizado).
- **La primera ejecución necesita internet** para que Play Services/ML Kit
  descarguen los modelos de OCR y traducción (el meta-data del manifest
  adelanta la descarga de OCR al momento de instalar, pero los modelos de
  Translate por idioma se siguen descargando en el primer uso de ese par de
  idiomas).
- Esto es una demo, no una app de producción: no gestiona rotación EXIF de
  la imagen, no reconoce alfabetos no latinos por defecto (haría falta
  añadir `text-recognition-chinese`/`-japanese`/`-korean`/`-devanagari`), ni
  guarda las fotos en la galería.

## Más documentación

- `delphikit.md` — guía prescriptiva paso a paso para añadir/tocar
  librerías de ML Kit (Gradle auxiliar, filtrado de duplicados,
  AAR/JavaReference, extracción de `.so`/`assets/` de un AAR, checklist
  final).
- `javabridge.md` — por qué RAD Studio no compila los `.java` del proyecto,
  y el patrón JNI completo en el lado Delphi.
- `sesion.md` — log cronológico de cada error real encontrado y su causa
  raíz.
- `prompt.md` — versión condensada en "reglas no negociables" + flujo paso
  a paso, pensada para arrancar rápido en una sesión nueva.

## Licencia

Copyright (C) 2026 Antonio Alcázar Ruiz (MiTeruel) — mrgarciagarcia@gmail.com

Este programa es software libre: puedes redistribuirlo y/o modificarlo bajo
los términos de la **GNU General Public License v3.0** (o, a tu elección,
cualquier versión posterior), publicada por la Free Software Foundation.
Cualquier app o trabajo derivado construido sobre este código que se
distribuya o publique a terceros debe licenciarse también bajo GPL-3.0 y
publicar su código fuente. Consulta [LICENSE](LICENSE) para el texto
completo.

## Referencias

- [ML Kit Text Recognition v2 — Android](https://developers.google.com/ml-kit/vision/text-recognition/v2/android)
- [ML Kit Translation — Android](https://developers.google.com/ml-kit/language/translation/android)
- [ML Kit Language Identification — Android](https://developers.google.com/ml-kit/language/identification/android)
- Documentación de RAD Studio 12 Athens (docwiki.embarcadero.com) sobre el
  manifest personalizado de Android
- Fuentes de la instalación de RAD Studio 12 Athens usadas para verificar
  firmas exactas de API: `FMX.Helpers.Android.pas`,
  `FMX.Media.Android.pas`, `System.Permissions.pas`,
  `Androidapi.JNIBridge.pas`
