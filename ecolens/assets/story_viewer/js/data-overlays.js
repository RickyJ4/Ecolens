/**
 * EcoLens Story Viewer - Data Overlays
 * Handles species POI markers, deforestation polygons, fire points, etc.
 */

const DataOverlays = {
    viewer: null,
    speciesEntities: [],
    deforestationEntity: null,
    fireEntities: [],
    populationEntities: [],
    selectedSpeciesId: null,

    /**
     * Initialize data overlays manager
     */
    init(viewer) {
        this.viewer = viewer;
        if (this.viewer) {
            this._setupClickHandler();
        }
    },

    /**
     * Check if viewer is available (null guard)
     */
    _requireViewer() {
        if (!this.viewer) {
            console.warn('[DataOverlays] Viewer not initialized');
            return false;
        }
        return true;
    },

    /**
     * Setup click handler for entity selection
     */
    _setupClickHandler() {
        if (!this._requireViewer()) return;
        const handler = new Cesium.ScreenSpaceEventHandler(this.viewer.scene.canvas);

        handler.setInputAction((click) => {
            const picked = this.viewer.scene.pick(click.position);
            if (Cesium.defined(picked) && picked.id) {
                const entity = picked.id;
                if (entity.speciesData) {
                    this._onSpeciesClick(entity);
                }
            }
        }, Cesium.ScreenSpaceEventType.LEFT_CLICK);
    },

    /**
     * Handle species POI click
     */
    _onSpeciesClick(entity) {
        const species = entity.speciesData;
        this.selectedSpeciesId = species.id;

        // Notify Flutter
        if (window.FlutterBridge) {
            FlutterBridge.onSpeciesSelected(species.id, species);
        }

        // Highlight selected entity
        this.speciesEntities.forEach(e => {
            e.billboard.scale = e.speciesData.id === species.id ? 0.7 : 0.5;
        });
    },

    /**
     * Add species POI markers from storyConfig
     */
    addSpeciesPOIs(speciesList, centerLocation) {
        if (!this._requireViewer()) return;
        if (!speciesList || speciesList.length === 0) return;

        // Clear existing
        this.removeSpeciesPOIs();

        speciesList.forEach((species, index) => {
            // Calculate position - spread around center if no explicit position
            const lat = species.latitude ?? (centerLocation.lat + this._getSpread(index, speciesList.length, 0.02));
            const lng = species.longitude ?? (centerLocation.lng + this._getSpread(index, speciesList.length, 0.02, true));
            const alt = species.altitude_m ?? 0;

            const entity = this.viewer.entities.add({
                position: Cesium.Cartesian3.fromDegrees(lng, lat, alt + 100),

                billboard: {
                    image: this._createSpeciesMarker(species),
                    scale: 0.5,
                    verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
                    heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
                    disableDepthTestDistance: Number.POSITIVE_INFINITY
                },

                label: {
                    text: species.name || species.common_name,
                    font: '14px Inter, sans-serif',
                    fillColor: Cesium.Color.WHITE,
                    outlineColor: Cesium.Color.BLACK,
                    outlineWidth: 2,
                    style: Cesium.LabelStyle.FILL_AND_OUTLINE,
                    verticalOrigin: Cesium.VerticalOrigin.TOP,
                    pixelOffset: new Cesium.Cartesian2(0, 10),
                    heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
                    disableDepthTestDistance: Number.POSITIVE_INFINITY,
                    show: false // Hidden initially, shown on hover/select
                }
            });

            // Store species data on entity
            entity.speciesData = {
                id: species.id || `species_${index}`,
                name: species.name || species.common_name,
                scientificName: species.scientific_name,
                conservationStatus: species.conservation_status || species.status,
                category: species.category,
                endemic: species.endemic,
                populationEstimate: species.population_estimate,
                description: species.description
            };

            this.speciesEntities.push(entity);
        });

        console.log(`[DataOverlays] Added ${speciesList.length} species POIs`);
    },

    /**
     * Get spread offset for distributing markers in a circle
     */
    _getSpread(index, total, radius, isLng = false) {
        const angle = (index / total) * 2 * Math.PI;
        return radius * (isLng ? Math.cos(angle) : Math.sin(angle));
    },

    /**
     * Create a species marker as canvas data URL
     */
    _createSpeciesMarker(species) {
        const canvas = document.createElement('canvas');
        canvas.width = 48;
        canvas.height = 48;
        const ctx = canvas.getContext('2d');

        // Background circle
        const color = this._getStatusColor(species.conservation_status || species.status);
        ctx.beginPath();
        ctx.arc(24, 24, 22, 0, 2 * Math.PI);
        ctx.fillStyle = color;
        ctx.fill();
        ctx.strokeStyle = '#ffffff';
        ctx.lineWidth = 2;
        ctx.stroke();

        // Icon (emoji or category symbol)
        ctx.font = '24px Arial';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillStyle = '#ffffff';

        const icon = species.icon || this._getCategoryIcon(species.category);
        ctx.fillText(icon, 24, 24);

        return canvas.toDataURL();
    },

    /**
     * Get color based on conservation status
     */
    _getStatusColor(status) {
        if (!status) return 'rgba(88, 166, 255, 0.9)';

        const s = status.toLowerCase();
        if (s.includes('critically')) return 'rgba(218, 54, 51, 0.9)';
        if (s.includes('endangered')) return 'rgba(219, 109, 40, 0.9)';
        if (s.includes('vulnerable')) return 'rgba(219, 171, 9, 0.9)';
        if (s.includes('near')) return 'rgba(163, 113, 247, 0.9)';
        return 'rgba(86, 211, 100, 0.9)';
    },

    /**
     * Get icon for species category
     */
    _getCategoryIcon(category) {
        const icons = {
            'mammal': '\ud83d\udc3e', // paw
            'bird': '\ud83e\udd85',   // eagle
            'reptile': '\ud83e\udd8e', // lizard
            'amphibian': '\ud83d\udc38', // frog
            'fish': '\ud83d\udc1f',   // fish
            'insect': '\ud83e\udd8b', // butterfly
            'plant': '\ud83c\udf3f',  // herb
            'tree': '\ud83c\udf33',   // tree
            'fauna': '\ud83d\udc3e',  // paw
            'flora': '\ud83c\udf3f',  // herb
        };
        return icons[category?.toLowerCase()] || '\ud83c\udf0d'; // earth
    },

    /**
     * Show/hide species POIs
     */
    setSpeciesVisible(visible) {
        this.speciesEntities.forEach(entity => {
            entity.show = visible;
        });
    },

    /**
     * Animate species appearing one by one
     */
    animateSpeciesIn(delayMs = 200) {
        this.speciesEntities.forEach((entity, index) => {
            entity.show = false;
            setTimeout(() => {
                entity.show = true;
                // Animate scale
                const startScale = 0;
                const endScale = 0.5;
                const duration = 300;
                const startTime = Date.now();

                const animate = () => {
                    const elapsed = Date.now() - startTime;
                    const progress = Math.min(elapsed / duration, 1);
                    const eased = 1 - Math.pow(1 - progress, 3); // ease-out
                    entity.billboard.scale = startScale + (endScale - startScale) * eased;

                    if (progress < 1) {
                        requestAnimationFrame(animate);
                    }
                };
                animate();
            }, index * delayMs);
        });
    },

    /**
     * Remove all species POIs
     */
    removeSpeciesPOIs() {
        if (!this._requireViewer()) return;
        this.speciesEntities.forEach(entity => {
            this.viewer.entities.remove(entity);
        });
        this.speciesEntities = [];
    },

    /**
     * Add deforestation polygon overlay
     */
    addDeforestationZone(polygon, options = {}) {
        if (!this._requireViewer()) return;
        if (!polygon || !polygon.coordinates) return;

        // Remove existing
        if (this.deforestationEntity) {
            this.viewer.entities.remove(this.deforestationEntity);
        }

        const positions = polygon.coordinates.flat().map(coord =>
            Cesium.Cartesian3.fromDegrees(coord[0], coord[1])
        );

        const config = window.EcoLensConfig?.effects || {};
        const color = options.color || config.deforestationColor || [218, 54, 51, 128];

        this.deforestationEntity = this.viewer.entities.add({
            polygon: {
                hierarchy: new Cesium.PolygonHierarchy(positions),
                material: new Cesium.Color(
                    color[0] / 255,
                    color[1] / 255,
                    color[2] / 255,
                    color[3] / 255
                ),
                outline: true,
                outlineColor: Cesium.Color.fromCssColorString('#DA3633'),
                outlineWidth: 2,
                heightReference: Cesium.HeightReference.CLAMP_TO_GROUND
            }
        });

        console.log('[DataOverlays] Added deforestation zone');
    },

    /**
     * Add fire point markers
     */
    addFirePoints(fireData) {
        if (!this._requireViewer()) return;
        if (!fireData || !fireData.points) return;

        // Clear existing
        this.removeFirePoints();

        fireData.points.forEach((fire, index) => {
            const entity = this.viewer.entities.add({
                position: Cesium.Cartesian3.fromDegrees(fire.lng, fire.lat),

                billboard: {
                    image: this._createFireMarker(),
                    scale: 0.4,
                    heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
                    disableDepthTestDistance: Number.POSITIVE_INFINITY
                },

                ellipse: fire.radiusM ? {
                    semiMajorAxis: fire.radiusM,
                    semiMinorAxis: fire.radiusM,
                    material: Cesium.Color.RED.withAlpha(0.2),
                    heightReference: Cesium.HeightReference.CLAMP_TO_GROUND
                } : undefined
            });

            entity.fireData = fire;
            this.fireEntities.push(entity);
        });

        console.log(`[DataOverlays] Added ${fireData.points.length} fire points`);
    },

    /**
     * Create fire marker
     */
    _createFireMarker() {
        const canvas = document.createElement('canvas');
        canvas.width = 32;
        canvas.height = 32;
        const ctx = canvas.getContext('2d');

        // Fire emoji
        ctx.font = '24px Arial';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText('\ud83d\udd25', 16, 16);

        return canvas.toDataURL();
    },

    /**
     * Remove fire points
     */
    removeFirePoints() {
        if (!this._requireViewer()) return;
        this.fireEntities.forEach(entity => {
            this.viewer.entities.remove(entity);
        });
        this.fireEntities = [];
    },

    /**
     * Add population/community markers
     */
    addPopulationMarkers(populationData, location) {
        if (!this._requireViewer()) return;
        if (!populationData) return;

        // Clear existing
        this.removePopulationMarkers();

        // Single aggregate marker at location
        const entity = this.viewer.entities.add({
            position: Cesium.Cartesian3.fromDegrees(location.lng, location.lat),

            billboard: {
                image: this._createPopulationMarker(populationData.count),
                scale: 0.6,
                heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
                disableDepthTestDistance: Number.POSITIVE_INFINITY
            },

            label: {
                text: `${populationData.count?.toLocaleString() || '?'} people`,
                font: '12px Inter, sans-serif',
                fillColor: Cesium.Color.WHITE,
                outlineColor: Cesium.Color.BLACK,
                outlineWidth: 2,
                style: Cesium.LabelStyle.FILL_AND_OUTLINE,
                verticalOrigin: Cesium.VerticalOrigin.TOP,
                pixelOffset: new Cesium.Cartesian2(0, 20),
                heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
                disableDepthTestDistance: Number.POSITIVE_INFINITY
            }
        });

        this.populationEntities.push(entity);
    },

    /**
     * Create population marker
     */
    _createPopulationMarker(count) {
        const canvas = document.createElement('canvas');
        canvas.width = 48;
        canvas.height = 48;
        const ctx = canvas.getContext('2d');

        // Background
        ctx.beginPath();
        ctx.arc(24, 24, 22, 0, 2 * Math.PI);
        ctx.fillStyle = 'rgba(163, 113, 247, 0.9)';
        ctx.fill();
        ctx.strokeStyle = '#ffffff';
        ctx.lineWidth = 2;
        ctx.stroke();

        // People icon
        ctx.font = '20px Arial';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillStyle = '#ffffff';
        ctx.fillText('\ud83d\udc65', 24, 24);

        return canvas.toDataURL();
    },

    /**
     * Remove population markers
     */
    removePopulationMarkers() {
        if (!this._requireViewer()) return;
        this.populationEntities.forEach(entity => {
            this.viewer.entities.remove(entity);
        });
        this.populationEntities = [];
    },

    /**
     * Remove all overlays
     */
    removeAll() {
        if (!this._requireViewer()) return;
        this.removeSpeciesPOIs();
        this.removeFirePoints();
        this.removePopulationMarkers();
        if (this.deforestationEntity) {
            this.viewer.entities.remove(this.deforestationEntity);
            this.deforestationEntity = null;
        }
    }
};

// Make globally available
window.DataOverlays = DataOverlays;
