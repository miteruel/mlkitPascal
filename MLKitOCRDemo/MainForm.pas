unit MainForm;

{ Copyright (C) 2026 Antonio Alcázar Ruiz (MiTeruel) <mrgarciagarcia@gmail.com>
  Part of the PluTony project. Licensed under the GNU GPL v3.0 or later;
  see LICENSE for the full text. }

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes,
  System.Variants, System.Permissions,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  FMX.Controls.Presentation, FMX.StdCtrls, FMX.Memo, FMX.Memo.Types,
  FMX.ScrollBox, FMX.Objects, FMX.Layouts, FMX.ListBox, FMX.TabControl,
  FMX.MediaLibrary, FMX.MediaLibrary.Actions, FMX.Media,
  FMX.ActnList
{$IFDEF ANDROID}
    , Androidapi.JNIBridge, Androidapi.JNI.JavaTypes,
  Androidapi.JNI.GraphicsContentViewText, Androidapi.JNI.App,
  Androidapi.Helpers,
  FMX.Helpers.Android, Android.JNI.MLKitOCR, Android.JNI.MLKitTranslate,
  Android.JNI.TTS, Android.JNI.MLKitLanguageId, System.Actions, FMX.StdActns,
  System.Messaging, FMX.Platform
{$ENDIF}
    ;

type
  TFormMain = class(TForm)
    TabControlMain: TTabControl;
    TabItemFoto: TTabItem;
    LayoutPhotoButtons: TLayout;
    ButtonTakePhoto: TButton;
    ButtonRecognize: TButton;
    ImagePreview: TImage;
    MemoResult: TMemo;
    TabItemTexto: TTabItem;
    LabelTextoHint: TLabel;
    MemoManualText: TMemo;
    TabItemVoz: TTabItem;
    ButtonStartVoice: TButton;
    LabelVozHint: TLabel;
    MemoVoiceResult: TMemo;
    TabItemVivo: TTabItem;
    ImageLiveCamera: TImage;
    CheckBoxAutoTranslate: TCheckBox;
    LabelLiveLanguage: TLabel;
    MemoLiveText: TMemo;
    CameraComponentLive: TCameraComponent;
    TimerLiveScan: TTimer;
    TimerLiveTranslateSlow: TTimer;
    LabelStatus: TLabel;
    ActionList1: TActionList;
    TakePhotoFromCameraAction1: TTakePhotoFromCameraAction;
    LayoutTranslate: TLayout;
    ComboLangSource: TComboBox;
    ComboLangTarget: TComboBox;
    ButtonSwapLanguages: TButton;
    ButtonDetectLanguage: TButton;
    ButtonTranslate: TButton;
    ButtonSpeak: TButton;
    MemoTranslated: TMemo;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure ButtonTakePhotoClick(Sender: TObject);
    procedure ButtonRecognizeClick(Sender: TObject);
    procedure TakePhotoFromCameraAction1DidFinishTaking(Image: TBitmap);
    procedure ButtonSwapLanguagesClick(Sender: TObject);
    procedure ButtonTranslateClick(Sender: TObject);
    procedure TabControlMainChange(Sender: TObject);
    procedure MemoManualTextChangeTracking(Sender: TObject);
    procedure MemoVoiceResultChangeTracking(Sender: TObject);
    procedure ButtonStartVoiceClick(Sender: TObject);
    procedure ButtonSpeakClick(Sender: TObject);
    procedure ButtonDetectLanguageClick(Sender: TObject);
    procedure CameraComponentLiveSampleBufferReady(Sender: TObject;
      const ATime: TMediaTime);
    procedure TimerLiveScanTimer(Sender: TObject);
    procedure TimerLiveTranslateSlowTimer(Sender: TObject);
  private
    FCapturedBitmap: TBitmap;
    FLanguageCodes: TArray<string>;
{$IFDEF ANDROID}
    FBridge: JMlKitTextRecognizerBridge;
    FOcrCallback: JOcrCallback;
    FTranslatorBridge: JMlKitTranslatorBridge;
    FTranslateCallback: JTranslateCallback;
    FTextToSpeech: JTextToSpeech;
    FTtsInitListener: JTextToSpeech_OnInitListener;
    FTtsReady: Boolean;
    FPendingSpeakText: string;
    FPendingSpeakLang: string;
    FLanguageIdBridge: JMlKitLanguageIdBridge;
    FLanguageIdCallback: JLanguageIdCallback;
    FLiveBusy: Boolean;
    FLiveOcrCallback: JOcrCallback;
    FLiveLanguageIdCallback: JLanguageIdCallback;
    FLiveTranslateCallback: JTranslateCallback;
    FLiveTranslateSlowShown: Boolean;
{$ENDIF}
    procedure SetBusy(ABusy: Boolean; const AStatusText: string = '');
    procedure ShowError(const AMessage: string);
    procedure RequestCameraPermission(const AOnGranted: TProc);
    procedure PopulateLanguages;
    function GetActiveSourceText: string;
    procedure UpdateTranslateButtonState;
    function LanguageDisplayName(const ACode: string): string;
    procedure StartLiveCamera;
    procedure StopLiveCamera;
{$IFDEF ANDROID}
    function ToJBitmap(const ABitmap: TBitmap): JBitmap;
    procedure HandleActivityResult(const Sender: TObject; const M: TMessage);
    procedure ApplicationEventHandler(const Sender: TObject; const M: TMessage);
    procedure SpeakPendingText;
    procedure DetectLiveLanguage(const AText: string);
    procedure TranslateLiveText(const AText, ASourceLanguage: string);
{$ENDIF}
  public
    { Public declarations }
  end;

var
  FormMain: TFormMain;

implementation

{$R *.fmx}

const
  CameraPermission = 'android.permission.CAMERA';
  { Arbitrary but must stay unique among any startActivityForResult calls this
    app makes, so HandleActivityResult can tell them apart - there is only
    this one for now. }
  VoiceRecognitionRequestCode = 4321;

{$IFDEF ANDROID}

type
  TOcrResultProc = reference to procedure(const AResult: string);

  { Implements the Java-side OcrCallback interface (java-wrapper/com/example/
    mlkitocr/OcrCallback.java) as a local JNI object so ML Kit's asynchronous
    Task can call back into Delphi. Instances must be kept alive (referenced
    by a field, not just a local variable) for as long as the corresponding
    ML Kit call is in flight - see TFormMain.FOcrCallback. }
  TOcrCallbackImpl = class(TJavaLocal, JOcrCallback)
  private
    FOnSuccess: TOcrResultProc;
    FOnError: TOcrResultProc;
  public
    constructor Create(const AOnSuccess, AOnError: TOcrResultProc);
    procedure onSuccess(text: JString); cdecl;
    procedure onError(message: JString); cdecl;
  end;

constructor TOcrCallbackImpl.Create(const AOnSuccess, AOnError: TOcrResultProc);
begin
  inherited Create;
  FOnSuccess := AOnSuccess;
  FOnError := AOnError;
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

procedure TOcrCallbackImpl.onError(message: JString);
var
  ErrorText: string;
begin
  ErrorText := JStringToString(message);
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(FOnError) then
        FOnError(ErrorText);
    end);
end;

type
  { Implements the Java-side TranslateCallback interface (java-wrapper/com/
    example/mlkitocr/TranslateCallback.java) as a local JNI object. Same
    keep-alive rule as TOcrCallbackImpl - see TFormMain.FTranslateCallback. }
  TTranslateCallbackImpl = class(TJavaLocal, JTranslateCallback)
  private
    FOnStatus: TOcrResultProc;
    FOnSuccess: TOcrResultProc;
    FOnError: TOcrResultProc;
  public
    constructor Create(const AOnStatus, AOnSuccess, AOnError: TOcrResultProc);
    procedure onStatus(message: JString); cdecl;
    procedure onSuccess(translatedText: JString); cdecl;
    procedure onError(message: JString); cdecl;
  end;

constructor TTranslateCallbackImpl.Create(const AOnStatus, AOnSuccess,
  AOnError: TOcrResultProc);
begin
  inherited Create;
  FOnStatus := AOnStatus;
  FOnSuccess := AOnSuccess;
  FOnError := AOnError;
end;

procedure TTranslateCallbackImpl.onStatus(message: JString);
var
  StatusText: string;
begin
  StatusText := JStringToString(message);
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(FOnStatus) then
        FOnStatus(StatusText);
    end);
end;

procedure TTranslateCallbackImpl.onSuccess(translatedText: JString);
var
  ResultText: string;
begin
  ResultText := JStringToString(translatedText);
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(FOnSuccess) then
        FOnSuccess(ResultText);
    end);
end;

procedure TTranslateCallbackImpl.onError(message: JString);
var
  ErrorText: string;
begin
  ErrorText := JStringToString(message);
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(FOnError) then
        FOnError(ErrorText);
    end);
end;

type
  { Implements the Java-side LanguageIdCallback interface (java-wrapper/com/
    example/mlkitocr/LanguageIdCallback.java) as a local JNI object. Same
    keep-alive rule as TOcrCallbackImpl - see TFormMain.FLanguageIdCallback. }
  TLanguageIdCallbackImpl = class(TJavaLocal, JLanguageIdCallback)
  private
    FOnSuccess: TOcrResultProc;
    FOnError: TOcrResultProc;
  public
    constructor Create(const AOnSuccess, AOnError: TOcrResultProc);
    procedure onSuccess(languageCode: JString); cdecl;
    procedure onError(message: JString); cdecl;
  end;

constructor TLanguageIdCallbackImpl.Create(const AOnSuccess, AOnError: TOcrResultProc);
begin
  inherited Create;
  FOnSuccess := AOnSuccess;
  FOnError := AOnError;
end;

procedure TLanguageIdCallbackImpl.onSuccess(languageCode: JString);
var
  DetectedCode: string;
begin
  DetectedCode := JStringToString(languageCode);
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(FOnSuccess) then
        FOnSuccess(DetectedCode);
    end);
end;

procedure TLanguageIdCallbackImpl.onError(message: JString);
var
  ErrorText: string;
begin
  ErrorText := JStringToString(message);
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(FOnError) then
        FOnError(ErrorText);
    end);
end;

type
  TTtsInitProc = reference to procedure(AStatus: Integer);

  { Implements android.speech.tts.TextToSpeech.OnInitListener as a local JNI
    object. Engine creation is asynchronous - onInit fires once (or never, if
    it fails outright) some time after TJTextToSpeech.JavaClass.init returns. }
  TTtsInitListenerImpl = class(TJavaLocal, JTextToSpeech_OnInitListener)
  private
    FOnInit: TTtsInitProc;
  public
    constructor Create(const AOnInit: TTtsInitProc);
    procedure onInit(status: Integer); cdecl;
  end;

constructor TTtsInitListenerImpl.Create(const AOnInit: TTtsInitProc);
begin
  inherited Create;
  FOnInit := AOnInit;
end;

procedure TTtsInitListenerImpl.onInit(status: Integer);
begin
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(FOnInit) then
        FOnInit(status);
    end);
end;
{$ENDIF}

procedure TFormMain.FormCreate(Sender: TObject);
begin
  FCapturedBitmap := TBitmap.Create;
  ButtonRecognize.Enabled := False;
  ButtonTranslate.Enabled := False;
  ButtonSpeak.Enabled := False;
  MemoResult.Lines.text := '';
  MemoManualText.Lines.text := '';
  MemoVoiceResult.Lines.text := '';
  MemoTranslated.Lines.text := '';
{$IFDEF ANDROID}
  TMessageManager.DefaultManager.SubscribeToMessage(TMessageResultNotification,
    HandleActivityResult);
  { Stop the live camera when the app leaves the foreground and restart it
    (if the "Vivo" tab is still the active one) when it comes back - a
    backgrounded app has no business holding the camera open (battery,
    fighting other apps for it), and on some devices the OS reclaims it while
    backgrounded, which would otherwise surface as another camera error the
    next time a frame is requested. }
  TMessageManager.DefaultManager.SubscribeToMessage(TApplicationEventMessage,
    ApplicationEventHandler);
{$ENDIF}
  PopulateLanguages;
  SetBusy(False);
end;

procedure TFormMain.FormDestroy(Sender: TObject);
begin
  StopLiveCamera;
{$IFDEF ANDROID}
  { Release the native TTS engine explicitly rather than relying on process
    teardown - shutdown() frees resources shared with the OS speech service. }
  if Assigned(FTextToSpeech) then
    FTextToSpeech.shutdown;
{$ENDIF}
end;

{ Which memo "Traducir"/"Escuchar" should read from depends on which of the
  input tabs is active; TabItemFoto is the implicit default (MemoResult)
  since it's the only one left once Texto, Voz and Vivo are ruled out. }
function TFormMain.GetActiveSourceText: string;
begin
  if TabControlMain.ActiveTab = TabItemTexto then
    Result := MemoManualText.Lines.Text
  else if TabControlMain.ActiveTab = TabItemVoz then
    Result := MemoVoiceResult.Lines.Text
  else if TabControlMain.ActiveTab = TabItemVivo then
    Result := MemoLiveText.Lines.Text
  else
    Result := MemoResult.Lines.Text;
end;

procedure TFormMain.UpdateTranslateButtonState;
begin
  ButtonTranslate.Enabled := not GetActiveSourceText.Trim.IsEmpty;
end;

procedure TFormMain.TabControlMainChange(Sender: TObject);
begin
  UpdateTranslateButtonState;
  if TabControlMain.ActiveTab = TabItemVivo then
    StartLiveCamera
  else
    StopLiveCamera;
end;

{ Looks up a "code" ML Kit understands (e.g. "es") against the language list
  already loaded by PopulateLanguages, so the live tab can show a readable
  name ("Espa"#241"ol (es)") instead of a bare code. Falls back to the code
  itself if the list hasn't loaded yet or doesn't contain it. }
function TFormMain.LanguageDisplayName(const ACode: string): string;
var
  i: Integer;
begin
  Result := ACode;
  for i := 0 to High(FLanguageCodes) do
    if FLanguageCodes[i] = ACode then
    begin
      Result := ComboLangSource.Items[i] + ' (' + ACode + ')';
      Break;
    end;
end;

procedure TFormMain.StartLiveCamera;
begin
  MemoLiveText.Lines.text := '';
  LabelLiveLanguage.text := 'Apunta con la cámara a un texto...';
  FLiveBusy := False;
  RequestCameraPermission(
    procedure
    begin
      { CameraComponentLive.Active := True blocks synchronously waiting for
        FMX's own internal camera thread to finish opening the device. If
        Camera.open() throws - confirmed once in the wild via logcat, a
        transient crash of Android's own camera service ("Camera service
        died!", DEAD_OBJECT) - FMX's wait event never gets signaled (see
        FMX.Media.Android.pas, TAndroidVideoCaptureDevice.GetCamera/
        OpenCamera: the SetEvent call sits right after Camera.open(), so an
        exception there skips it) and whichever thread called Active := True
        hangs forever. Running it on our own throwaway thread means that if
        it does hang again, it hangs a disposable background thread instead
        of the UI thread - the app stays responsive instead of ANRing and
        getting killed by the OS. }
      TThread.CreateAnonymousThread(
        procedure
        begin
          try
            CameraComponentLive.Active := True;
          except
            on E: Exception do
            begin
              TThread.Queue(nil,
                procedure
                begin
                  ShowError('No se pudo abrir la cámara: ' + E.message);
                end);
              Exit;
            end;
          end;

          { FocusMode/Quality are best-effort tuning, not required for the
            feature to work at all: some devices/HALs reject
            FOCUS_MODE_CONTINUOUS_PICTURE, or the mid-sized preview setting
            MediumQuality picks, with "setParameters failed" even though
            Active := True (Camera.open) itself succeeded - confirmed in the
            wild. Never let either failure block TimerLiveScan below: a
            worse focus/resolution beats no live recognition at all. }
          try
            { Default is single-shot autofocus (focuses once and stays
              there); with a shaky hand the text plane keeps moving, so
              switch to continuous autofocus (Android's
              FOCUS_MODE_CONTINUOUS_PICTURE) which keeps refocusing as the
              scene changes. Must be set after Active := True - it needs the
              native camera already open (Camera.getParameters). }
            CameraComponentLive.FocusMode := TFocusMode.ContinuousAutoFocus;
          except
            // Ignore - keep whatever focus mode the device defaulted to.
          end;
          try
            { Full sensor resolution is overkill for OCR and slows down every
              recognizeText() call in TimerLiveScanTimer; MediumQuality picks
              a mid-sized capture setting instead (same "needs the device
              already open" requirement as FocusMode above). }
            CameraComponentLive.Quality := TVideoCaptureQuality.MediumQuality;
          except
            // Ignore - keep whatever capture size the device defaulted to.
          end;

          TThread.Queue(nil,
            procedure
            begin
              TimerLiveScan.Enabled := True;
            end);
        end).Start;
    end);
end;

procedure TFormMain.StopLiveCamera;
begin
  TimerLiveScan.Enabled := False;
  { Also cancel the "still downloading" indicator: firing later, after the
    user has already left this tab (or backgrounded the app), would call
    SetBusy(True, ...) out of context - disabling buttons on whatever screen
    they're looking at now for a scan that no longer matters. }
  TimerLiveTranslateSlow.Enabled := False;
  try
    { Same defensive stance as StartLiveCamera: the underlying camera JNI
      calls have already thrown twice this session for reasons outside our
      control (a dead camera service, a rejected parameter) - there's no
      reason to assume teardown is exception-proof either, and this can run
      from FormDestroy/ApplicationEventHandler where an unhandled exception
      would be worse than just leaving the camera in whatever state it's in. }
    CameraComponentLive.Active := False;
  except
    // Ignore - nothing useful to do about a failed teardown here.
  end;
  FLiveBusy := False;
end;

procedure TFormMain.MemoManualTextChangeTracking(Sender: TObject);
begin
  UpdateTranslateButtonState;
end;

procedure TFormMain.MemoVoiceResultChangeTracking(Sender: TObject);
begin
  UpdateTranslateButtonState;
end;

procedure TFormMain.PopulateLanguages;
{$IFDEF ANDROID}
var
  Bridge: JMlKitTranslatorBridge;
  LanguagesCsv: string;
  Entry: string;
  Entries: TArray<string>;
  SourceDefaultIndex, TargetDefaultIndex, i: Integer;
{$ENDIF}
begin
{$IFDEF ANDROID}
  try
    Bridge := TJMlKitTranslatorBridge.JavaClass.init;
    LanguagesCsv := JStringToString(Bridge.getAllLanguages);
  except
    on E: Exception do
    begin
      ShowError('No se pudo cargar la lista de idiomas: ' + E.message);
      Exit;
    end;
  end;

  Entries := LanguagesCsv.Split([';']);
  SetLength(FLanguageCodes, Length(Entries));
  ComboLangSource.Items.BeginUpdate;
  ComboLangTarget.Items.BeginUpdate;
  try
    ComboLangSource.Items.Clear;
    ComboLangTarget.Items.Clear;
    SourceDefaultIndex := -1;
    TargetDefaultIndex := -1;
    for i := 0 to High(Entries) do
    begin
      Entry := Entries[i];
      FLanguageCodes[i] := Copy(Entry, 1, Pos('|', Entry) - 1);
      ComboLangSource.Items.Add(Copy(Entry, Pos('|', Entry) + 1, MaxInt));
      ComboLangTarget.Items.Add(Copy(Entry, Pos('|', Entry) + 1, MaxInt));
      if FLanguageCodes[i] = 'en' then
        SourceDefaultIndex := i;
      if FLanguageCodes[i] = 'es' then
        TargetDefaultIndex := i;
    end;
  finally
    ComboLangSource.Items.EndUpdate;
    ComboLangTarget.Items.EndUpdate;
  end;

  if SourceDefaultIndex >= 0 then
    ComboLangSource.ItemIndex := SourceDefaultIndex
  else if ComboLangSource.Items.Count > 0 then
    ComboLangSource.ItemIndex := 0;

  if TargetDefaultIndex >= 0 then
    ComboLangTarget.ItemIndex := TargetDefaultIndex
  else if ComboLangTarget.Items.Count > 0 then
    ComboLangTarget.ItemIndex := 0;
{$ENDIF}
end;

procedure TFormMain.SetBusy(ABusy: Boolean; const AStatusText: string);
begin
  ButtonTakePhoto.Enabled := not ABusy;
  ButtonRecognize.Enabled := (not ABusy) and (not FCapturedBitmap.IsEmpty);
  ButtonStartVoice.Enabled := not ABusy;
  ButtonTranslate.Enabled := (not ABusy) and
    (not GetActiveSourceText.Trim.IsEmpty);
  ButtonSpeak.Enabled := (not ABusy) and
    (not MemoTranslated.Lines.text.Trim.IsEmpty);
  LabelStatus.TextSettings.FontColor := TAlphaColorRec.Dimgray;
  LabelStatus.text := AStatusText;
end;

procedure TFormMain.ShowError(const AMessage: string);
begin
  LabelStatus.TextSettings.FontColor := TAlphaColorRec.Firebrick;
  LabelStatus.text := AMessage;
end;

{$IFDEF ANDROID}

function TFormMain.ToJBitmap(const ABitmap: TBitmap): JBitmap;
begin
  Result := TJBitmap.JavaClass.createBitmap(ABitmap.Width, ABitmap.Height,
    TJBitmap_Config.JavaClass.ARGB_8888);
  if not BitmapToJBitmap(ABitmap, Result) then
    raise Exception.Create('No se pudo convertir el bitmap para ML Kit.');
end;
{$ENDIF}

procedure TFormMain.RequestCameraPermission(const AOnGranted: TProc);
begin
  PermissionsService.RequestPermissions([CameraPermission],
    procedure(const APermissions: TClassicStringDynArray;
      const AGrantResults: TClassicPermissionStatusDynArray)
    begin
      if (Length(AGrantResults) > 0) and
        (AGrantResults[0] = TPermissionStatus.Granted) then
      begin
        if Assigned(AOnGranted) then
          AOnGranted();
      end
      else
        ShowError('Se necesita permiso de cámara para esta función.');
    end);
end;

procedure TFormMain.ButtonTakePhotoClick(Sender: TObject);
begin
  RequestCameraPermission(
    procedure
    begin
      SetBusy(False);
      TakePhotoFromCameraAction1.Execute;
    end);
end;

procedure TFormMain.TakePhotoFromCameraAction1DidFinishTaking(Image: TBitmap);
begin
  FCapturedBitmap.Assign(Image);
  ImagePreview.Bitmap.Assign(Image);
  MemoResult.Lines.text := '';
  MemoTranslated.Lines.text := '';
  UpdateTranslateButtonState;
  SetBusy(False, 'Foto capturada. Pulsa "Reconocer texto".');
end;

procedure TFormMain.ButtonRecognizeClick(Sender: TObject);
{$IFDEF ANDROID}
var
  OnSuccessProc, OnErrorProc: TOcrResultProc;
{$ENDIF}
begin
  if FCapturedBitmap.IsEmpty then
  begin
    ShowError('Primero toma una foto.');
    Exit;
  end;

{$IFDEF ANDROID}
  OnSuccessProc := procedure(const AText: string)
    begin
      SetBusy(False);
      MemoTranslated.Lines.text := '';
      if AText.Trim.IsEmpty then
        MemoResult.Lines.text := '(No se detectó texto en la imagen)'
      else
        MemoResult.Lines.text := AText;
      UpdateTranslateButtonState;
    end;
  OnErrorProc := procedure(const AError: string)
    begin
      SetBusy(False);
      ShowError('Error de ML Kit: ' + AError);
    end;
  try
    SetBusy(True, 'Reconociendo texto...');

    if not Assigned(FBridge) then
      FBridge := TJMlKitTextRecognizerBridge.JavaClass.init;

    { Keep a strong reference to the callback in a field: ML Kit's Task
      runs asynchronously, and if this were only a local variable its
      refcount would drop to zero as soon as this method returns. }
    FOcrCallback := TOcrCallbackImpl.Create(OnSuccessProc, OnErrorProc);

    FBridge.recognizeText(ToJBitmap(FCapturedBitmap), FOcrCallback);
  except
    on E: Exception do
    begin
      SetBusy(False);
      ShowError('Error inesperado: ' + E.message);
    end;
  end;
{$ELSE}
  ShowError(
    'El reconocimiento de texto con ML Kit solo está disponible en Android.');
{$ENDIF}
end;

procedure TFormMain.ButtonSwapLanguagesClick(Sender: TObject);
var
  SourceIndex, TargetIndex: Integer;
begin
  SourceIndex := ComboLangSource.ItemIndex;
  TargetIndex := ComboLangTarget.ItemIndex;
  ComboLangSource.ItemIndex := TargetIndex;
  ComboLangTarget.ItemIndex := SourceIndex;
end;

procedure TFormMain.ButtonDetectLanguageClick(Sender: TObject);
{$IFDEF ANDROID}
var
  TextToAnalyze: string;
  DetectedIndex: Integer;
  OnSuccessProc, OnErrorProc: TOcrResultProc;
{$ENDIF}
begin
  if GetActiveSourceText.Trim.IsEmpty then
  begin
    ShowError('Escribe, reconoce o dicta primero un texto.');
    Exit;
  end;

{$IFDEF ANDROID}
  TextToAnalyze := GetActiveSourceText;

  OnSuccessProc := procedure(const ALanguageCode: string)
    var
      i: Integer;
    begin
      SetBusy(False);
      { ML Kit reports "und" when it cannot reliably tell the language apart
        (text too short, ambiguous, mixed languages, etc.). }
      if ALanguageCode = 'und' then
      begin
        ShowError('No se pudo determinar el idioma del texto.');
        Exit;
      end;
      DetectedIndex := -1;
      for i := 0 to High(FLanguageCodes) do
        if FLanguageCodes[i] = ALanguageCode then
        begin
          DetectedIndex := i;
          Break;
        end;
      if DetectedIndex < 0 then
        ShowError('Idioma detectado ("' + ALanguageCode +
          '") no está en la lista de Translate.')
      else
      begin
        ComboLangSource.ItemIndex := DetectedIndex;
        SetBusy(False, 'Idioma detectado: ' + ComboLangSource.Items[DetectedIndex]);
      end;
    end;
  OnErrorProc := procedure(const AError: string)
    begin
      SetBusy(False);
      ShowError('Error detectando idioma: ' + AError);
    end;

  try
    SetBusy(True, 'Detectando idioma...');

    if not Assigned(FLanguageIdBridge) then
      FLanguageIdBridge := TJMlKitLanguageIdBridge.JavaClass.init;

    { Same keep-alive rule as FOcrCallback - see its comment in
      ButtonRecognizeClick. }
    FLanguageIdCallback := TLanguageIdCallbackImpl.Create(OnSuccessProc, OnErrorProc);

    FLanguageIdBridge.identifyLanguage(StringToJString(TextToAnalyze),
      FLanguageIdCallback);
  except
    on E: Exception do
    begin
      SetBusy(False);
      ShowError('Error inesperado: ' + E.message);
    end;
  end;
{$ELSE}
  ShowError(
    'La detección de idioma con ML Kit solo está disponible en Android.');
{$ENDIF}
end;

procedure TFormMain.ButtonTranslateClick(Sender: TObject);
{$IFDEF ANDROID}
var
  SourceLanguage, TargetLanguage, TextToTranslate: string;
  OnStatusProc, OnSuccessProc, OnErrorProc: TOcrResultProc;
{$ENDIF}
begin
  if GetActiveSourceText.Trim.IsEmpty then
  begin
    ShowError('Escribe, reconoce o dicta primero un texto.');
    Exit;
  end;
  if (ComboLangSource.ItemIndex < 0) or (ComboLangTarget.ItemIndex < 0) then
  begin
    ShowError('Selecciona idioma de origen y de destino.');
    Exit;
  end;

{$IFDEF ANDROID}
  SourceLanguage := FLanguageCodes[ComboLangSource.ItemIndex];
  TargetLanguage := FLanguageCodes[ComboLangTarget.ItemIndex];
  TextToTranslate := GetActiveSourceText;

  OnStatusProc := procedure(const AStatus: string)
    begin
      SetBusy(True, AStatus);
    end;
  OnSuccessProc := procedure(const AResult: string)
    begin
      SetBusy(False);
      MemoTranslated.Lines.text := AResult;
      ButtonSpeak.Enabled := not AResult.Trim.IsEmpty;
    end;
  OnErrorProc := procedure(const AError: string)
    begin
      SetBusy(False);
      ShowError('Error de Translate: ' + AError);
    end;

  try
    SetBusy(True, 'Preparando traducción...');

    if not Assigned(FTranslatorBridge) then
      FTranslatorBridge := TJMlKitTranslatorBridge.JavaClass.init;

    { Same keep-alive rule as FOcrCallback - see its comment in
      ButtonRecognizeClick. }
    FTranslateCallback := TTranslateCallbackImpl.Create(OnStatusProc,
      OnSuccessProc, OnErrorProc);

    FTranslatorBridge.translate(StringToJString(SourceLanguage),
      StringToJString(TargetLanguage), StringToJString(TextToTranslate),
      FTranslateCallback);
  except
    on E: Exception do
    begin
      SetBusy(False);
      ShowError('Error inesperado: ' + E.message);
    end;
  end;
{$ELSE}
  ShowError('La traducción con ML Kit solo está disponible en Android.');
{$ENDIF}
end;

procedure TFormMain.ButtonStartVoiceClick(Sender: TObject);
{$IFDEF ANDROID}
var
  VoiceIntent: JIntent;
{$ENDIF}
begin
{$IFDEF ANDROID}
  try
    VoiceIntent := TJIntent.JavaClass.init(
      StringToJString('android.speech.action.RECOGNIZE_SPEECH'));
    VoiceIntent.putExtra(StringToJString('android.speech.extra.LANGUAGE_MODEL'),
      StringToJString('free_form'));
    TAndroidHelper.Activity.startActivityForResult(VoiceIntent,
      VoiceRecognitionRequestCode);
    SetBusy(True, 'Escuchando...');
  except
    on E: Exception do
      ShowError('No se pudo iniciar el reconocimiento de voz: ' + E.message);
  end;
{$ELSE}
  ShowError('El reconocimiento de voz solo está disponible en Android.');
{$ENDIF}
end;

{$IFDEF ANDROID}
procedure TFormMain.HandleActivityResult(const Sender: TObject;
  const M: TMessage);
var
  Notification: TMessageResultNotification;
  ResultsList: JArrayList;
  RecognizedText: string;
  ErrorText: string;
begin
  if not (M is TMessageResultNotification) then
    Exit;
  Notification := TMessageResultNotification(M);
  if Notification.RequestCode <> VoiceRecognitionRequestCode then
    Exit;

  { Read everything out of the message synchronously, right here, instead of
    inside the TThread.Queue callback below: Notification/M is only
    guaranteed valid for the duration of this handler (whoever dispatched it
    owns its lifetime), so capturing the JNI object itself into a deferred
    closure risks reading it after it has been released. Only plain
    Delphi strings/booleans cross that boundary. }
  RecognizedText := '';
  ErrorText := '';
  if Notification.ResultCode <> TJActivity.JavaClass.RESULT_OK then
    ErrorText := 'No se reconoció ningún audio.'
  else if Notification.Value = nil then
    ErrorText := 'No se recibió resultado de voz.'
  else
  begin
    ResultsList := Notification.Value.getStringArrayListExtra(
      StringToJString('android.speech.extra.RESULTS'));
    if (ResultsList = nil) or (ResultsList.size = 0) then
      ErrorText := 'No se detectó ningún texto por voz.'
    else
      RecognizedText := JStringToString(TJString.Wrap(
        (ResultsList.get(0) as ILocalObject).GetObjectID));
  end;

  TThread.Queue(nil,
    procedure
    begin
      if not ErrorText.IsEmpty then
      begin
        SetBusy(False);
        ShowError(ErrorText);
        Exit;
      end;
      MemoVoiceResult.Lines.text := RecognizedText;
      UpdateTranslateButtonState;
      SetBusy(False, 'Voz reconocida. Pulsa "Traducir".');
    end);
end;

procedure TFormMain.ApplicationEventHandler(const Sender: TObject;
  const M: TMessage);
begin
  case TApplicationEventMessage(M).Value.Event of
    TApplicationEvent.WillBecomeInactive, TApplicationEvent.EnteredBackground:
      StopLiveCamera;
    TApplicationEvent.BecameActive, TApplicationEvent.WillBecomeForeground:
      if TabControlMain.ActiveTab = TabItemVivo then
        StartLiveCamera;
  end;
end;
{$ENDIF}

procedure TFormMain.ButtonSpeakClick(Sender: TObject);
begin
  if MemoTranslated.Lines.text.Trim.IsEmpty then
  begin
    ShowError('Primero traduce un texto.');
    Exit;
  end;
  if ComboLangTarget.ItemIndex < 0 then
  begin
    ShowError('Selecciona el idioma de destino.');
    Exit;
  end;

{$IFDEF ANDROID}
  FPendingSpeakText := MemoTranslated.Lines.text;
  FPendingSpeakLang := FLanguageCodes[ComboLangTarget.ItemIndex];

  if FTtsReady then
    SpeakPendingText
  else if not Assigned(FTextToSpeech) then
  begin
    try
      SetBusy(True, 'Iniciando motor de voz...');
      FTtsInitListener := TTtsInitListenerImpl.Create(
        procedure(AStatus: Integer)
        begin
          SetBusy(False);
          if AStatus = TTS_SUCCESS then
          begin
            FTtsReady := True;
            SpeakPendingText;
          end
          else
            ShowError('No se pudo iniciar el motor de voz del dispositivo.');
        end);
      FTextToSpeech := TJTextToSpeech.JavaClass.init(TAndroidHelper.Context,
        FTtsInitListener);
    except
      on E: Exception do
      begin
        SetBusy(False);
        ShowError('Error inesperado: ' + E.message);
      end;
    end;
  end;
{$ELSE}
  ShowError('La lectura en voz alta solo está disponible en Android.');
{$ENDIF}
end;

{$IFDEF ANDROID}
procedure TFormMain.SpeakPendingText;
var
  LangResult: Integer;
begin
  if FPendingSpeakText.Trim.IsEmpty then
    Exit;
  try
    LangResult := FTextToSpeech.setLanguage(
      TJLocaleTTS.JavaClass.init(StringToJString(FPendingSpeakLang)));
    if (LangResult = TTS_LANG_MISSING_DATA) or
      (LangResult = TTS_LANG_NOT_SUPPORTED) then
    begin
      ShowError('El motor de voz del dispositivo no soporta el idioma "' +
        FPendingSpeakLang +
        '". Prueba a instalar otro motor TTS (p.ej. RHVoice o eSpeak-NG) ' +
        'desde Play Store, o elige otro idioma.');
      Exit;
    end;
    FTextToSpeech.speak(TJCharSequence.Wrap(
      (StringToJString(FPendingSpeakText) as ILocalObject).GetObjectID),
      TTS_QUEUE_FLUSH, nil, StringToJString('mlkitocrdemo_utt'));
  except
    on E: Exception do
      ShowError('Error inesperado al reproducir voz: ' + E.message);
  end;
end;
{$ENDIF}

{ Fires for every camera frame (possibly off the main thread depending on
  platform, hence the Synchronize) - just paints it into the preview image.
  The actual OCR pass is throttled separately by TimerLiveScan, since running
  ML Kit on every single frame would flood it with overlapping requests. }
procedure TFormMain.CameraComponentLiveSampleBufferReady(Sender: TObject;
  const ATime: TMediaTime);
begin
  TThread.Synchronize(nil,
    procedure
    begin
      CameraComponentLive.SampleBufferToBitmap(ImageLiveCamera.Bitmap, True);
    end);
end;

procedure TFormMain.TimerLiveScanTimer(Sender: TObject);
{$IFDEF ANDROID}
var
  FrameCopy: TBitmap;
  OnSuccessProc, OnErrorProc: TOcrResultProc;
{$ENDIF}
begin
{$IFDEF ANDROID}
  { Skip this tick if the previous frame's OCR (+ language id) is still in
    flight, or there is no frame yet - never queue up overlapping requests. }
  if FLiveBusy or ImageLiveCamera.Bitmap.IsEmpty then
    Exit;

  FrameCopy := TBitmap.Create;
  FrameCopy.Assign(ImageLiveCamera.Bitmap);

  OnSuccessProc := procedure(const AText: string)
    begin
      FrameCopy.Free;
      if AText.Trim.IsEmpty then
      begin
        MemoLiveText.Lines.text := '';
        LabelLiveLanguage.text := 'Apunta con la cámara a un texto...';
        FLiveBusy := False;
        UpdateTranslateButtonState;
        Exit;
      end;
      MemoLiveText.Lines.text := AText;
      UpdateTranslateButtonState;
      DetectLiveLanguage(AText);
    end;
  OnErrorProc := procedure(const AError: string)
    begin
      FrameCopy.Free;
      FLiveBusy := False;
      { Unlike "no text found" (silent - the normal case while the camera
        isn't pointed at anything readable), an actual OCR failure is rare
        and worth surfacing - otherwise the tab just looks permanently stuck
        with zero clue why. }
      ShowError('Error de ML Kit: ' + AError);
    end;

  try
    FLiveBusy := True;
    if not Assigned(FBridge) then
      FBridge := TJMlKitTextRecognizerBridge.JavaClass.init;

    { Same keep-alive rule as FOcrCallback - see its comment in
      ButtonRecognizeClick. Uses its own field (not FOcrCallback) so a manual
      "Reconocer texto" tap on the Foto tab can never race with this one. }
    FLiveOcrCallback := TOcrCallbackImpl.Create(OnSuccessProc, OnErrorProc);
    FBridge.recognizeText(ToJBitmap(FrameCopy), FLiveOcrCallback);
  except
    on E: Exception do
    begin
      FrameCopy.Free;
      FLiveBusy := False;
      ShowError('Error inesperado: ' + E.message);
    end;
  end;
{$ENDIF}
end;

{$IFDEF ANDROID}
procedure TFormMain.DetectLiveLanguage(const AText: string);
var
  OnSuccessProc, OnErrorProc: TOcrResultProc;
begin
  { FLiveBusy stays True across this whole OCR -> detect -> (optional)
    translate chain, set back to False only at whichever step ends up being
    the last one - see TimerLiveScanTimer's comment on why it must not be
    cleared early. }
  OnSuccessProc := procedure(const ALanguageCode: string)
    var
      i, DetectedIndex: Integer;
    begin
      if ALanguageCode = 'und' then
      begin
        LabelLiveLanguage.text := 'Idioma: no determinado';
        FLiveBusy := False;
        Exit;
      end;
      LabelLiveLanguage.text := 'Idioma: ' + LanguageDisplayName(ALanguageCode);

      DetectedIndex := -1;
      for i := 0 to High(FLanguageCodes) do
        if FLanguageCodes[i] = ALanguageCode then
        begin
          DetectedIndex := i;
          Break;
        end;
      if DetectedIndex >= 0 then
        ComboLangSource.ItemIndex := DetectedIndex;

      if CheckBoxAutoTranslate.IsChecked and (DetectedIndex >= 0) and
        (ComboLangTarget.ItemIndex >= 0) then
        TranslateLiveText(AText, ALanguageCode)
      else
        FLiveBusy := False;
    end;
  OnErrorProc := procedure(const AError: string)
    begin
      FLiveBusy := False;
      ShowError('Error detectando idioma: ' + AError);
    end;

  try
    if not Assigned(FLanguageIdBridge) then
      FLanguageIdBridge := TJMlKitLanguageIdBridge.JavaClass.init;

    FLiveLanguageIdCallback := TLanguageIdCallbackImpl.Create(OnSuccessProc, OnErrorProc);
    FLanguageIdBridge.identifyLanguage(StringToJString(AText), FLiveLanguageIdCallback);
  except
    on E: Exception do
    begin
      FLiveBusy := False;
      ShowError('Error inesperado: ' + E.message);
    end;
  end;
end;

{ Only called from DetectLiveLanguage once a source language was both
  detected and matched in FLanguageCodes - ASourceLanguage is that code, not
  whatever ComboLangSource.ItemIndex happens to hold (avoids a race if the
  user changes it while this frame's chain is still in flight). }
procedure TFormMain.TranslateLiveText(const AText, ASourceLanguage: string);
var
  TargetLanguage: string;
  OnStatusProc, OnSuccessProc, OnErrorProc: TOcrResultProc;
begin
  TargetLanguage := FLanguageCodes[ComboLangTarget.ItemIndex];

  OnStatusProc := procedure(const AStatus: string)
    begin
      { Intentionally not surfaced anywhere - showing "Descargando
        modelo..."/"Traduciendo..." on every 1.5s tick would just flicker.
        TimerLiveTranslateSlow covers the one case worth telling the user
        about (see below). }
    end;
  OnSuccessProc := procedure(const AResult: string)
    begin
      TimerLiveTranslateSlow.Enabled := False;
      { Only touch the status label if the slow-download notice actually
        fired for this call - the common case (model already cached) never
        shows anything, so it shouldn't clear anything either. }
      if FLiveTranslateSlowShown then
        SetBusy(False);
      MemoTranslated.Lines.text := AResult;
      ButtonSpeak.Enabled := not AResult.Trim.IsEmpty;
      FLiveBusy := False;
    end;
  OnErrorProc := procedure(const AError: string)
    begin
      TimerLiveTranslateSlow.Enabled := False;
      FLiveBusy := False;
      ShowError('Error de Translate: ' + AError);
    end;

  try
    if not Assigned(FTranslatorBridge) then
      FTranslatorBridge := TJMlKitTranslatorBridge.JavaClass.init;

    FLiveTranslateCallback := TTranslateCallbackImpl.Create(OnStatusProc,
      OnSuccessProc, OnErrorProc);
    { Arms the "still working" notice for this call - see
      TimerLiveTranslateSlowTimer. Cancelled above the moment the real
      result (success or error) comes back, so it only ever fires when the
      call is genuinely slow (a first-time model download), never on the
      common fast/cached path. }
    FLiveTranslateSlowShown := False;
    TimerLiveTranslateSlow.Enabled := True;
    FTranslatorBridge.translate(StringToJString(ASourceLanguage),
      StringToJString(TargetLanguage), StringToJString(AText),
      FLiveTranslateCallback);
  except
    on E: Exception do
    begin
      TimerLiveTranslateSlow.Enabled := False;
      FLiveBusy := False;
      ShowError('Error inesperado: ' + E.message);
    end;
  end;
end;
{$ENDIF}

procedure TFormMain.TimerLiveTranslateSlowTimer(Sender: TObject);
begin
  { One-shot: only meant to fire once per slow call, immediately turned back
    off rather than left ticking every 1.5s. }
  TimerLiveTranslateSlow.Enabled := False;
{$IFDEF ANDROID}
  FLiveTranslateSlowShown := True;
{$ENDIF}
  SetBusy(True, 'Descargando modelo de idioma (primera vez, puede tardar)...');
end;

end.
