unit Android.JNI.MLKitLanguageId;

{ Copyright (C) 2026 Antonio Alcázar Ruiz (MiTeruel) <mrgarciagarcia@gmail.com>
  Part of the PluTony project. Licensed under the GNU GPL v3.0 or later;
  see LICENSE for the full text. }

{ JNI (Androidapi.JNIBridge) declarations for the Java wrapper classes in
  java-wrapper/com/example/mlkitocr/MlKitLanguageIdBridge.java and
  LanguageIdCallback.java. These declarations do not call ML Kit directly -
  they only describe the shape of our own thin Java wrapper, so this unit
  has no dependency on ML Kit's own Java package structure and does not need
  to change if the ML Kit SDK version changes. }

interface

{$IFDEF ANDROID}

uses
  Androidapi.JNIBridge,
  Androidapi.JNI.JavaTypes;

type
  JLanguageIdCallback = interface;
  JMlKitLanguageIdBridge = interface;

  { com.example.mlkitocr.LanguageIdCallback }

  JLanguageIdCallbackClass = interface(IJavaClass)
    ['{7B2E1A10-7F0A-4C1E-9C2A-0000000000E1}']
  end;

  [JavaSignature('com/example/mlkitocr/LanguageIdCallback')]
  JLanguageIdCallback = interface(IJavaInstance)
    ['{7B2E1A10-7F0A-4C1E-9C2A-0000000000E2}']
    procedure onSuccess(languageCode: JString); cdecl;
    procedure onError(message: JString); cdecl;
  end;
  TJLanguageIdCallback = class(TJavaGenericImport<JLanguageIdCallbackClass, JLanguageIdCallback>) end;

  { com.example.mlkitocr.MlKitLanguageIdBridge }

  JMlKitLanguageIdBridgeClass = interface(JObjectClass)
    ['{7B2E1A10-7F0A-4C1E-9C2A-0000000000F1}']
    {class} function init: JMlKitLanguageIdBridge; cdecl;
  end;

  [JavaSignature('com/example/mlkitocr/MlKitLanguageIdBridge')]
  JMlKitLanguageIdBridge = interface(JObject)
    ['{7B2E1A10-7F0A-4C1E-9C2A-0000000000F2}']
    procedure identifyLanguage(text: JString; callback: JLanguageIdCallback); cdecl;
  end;
  TJMlKitLanguageIdBridge = class(TJavaGenericImport<JMlKitLanguageIdBridgeClass, JMlKitLanguageIdBridge>) end;

{$ENDIF}

implementation

end.
