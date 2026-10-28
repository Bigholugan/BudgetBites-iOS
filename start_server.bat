@echo off
title BudgetBites iOS Server
echo ========================================================
echo   BudgetBites iOS - Instant Safari Web Clip / PWA
echo ========================================================
echo.
echo 1. Ensure your iPhone is on the same Wi-Fi network.
echo 2. Open Safari on your iPhone and visit:
echo.
echo      http://192.168.1.218:8080
echo.
echo 3. Tap the Share button (square with arrow) at bottom.
echo 4. Tap "Add to Home Screen".
echo.
echo Server is running... (Press Ctrl+C to stop)
echo ========================================================
cd /d "%~dp0Sources\BudgetBites\Resources\www"
python -m http.server 8080
