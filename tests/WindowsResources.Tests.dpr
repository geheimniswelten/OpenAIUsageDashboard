program WindowsResourcesTests;

{$APPTYPE CONSOLE}

uses System.SysUtils, System.Classes, System.IOUtils, Winapi.Windows;

type
  TIconHeader = packed record
    Reserved, Kind, Count: Word;
  end;
  TIconEntry = packed record
    Width, Height, Colors, Reserved: Byte;
    Planes, Bits: Word;
    Size, Offset: Cardinal;
  end;
  TGroupEntry = packed record
    Width, Height, Colors, Reserved: Byte;
    Planes, Bits: Word;
    Size: Cardinal;
    ResourceId: Word;
  end;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then raise Exception.Create(AMessage);
end;

procedure Verify(const AExe, AIcon, AResourceName: string);
var
  Module: HMODULE;
  GroupRes, ImageRes: HRSRC;
  GroupData, ImageData: Pointer;
  IconBytes: TBytes;
  FileHeader, GroupHeader: TIconHeader;
  Entry: TIconEntry;
  GroupEntry: TGroupEntry;
  I, J: Integer;
  Matched: Boolean;
  SmallIcon: HICON;
begin
  IconBytes := TFile.ReadAllBytes(AIcon);
  Check(Length(IconBytes) >= SizeOf(FileHeader), 'Invalid ICO header');
  Move(IconBytes[0], FileHeader, SizeOf(FileHeader));
  Check((FileHeader.Kind = 1) and (FileHeader.Count > 0), 'Expected an icon file');
  Check(Length(IconBytes) >= SizeOf(FileHeader) + FileHeader.Count * SizeOf(Entry), 'Truncated ICO entries');
  Module := LoadLibraryEx(PChar(AExe), 0, LOAD_LIBRARY_AS_DATAFILE);
  Check(Module <> 0, 'Cannot read EXE resources: ' + SysErrorMessage(GetLastError));
  try
    GroupRes := FindResource(Module, PChar(AResourceName), RT_GROUP_ICON);
    Check(GroupRes <> 0, AResourceName + ' missing');
    Check(SizeofResource(Module, GroupRes) >= SizeOf(GroupHeader), 'Invalid icon group');
    GroupData := LockResource(LoadResource(Module, GroupRes));
    Check(GroupData <> nil, 'Cannot load MAINICON');
    Move(GroupData^, GroupHeader, SizeOf(GroupHeader));
    Check(GroupHeader.Count = FileHeader.Count, 'MAINICON image count differs from asset (stale RES?)');
    Check(SizeofResource(Module, GroupRes) >= SizeOf(GroupHeader) + GroupHeader.Count * SizeOf(GroupEntry), 'Truncated group');
    for I := 0 to GroupHeader.Count - 1 do
    begin
      Move(PByte(NativeUInt(GroupData) + NativeUInt(SizeOf(GroupHeader) + I * SizeOf(GroupEntry)))^,
        GroupEntry, SizeOf(GroupEntry));
      ImageRes := FindResource(Module, MakeIntResource(GroupEntry.ResourceId), RT_ICON);
      Check(ImageRes <> 0, 'Icon image resource missing');
      ImageData := LockResource(LoadResource(Module, ImageRes));
      Check(ImageData <> nil, 'Cannot load icon image');
      Matched := False;
      for J := 0 to FileHeader.Count - 1 do
      begin
        Move(IconBytes[SizeOf(FileHeader) + J * SizeOf(Entry)], Entry, SizeOf(Entry));
        if (Entry.Width = GroupEntry.Width) and (Entry.Height = GroupEntry.Height) and
          (Entry.Bits = GroupEntry.Bits) then
        begin
          Check(UInt64(Entry.Offset) + Entry.Size <= UInt64(Length(IconBytes)), 'Invalid image offset');
          Matched := (Entry.Size = GroupEntry.Size) and
            (Entry.Size = SizeofResource(Module, ImageRes)) and
            CompareMem(@IconBytes[Entry.Offset], ImageData, Entry.Size);
          Break;
        end;
      end;
      Check(Matched, 'MAINICON bytes differ from current ICO asset');
    end;
    for I in [16, 32, 48] do
    begin
      SmallIcon := LoadImage(Module, PChar(AResourceName), IMAGE_ICON, I, I, 0);
      Check(SmallIcon <> 0, 'Windows cannot load MAINICON at size ' + IntToStr(I));
      DestroyIcon(SmallIcon);
    end;
    Writeln('WINDOWS_RESOURCES_OK: all ', FileHeader.Count,
      ' ', AResourceName, ' images match the ICO asset; Windows loads 16/32/48px icons.');
  finally
    FreeLibrary(Module);
  end;
end;

begin
  try
    Check(ParamCount in [2, 3], 'Usage: WindowsResources.Tests <EXE> <ICO> [resource name]');
    if ParamCount = 3 then
      Verify(ExpandFileName(ParamStr(1)), ExpandFileName(ParamStr(2)), ParamStr(3))
    else
      Verify(ExpandFileName(ParamStr(1)), ExpandFileName(ParamStr(2)), 'MAINICON');
  except
    on E: Exception do begin Writeln('FAIL: ', E.Message); ExitCode := 1; end;
  end;
end.
