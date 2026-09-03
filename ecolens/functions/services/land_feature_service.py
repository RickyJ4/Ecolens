from utils.geo_utils import distance_km


class LandFeatureService:
    def __init__(self, risk_thresholds=None):
        self.risk_thresholds = risk_thresholds or {
            "high": 5,
            "medium": 20
        }

    def proximity(self, point, features):
        """
        Calculate proximity to land features
        
        Args:
            point: (lat, lng) tuple
            features: dict of feature types and their locations
        
        Returns:
            dict: Categorized proximity data with risk levels
        """
        # Initialize results structure
        results = {
            "settlements": [],
            "rivers": [],
            "protected_areas": [],
            "infrastructure": []
        }

        for feature_type, locations in features.items():
            if not locations:
                continue

            for loc in locations:
                # loc should be a dict with 'coords' and 'name'
                if isinstance(loc, dict):
                    coords = loc.get('coords')
                    name = loc.get('name', 'Unknown')
                elif isinstance(loc, (list, tuple)) and len(loc) == 2:
                    coords = loc
                    name = 'Unknown'
                else:
                    continue
                
                dist = distance_km(point, coords)
                
                # Determine risk level
                if dist < self.risk_thresholds["high"]:
                    risk = "high"
                elif dist < self.risk_thresholds["medium"]:
                    risk = "medium"
                else:
                    risk = "low"
                
                feature_data = {
                    "type": name,
                    "distance_km": round(dist, 2),
                    "risk_level": risk,
                    "impact": self._get_impact_description(feature_type, risk)
                }
                
                results[feature_type].append(feature_data)
        
        # Sort each category by distance
        for category in results:
            results[category].sort(key=lambda x: x['distance_km'])
            results[category] = results[category][:5]  # Keep top 5
        
        return results

    def _get_impact_description(self, feature_type, risk_level):
        """Get impact description based on feature and risk"""
        impacts = {
            "settlements": {
                "high": "Immediate threat to community - air quality, water supply at risk",
                "medium": "Indirect effects on local ecosystem services",
                "low": "Minimal direct impact"
            },
            "rivers": {
                "high": "Critical - sedimentation and water quality degradation likely",
                "medium": "Watershed disruption and erosion risk",
                "low": "Minimal hydrological impact"
            },
            "protected_areas": {
                "high": "Severe - protected ecosystem integrity compromised",
                "medium": "Edge effects and wildlife corridor disruption",
                "low": "Buffer zone effects"
            },
            "infrastructure": {
                "high": "Direct threat to roads, facilities",
                "medium": "Access and connectivity at risk",
                "low": "Minimal infrastructure impact"
            }
        }
        
        return impacts.get(feature_type, {}).get(risk_level, "Impact unclear")

    def get_global_features(self):
        """
        Return global land features dataset
        
        TODO: Replace with real database queries
        For now, returns sample data for major regions
        """
        # Major cities and settlements in forest regions
        settlements = [
            {"name": "Manaus, Brazil", "coords": (-3.1190, -60.0217)},
            {"name": "Iquitos, Peru", "coords": (-3.7437, -73.2516)},
            {"name": "Porto Velho, Brazil", "coords": (-8.7619, -63.9039)},
            {"name": "Kinshasa, DRC", "coords": (-4.4419, 15.2663)},
            {"name": "Kisangani, DRC", "coords": (0.5150, 25.1917)},
            {"name": "Pontianak, Indonesia", "coords": (-0.0263, 109.3425)},
            {"name": "Palangkaraya, Indonesia", "coords": (-2.2089, 113.9167)},
            {"name": "Medan, Indonesia", "coords": (3.5952, 98.6722)},
            # Canada / North America
            {"name": "Vancouver, Canada", "coords": (49.2827, -123.1207)},
            {"name": "Prince George, Canada", "coords": (53.9171, -122.7497)},
            {"name": "Kamloops, Canada", "coords": (50.6745, -120.3273)},
            {"name": "Kelowna, Canada", "coords": (49.8880, -119.4960)},
            {"name": "Williams Lake, Canada", "coords": (52.1417, -122.1417)},
            {"name": "Quesnel, Canada", "coords": (52.9784, -122.4927)},
            {"name": "Seattle, USA", "coords": (47.6062, -122.3321)},
            {"name": "Portland, USA", "coords": (45.5152, -122.6784)},
        ]
        
        # Major rivers
        rivers = [
            {"name": "Amazon River", "coords": (-3.4653, -62.2159)},
            {"name": "Negro River", "coords": (-0.9719, -61.6558)},
            {"name": "Madeira River", "coords": (-8.7543, -63.8784)},
            {"name": "Congo River", "coords": (-0.6111, 25.1958)},
            {"name": "Ubangi River", "coords": (1.6145, 18.5596)},
            {"name": "Kapuas River", "coords": (-0.0333, 109.3333)},
            {"name": "Mahakam River", "coords": (0.4915, 117.1333)},
            # Canada / North America
            {"name": "Fraser River, Canada", "coords": (49.1913, -122.9105)},
            {"name": "Thompson River, Canada", "coords": (50.6745, -120.3273)},
            {"name": "Columbia River", "coords": (46.2441, -119.1857)},
            {"name": "Skeena River, Canada", "coords": (54.3167, -128.6167)},
            {"name": "Peace River, Canada", "coords": (56.2461, -117.2872)},
        ]
        
        # Protected areas (approximate centers)
        protected_areas = [
            {"name": "Jaú National Park, Brazil", "coords": (-1.9000, -61.8500)},
            {"name": "Tumucumaque National Park, Brazil", "coords": (2.0000, -54.5000)},
            {"name": "Virunga National Park, DRC", "coords": (-0.9167, 29.2833)},
            {"name": "Salonga National Park, DRC", "coords": (-2.3167, 20.8000)},
            {"name": "Tanjung Puting National Park, Indonesia", "coords": (-2.8500, 111.6500)},
            {"name": "Gunung Leuser National Park, Indonesia", "coords": (3.5667, 97.5000)},
            # Canada / North America
            {"name": "Great Bear Rainforest, Canada", "coords": (52.5000, -127.5000)},
            {"name": "Mount Revelstoke National Park, Canada", "coords": (51.0833, -118.0500)},
            {"name": "Yoho National Park, Canada", "coords": (51.4000, -116.5000)},
            {"name": "Wells Gray Provincial Park, Canada", "coords": (52.1000, -120.1000)},
            {"name": "Olympic National Park, USA", "coords": (47.8021, -123.6044)},
            {"name": "North Cascades National Park, USA", "coords": (48.7718, -121.2985)},
        ]
        
        # Infrastructure (roads, facilities)
        infrastructure = [
            {"name": "Trans-Amazonian Highway", "coords": (-7.0000, -58.0000)},
            {"name": "BR-163 Highway", "coords": (-10.5000, -55.0000)},
            {"name": "Kinshasa Airport", "coords": (-4.3858, 15.4446)},
            {"name": "Palangkaraya Airport", "coords": (-2.2256, 113.9428)},
            # Canada / North America
            {"name": "Trans-Canada Highway BC", "coords": (51.0000, -121.0000)},
            {"name": "BC Highway 97", "coords": (53.0000, -122.5000)},
            {"name": "Prince George Airport", "coords": (53.8839, -122.6789)},
            {"name": "Vancouver International Airport", "coords": (49.1967, -123.1815)},
        ]
        
        return {
            "settlements": settlements,
            "rivers": rivers,
            "protected_areas": protected_areas,
            "infrastructure": infrastructure
        }