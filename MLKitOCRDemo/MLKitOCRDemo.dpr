program MLKitOCRDemo;

uses
  System.StartUpCopy,
  FMX.Forms,
  MainForm in 'MainForm.pas' {FormMain},
  Android.JNI.MLKitOCR in 'Android.JNI.MLKitOCR.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
end.

 <uses-sdk android:minSdkVersion="23" android:targetSdkVersion="34" />.
