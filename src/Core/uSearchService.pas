unit uSearchService;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Threading,
  System.Generics.Collections, System.RegularExpressions, JsonDataObjects;

type
  TSearchOptions = record
    CaseSensitive: Boolean;
    UseRegex: Boolean;
    IncludeActive: Boolean;
    IncludeInactive: Boolean;
    IncludeUser: Boolean;
    IncludeAgent: Boolean;
    IncludeThought: Boolean;
    TargetSessionId: string; // Filter by specific session if not empty
  end;

  TSearchMatch = record
    Timestamp: string;
    Role: string;
    Snippet: string;
    MessageIndex: Integer;
  end;

  TSearchSessionResult = record
    SessionId: string;
    AgentType: string;
    SessionName: string;
    Workspace: string;
    Matches: TArray<TSearchMatch>;
  end;

  TSearchCompleteEvent = procedure(const AResults: TArray<TSearchSessionResult>) of object;

  TSearchService = class
  private
    FBaseConfigPath: string;
    FOnSearchComplete: TSearchCompleteEvent;
    function CreateSnippet(const AFullText, AQuery: string; const AOptions: TSearchOptions): string;
    function MatchesText(const AFullText, AQuery: string; const AOptions: TSearchOptions): Boolean;
  public
    procedure Search(const AQuery: string; const AOptions: TSearchOptions);
    property BaseConfigPath: string read FBaseConfigPath write FBaseConfigPath;
    property OnSearchComplete: TSearchCompleteEvent read FOnSearchComplete write FOnSearchComplete;
  end;

implementation

{ TSearchService }

function TSearchService.MatchesText(const AFullText, AQuery: string; const AOptions: TSearchOptions): Boolean;
var
  LRegOpt: TRegExOptions;
begin
  if AOptions.UseRegex then
  begin
    LRegOpt := [];
    if not AOptions.CaseSensitive then LRegOpt := [roIgnoreCase];
    try
      Result := TRegEx.IsMatch(AFullText, AQuery, LRegOpt);
    except
      Result := False;
    end;
  end
  else
  begin
    if AOptions.CaseSensitive then
      Result := Pos(AQuery, AFullText) > 0
    else
      Result := Pos(AQuery.ToLower, AFullText.ToLower) > 0;
  end;
end;

function TSearchService.CreateSnippet(const AFullText, AQuery: string; const AOptions: TSearchOptions): string;
var
  LPos, LStart, LEnd: Integer;
  LRegEx: TRegEx;
  LMatch: TMatch;
  LRegOpt: TRegExOptions;
const
  LContextLen = 40;
begin
  LPos := 0;
  if AOptions.UseRegex then
  begin
    LRegOpt := [];
    if not AOptions.CaseSensitive then LRegOpt := [roIgnoreCase];
    try
      LRegEx := TRegEx.Create(AQuery, LRegOpt);
      LMatch := LRegEx.Match(AFullText);
      if LMatch.Success then LPos := LMatch.Index;
    except
    end;
  end
  else
  begin
    if AOptions.CaseSensitive then LPos := Pos(AQuery, AFullText)
    else LPos := Pos(AQuery.ToLower, AFullText.ToLower);
  end;

  if LPos <= 0 then 
  begin
    if AFullText.Length > LContextLen * 2 then
      Result := AFullText.Substring(0, LContextLen * 2) + '...'
    else
      Result := AFullText;
    Exit;
  end;

  LStart := LPos - LContextLen;
  if LStart < 1 then LStart := 1;
  LEnd := LPos + AQuery.Length + LContextLen;
  if LEnd > AFullText.Length then LEnd := AFullText.Length;

  Result := AFullText.Substring(LStart - 1, LEnd - LStart + 1);
  if LStart > 1 then Result := '...' + Result;
  if LEnd < AFullText.Length then Result := Result + '...';
end;

procedure TSearchService.Search(const AQuery: string; const AOptions: TSearchOptions);
var
  LSearchQuery: string;
  LSearchOpts: TSearchOptions;
begin
  if AQuery.IsEmpty then Exit;
  LSearchQuery := AQuery;
  LSearchOpts := AOptions;

  System.Threading.TTask.Run(procedure
    var
      LBaseDir: string;
      LAgentDirs, LSessionDirs: TArray<string>;
      LAgentDir, LSessionDir, LHistoryFile, LMetaFile, LSessionName, LWorkspace: string;
      LMetaJson, LHistoryJson, LData, LUpdate: JsonDataObjects.TJsonObject;
      LSessResult: TSearchSessionResult;
      LMatches: TList<TSearchMatch>;
      LFinalResults: TList<TSearchSessionResult>;
      LHistoryLines: TStringList;
      LText, LRole, LMethod, LUpdateType, LCurrentText, LCurrentRole, LCurrentTimestamp: string;
      LIsActive: Boolean;
      i, LCurrentFirstIndex: Integer;
      LMatch: TSearchMatch;
      LResultsArr: TArray<TSearchSessionResult>;
      LBase: JsonDataObjects.TJsonBaseObject;

      procedure FlushCurrentMessage;
      var LInclude: Boolean;
      begin
        if (LCurrentText <> '') and (LCurrentRole <> '') then
        begin
          LInclude := False;
          if (LCurrentRole = 'user') and LSearchOpts.IncludeUser then LInclude := True
          else if (LCurrentRole = 'ai') and LSearchOpts.IncludeAgent then LInclude := True
          else if (LCurrentRole = 'thought') and LSearchOpts.IncludeThought then LInclude := True;

          if LInclude and MatchesText(LCurrentText, LSearchQuery, LSearchOpts) then
          begin
            LMatch.Timestamp := LCurrentTimestamp;
            LMatch.Role := LCurrentRole;
            LMatch.Snippet := CreateSnippet(LCurrentText, LSearchQuery, LSearchOpts);
            LMatch.MessageIndex := LCurrentFirstIndex;
            LMatches.Add(LMatch);
          end;
        end;
        LCurrentText := ''; LCurrentRole := '';
      end;

      procedure ProcessContent(AUpdate: JsonDataObjects.TJsonObject; var AOutText: string);
      var k, LIdx: Integer;
      begin
        LIdx := AUpdate.IndexOf('content');
        if LIdx < 0 then Exit;
        
        if AUpdate.Items[LIdx].Typ = jdtObject then
          AOutText := AOutText + AUpdate.O['content'].S['text']
        else if AUpdate.Items[LIdx].Typ = jdtArray then
        begin
          for k := 0 to AUpdate.A['content'].Count - 1 do
            if AUpdate.A['content'].O[k].S['type'] = 'text' then
              AOutText := AOutText + AUpdate.A['content'].O[k].S['text'];
        end;
      end;

    begin
      LBaseDir := TPath.Combine(FBaseConfigPath, 'sessions');
      if not TDirectory.Exists(LBaseDir) then Exit;

      LFinalResults := TList<TSearchSessionResult>.Create;
      LHistoryLines := TStringList.Create;
      try
        LAgentDirs := TDirectory.GetDirectories(LBaseDir);
        for LAgentDir in LAgentDirs do
        begin
          LSessionDirs := TDirectory.GetDirectories(LAgentDir);
          for LSessionDir in LSessionDirs do
          begin
            LHistoryFile := TPath.Combine(LSessionDir, 'history.json');
            if not TFile.Exists(LHistoryFile) then Continue;

            // Target Session Filter
            if (LSearchOpts.TargetSessionId <> '') and 
               not SameText(TPath.GetFileName(LSessionDir), LSearchOpts.TargetSessionId) then Continue;

            try
              LIsActive := False; LSessionName := TPath.GetFileName(LSessionDir); LWorkspace := '';
              LMetaFile := TPath.Combine(LSessionDir, 'metadata.json');
              if TFile.Exists(LMetaFile) then
              begin
                LMetaJson := JsonDataObjects.TJsonObject.ParseFromFile(LMetaFile) as JsonDataObjects.TJsonObject;
                try
                  if Assigned(LMetaJson) then begin
                    LSessionName := LMetaJson.S['name'];
                    LWorkspace := LMetaJson.S['workspace'];
                    LIsActive := LMetaJson.B['isActive'];
                  end;
                finally LMetaJson.Free; end;
              end;

              // Only apply Active/Inactive filter if TargetSessionId is NOT specified
              if (LSearchOpts.TargetSessionId = '') then
              begin
                if LIsActive and not LSearchOpts.IncludeActive then Continue;
                if not LIsActive and not LSearchOpts.IncludeInactive then Continue;
              end;

              LMatches := TList<TSearchMatch>.Create;
              try
                LHistoryLines.LoadFromFile(LHistoryFile, TEncoding.UTF8);
                LCurrentText := ''; LCurrentRole := ''; LCurrentFirstIndex := -1;

                for i := 0 to LHistoryLines.Count - 1 do
                begin
                  if LHistoryLines[i].Trim.IsEmpty then Continue;
                  LBase := JsonDataObjects.TJsonBaseObject.Parse(LHistoryLines[i]);
                  try
                    if (LBase <> nil) and (LBase is JsonDataObjects.TJsonObject) then
                    begin
                      LHistoryJson := JsonDataObjects.TJsonObject(LBase);
                      LData := LHistoryJson.O['data'];
                      if LData = nil then Continue;
                      
                      LMethod := LData.S['method'];
                      if LMethod = 'session/update' then
                      begin
                        LUpdate := LData.O['params'].O['update'];
                        LUpdateType := LUpdate.S['sessionUpdate'];
                        
                        LRole := 'ai';
                        if LUpdateType.Contains('user_') then LRole := 'user'
                        else if LUpdateType.Contains('thought') then LRole := 'thought';

                        if (LCurrentRole <> '') and (LCurrentRole <> LRole) then FlushCurrentMessage;

                        if LCurrentRole = '' then begin
                          LCurrentRole := LRole; LCurrentTimestamp := LHistoryJson.S['timestamp']; LCurrentFirstIndex := i;
                        end;
                        
                        ProcessContent(LUpdate, LCurrentText);
                      end 
                      else if LMethod = 'session/prompt' then
                      begin
                        FlushCurrentMessage;
                        LRole := 'user';
                        LText := LData.O['params'].S['prompt'];
                        LCurrentRole := LRole; LCurrentTimestamp := LHistoryJson.S['timestamp']; LCurrentFirstIndex := i;
                        LCurrentText := LText;
                        FlushCurrentMessage;
                      end
                      else FlushCurrentMessage;
                    end;
                  finally LBase.Free; end;
                end;
                FlushCurrentMessage;

                if LMatches.Count > 0 then begin
                  LSessResult.SessionId := TPath.GetFileName(LSessionDir);
                  LSessResult.AgentType := TPath.GetFileName(LAgentDir).Replace('-cli', '');
                  LSessResult.SessionName := LSessionName;
                  LSessResult.Workspace := LWorkspace;
                  LSessResult.Matches := LMatches.ToArray;
                  LFinalResults.Add(LSessResult);
                end;
              finally LMatches.Free; end;
            except end;
          end;
        end;

        LResultsArr := LFinalResults.ToArray;
        System.Classes.TThread.Queue(nil, procedure begin
          if Assigned(FOnSearchComplete) then FOnSearchComplete(LResultsArr);
        end);
      finally LHistoryLines.Free; LFinalResults.Free; end;
    end);
end;

end.
