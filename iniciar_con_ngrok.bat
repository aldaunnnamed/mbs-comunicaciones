@echo off
title MBS Comunicaciones - Servidor + ngrok
echo ==========================================
echo   MBS Comunicaciones - Modo ngrok (HTTPS)
echo ==========================================
echo.
echo URL publica: https://underrate-silk-librarian.ngrok-free.dev
echo.

:: Liberar puerto 3000 si ya esta ocupado
echo Verificando puerto 3000...
netstat -ano | findstr ":3000" | findstr "LISTENING" > "%TEMP%\mbs_port.tmp" 2>nul
for /f "tokens=5" %%p in (%TEMP%\mbs_port.tmp) do (
  echo Cerrando proceso en puerto 3000 (PID %%p)...
  taskkill /PID %%p /F >nul 2>&1
)
del "%TEMP%\mbs_port.tmp" >nul 2>&1

:: Iniciar ngrok en una ventana separada
start "ngrok - MBS Comunicaciones" cmd /k "ngrok http --domain=underrate-silk-librarian.ngrok-free.dev 3000"

:: Esperar 3 segundos a que ngrok levante el tunel
timeout /t 3 /nobreak >nul

:: Iniciar el servidor Node
cd /d "%~dp0mbs_backend"
echo Iniciando servidor Node en puerto 3000...
echo Presiona Ctrl+C para detener.
echo.
node src/app.js
pause
