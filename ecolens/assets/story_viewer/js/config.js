/**
 * EcoLens Story Viewer - Configuration
 * Global configuration, tokens, and constants
 */

const EcoLensConfig = {
    // Cesium ion access token. Kept out of the repository: copy js/keys.example.js to
    // js/keys.js (gitignored). The token ships to browsers, so scope it to the assets
    // this viewer needs in your Cesium ion account.
    cesiumToken: (window.ECOLENS_KEYS && window.ECOLENS_KEYS.cesiumIon) || '',

    // Default location (Amazon Basin)
    defaultLocation: {
        lat: -3.4653,
        lng: -62.2159,
        name: 'Amazon Rainforest'
    },

    // Camera settings
    camera: {
        defaultAltitude: 50000,
        minAltitude: 500,
        maxAltitude: 2000000,
        flyDuration: 3,
        freeLookResumeDelay: 5000 // ms before resuming scripted camera
    },

    // Chapter timing (seconds)
    chapterDurations: {
        arrival: 6,
        discovery: 10,
        temporal: 12,
        impact: 8,
        restoration: 8
    },

    // Visual effects
    effects: {
        ndviColorRamp: [
            { value: -0.5, color: [165, 0, 38, 200] },   // Red - no vegetation
            { value: 0,    color: [253, 174, 97, 200] }, // Orange - stressed
            { value: 0.3,  color: [255, 255, 191, 200]}, // Yellow - moderate
            { value: 0.5,  color: [166, 217, 106, 200]}, // Light green - healthy
            { value: 0.8,  color: [26, 152, 80, 200] }   // Dark green - dense
        ],
        deforestationColor: [218, 54, 51, 128], // #DA3633 with alpha
        restorationColor: [86, 211, 100, 128]   // #56D364 with alpha
    },

    // Risk level thresholds
    riskLevels: {
        critical: { min: 80, color: '#DA3633' },
        high:     { min: 60, color: '#DB6D28' },
        moderate: { min: 40, color: '#DBAB09' },
        low:      { min: 0,  color: '#56D364' }
    },

    // Species icons by category
    speciesIcons: {
        mammal: '/assets/icons/mammal.png',
        bird: '/assets/icons/bird.png',
        reptile: '/assets/icons/reptile.png',
        fish: '/assets/icons/fish.png',
        plant: '/assets/icons/plant.png',
        default: '/assets/icons/species.png'
    },

    // Soundscape URLs (Mixkit CDN)
    soundscapes: {
        healthy_forest: 'https://assets.mixkit.co/music/preview/mixkit-forest-birds-ambience-1210.mp3',
        deforested: 'https://assets.mixkit.co/music/preview/mixkit-wind-blowing-through-leaves-528.mp3',
        dawn: 'https://assets.mixkit.co/music/preview/mixkit-morning-birds-2472.mp3',
        night: 'https://assets.mixkit.co/music/preview/mixkit-crickets-and-insects-in-the-wild-ambience-39.mp3'
    }
};

// Make globally available
window.EcoLensConfig = EcoLensConfig;
