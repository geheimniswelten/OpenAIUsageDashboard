program SecretsTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Win.ComObj,
  Winapi.Windows,
  Winapi.WinRT,
  Dashboard.Secrets in '..\Dashboard.Secrets.pas';

var
  ErrorText: string;
  InitResult: HRESULT;
begin
  try
    InitResult := RoInitialize(RO_INIT_MULTITHREADED);
    if (InitResult < 0) and (InitResult <> RPC_E_CHANGED_MODE) then
      OleCheck(InitResult);
    { Keep the test apartment alive until process teardown.  Delphi's generated
      WinRT imports retain static class-factory interfaces until unit
      finalization, so an earlier RoUninitialize would invalidate those caches. }
    if TSecretStore.ProtectionSelfTest(ErrorText, False) then
      Writeln('SECRET_APPLICATION_LAYER_OK')
    else
    begin
      Writeln('SECRET_PROTECTION_FAILED: ' + ErrorText);
      ExitCode := 1;
    end;
  except
    on E: Exception do
    begin
      Writeln('SECRET_PROTECTION_FAILED: ' + E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
