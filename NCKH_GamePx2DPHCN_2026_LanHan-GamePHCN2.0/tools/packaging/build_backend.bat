@echo off
title Dong goi AI Backend sang EXE (PyInstaller)
echo ========================================================
echo   BAT DAU DONG GOI AI BACKEND PYTHON THANH FILE THUC THI
echo ========================================================
echo.

cd /d "%~dp0\..\.."

echo [1/3] Kiem tra file pose_landmarker_full.task...
if not exist "pose_landmarker_full.task" (
    echo [Loi] Khong tim thay file pose_landmarker_full.task trong thu muc goc!
    pause
    exit /b 1
)

echo [2/3] Dang thuc thi PyInstaller dong goi Backend (khoang 1-2 phut)...
pyinstaller --noconfirm --onedir --console --add-data "pose_landmarker_full.task;." --exclude-module torch --exclude-module torchvision --exclude-module scipy --exclude-module pandas --exclude-module matplotlib --exclude-module jedi --exclude-module tkinter --distpath "build\dist" --workpath "build\work" --name ai_backend main.py

if %ERRORLEVEL% NEQ 0 (
    echo [Loi] PyInstaller dong goi that bai!
    pause
    exit /b 1
)

echo [3/3] Sao chep model file vao thu muc build...
copy /Y "pose_landmarker_full.task" "build\dist\ai_backend\pose_landmarker_full.task" >nul
del /Q "build\work" >nul 2>&1

echo.
echo ========================================================
echo   DONG GOI AI BACKEND THANH CONG!
echo   Thu muc ket qua tai: build\dist\ai_backend
echo ========================================================
echo.
pause
