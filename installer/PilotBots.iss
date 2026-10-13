; Instalador do Pilot Bots para R1Delta
; Instala os arquivos da mod em qualquer versao do cliente (pastas app-* do launcher ou outra pasta escolhida).
; A tier0.dll oficial nao e substituida: o codigo nativo dos bots fica em pilotbots.dll e o pbinject
; acrescenta uma entrada de importacao na tier0.dll para o Windows carregar a pilotbots.dll junto.
; Faz backup dos arquivos originais (inclusive a tier0.dll) e restaura tudo ao desinstalar.

#define AppName "Pilot Bots para R1Delta"
#define AppVer "2.0.0"

[Setup]
AppId={{6B0C0E55-4F55-4C57-9D55-7B1C5B07B075}
AppName={#AppName}
AppVersion={#AppVer}
AppPublisher=lcvb1997
DefaultDirName={localappdata}\PilotBotsR1Delta
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=no
PrivilegesRequired=lowest
OutputDir=..\release
OutputBaseFilename=PilotBots_R1Delta_Setup_{#AppVer}
Compression=lzma2/ultra
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#AppName}
CloseApplications=no

[Languages]
Name: "ptbr"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "zh"; MessagesFile: "ChineseSimplified.isl"

[CustomMessages]
ptbr.PickTitle=Versoes do cliente
ptbr.PickSub=Escolha em quais pastas do R1Delta instalar o Pilot Bots.
ptbr.PickHelp=Marque as versoes do cliente que devem receber a mod. Se o launcher atualizar o jogo para uma versao nova, basta rodar este instalador de novo.
ptbr.AddFolder=Adicionar pasta...
ptbr.AddPrompt=Selecione a pasta do cliente R1Delta (a que contem a pasta "r1delta"):
ptbr.NotAClient=Essa pasta nao parece um cliente R1Delta (nao tem a subpasta "r1delta").
ptbr.NoneFound=Nenhum cliente R1Delta encontrado automaticamente. Use "Adicionar pasta..." para indicar onde ele esta.
ptbr.NoneSelected=Marque pelo menos uma pasta.
ptbr.CopyFail=Nao foi possivel copiar o arquivo abaixo. Feche o jogo e o launcher do R1Delta e tente de novo.
ptbr.VersionWarn=Esta pasta e a versao %1, mas os scripts da mod foram feitos para a 2.14.x. Pode dar incompatibilidade. Instalar mesmo assim?
ptbr.ModdedDll=A tier0.dll desta pasta e a versao modificada antiga do Pilot Bots (instalada a mao, sem backup):%n%1%n%nReinstale o R1Delta pelo launcher (ou restaure a tier0.dll original) e rode este instalador de novo. Esta pasta foi pulada.
ptbr.InjectFail=Nao foi possivel preparar a tier0.dll desta pasta (erro %2). Feche o jogo e o launcher e tente de novo:%n%1
ptbr.Done=Pilot Bots instalado em %1 pasta(s).
en.PickTitle=Client versions
en.PickSub=Choose which R1Delta folders get Pilot Bots.
en.PickHelp=Tick the client versions that should receive the mod. If the launcher updates the game to a new version, just run this installer again.
en.AddFolder=Add folder...
en.AddPrompt=Select the R1Delta client folder (the one containing the "r1delta" folder):
en.NotAClient=That folder does not look like an R1Delta client (no "r1delta" subfolder).
en.NoneFound=No R1Delta client found automatically. Use "Add folder..." to point to it.
en.NoneSelected=Tick at least one folder.
en.CopyFail=Could not copy the file below. Close the game and the R1Delta launcher and try again.
en.VersionWarn=This folder is version %1 but the mod scripts were made for 2.14.x. They may be incompatible. Install anyway?
en.ModdedDll=The tier0.dll in this folder is the old modified Pilot Bots build (copied by hand, no backup):%n%1%n%nReinstall R1Delta from the launcher (or restore the original tier0.dll) and run this installer again. This folder was skipped.
en.InjectFail=Could not prepare the tier0.dll in this folder (error %2). Close the game and the launcher and try again:%n%1
en.Done=Pilot Bots installed into %1 folder(s).

ru.PickTitle=Версии клиента
ru.PickSub=Выберите папки R1Delta, в которые нужно установить Pilot Bots.
ru.PickHelp=Отметьте версии клиента, которые должны получить мод. Если лаунчер обновит игру до новой версии, просто запустите этот установщик снова.
ru.AddFolder=Добавить папку...
ru.AddPrompt=Выберите папку клиента R1Delta (ту, где находится папка "r1delta"):
ru.NotAClient=Эта папка не похожа на клиент R1Delta (нет подпапки "r1delta").
ru.NoneFound=Клиент R1Delta не найден автоматически. Нажмите "Добавить папку...", чтобы указать его расположение.
ru.NoneSelected=Отметьте хотя бы одну папку.
ru.CopyFail=Не удалось скопировать файл ниже. Закройте игру и лаунчер R1Delta и повторите попытку.
ru.VersionWarn=Эта папка — версия %1, а скрипты мода сделаны для 2.14.x. Возможна несовместимость. Всё равно установить?
ru.ModdedDll=tier0.dll в этой папке — старая изменённая сборка Pilot Bots (скопирована вручную, без резервной копии):%n%1%n%nПереустановите R1Delta через лаунчер (или верните оригинальную tier0.dll) и запустите установщик снова. Эта папка пропущена.
ru.InjectFail=Не удалось подготовить tier0.dll в этой папке (ошибка %2). Закройте игру и лаунчер и повторите попытку:%n%1
ru.Done=Pilot Bots установлен в папок: %1.
zh.PickTitle=客户端版本
zh.PickSub=选择要安装 Pilot Bots 的 R1Delta 文件夹。
zh.PickHelp=勾选需要安装此模组的客户端版本。如果启动器将游戏更新到新版本,只需再次运行此安装程序。
zh.AddFolder=添加文件夹...
zh.AddPrompt=请选择 R1Delta 客户端文件夹(包含 "r1delta" 子文件夹的那个):
zh.NotAClient=该文件夹不像是 R1Delta 客户端(没有 "r1delta" 子文件夹)。
zh.NoneFound=未自动找到 R1Delta 客户端。请使用"添加文件夹..."指定其位置。
zh.NoneSelected=请至少勾选一个文件夹。
zh.CopyFail=无法复制下面的文件。请关闭游戏和 R1Delta 启动器后重试。
zh.VersionWarn=此文件夹版本为 %1,但模组脚本是为 2.14.x 制作的。可能不兼容。仍要安装吗?
zh.ModdedDll=此文件夹中的 tier0.dll 是旧版修改过的 Pilot Bots(手动复制,没有备份):%n%1%n%n请通过启动器重新安装 R1Delta(或恢复原始 tier0.dll),然后再次运行此安装程序。已跳过此文件夹。
zh.InjectFail=无法处理此文件夹中的 tier0.dll(错误 %2)。请关闭游戏和启动器后重试:%n%1
zh.Done=Pilot Bots 已安装到 %1 个文件夹。

[Files]
Source: "payload\POMotorNativoBots\*"; DestDir: "{app}\payload\bin_delta"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "payload\POScriptsIABots\*"; DestDir: "{app}\payload\scripts\vscripts"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "payload\POMenuETextos\*"; DestDir: "{app}\payload\resource"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "ferramentas\pbinject.exe"; DestDir: "{app}"; Flags: ignoreversion

[UninstallDelete]
Type: filesandordirs; Name: "{app}\backup"
Type: filesandordirs; Name: "{app}\payload"
Type: files; Name: "{app}\manifest.txt"
Type: files; Name: "{app}\files.txt"

[Code]
var
  PickPage: TWizardPage;
  PickList: TNewCheckListBox;
  AddBtn: TNewButton;
  InstalledCount: Integer;

{ Versao do cliente a partir do nome da pasta (app-2.14.12 -> v2.14.12); vazio se nao for pasta do launcher. }
function ClientVersion(const Target: String): String;
var
  N: String;
  I: Integer;
begin
  Result := '';
  N := ExtractFileName(RemoveBackslash(Target));
  if Copy(N, 1, 4) <> 'app-' then Exit;
  N := Copy(N, 5, MaxInt);
  if (N = '') or (Length(N) > 14) then Exit;
  for I := 1 to Length(N) do
    if not (((N[I] >= '0') and (N[I] <= '9')) or (N[I] = '.')) then Exit;
  Result := 'v' + N;
end;

function HasClient(const Dir: String): Boolean;
begin
  Result := DirExists(AddBackslash(Dir) + 'r1delta');
end;

procedure AddClient(const Dir: String; Checked: Boolean);
var
  I: Integer;
begin
  for I := 0 to PickList.Items.Count - 1 do
    if CompareText(PickList.ItemSubItem[I], Dir) = 0 then
    begin
      PickList.Checked[I] := True;
      Exit;
    end;
  I := PickList.AddCheckBox(ExtractFileName(RemoveBackslash(Dir)), Dir, 0, Checked, True, False, False, nil);
end;

procedure ScanLauncher;
var
  Root: String;
  FR: TFindRec;
begin
  Root := ExpandConstant('{localappdata}\R1Delta\');
  if FindFirst(Root + 'app-*', FR) then
  try
    repeat
      if (FR.Attributes and FILE_ATTRIBUTE_DIRECTORY <> 0) and HasClient(Root + FR.Name) then
        AddClient(Root + FR.Name, True);
    until not FindNext(FR);
  finally
    FindClose(FR);
  end;
end;

procedure AddBtnClick(Sender: TObject);
var
  Dir: String;
begin
  Dir := '';
  if BrowseForFolder(CustomMessage('AddPrompt'), Dir, False) then
  begin
    Dir := RemoveBackslash(Dir);
    if HasClient(Dir) then
      AddClient(Dir, True)
    else
      MsgBox(CustomMessage('NotAClient'), mbError, MB_OK);
  end;
end;

procedure InitializeWizard;
var
  Help: TNewStaticText;
begin
  PickPage := CreateCustomPage(wpWelcome, CustomMessage('PickTitle'), CustomMessage('PickSub'));

  Help := TNewStaticText.Create(PickPage);
  Help.Parent := PickPage.Surface;
  Help.Left := 0;
  Help.Top := 0;
  Help.Width := PickPage.SurfaceWidth;
  Help.AutoSize := False;
  Help.WordWrap := True;
  Help.Height := ScaleY(32);
  Help.Caption := CustomMessage('PickHelp');

  PickList := TNewCheckListBox.Create(PickPage);
  PickList.Parent := PickPage.Surface;
  PickList.Left := 0;
  PickList.Top := Help.Height + ScaleY(8);
  PickList.Width := PickPage.SurfaceWidth;
  PickList.Height := PickPage.SurfaceHeight - PickList.Top - ScaleY(36);

  AddBtn := TNewButton.Create(PickPage);
  AddBtn.Parent := PickPage.Surface;
  AddBtn.Caption := CustomMessage('AddFolder');
  AddBtn.Left := 0;
  AddBtn.Top := PickPage.SurfaceHeight - ScaleY(28);
  AddBtn.Width := ScaleX(130);
  AddBtn.Height := ScaleY(26);
  AddBtn.OnClick := @AddBtnClick;

  ScanLauncher;
  { instalacao silenciosa/teste: /CLIENTDIR="pasta" instala so nessa pasta }
  if ExpandConstant('{param:CLIENTDIR|}') <> '' then
  begin
    PickList.Items.Clear;
    AddClient(RemoveBackslash(ExpandConstant('{param:CLIENTDIR|}')), True);
  end;
  if PickList.Items.Count = 0 then
    MsgBox(CustomMessage('NoneFound'), mbInformation, MB_OK);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  I: Integer;
begin
  Result := True;
  if CurPageID = PickPage.ID then
  begin
    Result := False;
    for I := 0 to PickList.Items.Count - 1 do
      if PickList.Checked[I] then
        Result := True;
    if not Result then
      MsgBox(CustomMessage('NoneSelected'), mbError, MB_OK)
    else
      for I := 0 to PickList.Items.Count - 1 do
        if PickList.Checked[I] and (ClientVersion(PickList.ItemSubItem[I]) <> '') and
           (Copy(ClientVersion(PickList.ItemSubItem[I]), 1, 6) <> 'v2.14.') then
          if MsgBox(FmtMessage(CustomMessage('VersionWarn'), [ClientVersion(PickList.ItemSubItem[I])]),
                    mbConfirmation, MB_YESNO) = IDNO then
            Result := False;
  end;
end;

{ Lista (caminhos relativos) todos os arquivos de Base, recursivo. }
procedure CollectFiles(const Base, Rel: String; List: TStringList);
var
  FR: TFindRec;
begin
  if FindFirst(Base + Rel + '*', FR) then
  try
    repeat
      if (FR.Name <> '.') and (FR.Name <> '..') then
      begin
        if FR.Attributes and FILE_ATTRIBUTE_DIRECTORY <> 0 then
          CollectFiles(Base, Rel + FR.Name + '\', List)
        else
          List.Add(Rel + FR.Name);
      end;
    until not FindNext(FR);
  finally
    FindClose(FR);
  end;
end;

const
  Tier0 = 'bin_delta\tier0.dll';

{ A tier0.dll modificada antiga (instalador 1.x, que substituia a oficial) traz as funcoes dos bots embutidas. }
function IsOldModdedTier0(const Path: String): Boolean;
var
  Data: AnsiString;
begin
  Result := LoadStringFromFile(Path, Data) and (Pos('NavFindPathPilot', Data) > 0);
end;

function CopyOver(const Src, Dst: String): Boolean;
begin
  ForceDirectories(ExtractFilePath(Dst));
  Result := FileCopy(Src, Dst, False);
  if not Result then
    MsgBox(CustomMessage('CopyFail') + #13#10#13#10 + Dst, mbError, MB_OK);
end;

{ manifest.txt: uma linha por cliente, "indice|pasta". Backup dos originais em backup\indice\.
  Files inclui a tier0.dll, que nao vem no payload: so e salva e depois recebe a importacao. }
procedure InstallInto(const Target: String; Files, Manifest: TStringList);
var
  I, Idx, Rc: Integer;
  BackupBase, Src, Dst, Bak, Tier0Dst, Tier0Bak: String;
begin
  Idx := -1;
  for I := 0 to Manifest.Count - 1 do
    if CompareText(Copy(Manifest[I], Pos('|', Manifest[I]) + 1, MaxInt), Target) = 0 then
      Idx := StrToIntDef(Copy(Manifest[I], 1, Pos('|', Manifest[I]) - 1), -1);
  if Idx < 0 then
  begin
    Idx := Manifest.Count;
    Manifest.Add(IntToStr(Idx) + '|' + Target);
  end;
  BackupBase := ExpandConstant('{app}\backup\') + IntToStr(Idx) + '\';
  Tier0Dst := AddBackslash(Target) + 'r1delta\' + Tier0;
  Tier0Bak := BackupBase + Tier0;

  { Instalacao anterior (1.x) trocou a tier0.dll: volta a oficial do backup antes de tudo. }
  if IsOldModdedTier0(Tier0Dst) then
  begin
    if FileExists(Tier0Bak) and not IsOldModdedTier0(Tier0Bak) then
    begin
      if not CopyOver(Tier0Bak, Tier0Dst) then
        Exit;
    end
    else
    begin
      MsgBox(FmtMessage(CustomMessage('ModdedDll'), [Target]), mbError, MB_OK);
      Exit;
    end;
  end;

  { Backups primeiro; sem backup da tier0.dll nao se mexe nela. Arquivo que nao existia antes da
    primeira instalacao ganha um marcador .pbnew, para uma reinstalacao nao salvar a copia da mod
    como se fosse original. }
  for I := 0 to Files.Count - 1 do
  begin
    Dst := AddBackslash(Target) + 'r1delta\' + Files[I];
    Bak := BackupBase + Files[I];
    if not FileExists(Bak) and not FileExists(Bak + '.pbnew') then
    begin
      ForceDirectories(ExtractFilePath(Bak));
      if FileExists(Dst) then
        FileCopy(Dst, Bak, False)
      else
        SaveStringToFile(Bak + '.pbnew', '', False);
    end;
  end;
  if not FileExists(Tier0Bak) then
  begin
    MsgBox(FmtMessage(CustomMessage('InjectFail'), [Tier0Dst, 'backup']), mbError, MB_OK);
    Exit;
  end;

  for I := 0 to Files.Count - 1 do
  begin
    Src := ExpandConstant('{app}\payload\') + Files[I];
    Dst := AddBackslash(Target) + 'r1delta\' + Files[I];
    if FileExists(Src) and not CopyOver(Src, Dst) then
      Exit;
  end;

  { pbinject deixa como esta uma tier0.dll que ja tem a importacao (e retorna 0). }
  if not Exec(ExpandConstant('{app}\pbinject.exe'), '"' + Tier0Dst + '" "' + Tier0Dst + '"', '',
              SW_HIDE, ewWaitUntilTerminated, Rc) or (Rc <> 0) then
  begin
    MsgBox(FmtMessage(CustomMessage('InjectFail'), [Tier0Dst, IntToStr(Rc)]), mbError, MB_OK);
    Exit;
  end;
  InstalledCount := InstalledCount + 1;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Files, Old, Manifest: TStringList;
  I: Integer;
  Payload, FilesTxt, ManTxt: String;
begin
  if CurStep <> ssPostInstall then
    Exit;

  Payload := ExpandConstant('{app}\payload\');
  FilesTxt := ExpandConstant('{app}\files.txt');
  ManTxt := ExpandConstant('{app}\manifest.txt');

  Files := TStringList.Create;
  Old := TStringList.Create;
  Manifest := TStringList.Create;
  try
    CollectFiles(Payload, '', Files);
    if Files.IndexOf(Tier0) < 0 then
      Files.Add(Tier0);
    if FileExists(ManTxt) then
      Manifest.LoadFromFile(ManTxt);
    if FileExists(FilesTxt) then
    begin
      Old.LoadFromFile(FilesTxt);
      for I := 0 to Old.Count - 1 do
        if Files.IndexOf(Old[I]) < 0 then
          Files.Add(Old[I]);
    end;
    InstalledCount := 0;
    for I := 0 to PickList.Items.Count - 1 do
      if PickList.Checked[I] then
        InstallInto(PickList.ItemSubItem[I], Files, Manifest);

    Files.SaveToFile(FilesTxt);
    Manifest.SaveToFile(ManTxt);
  finally
    Files.Free;
    Old.Free;
    Manifest.Free;
  end;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo,
  MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to PickList.Items.Count - 1 do
    if PickList.Checked[I] then
      Result := Result + Space + PickList.ItemSubItem[I] + NewLine;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Files, Manifest: TStringList;
  I, J, P, Idx: Integer;
  Target, Dst, Bak: String;
begin
  if CurUninstallStep <> usUninstall then
    Exit;
  if not (FileExists(ExpandConstant('{app}\files.txt')) and FileExists(ExpandConstant('{app}\manifest.txt'))) then
    Exit;

  Files := TStringList.Create;
  Manifest := TStringList.Create;
  try
    Files.LoadFromFile(ExpandConstant('{app}\files.txt'));
    Manifest.LoadFromFile(ExpandConstant('{app}\manifest.txt'));
    for I := 0 to Manifest.Count - 1 do
    begin
      P := Pos('|', Manifest[I]);
      Idx := StrToIntDef(Copy(Manifest[I], 1, P - 1), -1);
      Target := Copy(Manifest[I], P + 1, MaxInt);
      if (Idx < 0) or not DirExists(Target) then
        Continue;
      for J := 0 to Files.Count - 1 do
      begin
        Dst := AddBackslash(Target) + 'r1delta\' + Files[J];
        Bak := ExpandConstant('{app}\backup\') + IntToStr(Idx) + '\' + Files[J];
        if FileExists(Bak) then
          FileCopy(Bak, Dst, False)
        else if CompareText(Files[J], Tier0) <> 0 then
          DeleteFile(Dst);
      end;
    end;
  finally
    Files.Free;
    Manifest.Free;
  end;
end;
