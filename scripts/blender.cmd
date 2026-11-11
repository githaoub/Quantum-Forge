@echo off
rem Run a pipeline script inside Blender without needing blender.exe on PATH.
rem
rem A stock Windows install puts Blender under
rem   C:\Program Files\Blender Foundation\Blender <version>\
rem and adds nothing to PATH, so `blender --background --python ...` fails with
rem "not recognized". The version folder also changes on every upgrade, which is
rem why this resolves the newest one instead of hardcoding it.
rem
rem   scripts\blender.cmd build_models.py
rem   scripts\blender.cmd render_models.py
rem
rem Override the binary with BLENDER_EXE if it lives somewhere unusual.

setlocal
set "SCRIPT=%~1"
if "%SCRIPT%"=="" (
  echo usage: scripts\blender.cmd ^<script.py^> [extra args]
  echo   e.g. scripts\blender.cmd build_models.py
  exit /b 2
)
if not exist "%~dp0%SCRIPT%" (
  echo no such script: %~dp0%SCRIPT%
  exit /b 2
)

set "BLENDER=%BLENDER_EXE%"
if not defined BLENDER for /f "delims=" %%I in ('where blender 2^>nul') do if not defined BLENDER set "BLENDER=%%I"

if not defined BLENDER (
  rem /o-n sorts descending, so "Blender 5.2" is tried before "Blender 4.1".
  for /f "delims=" %%D in ('dir /b /ad /o-n "%ProgramFiles%\Blender Foundation\Blender*" 2^>nul') do (
    if not defined BLENDER if exist "%ProgramFiles%\Blender Foundation\%%D\blender.exe" (
      set "BLENDER=%ProgramFiles%\Blender Foundation\%%D\blender.exe"
    )
  )
)

if not defined BLENDER (
  for /f "delims=" %%D in ('dir /b /ad /o-n "%LOCALAPPDATA%\Programs\Blender Foundation\Blender*" 2^>nul') do (
    if not defined BLENDER if exist "%LOCALAPPDATA%\Programs\Blender Foundation\%%D\blender.exe" (
      set "BLENDER=%LOCALAPPDATA%\Programs\Blender Foundation\%%D\blender.exe"
    )
  )
)

if not defined BLENDER (
  echo Could not find blender.exe.
  echo Set BLENDER_EXE to its full path, e.g.
  echo   set BLENDER_EXE=C:\Program Files\Blender Foundation\Blender 5.2\blender.exe
  exit /b 1
)

echo [blender] %BLENDER%
"%BLENDER%" --background --python "%~dp0%SCRIPT%" %2 %3 %4 %5 %6 %7 %8 %9
exit /b %ERRORLEVEL%
