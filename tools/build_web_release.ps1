# ========================================================
# SCRIPT TU DONG HOA EXPORT WEB VA DONG BO GH-PAGES
# Game Phuc Hoi Chuc Nang 2D - NCKH 2026 Lan & Han
# ========================================================

$ErrorActionPreference = "Stop"

$workspaceRoot = (Get-Item $PSScriptRoot).Parent.FullName
$godotExe = "D:\Lannn\1_NCKH\Godot_v4.7.2-stable_win64_console.exe"
if (-not (Test-Path $godotExe)) {
    $godotExe = "D:\Lannn\1_NCKH\Godot_v4.7.2-stable_win64.exe"
}
if (-not (Test-Path $godotExe)) {
    Write-Error "Khong tim thay Godot 4.7.2 tai D:\Lannn\1_NCKH\Godot_v4.7.2-stable_win64_console.exe!"
    exit 1
}

$projectPath = Join-Path $workspaceRoot "NCKH_GamePx2DPHCN_2026_LanHan-GamePHCN2.0"
$exportDir = Join-Path $workspaceRoot "web_release_system\github_pages_frontend"
$exportHtml = Join-Path $exportDir "game.html"
$indexHtml = Join-Path $exportDir "index.html"

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "1. DANG EXPORT GODOT WEB RELEASE..." -ForegroundColor Yellow
Write-Host "   Godot: $godotExe"
Write-Host "   Project: $projectPath"
Write-Host "   Output: $exportHtml"
Write-Host "====================================================" -ForegroundColor Cyan

& $godotExe --headless --path "$projectPath" --export-release "Web" "$exportHtml"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Godot Export that bai voi ma loi: $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Host ">> Export thanh cong!" -ForegroundColor Green

# Cap nhat dung dung luong file game.pck vao index.html
$pckFile = Join-Path $exportDir "game.pck"
if (Test-Path $pckFile) {
    $pckLength = (Get-Item $pckFile).Length
    $content = Get-Content -Raw -Encoding UTF8 $indexHtml
    $updated = $content -replace '"game\.pck":\s*\d+', "`"game.pck`": $pckLength"
    Set-Content -Path $indexHtml -Value $updated -Encoding UTF8
    Write-Host ">> Da dong bo fileSizes trong index.html: game.pck = $pckLength bytes" -ForegroundColor Green
}

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "HOAN TAT XUAT BAN! Nhap cac lenh sau de push len GitHub:" -ForegroundColor Green
Write-Host "   git add -A" -ForegroundColor White
Write-Host "   git commit -m 'Release: Web App PoseProvider & Internal Camera'" -ForegroundColor White
Write-Host "   git push origin main" -ForegroundColor White
Write-Host "   git subtree push --prefix web_release_system/github_pages_frontend origin gh-pages" -ForegroundColor White
Write-Host "====================================================" -ForegroundColor Cyan
