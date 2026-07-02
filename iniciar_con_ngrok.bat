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
  echo Cerrando proceso en puerto 3000 ^(PID %%p^)...
  taskkill /PID %%p /F >nul 2>&1
)
del "%TEMP%\mbs_port.tmp" >nul 2>&1
echo.

:: Iniciar ngrok en ventana separada
echo Iniciando ngrok...
start "ngrok - MBS" cmd /k "ngrok http --domain=underrate-silk-librarian.ngrok-free.dev 3000"

:: Esperar a que ngrok levante el tunel
timeout /t 3 /nobreak >nul

:: Iniciar servidor Node en ventana separada (cmd /k mantiene la ventana abierta si hay error)
echo Iniciando servidor Node...
start "Node - MBS Backend" cmd /k "cd /d "%~dp0mbs_backend" && node src/app.js"

echo.
echo Servidor iniciado correctamente.
echo - Backend : http://localhost:3000
echo - Publico : https://underrate-silk-librarian.ngrok-free.dev
echo.
echo Cierra las ventanas de ngrok y Node para detener el servidor.
echo.
pause
