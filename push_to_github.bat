@echo off
title Push BudgetBites to GitHub
echo ========================================================
echo   Pushing BudgetBites-iOS to GitHub
echo ========================================================
echo.
cd /d "%~dp0"
git push -u origin main
echo.
if %ERRORLEVEL% equ 0 (
    echo ========================================================
    echo   SUCCESS! The project was pushed to GitHub!
    echo   The cloud build is now running automatically at:
    echo   https://github.com/Bigholugan/BudgetBites-iOS/actions
    echo ========================================================
) else (
    echo ========================================================
    echo   Push failed. Please check the error message above.
    echo ========================================================
)
pause
