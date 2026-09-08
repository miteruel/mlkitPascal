unit Android.JNI.MLKitOCR;

{ Copyright (C) 2026 Antonio Alcázar Ruiz (MiTeruel) <mrgarciagarcia@gmail.com>
  Part of the PluTony project. Licensed under the GNU GPL v3.0 or later;
  see LICENSE for the full text. }

{ JNI (Androidapi.JNIBridge) declarations for the Java wrapper classes in
  java-wrapper/com/example/mlkitocr/*.java. These declarations do not call
  ML Kit directly - they only describe the shape of our own thin Java
  wrapper, so this unit has no dependency on ML Kit's own Java package
  structure and does not need to change if the ML Kit SDK version changes. }

interface

{$IFDEF ANDROID}

uses
  Androidapi.JNIBridge,
  Androidapi.JNI.JavaTypes,
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
