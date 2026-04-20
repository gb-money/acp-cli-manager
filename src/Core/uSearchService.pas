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
    Result := TRegEx.IsMatch(AFullText, AQuery, LRegOpt);
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
    LRegEx := TRegEx.Create(AQuery, LRegOpt);
    LMatch := LRegEx.Match(AFullText);
    if LMatch.Success then LPos := LMatch.Index;
  end
  else
  begin
    if AOptions.CaseSensitive then LPos := Pos(AQuery, AFullText)
    else LPos := Pos(AQuery.ToLower, AFullText.ToLower);
  end;

  if LPos = 0 then 
  begin
    if AFullText.Length > LContextLen * 2 then
      Exit(AFullText.Substring(0, LContextLen * 2) + '...')
    else
      Exit(AFullText);
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
      LAgentDir, LSessionDir, LHistoryFile, LMetaFile, LRawText, LSessionName, LWorkspace: string;
      LMetaJson, LHistoryJson, LData, LUpdate, LContent: JsonDataObjects.TJsonObject;
      LSessResult: TSearchSessionResult;
      LMatches: TList<TSearchMatch>;
      LFinalResults: TList<TSearchSessionResult>;
      LHistoryLines: TStringList;
      LText: string;
      LIsActive: Boolean;
      i: Integer;
      LMatch: TSearchMatch;
      LResultsArr: TArray<TSearchSessionResult>;
      LBase: JsonDataObjects.TJsonBaseObject;
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
            LMetaFile := TPath.Combine(LSessionDir, 'metadata.json');
            if not TFile.Exists(LHistoryFile) then Continue;

            try
              LIsActive := False;
              LSessionName := TPath.GetFileName(LSessionDir);
              LWorkspace := '';
              if TFile.Exists(LMetaFile) then
              begin
                LMetaJson := JsonDataObjects.TJsonObject.ParseFromFile(LMetaFile) as JsonDataObjects.TJsonObject;
                try
                  if Assigned(LMetaJson) then
                  begin
                    LSessionName := LMetaJson.S['name'];
                    LWorkspace := LMetaJson.S['workspace'];
                    LIsActive := LMetaJson.B['isActive'];
                  end;
                finally
                  LMetaJson.Free;
                end;
              end;

              if LIsActive and not LSearchOpts.IncludeActive then Continue;
              if not LIsActive and not LSearchOpts.IncludeInactive then Continue;

              LRawText := TFile.ReadAllText(LHistoryFile, TEncoding.UTF8);
              if not MatchesText(LRawText, LSearchQuery, LSearchOpts) then Continue;

              LMatches := TList<TSearchMatch>.Create;
              try
                LHistoryLines.Text := LRawText;
                for i := 0 to LHistoryLines.Count - 1 do
                begin
                  if LHistoryLines[i].Trim.IsEmpty then Continue;
                  LBase := JsonDataObjects.TJsonBaseObject.Parse(LHistoryLines[i]);
                  try
                    if (LBase <> nil) and (LBase is JsonDataObjects.TJsonObject) then
                    begin
                      LHistoryJson := LBase as JsonDataObjects.TJsonObject;
                      LData := LHistoryJson.O['data'];
                      if (LData <> nil) and (LData.S['method'] = 'session/update') then
                      begin
                        LUpdate := LData.O['params'].O['update'];
                        LContent := LUpdate.O['content'];
                        LText := LContent.S['text'];

                        if MatchesText(LText, LSearchQuery, LSearchOpts) then
                        begin
                          LMatch.Timestamp := LHistoryJson.S['timestamp'];
                          LMatch.Role := LUpdate.S['sessionUpdate'].Replace('_chunk', '').Replace('agent_', 'ai_').Replace('user_', 'user');
                          LMatch.Snippet := CreateSnippet(LText, LSearchQuery, LSearchOpts);
                          LMatch.MessageIndex := i;
                          LMatches.Add(LMatch);
                        end;
                      end;
                    end;
                  finally
                    LBase.Free;
                  end;
                end;

                if LMatches.Count > 0 then
                begin
                  LSessResult.SessionId := TPath.GetFileName(LSessionDir);
                  LSessResult.AgentType := TPath.GetFileName(LAgentDir).Replace('-cli', '');
                  LSessResult.SessionName := LSessionName;
                  LSessResult.Workspace := LWorkspace;
                  LSessResult.Matches := LMatches.ToArray;
                  LFinalResults.Add(LSessResult);
                end;
              finally
                LMatches.Free;
              end;
            except
            end;
          end;
        end;

        LResultsArr := LFinalResults.ToArray;
        System.Classes.TThread.Queue(nil, 
          procedure
          begin
            if Assigned(FOnSearchComplete) then
              FOnSearchComplete(LResultsArr);
          end);
      finally
        LHistoryLines.Free;
        LFinalResults.Free;
      end;
    end);
end;

end.
