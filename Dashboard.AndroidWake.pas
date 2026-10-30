unit Dashboard.AndroidWake;

interface

type
  TAndroidDisplayWake = class
  public
    class procedure Configure(const AStartHour, AEndHour: Integer); static;
    class procedure Stop; static;
    class procedure RequestPermission; static;
    class function Status: string; static;
    class function Test: string; static;
  end;

implementation

uses
  System.SysUtils,
  Androidapi.JNIBridge,
  Androidapi.JNI.JavaTypes,
  Androidapi.JNI.App,
  Androidapi.JNI.GraphicsContentViewText,
  Androidapi.Helpers;

type
  JDisplayWakeClass = interface(JObjectClass)
    ['{6262E713-534F-4AC0-91EA-DF342595E5B9}']
    {class} procedure configure(activity: JActivity; startHour, endHour: Integer); cdecl;
    {class} procedure stop(context: JContext); cdecl;
    {class} procedure requestExactPermission(activity: JActivity); cdecl;
    {class} function status(context: JContext): JString; cdecl;
    {class} function test(activity: JActivity): JString; cdecl;
  end;

  [JavaSignature('de/hausintern/dashboard/DisplayWake')]
  JDisplayWake = interface(JObject)
    ['{08300D80-7100-4629-B2B0-AAD8C8ACD9F1}']
  end;

  TJDisplayWake = class(TJavaGenericImport<JDisplayWakeClass, JDisplayWake>);

class procedure TAndroidDisplayWake.Configure(const AStartHour, AEndHour: Integer);
begin
  TJDisplayWake.JavaClass.configure(TAndroidHelper.Activity, AStartHour, AEndHour);
end;

class procedure TAndroidDisplayWake.Stop;
begin
  TJDisplayWake.JavaClass.stop(TAndroidHelper.Context);
end;

class procedure TAndroidDisplayWake.RequestPermission;
begin
  TJDisplayWake.JavaClass.requestExactPermission(TAndroidHelper.Activity);
end;

class function TAndroidDisplayWake.Status: string;
begin
  Result := JStringToString(TJDisplayWake.JavaClass.status(TAndroidHelper.Context));
end;

class function TAndroidDisplayWake.Test: string;
begin
  Result := JStringToString(TJDisplayWake.JavaClass.test(TAndroidHelper.Activity));
end;

end.
