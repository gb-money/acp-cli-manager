program Manager;

uses
  System.StartUpCopy,
  FMX.Forms,
  uMain in 'uMain.pas' {S},
  uDebugRPC in 'src\UI\uDebugRPC.pas' {frmDebugRPC},
  uSessionManager in 'src\Core\uSessionManager.pas',
  uAgentTypes in 'src\Core\uAgentTypes.pas',
  uThemeManager in 'src\UI\uThemeManager.pas',
  uAgentControl in 'src\UI\uAgentControl.pas',
  uAgentHandler in 'src\Agents\uAgentHandler.pas',
  uACPAgent in 'src\Agents\uACPAgent.pas',
  uConversationService in 'src\Core\uConversationService.pas',
  uSearchService in 'src\Core\uSearchService.pas',
  uWebACPCommandHandler in 'src\Core\uWebACPCommandHandler.pas',
  uAgentProcess in 'src\Core\uAgentProcess.pas',
  uACPClient in 'src\ACP\uACPClient.pas',
  uACPProtocol in 'src\ACP\uACPProtocol.pas',
  uGeminiAgent in 'src\Agents\Gemini\uGeminiAgent.pas',
  uGeminiAgentHandler in 'src\Agents\Gemini\uGeminiAgentHandler.pas',
  uFileExplorer in 'src\UI\uFileExplorer.pas' {frmFileExplorer},
  uExplorerControl in 'src\UI\uExplorerControl.pas',
  uFileViewer in 'src\UI\uFileViewer.pas' {frmFileViewer},
  uFileViewerControl in 'src\UI\uFileViewerControl.pas',
  uDiffViewer in 'src\UI\uDiffViewer.pas' {frmDiffViewer},
  uDiffViewerControl in 'src\UI\uDiffViewerControl.pas',
  uUIControl in 'src\UI\uUIControl.pas',
  JsonDataObjects in 'src\modules\JsonDataObjects\Source\JsonDataObjects.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TS, S);
  Application.CreateForm(TfrmDebugRPC, frmDebugRPC);
  Application.Run;
end.
