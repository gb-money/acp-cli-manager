unit uAgentProcess;

interface

uses
  System.Classes, System.SysUtils, Winapi.Windows;

type
  TProcessOutputEvent = procedure(Sender: TObject; const Text: string) of object;
  TProcessTerminatedEvent = procedure(Sender: TObject; ExitCode: Cardinal) of object;

  TAgentProcess = class;

  TProcessReaderThread = class(TThread)
  private
    FProcessHandle: THandle;
    FReadPipe: THandle;
    [Weak] FOwner: TAgentProcess;
    procedure QueueOutput(const AText: string);
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TAgentProcess; AReadPipe: THandle; AProcHandle: THandle);
    destructor Destroy; override;
  end;

  TAgentProcess = class(TComponent)
  private
    FCommandLine: string;
    FProcessInfo: TProcessInformation;
    FProcessRunning: Boolean;
    FReaderThread: TProcessReaderThread;
    FStdInRead, FStdInWrite: THandle;
    FStdOutRead, FStdOutWrite: THandle;
    FJobHandle: THandle;
    FOnOutput: TProcessOutputEvent;
    FOnTerminated: TProcessTerminatedEvent;
    FIsStopping: Boolean;
    procedure CleanupHandles;
    procedure SetupJobObject;
  protected
    procedure DoOutput(const Text: string);
    procedure DoTerminated(ExitCode: Cardinal);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Start: Boolean;
    procedure Stop;
    procedure WriteLine(const Text: string);
    function IsRunning: Boolean;
    property CommandLine: string read FCommandLine write FCommandLine;
    property OnOutput: TProcessOutputEvent read FOnOutput write FOnOutput;
    property OnTerminated: TProcessTerminatedEvent read FOnTerminated write FOnTerminated;
    property IsStopping: Boolean read FIsStopping;
  end;

implementation

{ TProcessReaderThread }

constructor TProcessReaderThread.Create(AOwner: TAgentProcess; AReadPipe: THandle; AProcHandle: THandle);
begin
  inherited Create(True);
  FreeOnTerminate := False; 
  FOwner := AOwner;
  FReadPipe := AReadPipe;
  // 핸들을 복제하여 부모의 생명주기와 분리 (핵심 안전장치)
  DuplicateHandle(GetCurrentProcess, AProcHandle, GetCurrentProcess, @FProcessHandle, 0, False, DUPLICATE_SAME_ACCESS);
end;

destructor TProcessReaderThread.Destroy;
begin
  if FProcessHandle <> 0 then CloseHandle(FProcessHandle);
  inherited;
end;

procedure TProcessReaderThread.QueueOutput(const AText: string);
begin
  TThread.Queue(nil, procedure
  var
    CurrentOwner: TAgentProcess;
  begin
    CurrentOwner := FOwner;
    if Assigned(CurrentOwner) and not CurrentOwner.FIsStopping and Assigned(CurrentOwner.FOnOutput) then
      CurrentOwner.FOnOutput(CurrentOwner, AText);
  end);
end;

procedure TProcessReaderThread.Execute;
var
  Buffer: array[0..8191] of Byte;
  BytesRead: DWORD;
  RawBytes: TBytes;
  TextChunk: string;
begin
  while not Terminated do
  begin
    if not ReadFile(FReadPipe, Buffer, SizeOf(Buffer), BytesRead, nil) then Break;
    if (BytesRead > 0) and not Terminated then
    begin
      SetLength(RawBytes, BytesRead);
      Move(Buffer[0], RawBytes[0], BytesRead);
      try
        TextChunk := TEncoding.UTF8.GetString(RawBytes);
      except
        TextChunk := TEncoding.Default.GetString(RawBytes);
      end;

      if Assigned(FOwner) and not FOwner.FIsStopping then
        QueueOutput(TextChunk);
    end;
  end;

  // 종료 알림 (종료 중이 아닐 때만)
  if Assigned(FOwner) and not FOwner.FIsStopping then
  begin
    TThread.Queue(nil, procedure
    var
      ExitCode: Cardinal;
    begin
      if Assigned(FOwner) and not FOwner.FIsStopping then
      begin
        ExitCode := 0;
        GetExitCodeProcess(FProcessHandle, ExitCode);
        FOwner.DoTerminated(ExitCode);
      end;
    end);
  end;
end;

{ TAgentProcess }

constructor TAgentProcess.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FJobHandle := 0;
  SetupJobObject;
end;

procedure TAgentProcess.SetupJobObject;
var
  Info: TJobObjectExtendedLimitInformation;
begin
  FJobHandle := CreateJobObject(nil, nil);
  if FJobHandle <> 0 then
  begin
    FillChar(Info, SizeOf(Info), 0);
    Info.BasicLimitInformation.LimitFlags := JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    SetInformationJobObject(FJobHandle, JobObjectExtendedLimitInformation, @Info, SizeOf(Info));
  end;
end;

destructor TAgentProcess.Destroy;
begin
  FIsStopping := True;
  Stop;
  if FJobHandle <> 0 then CloseHandle(FJobHandle);
  inherited;
end;

procedure TAgentProcess.CleanupHandles;
begin
  if FStdInWrite <> 0 then CloseHandle(FStdInWrite);
  if FStdInRead <> 0 then CloseHandle(FStdInRead);
  if FStdOutWrite <> 0 then CloseHandle(FStdOutWrite);
  if FStdOutRead <> 0 then CloseHandle(FStdOutRead);
  FStdInWrite := 0; FStdInRead := 0; FStdOutWrite := 0; FStdOutRead := 0;
  if FProcessInfo.hProcess <> 0 then CloseHandle(FProcessInfo.hProcess);
  if FProcessInfo.hThread <> 0 then CloseHandle(FProcessInfo.hThread);
  FProcessInfo.hProcess := 0; FProcessInfo.hThread := 0;
  FProcessRunning := False;
end;

procedure TAgentProcess.DoOutput(const Text: string);
begin
  if Assigned(FOnOutput) and not FIsStopping then FOnOutput(Self, Text);
end;

procedure TAgentProcess.DoTerminated(ExitCode: Cardinal);
begin
  FProcessRunning := False;
  if Assigned(FOnTerminated) and not FIsStopping then FOnTerminated(Self, ExitCode);
end;

function TAgentProcess.IsRunning: Boolean;
var ExitCode: DWORD;
begin
  Result := FProcessRunning and (FProcessInfo.hProcess <> 0) and
            GetExitCodeProcess(FProcessInfo.hProcess, ExitCode) and (ExitCode = STILL_ACTIVE);
end;

function TAgentProcess.Start: Boolean;
var SA: TSecurityAttributes; SI: TStartupInfo;
begin
  Result := False; Stop; FIsStopping := False;
  SA.nLength := SizeOf(SA); SA.lpSecurityDescriptor := nil; SA.bInheritHandle := True;
  if not CreatePipe(FStdOutRead, FStdOutWrite, @SA, 0) then Exit;
  SetHandleInformation(FStdOutRead, HANDLE_FLAG_INHERIT, 0);
  if not CreatePipe(FStdInRead, FStdInWrite, @SA, 0) then begin CleanupHandles; Exit; end;
  SetHandleInformation(FStdInWrite, HANDLE_FLAG_INHERIT, 0);
  FillChar(SI, SizeOf(SI), 0); SI.cb := SizeOf(SI);
  SI.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW; SI.wShowWindow := SW_HIDE;
  SI.hStdInput := FStdInRead; SI.hStdOutput := FStdOutWrite; SI.hStdError := FStdOutWrite;
  UniqueString(FCommandLine);
  if CreateProcess(nil, PChar(FCommandLine), nil, nil, True, CREATE_NO_WINDOW, nil, nil, SI, FProcessInfo) then
  begin
    FProcessRunning := True;
    if FJobHandle <> 0 then AssignProcessToJobObject(FJobHandle, FProcessInfo.hProcess);
    CloseHandle(FStdOutWrite); FStdOutWrite := 0;
    CloseHandle(FStdInRead);   FStdInRead := 0;
    FReaderThread := TProcessReaderThread.Create(Self, FStdOutRead, FProcessInfo.hProcess);
    FReaderThread.Start;
    Result := True;
  end else 
  begin
    DoOutput('ERROR: CreateProcess failed. ' + SysErrorMessage(GetLastError));
    CleanupHandles;
  end;
end;

procedure TAgentProcess.Stop;
begin
  if FIsStopping and not FProcessRunning then Exit;
  FIsStopping := True;
  FProcessRunning := False;
  
  // 1. 파이프를 먼저 닫아서 ReadFile 블로킹 해제
  if FStdInWrite <> 0 then begin CloseHandle(FStdInWrite); FStdInWrite := 0; end;
  if FStdOutRead <> 0 then begin CloseHandle(FStdOutRead); FStdOutRead := 0; end;
  
  // 2. 프로세스 강제 종료
  if FProcessInfo.hProcess <> 0 then TerminateProcess(FProcessInfo.hProcess, 0);
  
  // 3. 스레드 종료 대기 및 해제
  if Assigned(FReaderThread) then 
  begin 
    FReaderThread.Terminate; 
    FReaderThread.WaitFor;
    FreeAndNil(FReaderThread);
  end;
  
  CleanupHandles;
end;

procedure TAgentProcess.WriteLine(const Text: string);
var Bytes: TBytes; Written: DWORD;
begin
  if (FStdInWrite <> 0) and IsRunning and not FIsStopping then
  begin
    Bytes := TEncoding.UTF8.GetBytes(Text + #10);
    WriteFile(FStdInWrite, Bytes[0], Length(Bytes), Written, nil);
    FlushFileBuffers(FStdInWrite);
  end;
end;

end.
