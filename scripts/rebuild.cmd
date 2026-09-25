@echo off
rem Double-click or run from any shell: rebuilds the FinBot dev stack with no cache.
rem Flags pass straight through, e.g.  rebuild.cmd -WipeData  or  rebuild.cmd -WithLlm
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0rebuild.ps1" %*
