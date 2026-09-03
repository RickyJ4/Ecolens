/* ============================================================
   EcoLens - Historical Event Evidence
   Localized geometry and story beats for event reconstructions.

   These geometries are intentionally lightweight so the map can run
   offline from bundled assets. They are simplified local evidence
   footprints and affected-place anchors, not official survey polygons.
   ============================================================ */

window.HistoricalEventEvidence = {
    'camp-fire-2018': {
        evidenceQuality: 'localized',
        evidenceLabel: 'Local perimeter and town impacts',
        evidenceNote: 'Simplified footprint around the Camp Fire burn area with documented ignition and affected communities.',
        story: 'This reconstruction is centered on the Camp Fire footprint in Butte County: ignition near Pulga, rapid spread through the Feather River canyon, and catastrophic urban loss in Concow, Paradise, and Magalia. The key local story is not a generic California fire; it is a wind-driven canyon-to-town disaster where evacuation routes, power infrastructure, and the wildland-urban edge all overlapped.',
        localImpacts: [
            'Ignition area near Pulga and Camp Creek Road.',
            'Concow and Paradise sat inside the fast-moving burn corridor.',
            'Skyway, Clark Road, and Pentz Road became critical evacuation routes.',
            'The mapped footprint shows the local burn area instead of a generic radius.'
        ],
        timeline: [
            { progress: 0.00, date: '2018-11-08 06:33', label: 'Ignition reported near Pulga', note: 'Wind pushed fire west from the Feather River canyon.' },
            { progress: 0.22, date: '2018-11-08 morning', label: 'Concow impact corridor', note: 'Fire entered communities before many residents could leave.' },
            { progress: 0.46, date: '2018-11-08 afternoon', label: 'Paradise urban core burned', note: 'Structure loss concentrated inside the town footprint.' },
            { progress: 0.72, date: '2018-11-10', label: 'Perimeter expansion and suppression', note: 'Containment focused around the Butte County fire edge.' },
            { progress: 1.00, date: '2018-11-25', label: '100 percent contained', note: 'Recovery shifted to debris removal, rebuilding, and watershed risk.' }
        ],
        focusGeometry: {
            type: 'FeatureCollection',
            features: [
                {
                    type: 'Feature',
                    geometry: {
                        type: 'Polygon',
                        coordinates: [[
                            [-121.505, 39.947],
                            [-121.365, 39.956],
                            [-121.270, 39.885],
                            [-121.307, 39.785],
                            [-121.438, 39.715],
                            [-121.603, 39.724],
                            [-121.664, 39.805],
                            [-121.604, 39.905],
                            [-121.505, 39.947]
                        ]]
                    },
                    properties: { name: 'Camp Fire simplified burn footprint', role: 'footprint' }
                },
                {
                    type: 'Feature',
                    geometry: {
                        type: 'LineString',
                        coordinates: [
                            [-121.4370, 39.8102],
                            [-121.525, 39.759],
                            [-121.610, 39.759],
                            [-121.585, 39.813]
                        ]
                    },
                    properties: { name: 'Fire spread and community impact corridor', role: 'corridor' }
                },
                { type: 'Feature', geometry: { type: 'Point', coordinates: [-121.4370, 39.8102] }, properties: { name: 'Pulga ignition area', role: 'origin' } },
                { type: 'Feature', geometry: { type: 'Point', coordinates: [-121.526, 39.759] }, properties: { name: 'Concow', role: 'community' } },
                { type: 'Feature', geometry: { type: 'Point', coordinates: [-121.621, 39.759] }, properties: { name: 'Paradise', role: 'community' } },
                { type: 'Feature', geometry: { type: 'Point', coordinates: [-121.579, 39.812] }, properties: { name: 'Magalia', role: 'community' } }
            ]
        },
        fitFootprint: true,
        maxFocusZoom: 11.4
    },

    'maui-lahaina-2023': {
        evidenceQuality: 'localized',
        evidenceLabel: 'Lahaina town impact area',
        evidenceNote: 'Simplified Lahaina urban burn footprint and documented local landmarks.',
        story: 'This event is pinned to Lahaina itself: the coastal town footprint, Front Street, Lahaina Harbor, and the upslope evacuation corridors that were exposed to high winds and rapid fire spread. The purpose is to show where the disaster happened in town rather than flying over Maui in general.',
        localImpacts: [
            'The local burn footprint follows Lahaina town, not the whole island.',
            'Front Street and Lahaina Harbor are marked as affected landmarks.',
            'Upslope neighborhoods and road corridors are included as evidence anchors.'
        ],
        timeline: [
            { progress: 0.00, date: '2023-08-08 morning', label: 'High-wind fire conditions', note: 'Dry fuels and damaging winds elevated fire spread risk.' },
            { progress: 0.35, date: '2023-08-08 afternoon', label: 'Fire enters Lahaina town', note: 'Urban impacts concentrate along the coastal settlement.' },
            { progress: 0.65, date: '2023-08-08 evening', label: 'Harbor and Front Street corridor impacted', note: 'Historic district and waterfront losses become visible.' },
            { progress: 1.00, date: '2023-08-11', label: 'Suppression and search phase', note: 'Response turns to recovery, damage assessment, and shelter.' }
        ],
        focusGeometry: {
            type: 'FeatureCollection',
            features: [
                {
                    type: 'Feature',
                    geometry: {
                        type: 'Polygon',
                        coordinates: [[
                            [-156.703, 20.891],
                            [-156.676, 20.895],
                            [-156.657, 20.878],
                            [-156.665, 20.862],
                            [-156.690, 20.866],
                            [-156.710, 20.879],
                            [-156.703, 20.891]
                        ]]
                    },
                    properties: { name: 'Lahaina simplified urban burn footprint', role: 'footprint' }
                },
                { type: 'Feature', geometry: { type: 'Point', coordinates: [-156.6825, 20.8783] }, properties: { name: 'Lahaina historic district', role: 'community' } },
                { type: 'Feature', geometry: { type: 'Point', coordinates: [-156.6787, 20.8725] }, properties: { name: 'Lahaina Harbor', role: 'landmark' } },
                { type: 'Feature', geometry: { type: 'Point', coordinates: [-156.6740, 20.8860] }, properties: { name: 'Lahainaluna Road corridor', role: 'corridor' } }
            ]
        },
        fitFootprint: true,
        maxFocusZoom: 13.4
    },

    'ahr-valley-2021': {
        evidenceQuality: 'localized',
        evidenceLabel: 'Ahr River flood corridor',
        evidenceNote: 'Simplified river-corridor geometry through the documented flash-flood communities.',
        story: 'The Ahr Valley flood is shown as a river-corridor disaster. The map follows the Ahr through Schuld, Altenahr, Mayschoss, Bad Neuenahr-Ahrweiler, and Sinzig, where narrow valley geometry and extreme rainfall turned channel flooding into a settlement-scale disaster.',
        localImpacts: [
            'The event layer follows the Ahr River corridor rather than a circular flood zone.',
            'Affected towns are labeled along the valley.',
            'The timeline emphasizes the short rainfall-to-flood response window.'
        ],
        timeline: [
            { progress: 0.00, date: '2021-07-14', label: 'Extreme rainfall begins', note: 'Rainfall accumulated over steep catchments feeding the Ahr.' },
            { progress: 0.30, date: '2021-07-14 night', label: 'Rapid river rise', note: 'Flash-flood conditions moved downstream through narrow valley towns.' },
            { progress: 0.62, date: '2021-07-15', label: 'Town corridor inundation', note: 'Damage clustered along the river, bridges, roads, and valley-floor buildings.' },
            { progress: 1.00, date: '2021-07-16', label: 'Floodwaters recede', note: 'Recovery shifted to debris, infrastructure, and warning-system review.' }
        ],
        focusGeometry: {
            type: 'FeatureCollection',
            features: [
                {
                    type: 'Feature',
                    geometry: {
                        type: 'LineString',
                        coordinates: [
                            [6.889, 50.447],
                            [6.965, 50.463],
                            [7.018, 50.482],
                            [7.061, 50.502],
                            [7.104, 50.543],
                            [7.190, 50.548]
                        ]
                    },
                    properties: { name: 'Ahr River flood corridor', role: 'corridor' }
                },
                {
                    type: 'Feature',
                    geometry: {
                        type: 'Polygon',
                        coordinates: [[
                            [6.865, 50.432],
                            [6.986, 50.447],
                            [7.090, 50.500],
                            [7.215, 50.537],
                            [7.201, 50.566],
                            [7.078, 50.535],
                            [6.952, 50.485],
                            [6.865, 50.432]
                        ]]
                    },
                    properties: { name: 'Simplified valley impact envelope', role: 'footprint' }
                },
                { type: 'Feature', geometry: { type: 'Point', coordinates: [6.889, 50.447] }, properties: { name: 'Schuld', role: 'community' } },
                { type: 'Feature', geometry: { type: 'Point', coordinates: [6.965, 50.463] }, properties: { name: 'Altenahr', role: 'community' } },
                { type: 'Feature', geometry: { type: 'Point', coordinates: [7.061, 50.502] }, properties: { name: 'Mayschoss', role: 'community' } },
                { type: 'Feature', geometry: { type: 'Point', coordinates: [7.104, 50.543] }, properties: { name: 'Bad Neuenahr-Ahrweiler', role: 'community' } }
            ]
        },
        fitFootprint: true,
        maxFocusZoom: 11.7
    },

    'pakistan-floods-2022': {
        evidenceQuality: 'regional',
        evidenceLabel: 'Sindh floodplain case area',
        evidenceNote: 'Regional Indus floodplain case geometry; flood extent varied through the 2022 monsoon season.',
        story: 'This case focuses on the Sindh and lower Indus floodplain, where prolonged monsoon flooding connected river overflow, standing water, roads, farms, and displacement around Dadu, Jacobabad, and Lake Manchar. It is a regional floodplain reconstruction, not a single-point flood.',
        localImpacts: [
            'Lower Indus floodplain envelope is mapped instead of a single point.',
            'Dadu, Jacobabad, and Lake Manchar are marked as local evidence anchors.',
            'The timeline separates monsoon onset, peak inundation, and slow drainage.'
        ],
        timeline: [
            { progress: 0.00, date: '2022-06-14', label: 'Monsoon flood season begins', note: 'Rainfall and river levels begin compounding across Pakistan.' },
            { progress: 0.42, date: '2022-08-26', label: 'Lower Indus floodplain expands', note: 'Large areas of Sindh hold standing water.' },
            { progress: 0.72, date: '2022-09-10', label: 'Lake Manchar and Dadu pressure', note: 'Drainage, displacement, and infrastructure impacts intensify.' },
            { progress: 1.00, date: '2022-10-01', label: 'Slow recession and recovery', note: 'Water remains in low-lying areas after rainfall peaks.' }
        ],
        focusGeometry: {
            type: 'FeatureCollection',
            features: [
                {
                    type: 'Feature',
                    geometry: {
                        type: 'Polygon',
                        coordinates: [[
                            [67.05, 25.05],
                            [68.75, 25.20],
                            [69.10, 27.85],
                            [68.35, 29.05],
                            [67.18, 28.58],
                            [66.72, 26.72],
                            [67.05, 25.05]
                        ]]
                    },
                    properties: { name: 'Lower Indus floodplain case area', role: 'footprint' }
                },
                { type: 'Feature', geometry: { type: 'Point', coordinates: [68.300, 26.730] }, properties: { name: 'Dadu', role: 'community' } },
                { type: 'Feature', geometry: { type: 'Point', coordinates: [68.438, 28.281] }, properties: { name: 'Jacobabad', role: 'community' } },
                { type: 'Feature', geometry: { type: 'Point', coordinates: [67.663, 26.438] }, properties: { name: 'Lake Manchar', role: 'landmark' } }
            ]
        },
        fitFootprint: true,
        maxFocusZoom: 8.5
    },

    'amazon-deforestation-2019': {
        evidenceQuality: 'localized',
        evidenceLabel: 'Para forest-loss frontier',
        evidenceNote: 'Representative Para frontier geometry around the selected deforestation case area.',
        story: 'This reconstruction stays on the Para forest-loss frontier rather than treating the whole Amazon as one event. The map highlights a road-edge clearing pattern: access corridors, rectangular pasture conversion, habitat fragmentation, and carbon loss radiating from settlement and transport routes.',
        localImpacts: [
            'The footprint follows a deforestation frontier case area in Para.',
            'Access-road style fragmentation is marked as the local pattern.',
            'The story focuses on clearing expansion, not a single disaster point.'
        ],
        timeline: [
            { progress: 0.00, date: '2019', label: 'Frontier clearing baseline', note: 'Forest edge and access corridors already visible.' },
            { progress: 0.35, date: '2020', label: 'Clearing expands from roads', note: 'Pasture and bare-soil patches increase along the frontier.' },
            { progress: 0.68, date: '2021', label: 'Peak annual loss period', note: 'Fragmentation and fire-linked clearing intensify.' },
            { progress: 1.00, date: '2023', label: 'Landscape fragmentation visible', note: 'Remaining forest is split by a larger cleared matrix.' }
        ],
        focusGeometry: {
            type: 'FeatureCollection',
            features: [
                {
                    type: 'Feature',
                    geometry: {
                        type: 'Polygon',
                        coordinates: [[
                            [-55.38, -5.55],
                            [-54.48, -5.55],
                            [-54.32, -4.82],
                            [-55.28, -4.72],
                            [-55.58, -5.12],
                            [-55.38, -5.55]
                        ]]
                    },
                    properties: { name: 'Para deforestation frontier case area', role: 'footprint' }
                },
                {
                    type: 'Feature',
                    geometry: {
                        type: 'LineString',
                        coordinates: [
                            [-55.50, -5.18],
                            [-55.15, -5.09],
                            [-54.84, -5.03],
                            [-54.45, -4.96]
                        ]
                    },
                    properties: { name: 'Access corridor and clearing edge', role: 'corridor' }
                },
                { type: 'Feature', geometry: { type: 'Point', coordinates: [-54.95, -5.15] }, properties: { name: 'Selected frontier focus', role: 'origin' } }
            ]
        },
        fitFootprint: true,
        maxFocusZoom: 9.4
    },

    'jakobshavn-glacier': {
        evidenceQuality: 'localized',
        evidenceLabel: 'Glacier front retreat transect',
        evidenceNote: 'Simplified retreat transect and fjord focus area for Jakobshavn Isbrae.',
        story: 'The Jakobshavn case is mapped as an ice-front retreat story. The evidence layer marks the fjord, retreat transect, and glacier-front positions so the change reads as a place-specific loss of ice geometry, not a generic Arctic flyover.',
        localImpacts: [
            'Retreat transect points are shown along the glacier-fjord axis.',
            'The focus area covers Jakobshavn Isbrae and Ilulissat Icefjord.',
            'Timeline labels emphasize front retreat and ice dynamics.'
        ],
        timeline: [
            { progress: 0.00, date: '2000', label: 'Earlier glacier front position', note: 'Terminus position near the outer fjord baseline.' },
            { progress: 0.45, date: '2010', label: 'Accelerated retreat phase', note: 'Ice-front retreat and speed changes become pronounced.' },
            { progress: 1.00, date: '2020', label: 'Retreated front and fjord exposure', note: 'More fjord water is exposed along the glacier axis.' }
        ],
        focusGeometry: {
            type: 'FeatureCollection',
            features: [
                {
                    type: 'Feature',
                    geometry: {
                        type: 'Polygon',
                        coordinates: [[
                            [-50.20, 69.02],
                            [-49.45, 69.05],
                            [-49.36, 69.32],
                            [-50.05, 69.34],
                            [-50.20, 69.02]
                        ]]
                    },
                    properties: { name: 'Jakobshavn fjord focus area', role: 'footprint' }
                },
                {
                    type: 'Feature',
                    geometry: {
                        type: 'LineString',
                        coordinates: [
                            [-50.02, 69.12],
                            [-49.84, 69.17],
                            [-49.66, 69.21],
                            [-49.50, 69.24]
                        ]
                    },
                    properties: { name: 'Glacier retreat transect', role: 'corridor' }
                },
                { type: 'Feature', geometry: { type: 'Point', coordinates: [-49.83, 69.17] }, properties: { name: 'Jakobshavn Isbrae front', role: 'origin' } }
            ]
        },
        fitFootprint: true,
        maxFocusZoom: 10.2
    },

    'gangotri-glacier': {
        evidenceQuality: 'localized',
        evidenceLabel: 'Gangotri snout retreat transect',
        evidenceNote: 'Simplified glacier snout retreat line near Gomukh and Gangotri Glacier.',
        story: 'The Gangotri case is centered on the glacier snout and the retreat path near Gomukh. The map marks the retreat transect instead of treating the Himalaya as a scenic backdrop, tying the story to the headwaters landscape that feeds the Ganges system.',
        localImpacts: [
            'Gomukh and the snout retreat path are marked as local anchors.',
            'The focus area follows the glacier valley, not a circular buffer.',
            'The timeline links ice retreat to downstream water timing and hazard risk.'
        ],
        timeline: [
            { progress: 0.00, date: '1993', label: 'Earlier snout position', note: 'Retreat measurement begins from an older terminus position.' },
            { progress: 0.55, date: '2010', label: 'Ongoing retreat', note: 'The terminus pulls farther up-valley.' },
            { progress: 1.00, date: '2021', label: 'Recent mapped snout position', note: 'Retreat affects headwater timing and local slope stability.' }
        ],
        focusGeometry: {
            type: 'FeatureCollection',
            features: [
                {
                    type: 'Feature',
                    geometry: {
                        type: 'LineString',
                        coordinates: [
                            [79.075, 30.915],
                            [79.125, 30.918],
                            [79.170, 30.920],
                            [79.222, 30.928]
                        ]
                    },
                    properties: { name: 'Gangotri retreat transect', role: 'corridor' }
                },
                {
                    type: 'Feature',
                    geometry: {
                        type: 'Polygon',
                        coordinates: [[
                            [79.045, 30.880],
                            [79.260, 30.890],
                            [79.270, 30.965],
                            [79.060, 30.955],
                            [79.045, 30.880]
                        ]]
                    },
                    properties: { name: 'Gangotri glacier valley focus area', role: 'footprint' }
                },
                { type: 'Feature', geometry: { type: 'Point', coordinates: [79.075, 30.915] }, properties: { name: 'Gomukh older snout area', role: 'origin' } },
                { type: 'Feature', geometry: { type: 'Point', coordinates: [79.170, 30.920] }, properties: { name: 'Recent snout focus', role: 'landmark' } }
            ]
        },
        fitFootprint: true,
        maxFocusZoom: 11.5
    },

    'us-megadrought-2020': {
        evidenceQuality: 'regional',
        evidenceLabel: 'Lake Mead drought indicator area',
        evidenceNote: 'Regional drought case focused on Lake Mead as a visible water-level indicator.',
        story: 'The western megadrought is too broad for one perimeter, so this case uses Lake Mead as the local evidence window. The map focuses on the reservoir basin where declining levels were visible, measurable, and tied to Colorado River water stress.',
        localImpacts: [
            'Lake Mead is used as a local indicator rather than drawing the entire western drought area.',
            'Hoover Dam and exposed reservoir margins are marked as context anchors.',
            'The timeline tracks drought severity and reservoir-level stress.'
        ],
        timeline: [
            { progress: 0.00, date: '2020', label: 'Dry conditions deepen', note: 'Exceptional drought expands across the region.' },
            { progress: 0.55, date: '2021', label: 'Lake Mead declines', note: 'Reservoir storage and water-supply pressure become highly visible.' },
            { progress: 1.00, date: '2022', label: 'Record-low indicator period', note: 'Drought impacts compound with heat and water demand.' }
        ],
        focusGeometry: {
            type: 'FeatureCollection',
            features: [
                {
                    type: 'Feature',
                    geometry: {
                        type: 'Polygon',
                        coordinates: [[
                            [-114.98, 35.84],
                            [-114.50, 35.86],
                            [-114.44, 36.32],
                            [-114.93, 36.34],
                            [-114.98, 35.84]
                        ]]
                    },
                    properties: { name: 'Lake Mead drought indicator area', role: 'footprint' }
                },
                { type: 'Feature', geometry: { type: 'Point', coordinates: [-114.737, 36.016] }, properties: { name: 'Hoover Dam', role: 'landmark' } },
                { type: 'Feature', geometry: { type: 'Point', coordinates: [-114.700, 36.120] }, properties: { name: 'Lake Mead reservoir', role: 'landmark' } }
            ]
        },
        fitFootprint: true,
        maxFocusZoom: 9.8
    },

    'black-summer-2019': {
        evidenceQuality: 'regional',
        evidenceLabel: 'NSW South Coast fireground case',
        evidenceNote: 'Representative Black Summer case area in the NSW South Coast firegrounds.',
        story: 'Black Summer was a continental-scale fire season, so this map uses a specific NSW South Coast fireground as the evidence window. It marks the Bega Valley and coastal settlement corridor where fire, smoke, evacuation, and habitat impacts were locally visible.',
        localImpacts: [
            'The mapped case focuses on one South Coast fireground rather than all of Australia.',
            'Bega Valley and coastal evacuation context are marked.',
            'The story avoids pretending a national fire season has one precise perimeter.'
        ],
        timeline: [
            { progress: 0.00, date: '2019-09', label: 'Fire season escalates', note: 'Dry fuels and heat build across southeast Australia.' },
            { progress: 0.48, date: '2019-12', label: 'South Coast firegrounds expand', note: 'Communities, forests, and road corridors are exposed.' },
            { progress: 0.82, date: '2020-01', label: 'Peak smoke and evacuation impacts', note: 'Regional habitat and settlement impacts intensify.' },
            { progress: 1.00, date: '2020-03', label: 'Season ends', note: 'Recovery and ecological assessment continue.' }
        ],
        focusGeometry: {
            type: 'FeatureCollection',
            features: [
                {
                    type: 'Feature',
                    geometry: {
                        type: 'Polygon',
                        coordinates: [[
                            [149.38, -37.28],
                            [150.18, -37.20],
                            [150.12, -36.48],
                            [149.32, -36.55],
                            [149.38, -37.28]
                        ]]
                    },
                    properties: { name: 'NSW South Coast fireground case area', role: 'footprint' }
                },
                { type: 'Feature', geometry: { type: 'Point', coordinates: [149.84, -36.67] }, properties: { name: 'Bega Valley focus', role: 'community' } },
                { type: 'Feature', geometry: { type: 'Point', coordinates: [150.05, -36.89] }, properties: { name: 'Coastal evacuation corridor', role: 'corridor' } }
            ]
        },
        fitFootprint: true,
        maxFocusZoom: 9.3
    },

    'canada-wildfires-2023': {
        evidenceQuality: 'regional',
        evidenceLabel: 'Alberta fire cluster case',
        evidenceNote: 'Representative 2023 Canadian wildfire cluster area; the national season covered many provinces.',
        story: 'Canada 2023 was not one fire. This reconstruction uses an Alberta cluster as a local case window while preserving the national-season metrics in the panel. The map marks a real regional fire landscape instead of implying one national footprint.',
        localImpacts: [
            'A regional Alberta cluster is mapped as the case area.',
            'National metrics remain in the metadata but are not drawn as one giant perimeter.',
            'The timeline separates early-season starts, peak evacuations, and smoke impacts.'
        ],
        timeline: [
            { progress: 0.00, date: '2023-05', label: 'Early-season fires expand', note: 'Dry spring conditions create widespread starts.' },
            { progress: 0.45, date: '2023-06', label: 'Evacuations and smoke impacts', note: 'Multiple provinces experience severe fire and smoke conditions.' },
            { progress: 0.78, date: '2023-08', label: 'Record area continues growing', note: 'Long-duration burning pushes the national season into record territory.' },
            { progress: 1.00, date: '2023-10', label: 'Season winds down', note: 'Recovery, emissions analysis, and community rebuilding continue.' }
        ],
        focusGeometry: {
            type: 'FeatureCollection',
            features: [
                {
                    type: 'Feature',
                    geometry: {
                        type: 'Polygon',
                        coordinates: [[
                            [-116.32, 55.78],
                            [-114.80, 55.84],
                            [-114.66, 56.62],
                            [-116.18, 56.70],
                            [-116.32, 55.78]
                        ]]
                    },
                    properties: { name: 'Alberta wildfire cluster case area', role: 'footprint' }
                },
                { type: 'Feature', geometry: { type: 'Point', coordinates: [-115.57, 56.23] }, properties: { name: 'Alberta case focus', role: 'origin' } }
            ]
        },
        fitFootprint: true,
        maxFocusZoom: 8.6
    }
};
