"""
Hydrology Analysis Agent - Layer 11

Water features:
- Detected via Gemini AI with Google Search grounding (semi-real, model-mediated)

Water stress / precipitation / seasonality:
- Pulled from Open-Meteo Historical Weather API
  (https://open-meteo.com/en/docs/historical-weather-api)
- 10 years of daily precipitation aggregated into annual + monthly stats
- Wet/dry seasons derived from monthly precipitation distribution
- Baseline stress derived from absolute precipitation + interannual variability
- No hardcoded regional lookup tables — every location gets its own real data
"""

import math
import requests

OPEN_METEO_URL = "https://archive-api.open-meteo.com/v1/archive"
OPEN_METEO_TIMEOUT = 10
HISTORICAL_YEARS = 10  # how many years of historical precipitation to fetch


class HydrologyAnalysisAgent:
    """
    Analyzes water resources and accessibility using:
    - Gemini AI for nearby water feature detection
    - Open-Meteo for real precipitation history (no lookup tables)
    """

    SEARCH_RADIUS_KM = 20

    def __init__(self):
        pass


    def analyze(self, lat: float, lng: float, bbox: dict, habitat_type: str = "") -> dict:
        """
        Main entry point - analyze water resources
        
        Args:
            lat: Center latitude
            lng: Center longitude
            bbox: Bounding box for context
            habitat_type: Habitat type for regional water stress lookup
            
        Returns:
            Complete hydrology analysis dict
        """
        try:
            # Get regional water stress FIRST (needed for accessibility adjustment)
            water_stress = self._get_regional_water_stress(lat, lng, habitat_type)
            
            # Fetch water features from OSM
            water_features = self._fetch_water_features(lat, lng)
            
            # Parse and calculate distances
            parsed_features = self._parse_water_features(water_features, lat, lng)
            
            # Assess water accessibility (now with water stress for adjustment)
            accessibility = self._assess_water_accessibility(parsed_features, water_stress)
            
            # Generate seasonal patterns
            seasonal = self._generate_seasonal_patterns(water_stress)
            
            # Planting implications
            implications = self._generate_planting_implications(accessibility, water_stress)
            
            return {
                "available": True,
                "water_features": {
                    "nearest_water": parsed_features[0] if parsed_features else {"available": False},
                    "all_within_20km": parsed_features[:10],  # Top 10 closest
                    "count": len(parsed_features),
                    "permanent_count": accessibility.get('permanent_count', 0)
                },
                "water_accessibility": accessibility,
                "water_stress": water_stress,
                "seasonal_patterns": seasonal,
                "planting_implications": implications,
                "data_sources": [
                    "OpenStreetMap Overpass API (water features)",
                    "Regional climate databases (water stress)"
                ],
                "confidence": "medium",
                "note": "Water features from community-maintained OSM data. Ground verification recommended."
            }
            
        except Exception as e:
            print(f"❌ Hydrology analysis error: {e}")
            return self._unavailable_response(str(e), lat, lng, habitat_type)

    def _fetch_water_features(self, lat: float, lng: float) -> dict:
        """
        Query water features using Gemini AI with geographic knowledge.
        More reliable than Overpass API which often times out.
        """
        try:
            import os
            from google import genai
            from google.genai import types
            import json
            import re

            client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])

            prompt = f"""Analyze water resources near coordinates {lat}, {lng}.

Identify the nearest rivers, lakes, streams, or water bodies within 20km.
For each water feature, provide:
1. Name (if known, otherwise describe location)
2. Type (river, lake, stream, reservoir, wetland)
3. Approximate distance in km from the coordinates
4. Whether it's permanent (year-round) or seasonal

Return ONLY valid JSON in this exact format:
{{
    "water_features": [
        {{
            "name": "Name of water body",
            "type": "river",
            "distance_km": 2.5,
            "permanent": true
        }}
    ],
    "region_info": {{
        "major_watershed": "Name of watershed/basin",
        "water_availability": "abundant"
    }}
}}

Be accurate based on geographic knowledge. List up to 5 nearest water features."""

            print(f"   🧠 Querying Gemini for water features at {lat}, {lng}...")
            
            response = client.models.generate_content(
                model="gemini-2.5-flash",
                contents=prompt,
                config=types.GenerateContentConfig(
                    tools=[types.Tool(google_search=types.GoogleSearch())]
                )
            )
            
            # Parse JSON response
            text = response.text
            json_match = re.search(r'```json\s*(.*?)\s*```', text, re.DOTALL)
            if json_match:
                json_str = json_match.group(1)
            else:
                json_match = re.search(r'\{.*\}', text, re.DOTALL)
                json_str = json_match.group(0) if json_match else "{}"
            
            data = json.loads(json_str)
            water_features = data.get('water_features', [])
            
            if water_features:
                # Convert to internal format
                elements = []
                for i, feat in enumerate(water_features):
                    elements.append({
                        "type": "way",
                        "id": 900000 + i,
                        "center": {"lat": lat, "lon": lng},
                        "tags": {
                            "waterway": feat.get('type', 'river'),
                            "name": feat.get('name', 'Unknown'),
                            "source": "gemini",
                            "distance_km": feat.get('distance_km', 0),
                            "permanent": "yes" if feat.get('permanent', True) else "no"
                        }
                    })
                
                print(f"   ✅ Gemini found {len(elements)} water feature(s)")
                return {
                    "elements": elements,
                    "source": "gemini",
                    "region_info": data.get('region_info', {})
                }
            else:
                print("   ⚠️ No water features identified")
                return {"elements": [], "source": "gemini"}
                
        except Exception as e:
            print(f"   ❌ Water analysis error: {e}")
            return {"elements": [], "error": str(e)}
    
    def _get_major_rivers_fallback(self, lat: float, lng: float) -> dict:
        """
        Use Gemini with Google Maps grounding to identify water features
        when OSM Overpass API fails
        """
        try:
            import os
            from google import genai
            from google.genai import types

            client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])

            prompt = f"""Analyze the water resources at coordinates {lat}, {lng}.

Using your knowledge and Google Maps, identify:
1. The nearest major river, lake, or water body to these coordinates
2. The approximate distance in km from this point to the nearest significant water source
3. Whether this water source is permanent (year-round) or seasonal
4. The name of the water body if known

Respond in this exact JSON format:
{{
    "water_features": [
        {{
            "name": "Name of water body",
            "type": "river|lake|stream|reservoir",
            "distance_km": 5.2,
            "permanent": true,
            "description": "Brief description"
        }}
    ],
    "region_hydrology": {{
        "description": "Brief description of regional water availability",
        "major_watershed": "Name of watershed/basin if known",
        "water_availability": "abundant|moderate|limited|scarce"
    }}
}}

Be accurate - use your geographic knowledge. If this is the Amazon region, identify nearby rivers. If this is an arid region, note the scarcity."""

            print("   🧠 Using Gemini to analyze water features...")
            
            response = client.models.generate_content(
                model="gemini-2.5-flash",
                contents=prompt,
                config=types.GenerateContentConfig(
                    tools=[types.Tool(google_search=types.GoogleSearch())]
                )
            )
            
            # Parse response
            import json
            import re
            
            text = response.text
            json_match = re.search(r'```json\s*(.*?)\s*```', text, re.DOTALL)
            if json_match:
                json_str = json_match.group(1)
            else:
                json_match = re.search(r'\{.*\}', text, re.DOTALL)
                json_str = json_match.group(0) if json_match else "{}"
            
            data = json.loads(json_str)
            water_features = data.get('water_features', [])
            
            if water_features:
                # Convert to OSM-like format
                elements = []
                for i, feat in enumerate(water_features):
                    elements.append({
                        "type": "way",
                        "id": 900000 + i,
                        "center": {"lat": lat, "lon": lng},
                        "tags": {
                            "waterway": feat.get('type', 'river'),
                            "name": feat.get('name', 'Unknown'),
                            "source": "gemini_analysis",
                            "distance_km": feat.get('distance_km', 0),
                            "permanent": "yes" if feat.get('permanent', True) else "no"
                        }
                    })
                
                print(f"   ✅ Gemini identified {len(elements)} water feature(s)")
                return {
                    "elements": elements,
                    "source": "gemini_analysis",
                    "region_hydrology": data.get('region_hydrology', {})
                }
            else:
                print("   ⚠️ Gemini found no water features")
                return {"elements": [], "source": "gemini_analysis"}
                
        except Exception as e:
            print(f"   ❌ Gemini water analysis failed: {e}")
            return {"elements": [], "error": str(e)}

    def _parse_water_features(self, osm_data: dict, center_lat: float, center_lng: float) -> list:
        """
        Extract water features and calculate distances
        Filters out features outside search radius
        Handles both OSM data and Gemini-analyzed data
        """
        features = []
        seen_ids = set()
        
        for element in osm_data.get('elements', []):
            if element['type'] not in ['way', 'relation']:
                continue
            
            # Skip duplicates
            elem_id = f"{element['type']}_{element['id']}"
            if elem_id in seen_ids:
                continue
            seen_ids.add(elem_id)
            
            tags = element.get('tags', {})
            
            # Determine water type
            waterway_type = tags.get('waterway') or tags.get('natural', 'unknown')
            name = tags.get('name', f'Unnamed {waterway_type}')
            
            # Get coordinates
            if 'center' in element:
                feat_lat = element['center']['lat']
                feat_lng = element['center']['lon']
            else:
                continue  # Skip if no coordinates
            
            # Check if distance is pre-computed (from Gemini)
            if 'distance_km' in tags:
                distance_km = float(tags.get('distance_km', 0))
            else:
                # Calculate distance using haversine
                distance_km = self._haversine_distance(
                    center_lat, center_lng,
                    feat_lat, feat_lng
                )
            
            # FILTER: Skip features outside the search radius (unless from Gemini)
            if distance_km > self.SEARCH_RADIUS_KM and 'source' not in tags:
                continue
            
            # Classify size and permanence
            size = self._classify_waterway_size(waterway_type, tags)
            
            # Handle permanent tag from both OSM and Gemini
            if 'permanent' in tags:
                permanent = tags.get('permanent') == 'yes' or tags.get('permanent') == True
            else:
                permanent = self._is_permanent(tags)
            
            features.append({
                "name": name,
                "type": waterway_type,
                "distance_km": round(distance_km, 2),
                "size": size,
                "permanent": permanent,
                "coordinates": {"lat": feat_lat, "lng": feat_lng},
                "source": tags.get('source', 'osm')
            })
        
        # Sort by distance
        features.sort(key=lambda x: x['distance_km'])
        
        # Debug output
        permanent_count = sum(1 for f in features if f['permanent'])
        print(f"   📊 Found {len(features)} water features ({permanent_count} permanent)")
        if features:
            print(f"   📍 Nearest: {features[0]['name']} ({features[0]['type']}) at {features[0]['distance_km']}km")
        
        return features

    def _haversine_distance(self, lat1: float, lon1: float, lat2: float, lon2: float) -> float:
        """
        Calculate great-circle distance between two points (km)
        """
        R = 6371  # Earth radius in km
        
        lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
        dlat = lat2 - lat1
        dlon = lon2 - lon1
        
        a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
        c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
        
        return R * c

    def _classify_waterway_size(self, waterway_type: str, tags: dict) -> str:
        """
        Classify water body as major, moderate, or minor
        """
        if waterway_type == 'river':
            width = tags.get('width', '')
            try:
                if 'km' in str(width):
                    return "major"
                width_val = float(str(width).replace('m', '').strip()) if width else 0
                if width_val > 100:
                    return "major"
                elif width_val > 20:
                    return "moderate"
            except (ValueError, TypeError):
                pass
            return "moderate"
        elif waterway_type in ['stream', 'creek', 'drain', 'ditch']:
            return "minor"
        elif waterway_type in ['lake', 'reservoir']:
            return "major"
        elif waterway_type == 'pond':
            return "minor"
        else:
            return "moderate"

    def _is_permanent(self, tags: dict) -> bool:
        """
        Determine if water body is permanent
        """
        intermittent = tags.get('intermittent', 'no')
        seasonal = tags.get('seasonal', 'no')
        
        if intermittent == 'yes' or seasonal == 'yes':
            return False
        return True

    def _assess_water_accessibility(self, features: list, water_stress: dict = None) -> dict:
        """
        Rate water accessibility for restoration
        Based on NEAREST PERMANENT water distance, adjusted for regional water stress
        """
        if not features:
            return {
                "rating": "unknown",
                "category": "No data",
                "description": "No water features found within search radius. May be data gaps.",
                "irrigation_feasibility": "unknown",
                "irrigation_cost_multiplier": 1.5
            }
        
        # Prioritize permanent water sources
        permanent_features = [f for f in features if f.get('permanent', True)]
        
        # Use nearest permanent if available, otherwise nearest any
        if permanent_features:
            nearest = permanent_features[0]
            note = "permanent water"
        else:
            nearest = features[0]
            note = "seasonal/intermittent only"
        
        nearest_distance = nearest['distance_km']
        water_type = nearest.get('type', 'unknown')
        water_name = nearest.get('name', 'Unknown')
        
        # Get water stress level if provided
        stress_level = water_stress.get('baseline_stress', 'medium') if water_stress else 'medium'
        
        # Base rating on distance
        if nearest_distance < 1:
            base_rating = "excellent"
            category = "<1 km"
            description = "Immediate water access. Ideal for riparian restoration."
            irrigation_feasibility = "not needed"
            cost_mult = 1.0
        elif nearest_distance < 5:
            base_rating = "good"
            category = "1-5 km"
            description = "Close water access. Water transport feasible if needed."
            irrigation_feasibility = "feasible"
            cost_mult = 1.2
        elif nearest_distance < 10:
            base_rating = "moderate"
            category = "5-10 km"
            description = "Moderate distance. Drought-tolerant species recommended."
            irrigation_feasibility = "costly"
            cost_mult = 1.5
        else:
            base_rating = "poor"
            category = ">10 km"
            description = "Remote from water. Must rely on rainfall. Only hardy species viable."
            irrigation_feasibility = "not practical"
            cost_mult = 2.0
        
        # ADJUST for high water stress regions (arid zones need closer water)
        # In arid regions, even nearby water may be unreliable
        if stress_level in ['high', 'very high']:
            # In very high stress regions, be skeptical of "streams" - likely dry wadis
            if water_type in ['stream', 'drain', 'ditch']:
                # Streams in arid regions are often seasonal/ephemeral
                if base_rating == 'excellent':
                    base_rating = 'moderate'
                    description = "Water source may be seasonal in this arid region. Verify permanence before relying on it."
                elif base_rating == 'good':
                    base_rating = 'moderate'
                    description += " (Water source reliability uncertain in high stress region)"
            # Even for rivers/lakes, adjust expectations
            elif base_rating == 'excellent':
                base_rating = 'good'
                description += " (Adjusted for high water stress region)"
                
        elif stress_level == 'medium-high':
            if base_rating == 'good' and nearest_distance > 3:
                base_rating = 'moderate'
                description += " (Adjusted for moderate-high water stress region)"
        
        # Penalize if only seasonal water available
        if note == "seasonal/intermittent only" and base_rating in ['excellent', 'good']:
            base_rating = 'poor'
            description = f"Only seasonal water available. Water stress severe during dry periods."
        
        return {
            "rating": base_rating,
            "category": category,
            "description": description,
            "irrigation_feasibility": irrigation_feasibility,
            "irrigation_cost_multiplier": cost_mult,
            "nearest_distance_km": nearest_distance,
            "nearest_name": water_name,
            "nearest_type": water_type,
            "permanent_water": note == "permanent water",
            "total_features": len(features),
            "permanent_count": len(permanent_features)
        }

    def _get_regional_water_stress(self, lat: float, lng: float,
                                   habitat_type: str) -> dict:
        """
        Fetch real precipitation history from Open-Meteo (10 years daily)
        and derive water stress metrics from actual data — not a lookup table.

        Returns the same dict shape the rest of the agent expects:
        baseline_stress, annual_precipitation_mm, drought_risk,
        wet_season, dry_season, climate_trend, optimal_planting,
        region, confidence.
        """
        from datetime import date

        end_year = date.today().year - 1
        start_year = end_year - HISTORICAL_YEARS + 1
        params = {
            'latitude': lat,
            'longitude': lng,
            'start_date': f'{start_year}-01-01',
            'end_date': f'{end_year}-12-31',
            'daily': 'precipitation_sum',
            'timezone': 'UTC',
        }

        try:
            resp = requests.get(OPEN_METEO_URL, params=params,
                                timeout=OPEN_METEO_TIMEOUT)
            resp.raise_for_status()
            payload = resp.json()
            daily = payload.get('daily', {})
            dates = daily.get('time', []) or []
            precip = daily.get('precipitation_sum', []) or []
            if not dates or not precip or len(dates) != len(precip):
                raise ValueError('Open-Meteo returned no precipitation series')
        except Exception as e:
            print(f"⚠️ Open-Meteo fetch failed for ({lat}, {lng}): {e}")
            return {
                'baseline_stress': 'unknown',
                'annual_precipitation_mm': None,
                'drought_risk': 'unknown',
                'wet_season': 'Unknown',
                'dry_season': 'Unknown',
                'climate_trend': 'Unknown',
                'optimal_planting': 'Data unavailable',
                'region': 'Open-Meteo lookup failed',
                'confidence': 'low',
                'data_source': 'Open-Meteo (unavailable)',
            }

        annual_totals = {}
        monthly_totals = [0.0] * 12
        monthly_counts = [0] * 12
        for d, mm in zip(dates, precip):
            if mm is None:
                continue
            year = int(d[:4])
            month_idx = int(d[5:7]) - 1
            annual_totals[year] = annual_totals.get(year, 0.0) + mm
            monthly_totals[month_idx] += mm
            monthly_counts[month_idx] += 1

        annual_values = list(annual_totals.values())
        annual_mean = (sum(annual_values) / len(annual_values)
                       if annual_values else 0.0)
        annual_std = self._stddev(annual_values) if len(annual_values) > 1 else 0.0
        coeff_var = (annual_std / annual_mean) if annual_mean > 0 else 0.0

        monthly_mean_mm = [
            (monthly_totals[i] / monthly_counts[i] * 30
             if monthly_counts[i] > 0 else 0.0)
            for i in range(12)
        ]

        wet_months, dry_months = self._split_wet_dry(monthly_mean_mm)
        optimal_planting = self._optimal_planting(wet_months)

        return {
            'baseline_stress': self._stress_class(annual_mean),
            'annual_precipitation_mm': round(annual_mean),
            'precipitation_stddev_mm': round(annual_std),
            'interannual_variability_pct': round(coeff_var * 100, 1),
            'drought_risk': self._drought_class(coeff_var),
            'wet_season': self._month_range(wet_months),
            'dry_season': self._month_range(dry_months),
            'climate_trend': self._trend_class(annual_totals),
            'optimal_planting': optimal_planting,
            'region': 'Open-Meteo historical (location-specific)',
            'confidence': 'high' if len(annual_values) >= 5 else 'medium',
            'years_analyzed': len(annual_values),
            'data_source': (
                f'Open-Meteo Historical Weather API '
                f'({start_year}-{end_year})'
            ),
        }

    @staticmethod
    def _stddev(values):
        n = len(values)
        mean = sum(values) / n
        variance = sum((v - mean) ** 2 for v in values) / n
        return math.sqrt(variance)

    @staticmethod
    def _stress_class(annual_mean_mm: float) -> str:
        if annual_mean_mm < 250:
            return 'high'
        if annual_mean_mm < 500:
            return 'medium-high'
        if annual_mean_mm < 1000:
            return 'low-medium'
        return 'low'

    @staticmethod
    def _drought_class(coeff_var: float) -> str:
        # Higher interannual variability ≈ higher drought risk
        if coeff_var >= 0.35:
            return 'very high'
        if coeff_var >= 0.22:
            return 'high'
        if coeff_var >= 0.15:
            return 'medium'
        return 'low'

    @staticmethod
    def _split_wet_dry(monthly_mean_mm):
        """Months in the top half of monthly precipitation are 'wet'."""
        median = sorted(monthly_mean_mm)[6]
        wet = [i for i, v in enumerate(monthly_mean_mm) if v >= median]
        dry = [i for i, v in enumerate(monthly_mean_mm) if v < median]
        return wet, dry

    @staticmethod
    def _month_range(indices) -> str:
        if not indices:
            return 'Unknown'
        names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
        sorted_idx = sorted(indices)
        # Detect contiguous runs (incl. wraparound) for a clean label
        contiguous = all(
            sorted_idx[i] - sorted_idx[i - 1] == 1
            for i in range(1, len(sorted_idx))
        )
        if contiguous:
            return f"{names[sorted_idx[0]]}-{names[sorted_idx[-1]]}"
        return ', '.join(names[i] for i in sorted_idx)

    @staticmethod
    def _optimal_planting(wet_months) -> str:
        if not wet_months:
            return 'Data insufficient'
        names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
        first = sorted(wet_months)[0]
        return f"{names[first]} (start of wet season)"

    @staticmethod
    def _trend_class(annual_totals: dict) -> str:
        """Simple linear trend over the years analyzed."""
        if len(annual_totals) < 4:
            return 'Insufficient data for trend'
        years = sorted(annual_totals.keys())
        values = [annual_totals[y] for y in years]
        n = len(years)
        x_mean = sum(years) / n
        y_mean = sum(values) / n
        num = sum((years[i] - x_mean) * (values[i] - y_mean) for i in range(n))
        den = sum((years[i] - x_mean) ** 2 for i in range(n))
        slope_per_year = num / den if den > 0 else 0.0
        pct_per_year = (slope_per_year / y_mean * 100) if y_mean > 0 else 0.0
        if pct_per_year >= 1.0:
            return f'Precipitation increasing (~{pct_per_year:+.1f}%/yr)'
        if pct_per_year <= -1.0:
            return f'Precipitation decreasing (~{pct_per_year:+.1f}%/yr)'
        return f'Stable (~{pct_per_year:+.1f}%/yr)'

    def _generate_seasonal_patterns(self, water_stress: dict) -> dict:
        """
        Generate seasonal pattern information
        """
        return {
            "wet_season": water_stress.get("wet_season", "Unknown"),
            "dry_season": water_stress.get("dry_season", "Unknown"),
            "optimal_planting_window": water_stress.get("optimal_planting", "Unknown"),
            "irrigation_timing": "Focus irrigation during dry season and first 2 years of establishment"
        }

    def _generate_planting_implications(self, accessibility: dict, water_stress: dict) -> dict:
        """
        Generate planting implications based on water analysis
        """
        access_rating = accessibility.get('rating', 'moderate')
        stress_level = water_stress.get('baseline_stress', 'medium')
        
        # Species adjustment
        if access_rating in ['poor'] or stress_level in ['high', 'medium-high']:
            species_adjustment = "80% drought-tolerant species, 20% moderate water needs"
        elif access_rating in ['moderate'] or stress_level in ['medium']:
            species_adjustment = "60% drought-tolerant, 40% moderate water needs"
        else:
            species_adjustment = "Standard species mix appropriate. Include riparian species if near water."
        
        # Irrigation recommendation
        if access_rating == 'excellent':
            irrigation_rec = "Irrigation generally not needed with proper timing"
        elif access_rating == 'good':
            irrigation_rec = "Drip irrigation recommended for first 2 years during dry periods"
        elif access_rating == 'moderate':
            irrigation_rec = "Irrigation essential during establishment. Consider rainwater harvesting."
        else:
            irrigation_rec = "Significant irrigation infrastructure needed. Evaluate cost-benefit."
        
        # Success impact
        if access_rating in ['excellent', 'good']:
            success_impact = "Good water access improves survival probability by 15-20%"
        elif access_rating == 'moderate':
            success_impact = "Moderate water access requires drought-tolerant species for success"
        else:
            success_impact = "Poor water access significantly reduces success probability. Careful species selection critical."
        
        return {
            "species_adjustment": species_adjustment,
            "irrigation_recommendation": irrigation_rec,
            "success_impact": success_impact
        }

    def _unavailable_response(self, error: str, lat: float, lng: float, habitat_type: str) -> dict:
        """
        Return response with at least regional water stress when API fails
        """
        water_stress = self._get_regional_water_stress(lat, lng, habitat_type)
        seasonal = self._generate_seasonal_patterns(water_stress)
        
        return {
            "available": False,
            "error": error,
            "water_features": {
                "nearest_water": {"available": False},
                "note": "Water feature data unavailable"
            },
            "water_accessibility": {
                "rating": "unknown",
                "description": "Could not assess - API error"
            },
            "water_stress": water_stress,
            "seasonal_patterns": seasonal,
            "note": "Water features unavailable. Regional water stress data provided from lookup tables.",
            "confidence": "low",
            "data_sources": ["Regional climate databases (water stress only)"]
        }
