@echo off
setlocal EnableExtensions
title ProjectR

rem === LOVE 실행 파일 경로 ===
set "LOVE_EXE=C:\Program Files\LOVE\love.exe"

rem === 이 BAT 파일이 있는 폴더 = 프로젝트 루트 ===
set "GAME_DIR=%~dp0"

rem 끝에 붙는 \ 제거 (LOVE 파싱 안정화)
if "%GAME_DIR:~-1%"=="\" set "GAME_DIR=%GAME_DIR:~0,-1%"

rem 경로 검증
if not exist "%LOVE_EXE%" (
    echo [ERROR] love.exe not found:
    echo %LOVE_EXE%
    pause
    exit /b
)

if not exist "%GAME_DIR%\main.lua" (
    echo [ERROR] main.lua not found in:
    echo %GAME_DIR%
    pause
    exit /b
)

rem 실행
"%LOVE_EXE%" "%GAME_DIR%"
