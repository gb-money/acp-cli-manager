unit uConversationService;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, JsonDataObjects, uSessionManager;

type
  TConversationService = class
  private
    class procedure ProcessLogEntry(ALogEntry: TJsonObject; LMessages: TJsonArray; var LLastMsg: TJsonObject);
  public
    // 3. sessionId 기반으로 채팅 UI 데이터 가져오기 (정제된 배열 반환) - 고속 Read
    class function GetConversationsBySessionId(ASession: TSessionInfo): TJsonArray;
    
    // 4. 새로운 RPC 로그 추가 - 고속 Append
    class procedure AppendLog(ASession: TSessionInfo; const ADirection, ARawText: string);
    
    // 5. Resume (복구) 관련 기능
    class procedure StartRestoration(ASession: TSessionInfo);
    class procedure FinalizeRestoration(ASession: TSessionInfo);
  end;

implementation

{ TConversationService }

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
  LStream := nil;
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

      // TJsonObject 대신 TJsonBaseObject를 사용하여 Array/Object 자동 판별
      LBase := TJsonBaseObject.Parse(LLine);
      try
        if Assigned(LBase) then
        begin
          if LBase is TJsonObject then
            ProcessLogEntry(TJsonObject(LBase), Result, LLastMsg)
          else if LBase is TJsonArray then
          begin
            // 기존 통째로 저장된 Array 포맷 대응
            for J := 0 to TJsonArray(LBase).Count - 1 do
              if TJsonArray(LBase).Items[J].Typ = jdtObject then
                ProcessLogEntry(TJsonArray(LBase).O[J], Result, LLastMsg);
          end;
        end;
      finally
        LBase.Free;
      end;
    end;
  finally
    LLines.Free;
  end;
end;

class procedure TConversationService.ProcessLogEntry(ALogEntry: TJsonObject; LMessages: TJsonArray; var LLastMsg: TJsonObject);
var
  LEntryData, LParamsObj, LUpdateObj: TJsonObject;
  LUpdateType, LChunkText, LRole, LPrompt: string;
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
            if LParamsObj.A['prompt'].Items[K].Typ = jdtObject then
              LPrompt := LPrompt + LParamsObj.A['prompt'].O[K].S['text'];
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
      
      LJSON := LLogObj.ToJSON(False);
      // 줄바꿈 문자는 JSON-RPC 로그 보존을 위해 제거하되, #9(Tab)은 JSON 문자열 내부의 \t로 인코딩되므로 굳이 공백 치환할 필요 없음
      LJSON := LJSON.Replace(#13, '').Replace(#10, '');
      
      TFile.AppendAllText(LTargetFile, LJSON + sLineBreak, TEncoding.UTF8);
    except
      on E: Exception do ;
    end;
  finally
    LLogObj.Free;
  end;
end;

class procedure TConversationService.StartRestoration(ASession: TSessionInfo);
var
  LNewPath: string;
begin
  if (ASession = nil) or (ASession.LogPath = '') then Exit;
  LNewPath := ASession.LogPath + '.new';
  if TFile.Exists(LNewPath) then TFile.Delete(LNewPath);
  TFile.WriteAllText(LNewPath, '', TEncoding.UTF8);
end;

class procedure TConversationService.FinalizeRestoration(ASession: TSessionInfo);
var
  LNewPath: string;
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
