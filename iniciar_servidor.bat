@echo off
title MBS Comunicaciones - Servidor
echo ==========================================
echo   MBS Comunicaciones - Iniciando servidor
echo ==========================================
cd /d "%~dp0mbs_backend"
echo Directorio: %CD%
echo.
echo Iniciando servidor en http://localhost:3000
echo Presiona Ctrl+C para detener.
echo.
node src/app.js
pause
