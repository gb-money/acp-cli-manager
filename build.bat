@echo off
set DCC="C:\Program Files (x86)\Embarcadero\Studio\22.0\bin\dcc32.exe"
set PROJECT=Manager.dpr

echo Building Project...
%DCC% -$O- -$W+ -$R+ -$Q+ --no-config -B -Q -TX.exe ^
  -AGenerics.Collections=System.Generics.Collections;Generics.Defaults=System.Generics.Defaults;WinTypes=Winapi.Windows;WinProcs=Winapi.Windows;DbiTypes=BDE;DbiProcs=BDE;DbiErrs=BDE ^
  -DDEBUG;SKIA -E.\Win32\Debug ^
  -I"c:\program files (x86)\embarcadero\studio\22.0\lib\Win32\debug\EN";"c:\program files (x86)\embarcadero\studio\22.0\lib\Win32\debug";"c:\program files (x86)\embarcadero\studio\22.0\lib\Win32\release\EN";"C:\Users\MyName\Documents\Skia4Delphi\Library\RAD Studio 11 Alexandria\Win32\Release";C:\Users\MyName\Documents\Skia4Delphi\Source;C:\Users\MyName\Documents\Skia4Delphi\Source\FMX;C:\Users\MyName\Documents\Skia4Delphi\Source\VCL;C:\Users\MyName\Documents\Skia4Delphi\Source\FMX\Designtime;C:\Users\MyName\Documents\Skia4Delphi\Source\VCL\Designtime;"c:\program files (x86)\embarcadero\studio\22.0\lib\Win32\release";C:\Users\MyName\Documents\Embarcadero\Studio\22.0\Imports;"C:\Program Files (x86)\Embarcadero\Studio\22.0\Imports";C:\Users\Public\Documents\Embarcadero\Studio\22.0\Dcp;"C:\Program Files (x86)\Embarcadero\Studio\22.0\include";C:\Users\MyName\Documents\Delphi\BlessServer\Library;C:\Users\MyName\Documents\Delphi\BlessServer\Library\DelphiToFPC;C:\Users\MyName\Documents\Delphi\BlessServer\Library\Net;C:\Users\MyName\Documents\Delphi\BlessServer\Library\Utils ^
  -R"c:\program files (x86)\embarcadero\studio\22.0\lib\Win32\release\EN";"C:\Users\MyName\Documents\Skia4Delphi\Library\RAD Studio 11 Alexandria\Win32\Release";C:\Users\MyName\Documents\Skia4Delphi\Source;C:\Users\MyName\Documents\Skia4Delphi\Source\FMX;C:\Users\MyName\Documents\Skia4Delphi\Source\VCL;C:\Users\MyName\Documents\Skia4Delphi\Source\FMX\Designtime;C:\Users\MyName\Documents\Skia4Delphi\Source\VCL\Designtime;"c:\program files (x86)\embarcadero\studio\22.0\lib\Win32\release";C:\Users\MyName\Documents\Embarcadero\Studio\22.0\Imports;"C:\Program Files (x86)\Embarcadero\Studio\22.0\Imports";C:\Users\Public\Documents\Embarcadero\Studio\22.0\Dcp;"C:\Program Files (x86)\Embarcadero\Studio\22.0\include";C:\Users\MyName\Documents\Delphi\BlessServer\Library;C:\Users\MyName\Documents\Delphi\BlessServer\Library\DelphiToFPC;C:\Users\MyName\Documents\Delphi\BlessServer\Library\Net;C:\Users\MyName\Documents\Delphi\BlessServer\Library\Utils ^
  -U"c:\program files (x86)\embarcadero\studio\22.0\lib\Win32\debug\EN";"c:\program files (x86)\embarcadero\studio\22.0\lib\Win32\debug";"c:\program files (x86)\embarcadero\studio\22.0\lib\Win32\release\EN";"C:\Users\MyName\Documents\Skia4Delphi\Library\RAD Studio 11 Alexandria\Win32\Release";C:\Users\MyName\Documents\Skia4Delphi\Source;C:\Users\MyName\Documents\Skia4Delphi\Source\FMX;C:\Users\MyName\Documents\Skia4Delphi\Source\VCL;C:\Users\MyName\Documents\Skia4Delphi\Source\FMX\Designtime;C:\Users\MyName\Documents\Skia4Delphi\Source\VCL\Designtime;"c:\program files (x86)\embarcadero\studio\22.0\lib\Win32\release";C:\Users\MyName\Documents\Embarcadero\Studio\22.0\Imports;"C:\Program Files (x86)\Embarcadero\Studio\22.0\Imports";C:\Users\Public\Documents\Embarcadero\Studio\22.0\Dcp;"C:\Program Files (x86)\Embarcadero\Studio\22.0\include";C:\Users\MyName\Documents\Delphi\BlessServer\Library;C:\Users\MyName\Documents\Delphi\BlessServer\Library\DelphiToFPC;C:\Users\MyName\Documents\Delphi\BlessServer\Library\Net;C:\Users\MyName\Documents\Delphi\BlessServer\Library\Utils ^
  -NSWinapi;System.Win;Data.Win;Datasnap.Win;Web.Win;Soap.Win;Xml.Win;Bde;System;Xml;Data;Datasnap;Web;Soap; ^
  %PROJECT%

if %ERRORLEVEL% NEQ 0 (
    echo Build FAILED!
    exit /b %ERRORLEVEL%
)

echo Copying HTML Files...
copy /Y "src\UI\index.html" "Win32\Debug\index.html"
copy /Y "src\UI\explorer.html" "Win32\Debug\explorer.html"

echo Syncing Assets Folder...
if not exist "Win32\Debug\assets" mkdir "Win32\Debug\assets"
xcopy /E /I /Y "src\UI\assets" "Win32\Debug\assets"

echo Build and Asset Sync Success!
