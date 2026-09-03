"""
Soil Analysis Agent - Layer 9

Uses ISRIC SoilGrids v2.0 REST API to analyze soil properties
for reforestation suitability assessment.

API Base: https://rest.isric.org/soilgrids/v2.0/properties/query
Authentication: None required (free, open API)
"""

import requests
import time


class SoilAnalysisAgent:
    """
    Analyzes soil properties using ISRIC SoilGrids v2.0 API
    
    Provides:
    - Soil texture classification (USDA)
    - Fertility assessment
    - pH analysis
    - Planting recommendations and amendments
    """
    
    BASE_URL = "https://rest.isric.org/soilgrids/v2.0/properties/query"
    
    # Properties to fetch from SoilGrids
    PROPERTIES = [
        'phh2o',    # pH in water (acidity/alkalinity)
        'clay',     # Clay content (g/kg)
        'sand',     # Sand content (g/kg)
        'silt',     # Silt content (g/kg)
        'soc',      # Soil organic carbon (g/kg)
        'bdod',     # Bulk density (kg/dm³)
        'cec',      # Cation exchange capacity (mmol(c)/kg)
        'nitrogen'  # Total nitrogen (cg/kg)
    ]

    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            'Accept': 'application/json',
            'User-Agent': 'EcoLens/2.0'
        })

    def analyze(self, lat: float, lng: float) -> dict:
        """
        Main entry point - analyze soil at given coordinates
        
        Args:
            lat: Latitude
            lng: Longitude
            
        Returns:
            Complete soil analysis dict
        """
        try:
            # Fetch all soil properties from SoilGrids
            raw_data = self._fetch_soil_properties(lat, lng)
            
            if not raw_data:
                return self._unavailable_response("No data returned from SoilGrids API")
            
            # Extract values from response
            values = self._extract_values(raw_data)
            
            # Process into analysis
            return self._process_soil_data(values, lat, lng)
            
        except Exception as e:
            print(f"❌ Soil analysis error: {e}")
            return self._unavailable_response(str(e))

    def _fetch_soil_properties(self, lat: float, lng: float) -> dict:
        """
        Fetch all soil properties from ISRIC SoilGrids API
        with retry logic and increased timeout
        """
        results = {}
        max_retries = 3
        base_timeout = 60  # Increased from 30s
        
        print(f"   📡 Fetching soil data from ISRIC SoilGrids...")
        
        for prop in self.PROPERTIES:
            for attempt in range(max_retries):
                try:
                    params = {
                        'lon': lng,  # Longitude FIRST (API requirement)
                        'lat': lat,  # Latitude SECOND
                        'property': prop,
                        'depth': '5-15cm',  # Valid depth interval (root zone)
                        'value': 'mean'
                    }
                    
                    response = self.session.get(
                        self.BASE_URL, 
                        params=params, 
                        timeout=base_timeout
                    )
                    
                    if response.status_code == 200:
                        data = response.json()
                        results[prop] = data
                        # Success - log actual value for debugging
                        try:
                            val = data.get('properties', {}).get('layers', [{}])[0].get('depths', [{}])[0].get('values', {}).get('mean')
                            print(f"      ✅ {prop}: {val}")
                        except:
                            pass
                        break  # Success, exit retry loop
                    else:
                        print(f"   ⚠️ SoilGrids returned {response.status_code} for {prop}")
                        results[prop] = None
                        break  # Non-retryable error
                    
                except requests.exceptions.Timeout:
                    if attempt < max_retries - 1:
                        wait_time = (attempt + 1) * 2  # Exponential backoff: 2s, 4s
                        print(f"   ⏳ Timeout for {prop}, retry {attempt + 1}/{max_retries} in {wait_time}s...")
                        time.sleep(wait_time)
                    else:
                        print(f"   ❌ {prop}: Failed after {max_retries} attempts (timeout)")
                        results[prop] = None
                        
                except Exception as e:
                    print(f"   ❌ Error fetching {prop}: {e}")
                    results[prop] = None
                    break
            
            # Rate limiting - be respectful to API
            time.sleep(0.3)
        
        # Check if we got any real data
        real_data_count = sum(1 for v in results.values() if v is not None)
        print(f"   📊 Retrieved {real_data_count}/{len(self.PROPERTIES)} soil properties")
        
        return results

    def _extract_values(self, raw_data: dict) -> dict:
        """
        Extract mean values from SoilGrids response structure
        
        Response structure:
        {
          "properties": {
            "layers": [{
              "depths": [{
                "values": {
                  "mean": 58
                }
              }],
              "unit_measure": {
                "mapped_units": "pH x 10"
              }
            }]
          }
        }
        """
        values = {}
        
        for prop, data in raw_data.items():
            if data is None:
                values[prop] = None
                continue
            
            try:
                layers = data.get('properties', {}).get('layers', [])
                if layers:
                    depths = layers[0].get('depths', [])
                    if depths:
                        mean_val = depths[0].get('values', {}).get('mean')
                        unit = layers[0].get('unit_measure', {}).get('mapped_units', '')
                        values[prop] = {
                            'value': mean_val,
                            'unit': unit
                        }
                    else:
                        values[prop] = None
                else:
                    values[prop] = None
            except (KeyError, IndexError, TypeError) as e:
                print(f"⚠️ Error extracting {prop}: {e}")
                values[prop] = None
        
        return values

    def _process_soil_data(self, values: dict, lat: float, lng: float) -> dict:
        """
        Process raw values into comprehensive soil analysis
        """
        # Extract individual values with unit conversion
        ph_raw = values.get('phh2o', {})
        ph = ph_raw.get('value', 0) / 10.0 if ph_raw and ph_raw.get('value') else None  # pH x 10 -> actual pH
        
        sand_raw = values.get('sand', {})
        sand_g_kg = sand_raw.get('value', 0) if sand_raw and sand_raw.get('value') else 0
        sand_percent = sand_g_kg / 10.0  # g/kg -> %
        
        clay_raw = values.get('clay', {})
        clay_g_kg = clay_raw.get('value', 0) if clay_raw and clay_raw.get('value') else 0
        clay_percent = clay_g_kg / 10.0
        
        silt_raw = values.get('silt', {})
        silt_g_kg = silt_raw.get('value', 0) if silt_raw and silt_raw.get('value') else 0
        silt_percent = silt_g_kg / 10.0
        
        soc_raw = values.get('soc', {})
        soc = soc_raw.get('value', 0) / 10.0 if soc_raw and soc_raw.get('value') else 0  # dg/kg -> g/kg
        
        cec_raw = values.get('cec', {})
        cec = cec_raw.get('value', 0) / 10.0 if cec_raw and cec_raw.get('value') else 0  # mmol(c)/kg / 10
        
        nitrogen_raw = values.get('nitrogen', {})
        nitrogen = nitrogen_raw.get('value', 0) if nitrogen_raw and nitrogen_raw.get('value') else 0  # cg/kg
        
        bdod_raw = values.get('bdod', {})
        bulk_density = bdod_raw.get('value', 0) / 100.0 if bdod_raw and bdod_raw.get('value') else 0  # cg/cm³ -> g/cm³

        # Classify soil texture
        texture_class, texture_desc = self._classify_texture(sand_percent, clay_percent, silt_percent)
        
        # Assess fertility
        fertility_level, fertility_desc = self._assess_fertility(soc, cec)
        
        # Analyze pH
        ph_class, ph_suitability = self._classify_ph(ph) if ph else ("unknown", "pH data unavailable")
        
        # Assess water retention
        water_level, water_desc, irrigation = self._assess_water_retention(texture_class, soc)
        
        # Generate recommendations
        recommendations = self._generate_recommendations(ph, texture_class, soc, clay_percent)
        
        # Determine amendments needed
        amendments = self._determine_amendments(ph, texture_class, soc, fertility_level)
        
        return {
            "available": True,
            "soil_texture": {
                "class": texture_class,
                "sand_percent": round(sand_percent, 1),
                "clay_percent": round(clay_percent, 1),
                "silt_percent": round(silt_percent, 1),
                "description": texture_desc
            },
            "fertility": {
                "level": fertility_level,
                "organic_carbon_g_kg": round(soc, 1),
                "cec_mmol_kg": round(cec, 1),
                "nitrogen_cg_kg": round(nitrogen, 1),
                "interpretation": fertility_desc
            },
            "ph": {
                "value": round(ph, 1) if ph else None,
                "classification": ph_class,
                "suitable_for": ph_suitability
            },
            "bulk_density": {
                "value_g_cm3": round(bulk_density, 2),
                "interpretation": self._interpret_bulk_density(bulk_density)
            },
            "water_retention": {
                "level": water_level,
                "description": water_desc,
                "irrigation_needs": irrigation
            },
            "planting_recommendations": recommendations,
            "amendments_needed": amendments,
            "coordinates": {"lat": lat, "lng": lng},
            "confidence": "medium",
            "data_source": "ISRIC SoilGrids v2.0 (model-based, 250m resolution)",
            "note": "Soil analysis based on global models. Field sampling recommended for final verification."
        }

    def _classify_texture(self, sand: float, clay: float, silt: float) -> tuple:
        """
        USDA soil texture classification based on texture triangle
        """
        if sand > 85:
            return "Sand", "Excellent drainage, very low water retention. Add organic matter."
        elif sand > 70 and clay < 15:
            return "Loamy Sand", "Good drainage, low water retention. Add organic matter."
        elif clay > 40:
            return "Clay", "Poor drainage, waterlogging risk. Improve drainage before planting."
        elif clay > 35 and sand < 45:
            return "Clay Loam", "Moderate drainage. Can become compacted."
        elif sand > 50 and clay < 20 and silt < 50:
            return "Sandy Loam", "Ideal balance - excellent for restoration. Good drainage and structure."
        elif silt > 50 and clay < 27:
            return "Silt Loam", "Good water retention, may crust. Suitable for most species."
        elif silt > 40 and clay < 40:
            return "Loam", "Optimal soil - excellent drainage and water retention. Ideal for planting."
        elif sand > 45 and clay > 20:
            return "Sandy Clay Loam", "Moderate drainage. Good for deep-rooted species."
        else:
            return "Mixed", "Variable properties. Site assessment recommended."

    def _assess_fertility(self, soc: float, cec: float) -> tuple:
        """
        Assess fertility based on organic carbon and CEC
        """
        if soc > 20 and cec > 15:
            return "high", "Excellent natural fertility. Minimal fertilization needed at planting."
        elif soc > 10 and cec > 8:
            return "moderate", "Adequate fertility. Light fertilization recommended at planting."
        elif soc > 5:
            return "low-moderate", "Below optimal fertility. Organic amendments will improve success."
        else:
            return "low", "Low fertility. Organic amendments essential for successful establishment."

    def _classify_ph(self, ph: float) -> tuple:
        """
        Classify pH and determine species suitability
        """
        if ph < 4.5:
            return "strongly acidic", "Very acid-tolerant species only (blueberry, cranberry)"
        elif ph < 5.5:
            return "acidic", "Acid-tolerant species (pine, spruce, oak, rhododendron)"
        elif ph < 6.5:
            return "slightly acidic", "Most species suitable. Optimal for many trees."
        elif ph < 7.5:
            return "neutral", "Excellent for most species. Optimal growing conditions."
        elif ph < 8.5:
            return "alkaline", "Alkali-tolerant species (juniper, ash, elm, hackberry)"
        else:
            return "strongly alkaline", "Limited species. Soil amendment recommended."

    def _assess_water_retention(self, texture: str, soc: float) -> tuple:
        """
        Assess water retention capacity
        """
        high_retention = ["Clay", "Clay Loam", "Silt Loam"]
        moderate_retention = ["Loam", "Sandy Clay Loam", "Mixed"]
        low_retention = ["Sand", "Loamy Sand", "Sandy Loam"]
        
        if texture in high_retention:
            level = "high"
            desc = "High water holding capacity. Good for drought resistance."
            irrigation = "Generally not needed after establishment"
        elif texture in moderate_retention:
            level = "moderate"
            desc = "Moderate water holding capacity. Most species suitable."
            irrigation = "Irrigation helpful during establishment (1-2 years)"
        else:
            level = "low"
            desc = "Low water holding capacity. Frequent watering may be needed."
            irrigation = "Regular irrigation essential during establishment (2-3 years)"
        
        # Organic matter improves water retention
        if soc > 15 and level == "low":
            level = "low-moderate"
            desc += " Organic matter helps retention."
        
        return level, desc, irrigation

    def _interpret_bulk_density(self, bd: float) -> str:
        """
        Interpret bulk density for root penetration
        """
        if bd < 1.1:
            return "Low density - excellent root penetration and aeration"
        elif bd < 1.4:
            return "Moderate density - good conditions for most species"
        elif bd < 1.6:
            return "Moderately high - may restrict root growth. Consider deep ripping."
        else:
            return "High density - compacted soil. Remediation recommended before planting."

    def _generate_recommendations(self, ph: float, texture: str, soc: float, clay: float) -> list:
        """
        Generate planting recommendations based on soil properties
        """
        recommendations = []
        
        # pH-based recommendations
        if ph and ph < 5.5:
            recommendations.append("Acidic soil: Choose acid-tolerant species (pine, spruce, oak) or apply lime (2-3 tonnes/ha)")
        elif ph and ph > 7.5:
            recommendations.append("Alkaline soil: Choose alkali-tolerant species (juniper, ash, mesquite) or apply sulfur amendment")
        
        # Texture-based recommendations
        if texture in ["Sand", "Loamy Sand"]:
            recommendations.append("Sandy soil: Add 10-15cm organic mulch before planting to improve water retention")
            recommendations.append("Consider drought-tolerant species for sandy conditions")
        elif texture == "Clay":
            recommendations.append("Clay soil: Ensure adequate drainage. Avoid planting in depressions.")
            recommendations.append("Use deep-rooted species that tolerate poor drainage")
        elif texture in ["Loam", "Sandy Loam"]:
            recommendations.append("Excellent soil structure - suitable for wide range of species")
        
        # Organic matter recommendations
        if soc < 10:
            recommendations.append("Low organic matter: Apply 5-10cm compost layer before planting")
        elif soc < 15:
            recommendations.append("Moderate organic matter: Light application of compost recommended")
        
        # Clay-specific
        if clay > 35:
            recommendations.append("High clay content: Consider raised planting beds or mounded planting")
        
        if not recommendations:
            recommendations.append("Soil conditions are favorable for most native species")
        
        return recommendations

    def _determine_amendments(self, ph: float, texture: str, soc: float, fertility: str) -> list:
        """
        Determine soil amendments needed
        """
        amendments = []
        
        # pH amendments
        if ph and ph < 5.0:
            amendments.append({
                "type": "Agricultural lime",
                "amount": "2-4 tonnes/ha",
                "reason": "Raise pH for broader species compatibility",
                "cost_per_ha": 200
            })
        elif ph and ph > 8.0:
            amendments.append({
                "type": "Elemental sulfur",
                "amount": "500-1000 kg/ha",
                "reason": "Lower pH for better nutrient availability",
                "cost_per_ha": 300
            })
        
        # Organic matter amendments
        if soc < 10:
            amendments.append({
                "type": "Compost/organic matter",
                "amount": "20-30 tonnes/ha",
                "reason": "Improve soil structure, fertility, and water retention",
                "cost_per_ha": 500
            })
        elif soc < 15:
            amendments.append({
                "type": "Organic mulch",
                "amount": "5-10 cm layer",
                "reason": "Improve soil structure and moisture retention",
                "cost_per_ha": 300
            })
        
        # Texture-based amendments
        if texture == "Sand":
            amendments.append({
                "type": "Bentonite clay or biochar",
                "amount": "2-5 tonnes/ha",
                "reason": "Improve water retention in sandy soil",
                "cost_per_ha": 400
            })
        elif texture == "Clay":
            amendments.append({
                "type": "Gypsum",
                "amount": "2-4 tonnes/ha",
                "reason": "Improve clay structure and drainage",
                "cost_per_ha": 250
            })
        
        # Fertility amendments
        if fertility == "low":
            amendments.append({
                "type": "Slow-release fertilizer (NPK)",
                "amount": "200-400 kg/ha",
                "reason": "Boost initial nutrient availability for establishment",
                "cost_per_ha": 350
            })
        
        return amendments

    def _unavailable_response(self, error: str) -> dict:
        """
        Return standardized response when soil data unavailable
        """
        return {
            "available": False,
            "error": error,
            "note": "Soil data unavailable. Manual soil testing recommended before planting.",
            "recommendation": "Collect soil samples (0-30cm depth) from 5+ locations for lab analysis before final species selection",
            "confidence": "none",
            "data_source": "N/A"
        }
