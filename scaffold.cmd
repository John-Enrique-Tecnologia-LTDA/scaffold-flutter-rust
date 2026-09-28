@echo off
rem Lançador no Windows: roda o binário pré-compilado de bin\. Para recompilar: build.sh (no WSL/Git Bash)
"%~dp0bin\scaffold-windows-x64.exe" %*
