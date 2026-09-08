unit Android.JNI.TTS;

{ Copyright (C) 2026 Antonio Alcázar Ruiz (MiTeruel) <mrgarciagarcia@gmail.com>
  Part of the PluTony project. Licensed under the GNU GPL v3.0 or later;
  see LICENSE for the full text. }

{ JNI (Androidapi.JNIBridge) declarations for android.speech.tts.TextToSpeech
  and java.util.Locale. Written directly against the stable Android SDK
  (not a third-party library, no wrapper .jar needed) - the same pattern used
  elsewhere in this project for calling Android SDK classes straight from
  Delphi (e.g. JBitmap, JIntent).

  Locale is redeclared here under a distinct name (JLocaleTTS) instead of
  reusing whatever `java.util.Locale` binding might already exist elsewhere,
  to avoid any duplicate-identifier clash - only the JavaSignature attribute
  needs to match the real Java class, the Pascal identifier name is free. }

interface

{$IFDEF ANDROID}

uses
  Androidapi.JNIBridge,
  Androidapi.JNI.JavaTypes,
  Androidapi.JNI.GraphicsContentViewText,
  Androidapi.JNI.Os;

type
  JLocaleTTS = interface;
  JTextToSpeech = interface;
  JTextToSpeech_OnInitListener = interface;

  { java.util.Locale }

  JLocaleTTSClass = interface(JObjectClass)
    ['{7B2E1A10-7F0A-4C1E-9C2A-0000000000D5}']
    {class} function init(language: JString): JLocaleTTS; cdecl;
  end;

  [JavaSignature('java/util/Locale')]
  JLocaleTTS = interface(JObject)
    ['{7B2E1A10-7F0A-4C1E-9C2A-0000000000D6}']
  end;
  TJLocaleTTS = class(TJavaGenericImport<JLocaleTTSClass, JLocaleTTS>) end;

  { android.speech.tts.TextToSpeech$OnInitListener }

  JTextToSpeech_OnInitListenerClass = interface(IJavaClass)
    ['{7B2E1A10-7F0A-4C1E-9C2A-0000000000E1}']
  end;

  [JavaSignature('android/speech/tts/TextToSpeech$OnInitListener')]
  JTextToSpeech_OnInitListener = interface(IJavaInstance)
    ['{7B2E1A10-7F0A-4C1E-9C2A-0000000000E2}']
    procedure onInit(status: Integer); cdecl;
  end;
  TJTextToSpeech_OnInitListener = class(TJavaGenericImport<JTextToSpeech_OnInitListenerClass, JTextToSpeech_OnInitListener>) end;

  { android.speech.tts.TextToSpeech }

  JTextToSpeechClass = interface(JObjectClass)
    ['{7B2E1A10-7F0A-4C1E-9C2A-0000000000F1}']
    {class} function init(context: JContext;
      listener: JTextToSpeech_OnInitListener): JTextToSpeech; cdecl;
  end;

  [JavaSignature('android/speech/tts/TextToSpeech')]
  JTextToSpeech = interface(JObject)
    ['{7B2E1A10-7F0A-4C1E-9C2A-0000000000F2}']
    function setLanguage(loc: JLocaleTTS): Integer; cdecl;
    function speak(text: JCharSequence; queueMode: Integer; params: JBundle;
      utteranceId: JString): Integer; cdecl;
    function isSpeaking: Boolean; cdecl;
    function stop: Integer; cdecl;
    procedure shutdown; cdecl;
  end;
  TJTextToSpeech = class(TJavaGenericImport<JTextToSpeechClass, JTextToSpeech>) end;

const
  { Stable, unchanged since API level 1 - hardcoded instead of read via JNI
    static-field access to keep this unit simple. }
  TTS_SUCCESS = 0;
  TTS_LANG_MISSING_DATA = -1;
  TTS_LANG_NOT_SUPPORTED = -2;
  TTS_QUEUE_FLUSH = 0;

{$ENDIF}

implementation

end.
