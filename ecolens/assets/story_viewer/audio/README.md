# EcoLens Story Viewer - Audio Assets

This folder contains ambient audio files for the immersive 360° experience.

## Required Audio Files

Place the following MP3 files in this folder:

1. **forest-dawn.mp3** - Dawn ambience (birds waking up, gentle morning sounds)
2. **forest-jungle.mp3** - Dense jungle ambience (insects, birds, rustling leaves)
3. **forest-peaceful.mp3** - Peaceful forest (gentle breeze, distant birds)

## Recommended Sources (CC0/Public Domain)

- [Pixabay](https://pixabay.com/sound-effects/) - Free sound effects, no attribution required
- [Freesound](https://freesound.org/) - CC0 sounds (search "forest ambience")
- [BBC Sound Effects](https://sound-effects.bbcrewind.co.uk/) - Royalty-free for non-commercial use
- [Mixkit](https://mixkit.co/free-sound-effects/) - Free sound effects

## Download Instructions

1. Visit one of the sources above
2. Search for "forest ambience" or "jungle sounds"
3. Download MP3 files (keep them under 2MB for faster loading)
4. Rename to match the expected filenames above
5. Rebuild the Flutter app to include the new assets

## Audio Specifications

- Format: MP3 (for best WebView compatibility)
- Bitrate: 128kbps recommended (balance of quality and size)
- Duration: 30-60 seconds (will loop)
- Size: Keep under 2MB per file

## Note

The app will gracefully continue without audio if these files are not present.
The visual 360° panorama experience works independently of audio.
