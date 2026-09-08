unit Android.JNI.MLKitTranslate;

{ Copyright (C) 2026 Antonio Alcázar Ruiz (MiTeruel) <mrgarciagarcia@gmail.com>
  Part of the PluTony project. Licensed under the GNU GPL v3.0 or later;
  see LICENSE for the full text. }

{ JNI (Androidapi.JNIBridge) declarations for the Java wrapper classes in
  java-wrapper/com/example/mlkitocr/MlKitTranslatorBridge.java and
  TranslateCallback.java. These declarations do not call ML Kit directly -
  they only describe the shape of our own thin Java wrapper, so this unit
  has no dependency on ML Kit's own Java package structure and does not need
  to change if the ML Kit SDK version changes. }

interface

{$IFDEF ANDROID}

uses
  Androidapi.JNIBridge,
  Androidapi.JNI.JavaTypes;

type
  JTranslateCallback = interface;
  JMlKitTranslatorBridge = interface;

  { com.example.mlkitocr.TranslateCallback }

  JTranslateCallbackClass = interface(IJavaClass)
    ['{7B2E1A10-7F0A-4C1E-9C2A-0000000000C1}']
  end;

  [JavaSignature('com/example/mlkitocr/TranslateCallback')]
  JTranslateCallback = interface(IJavaInstance)
    ['{7B2E1A10-7F0A-4C1E-9C2A-0000000000C2}']
    procedure onStatus(message: JString); cdecl;
    procedure onSuccess(translatedText: JString); cdecl;
    procedure onError(message: JString); cdecl;
  end;
  TJTranslateCallback = class(TJavaGenericImport<JTranslateCallbackClass, JTranslateCallback>) end;

  { com.example.mlkitocr.MlKitTranslatorBridge }

  JMlKitTranslatorBridgeClass = interface(JObjectClass)
    ['{7B2E1A10-7F0A-4C1E-9C2A-0000000000D1}']
    {class} function init: JMlKitTranslatorBridge; cdecl;
  end;

  [JavaSignature('com/example/mlkitocr/MlKitTranslatorBridge')]
  JMlKitTranslatorBridge = interface(JObject)
    ['{7B2E1A10-7F0A-4C1E-9C2A-0000000000D2}']
    function getAllLanguages: JString; cdecl;
    procedure translate(sourceLanguage: JString; targetLanguage: JString;
      text: JString; callback: JTranslateCallback); cdecl;
  end;
  TJMlKitTranslatorBridge = class(TJavaGenericImport<JMlKitTranslatorBridgeClass, JMlKitTranslatorBridge>) end;

{$ENDIF}

implementation

end.
