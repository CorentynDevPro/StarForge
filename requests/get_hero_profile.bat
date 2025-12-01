@echo off
rem get_hero_profile.bat - adaptation du script bash pour cmd (Windows)
rem Requirements: curl (fourni sur Windows 10+), PowerShell (pour lecture de mot de passe masqué et sanitization). jq est optionnel pour l'affichage/extractions.

setlocal

set "OUTDIR=gotest_outputs"
if not exist "%OUTDIR%" mkdir "%OUTDIR%"

set "URL=https://pcmob.parse.gemsofwar.com/call_function"
set "CLIENT_VER=8.9.0"

rem ---------- pretty_print : affiche proprement si jq est présent ----------
:pretty_print
set "f=%~1"
where jq >nul 2>&1
if %ERRORLEVEL%==0 (
  jq . "%f%" || type "%f%"
) else (
  echo (Installer jq pour afficher proprement : choco install jq ^| scoop install jq)
  type "%f%"
)
goto :eof

rem ---------- fetch_by_namecode ----------
:fetch_by_namecode
set "nc=%~1"
if "%nc%"=="" (
  echo NameCode vide. Abandon.
  goto :eof
)

rem sanitize le nom de fichier (remplace tout ce qui n'est pas A-Z a-z 0-9 _ . - par _ ) via PowerShell
for /f "usebackq delims=" %%S in (`powershell -NoProfile -Command "[regex]::Replace('%nc%','[^A-Za-z0-9_.-]','_')"`) do set "safe=%%S"

set "out=%OUTDIR%\get_hero_profile_%safe%.json"
set "hdr=%OUTDIR%\get_hero_profile_%safe%.http"

echo Récupération du profil pour NameCode=%nc% ...
for /f "usebackq delims=" %%H in (`curl -s -D "%hdr%" -H "Content-Type: application/json" -H "Accept: application/json" -H "User-Agent: Mozilla/5.0 (Windows) curl" -H "Origin: https://pcmob.parse.gemsofwar.com" -X POST -d "{\"functionName\":\"get_hero_profile\",\"clientVersion\":\"%CLIENT_VER%\",\"NameCode\":\"%nc%\"}" "%URL%" -o "%out%" -w "%%{http_code}"`) do set "http=%%H"

echo HTTP: %http%
echo Body: %out%
echo Headers: %hdr%
echo.
call :pretty_print "%out%"
goto :eof

rem ---------- do_login_and_fetch ----------
:do_login_and_fetch
set "user=%~1"
set "pass=%~2"
if "%user%"=="" (
  echo Username vide. Abandon.
  goto :eof
)
rem sanitize username for file name
for /f "usebackq delims=" %%S in (`powershell -NoProfile -Command "[regex]::Replace('%user%','[^A-Za-z0-9_.-]','_')"`) do set "safe=%%S"

set "login_out=%OUTDIR%\login_user_%safe%.json"
set "login_hdr=%OUTDIR%\login_user_%safe%.http"

echo Tentative de connexion pour username=%user% ...
for /f "usebackq delims=" %%H in (`curl -s -D "%login_hdr%" -H "Content-Type: application/json" -H "Accept: application/json" -H "User-Agent: Mozilla/5.0 (Windows) curl" -H "Origin: https://pcmob.parse.gemsofwar.com" -X POST -d "{\"functionName\":\"login_user\",\"username\":\"%user%\",\"password\":\"%pass%\",\"clientVersion\":\"%CLIENT_VER%\"}" "%URL%" -o "%login_out%" -w "%%{http_code}"`) do set "http=%%H"

echo HTTP: %http%
echo Login body: %login_out%
echo Login headers: %login_hdr%
echo.
call :pretty_print "%login_out%"
echo.

rem tenter d'extraire un NameCode si jq est présent
where jq >nul 2>&1
if %ERRORLEVEL%==0 (
  for /f "usebackq delims=" %%N in (`jq -r ".result.NameCode // .result.nameCode // .result.InviteCode // .result.inviteCode // .result.username // .result.user.NameCode // empty" "%login_out%" 2^>nul`) do set "namecode=%%N"
  if defined namecode (
    echo NameCode detecte dans la reponse de login: %namecode%
    echo.
    call :fetch_by_namecode "%namecode%"
    goto :eof
  ) else (
    echo Aucun NameCode detecte automatiquement dans la reponse de login.
    echo Ouvrez %login_out% pour inspecter la reponse.
    goto :eof
  )
) else (
  echo jq non trouve : impossible d'extraire automatiquement le NameCode depuis la reponse de login.
  echo Ouvrez %login_out% et cherchez le NameCode/InviteCode manuellement.
  goto :eof
)

rem ---------- usage ----------
:print_usage
echo Usage:
echo   %~nx0            ^-> demande l'Invite/NameCode
echo   %~nx0 --login    ^-> demande username puis password (interactif, mot de passe masqué)
echo   %~nx0 --help
goto :eof

rem ---------- main ----------
if "%~1"=="--help" (
  call :print_usage
  goto :eof
)

if "%~1"=="--login" (
  set /p "USERNAME=Username: "
  if "%USERNAME%"=="" (
    echo Username vide. Abandon.
    goto :eof
  )
  rem lire mot de passe en mode masqué via PowerShell
  for /f "usebackq delims=" %%P in (`powershell -NoProfile -Command "$p = Read-Host -AsSecureString -Prompt 'Password'; $B = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($p); [Runtime.InteropServices.Marshal]::PtrToStringAuto($B)"`) do set "PASSWORD=%%P"
  echo.
  if "%PASSWORD%"=="" (
    echo Password vide. Abandon.
    goto :eof
  )
  call :do_login_and_fetch "%USERNAME%" "%PASSWORD%"
  goto :eof
)

rem par défaut : demander Invite/NameCode
set /p "INV=Enter Invite/NameCode: "
if "%INV%"=="" (
  echo Aucun code fourni. Abandon.
  goto :eof
)
call :fetch_by_namecode "%INV%"

endlocal
exit /b 0
