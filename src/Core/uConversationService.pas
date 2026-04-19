unit uConversationService;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.RegularExpressions, JsonDataObjects, uSessionManager;

type
  TConversationService = class
  private
    class function CleanContent(const AContent: string): string;
    class procedure ProcessLogEntry(ALogEntry: TJsonObject; LMessages: TJsonArray; var LLastMsg: TJsonObject);
  public
    class function GetConversationsBySessionId(ASession: TSessionInfo): TJsonArray;
    class procedure AppendLog(ASession: TSessionInfo; const ADirection, ARawText: string);
    class procedure StartRestoration(ASession: TSessionInfo);
    class procedure FinalizeRestoration(ASession: TSessionInfo);
  end;

implementation

{ TConversationService }

class function TConversationService.CleanContent(const AContent: string): string;
var
  LIdx: Integer;
  LMatches: TMatchCollection;
  LMatch: TMatch;
  LRaw, LPath, LFile: string;
begin
  Result := AContent;
  
  // 1. Remove context blocks added by agent
  LIdx := Result.ToLower.IndexOf('--- content from');
  if LIdx < 0 then LIdx := Result.ToLower.IndexOf('--- context from');
  if LIdx >= 0 then
    Result := Result.Substring(0, LIdx).Trim;

  // 2. Normalize @file:/// paths to @filename for UI
  try
    LMatches := TRegEx.Matches(Result, '@file:///[^\s\xa0\n]+');
    for LMatch in LMatches do
    begin
      LRaw := LMatch.Value;
      LPath := LRaw.Replace('@file:///', '').Replace('/', PathDelim);
      LFile := TPath.GetFileName(LPath);
      Result := Result.Replace(LRaw, '@' + LFile);
    end;
  except
  end;
end;

class function TConversationService.GetConversationsBySessionId(ASession: TSessionInfo): TJsonArray;
var
  LStream: TFileStream;
  LLines: TStringList;
  LBase: TJsonBaseObject;
  LLastMsg: TJsonObject;
  I, J: Integer;
  LLine: string;
begin
  Result := TJsonArray.Create;
  if (ASession = nil) or (ASession.LogPath = '') or not TFile.Exists(ASession.LogPath) then Exit;

  LLastMsg := nil;
  LLines := TStringList.Create;
  try
    LStream := TFileStream.Create(ASession.LogPath, fmOpenRead or fmShareDenyNone);
    try
      LLines.LoadFromStream(LStream, TEncoding.UTF8);
    finally
      LStream.Free;
    end;

    for I := 0 to LLines.Count - 1 do
    begin
      LLine := LLines[I].Trim;
      if LLine = '' then Continue;

      LBase := TJsonBaseObject.Parse(LLine);
      try
        if Assigned(LBase) then
        begin
          if LBase is TJsonObject then
            ProcessLogEntry(TJsonObject(LBase), Result, LLastMsg)
          else if LBase is TJsonArray then
          begin
            for J := 0 to TJsonArray(LBase).Count - 1 do
              if TJsonArray(LBase).Items[J].Typ = jdtObject then
                ProcessLogEntry(TJsonArray(LBase).O[J], Result, LLastMsg);
          end;
        end;
      finally
        LBase.Free;
      end;
    end;

    // Apply CleanContent AFTER all chunks have been assembled into full messages
    for I := 0 to Result.Count - 1 do
    begin
      if Result.Items[I].Typ = jdtObject then
      begin
        Result.O[I].S['content'] := CleanContent(Result.O[I].S['content']);
      end;
    end;
    
  finally
    LLines.Free;
  end;
end;

class procedure TConversationService.ProcessLogEntry(ALogEntry: TJsonObject; LMessages: TJsonArray; var LLastMsg: TJsonObject);
var
  LEntryData, LParamsObj, LUpdateObj, LResObj: TJsonObject;
  LUpdateType, LChunkText, LRole, LPrompt, LUri: string;
  K: Integer;
begin
  if (ALogEntry = nil) or not ALogEntry.Contains('data') then Exit;
  LEntryData := ALogEntry.O['data'];
  
  if SameText(LEntryData.S['method'], 'session/prompt') then
  begin
    LParamsObj := LEntryData.O['params'];
    LLastMsg := LMessages.AddObject;
    LLastMsg.S['role'] := 'user';
    LLastMsg.S['timestamp'] := ALogEntry.S['timestamp'];
    
    if LParamsObj.IndexOf('prompt') >= 0 then
    begin
      case LParamsObj.Items[LParamsObj.IndexOf('prompt')].Typ of
        jdtString: LLastMsg.S['content'] := LParamsObj.S['prompt'];
        jdtArray: 
        begin
          LPrompt := '';
          for K := 0 to LParamsObj.A['prompt'].Count - 1 do
          begin
            if LParamsObj.A['prompt'].Items[K].Typ = jdtObject then
            begin
              LResObj := LParamsObj.A['prompt'].O[K];
              if LResObj.S['type'] = 'text' then
                LPrompt := LPrompt + LResObj.S['text']
              else if LResObj.S['type'] = 'resource' then
              begin
                LUri := LResObj.O['resource'].S['uri'];
                LPrompt := LPrompt + '@"' + LUri + '" ';
              end;
            end;
          end;
          LLastMsg.S['content'] := LPrompt;
        end;
      end;
    end;
  end
  else if SameText(LEntryData.S['method'], 'session/update') then
  begin
    if LEntryData.Contains('params') and (LEntryData.Items[LEntryData.IndexOf('params')].Typ = jdtObject) and LEntryData.O['params'].Contains('update') then
    begin
      LUpdateObj := LEntryData.O['params'].O['update'];
      LUpdateType := LUpdateObj.S['sessionUpdate'];
      
      if (LUpdateType = 'agent_thought_chunk') or (LUpdateType = 'agent_message_chunk') or 
         (LUpdateType = 'user_message_chunk') or (LUpdateType = 'full_message') then
      begin
        if LUpdateType = 'full_message' then
        begin
          LRole := LUpdateObj.S['role'];
          if (LRole = 'assistant') or (LRole = '') then LRole := 'ai';
        end
        else
        begin
          LRole := 'ai';
          if LUpdateType = 'agent_thought_chunk' then LRole := 'thought'
          else if LUpdateType = 'user_message_chunk' then LRole := 'user';
        end;
        
        LChunkText := '';
        if LUpdateObj.Contains('content') then
        begin
          case LUpdateObj.Items[LUpdateObj.IndexOf('content')].Typ of
            jdtObject: LChunkText := LUpdateObj.O['content'].S['text'];
            jdtArray: 
            begin
              for K := 0 to LUpdateObj.A['content'].Count - 1 do
                if LUpdateObj.A['content'].Items[K].Typ = jdtObject then
                  LChunkText := LChunkText + LUpdateObj.A['content'].O[K].S['text'];
            end;
          end;
        end;

        if LChunkText <> '' then
        begin
          if (LUpdateType <> 'full_message') and Assigned(LLastMsg) and (LLastMsg.S['role'] = LRole) then
            LLastMsg.S['content'] := LLastMsg.S['content'] + LChunkText
          else
          begin
            LLastMsg := LMessages.AddObject;
            LLastMsg.S['role'] := LRole;
            LLastMsg.S['content'] := LChunkText;
            LLastMsg.S['timestamp'] := ALogEntry.S['timestamp'];
          end;
        end;
      end;
    end;
  end;
end;

class procedure TConversationService.AppendLog(ASession: TSessionInfo; const ADirection, ARawText: string);
var
  LLogObj: TJsonObject;
  LTargetFile, LJSON: string;
  LBase: TJsonBaseObject;
begin
  if (ASession = nil) or (ASession.LogPath = '') then Exit;
  LTargetFile := ASession.LogPath;
  if ASession.IsLoading and TFile.Exists(ASession.LogPath + '.new') then
    LTargetFile := ASession.LogPath + '.new';

  LLogObj := TJsonObject.Create;
  try
    try
      LLogObj.S['timestamp'] := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now);
      LLogObj.S['direction'] := ADirection.Trim;
      LBase := TJsonBaseObject.Parse(ARawText);
      try
        if Assigned(LBase) then
        begin
          if LBase is TJsonObject then LLogObj.O['data'].Assign(TJsonObject(LBase))
          else if LBase is TJsonArray then LLogObj.A['data'].Assign(TJsonArray(LBase));
        end;
      finally
        LBase.Free;
      end;
      LJSON := LLogObj.ToJSON(False).Replace(#13, '').Replace(#10, '');
      TFile.AppendAllText(LTargetFile, LJSON + sLineBreak, TEncoding.UTF8);
    except
    end;
  finally
    LLogObj.Free;
  end;
end;

class procedure TConversationService.StartRestoration(ASession: TSessionInfo);
var LNewPath: string;
begin
  if (ASession = nil) or (ASession.LogPath = '') then Exit;
  LNewPath := ASession.LogPath + '.new';
  if TFile.Exists(LNewPath) then TFile.Delete(LNewPath);
  TFile.WriteAllText(LNewPath, '', TEncoding.UTF8);
end;

class procedure TConversationService.FinalizeRestoration(ASession: TSessionInfo);
var LNewPath: string;
begin
  if (ASession = nil) or (ASession.LogPath = '') then Exit;
  LNewPath := ASession.LogPath + '.new';
  if TFile.Exists(LNewPath) then
  begin
    if TFile.Exists(ASession.LogPath) then TFile.Delete(ASession.LogPath);
    TFile.Move(LNewPath, ASession.LogPath);
  end;
end;

end.
