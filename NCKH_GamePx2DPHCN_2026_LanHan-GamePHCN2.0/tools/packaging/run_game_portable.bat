@echo off
title Khoi dong Game Pixel 2D Phuc Hoi Chuc Nang
echo ========================================================
echo   KHOI DONG HE THONG GAME PIXEL 2D PHUC HOI CHUC NANG
echo   De tai NCKH - Tac gia: Nong Thi Hong Lan
echo ========================================================
echo.

cd /d "%~dp0"

echo [1/2] Dang kiem tra luong AI Backend...
if exist "ai_backend\ai_backend.exe" (
    echo       Da tim thay AI Backend dong goi san.
) else (
    echo [Canh bao] Chua tim thay thu muc ai_backend!
)

echo [2/2] Dang khoi dong Game...
start "" "GamePixel2D_PHCN.exe"

exit
