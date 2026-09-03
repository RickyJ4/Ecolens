# EcoLens Story Viewer - Library Downloader
# Downloads Pannellum and Howler libraries for local WebView use

Write-Host "Downloading Pannellum 360 viewer..." -ForegroundColor Cyan
Invoke-WebRequest -Uri "https://cdn.jsdelivr.net/npm/pannellum@2.5.6/build/pannellum.js" -OutFile "pannellum.js"
Write-Host "  pannellum.js downloaded" -ForegroundColor Green

Invoke-WebRequest -Uri "https://cdn.jsdelivr.net/npm/pannellum@2.5.6/build/pannellum.css" -OutFile "pannellum.css"
Write-Host "  pannellum.css downloaded" -ForegroundColor Green

Write-Host "Downloading Howler.js spatial audio..." -ForegroundColor Cyan
Invoke-WebRequest -Uri "https://cdn.jsdelivr.net/npm/howler@2.2.4/dist/howler.min.js" -OutFile "howler.min.js"
Write-Host "  howler.min.js downloaded" -ForegroundColor Green

Write-Host ""
Write-Host "All libraries downloaded successfully!" -ForegroundColor Green
Write-Host "The story viewer will now use local copies for immersive mode." -ForegroundColor White
