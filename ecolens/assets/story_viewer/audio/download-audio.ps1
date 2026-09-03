# EcoLens Story Viewer - Audio Download Script
# Downloads sample forest ambience audio for the immersive 360° experience
#
# Note: These are placeholder URLs. Replace with actual CC0 audio sources.
# Recommended: Download manually from Pixabay or Freesound for best quality.

$audioDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "EcoLens Audio Download Script" -ForegroundColor Green
Write-Host "=============================" -ForegroundColor Green
Write-Host ""
Write-Host "This script helps you set up audio for the immersive 360° experience."
Write-Host ""
Write-Host "RECOMMENDED: Download audio manually from these sources:" -ForegroundColor Yellow
Write-Host "  1. Pixabay: https://pixabay.com/sound-effects/search/forest/" -ForegroundColor Cyan
Write-Host "  2. Freesound: https://freesound.org/search/?q=forest+ambience" -ForegroundColor Cyan
Write-Host "  3. Mixkit: https://mixkit.co/free-sound-effects/nature/" -ForegroundColor Cyan
Write-Host ""
Write-Host "Required files:" -ForegroundColor Yellow
Write-Host "  - forest-dawn.mp3    (morning birds, sunrise ambience)" -ForegroundColor White
Write-Host "  - forest-jungle.mp3  (dense jungle, insects, birds)" -ForegroundColor White
Write-Host "  - forest-peaceful.mp3 (calm forest, gentle breeze)" -ForegroundColor White
Write-Host ""
Write-Host "Place the downloaded files in: $audioDir" -ForegroundColor Green
Write-Host ""

# Check if files exist
$files = @("forest-dawn.mp3", "forest-jungle.mp3", "forest-peaceful.mp3")
$missing = @()

foreach ($file in $files) {
    $path = Join-Path $audioDir $file
    if (Test-Path $path) {
        Write-Host "  [OK] $file" -ForegroundColor Green
    } else {
        Write-Host "  [MISSING] $file" -ForegroundColor Red
        $missing += $file
    }
}

Write-Host ""

if ($missing.Count -eq 0) {
    Write-Host "All audio files are present!" -ForegroundColor Green
    Write-Host "Rebuild your Flutter app to include the audio assets." -ForegroundColor Yellow
} else {
    Write-Host "$($missing.Count) file(s) missing. Download from the sources above." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "NOTE: The app will work without audio - the 360° panoramas" -ForegroundColor Cyan
    Write-Host "will still display and function correctly." -ForegroundColor Cyan
}

Write-Host ""
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
