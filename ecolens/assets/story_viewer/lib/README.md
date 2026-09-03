# EcoLens Story Viewer - Local Libraries

This folder contains local copies of external libraries for WebView compatibility.

## Required Libraries

1. **pannellum.js** - 360° panorama viewer
   - Source: https://cdn.jsdelivr.net/npm/pannellum@2.5.6/build/pannellum.js

2. **pannellum.css** - Pannellum styles
   - Source: https://cdn.jsdelivr.net/npm/pannellum@2.5.6/build/pannellum.css

3. **howler.min.js** - Spatial audio library
   - Source: https://cdn.jsdelivr.net/npm/howler@2.2.4/dist/howler.min.js

## Download Instructions

Run this PowerShell script from this directory:

```powershell
# Download Pannellum
Invoke-WebRequest -Uri "https://cdn.jsdelivr.net/npm/pannellum@2.5.6/build/pannellum.js" -OutFile "pannellum.js"
Invoke-WebRequest -Uri "https://cdn.jsdelivr.net/npm/pannellum@2.5.6/build/pannellum.css" -OutFile "pannellum.css"

# Download Howler
Invoke-WebRequest -Uri "https://cdn.jsdelivr.net/npm/howler@2.2.4/dist/howler.min.js" -OutFile "howler.min.js"
```

Or use curl:

```bash
curl -o pannellum.js https://cdn.jsdelivr.net/npm/pannellum@2.5.6/build/pannellum.js
curl -o pannellum.css https://cdn.jsdelivr.net/npm/pannellum@2.5.6/build/pannellum.css
curl -o howler.min.js https://cdn.jsdelivr.net/npm/howler@2.2.4/dist/howler.min.js
```

## Why Local Copies?

Android WebView loading from `file://` protocol may block external CDN requests due to:
- Mixed content restrictions
- CORS policies
- Network security config

Local copies ensure the immersive 360° experience works reliably on all devices.
