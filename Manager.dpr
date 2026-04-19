program Manager;

uses
  System.StartUpCopy,
  FMX.Forms,
  uMain in 'uMain.pas' {S},
  uDebugRPC in 'src\UI\uDebugRPC.pas' {frmDebugRPC},
  uSessionManager in 'src\Core\uSessionManager.pas',
  uThemeManager in 'src\UI\uThemeManager.pas',
  uAgentControl in 'src\UI\uAgentControl.pas',
  uAgent in 'src\Agents\uAgent.pas',
  uACPAgent in 'src\Agents\uACPAgent.pas',
  uConversationService in 'src\Core\uConversationService.pas',
  uWebACPCommandHandler in 'src\Core\uWebACPCommandHandler.pas',
  uAgentProcess in 'src\Core\uAgentProcess.pas',
  uACPClient in 'src\ACP\uACPClient.pas',
  uACPProtocol in 'src\ACP\uACPProtocol.pas',
  uGeminiAgent in 'src\Agents\Gemini\uGeminiAgent.pas',
  uActionModule in 'src\Actions\uActionModule.pas' {dmActions: TDataModule},
  JsonDataObjects in 'src\modules\JsonDataObjects\Source\JsonDataObjects.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TS, S);
  Application.CreateForm(TdmActions, dmActions);
  Application.CreateForm(TfrmDebugRPC, frmDebugRPC);
  Application.Run;
end.
