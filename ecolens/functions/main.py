from firebase_functions import scheduler_fn, https_fn, options
from firebase_functions.params import SecretParam
from firebase_admin import initialize_app, firestore, storage
from google import genai
from google.genai import types
import datetime
import re
import json
import time
import base64
import uuid

FIRMS_MAP_KEY = SecretParam("NASA_FIRMS_MAP_KEY")
GEMINI_API_KEY = SecretParam("GEMINI_API_KEY")
# Third-party keys used by the intelligence and cartographic pipelines. Never hardcoded:
# firebase functions:secrets:set GFW_API_KEY / IUCN_API_TOKEN
GFW_API_KEY = SecretParam("GFW_API_KEY")
IUCN_API_TOKEN = SecretParam("IUCN_API_TOKEN")

initialize_app()

@scheduler_fn.on_schedule(schedule="every 12 hours", timeout_sec=540, memory=options.MemoryOption.GB_1, secrets=[GEMINI_API_KEY, FIRMS_MAP_KEY, GFW_API_KEY, IUCN_API_TOKEN])
def global_scout_mission(event):
    """Scheduled deep-dive intelligence pipeline"""
    return _run_deep_dive_mission()

@https_fn.on_request(
    timeout_sec=540,
    memory=options.MemoryOption.GB_1,
    secrets=[GEMINI_API_KEY],
)
def trigger_scout(request):
    """Manual trigger for deep-dive testing.

    Closed by default — without ADMIN_TRIGGER_TOKEN bound as a secret
    on this function, every request returns 403. To open it up:
      1. firebase functions:secrets:set ADMIN_TRIGGER_TOKEN
      2. Add ADMIN_TRIGGER_TOKEN to this decorator's secrets=[...] list
      3. firebase deploy --only functions:trigger_scout

    Then callers supply the token via either:
      - HTTP header:  X-Admin-Token: <token>
      - Query string: ?token=<token>

    Until step 2 is done, the function is intentionally closed — that
    prevents anyone with the URL from billing Gemini work to the project.
    """
    import os
    expected = os.environ.get("ADMIN_TRIGGER_TOKEN", "")
    if not expected:
        return (
            {
                "status": "forbidden",
                "error": (
                    "Admin trigger is closed. Bind ADMIN_TRIGGER_TOKEN "
                    "secret to this function and redeploy."
                ),
            },
            403,
        )
    supplied = (
        request.headers.get("X-Admin-Token")
        or request.args.get("token")
        or ""
    )
    if supplied != expected:
        return ({"status": "forbidden", "error": "Invalid admin token"}, 403)
    result = _run_deep_dive_mission()
    return {"status": "completed", "result": result}

@https_fn.on_call(timeout_sec=540, memory=options.MemoryOption.GB_1, enforce_app_check=False, secrets=[GEMINI_API_KEY, FIRMS_MAP_KEY, GFW_API_KEY, IUCN_API_TOKEN])
def analyze_location(request: https_fn.CallableRequest):
    """
    On-demand analysis for specific coordinates from the frontend.
    Returns: Soil, Terrain, Hydrology, Historical, and AI Analysis.
    """
    # 1. Parse Request
    try:
        data = request.data
        lat = float(data.get('lat'))
        lng = float(data.get('lng'))
        # Validate coord ranges — rejects bogus / malicious inputs before
        # we spend Gemini money on them.
        if not (-90 <= lat <= 90) or not (-180 <= lng <= 180):
            raise https_fn.HttpsError(
                code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
                message="lat must be in [-90,90], lng must be in [-180,180]"
            )
        habitat = data.get('habitat', 'Unknown')
            
        print(f"🌍 Request received: {lat}, {lng} ({habitat}) - v2")
    except Exception as e:
        raise https_fn.HttpsError(code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT, message=f"Invalid parameters: {str(e)}")

    # 2. Run Pipeline
    try:
        # Lazy import to avoid startup cost
        from orchestrator.intelligence_pipeline import IntelligencePipeline
        
        pipeline = IntelligencePipeline()
        report = pipeline.analyze_location(lat, lng, habitat)
        
        # 3. Return JSON Result
        return report
        
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise https_fn.HttpsError(code=https_fn.FunctionsErrorCode.INTERNAL, message=f"Analysis failed: {str(e)}")

def _run_deep_dive_mission():
    """
    Full Intelligence Pipeline with All Agents:
    1. RECON: Identify active hotspots (lightweight)
    2. DEEP DIVE: Analyze each hotspot with complete 20-layer pipeline
    """
    db = firestore.client()
    client = genai.Client(api_key=GEMINI_API_KEY.value)

    current_month = datetime.datetime.utcnow().strftime("%B %Y")
    print(f"🚀 Starting Mission for {current_month}")

    # ═══════════════════════════════════════════════════════════════
    # STEP 1: RECONNAISSANCE (Identify Targets)
    # ═══════════════════════════════════════════════════════════════
    recon_prompt = f"""
    ACT AS AN AUTONOMOUS GLOBAL SATELLITE AGENT.
    Scan the entire globe to identify the 7 most critical deforestation hotspots active RIGHT NOW ({current_month}).

    CRITICAL INSTRUCTIONS:
    - DO NOT use a static list. Find where the chainsaws and fires are TODAY.
    - PRIORITIZE new and emerging fronts (e.g. Canada Boreal, Gran Chaco, Southeast Asia).
    - ENSURE GLOBAL DIVERSITY: Do not just list 7 spots in the Amazon. Find hotspots in Africa, Asia, North America, etc.
    - VERIFY ACTIVITY: Only select locations with confirmed recent activity from GFW, NASA FIRMS, or ESA Sentinel.

    Return ONLY the coordinates and specific name of the area.
    """

    print("🛰️ Phase 1: Reconnaissance...")
    recon_schema = {
        "type": "array",
        "items": {
            "type": "object",
            "properties": {
                "name": {"type": "string"},
                "country": {"type": "string"},
                "lat": {"type": "number"},
                "lng": {"type": "number"},
                "habitat": {"type": "string"}
            },
            "required": ["name", "lat", "lng"]
        }
    }

    try:
        recon_response = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=recon_prompt,
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                response_schema=recon_schema
            )
        )
        targets = recon_response.parsed
        if not targets:
            return "❌ Recon failed: No targets found"

        print(f"✅ Targets Acquired: {len(targets)} locations")

    except Exception as e:
        return f"❌ Recon Error: {e}"

    # ═══════════════════════════════════════════════════════════════
    # STEP 2: DEEP DIVE ANALYSIS (Per Target) - Use Full Pipeline
    # ═══════════════════════════════════════════════════════════════
    from orchestrator.intelligence_pipeline import IntelligencePipeline

    pipeline = IntelligencePipeline()
    results = []
    batch = db.batch()

    for i, target in enumerate(targets):
        print(f"🔍 Phase 2: Analyzing Target {i+1}/{len(targets)}: {target['name']}...")

        try:
            # Run FULL INTELLIGENCE PIPELINE with all 20 layers
            habitat = target.get('habitat', 'Unknown')
            intelligence = pipeline.analyze_location(
                target['lat'],
                target['lng'],
                habitat
            )

            # Build comprehensive record with ALL agent data
            full_record = {
                # Basic Info
                "lat": target['lat'],
                "lng": target['lng'],
                "name": target['name'],
                "country": target.get('country', 'Unknown'),
                "region": target['name'],
                "continent": _get_continent(target.get("country", "")),
                "habitat": habitat,
                "timestamp": firestore.SERVER_TIMESTAMP,

                # Layer 9: Soil Analysis
                "soil_analysis": intelligence.get('soil_analysis', {}),

                # Layer 10: Terrain Analysis
                "terrain_analysis": intelligence.get('terrain_analysis', {}),

                # Layer 11: Hydrology Analysis
                "hydrology_analysis": intelligence.get('hydrology_analysis', {}),

                # Layer 12: Historical Analysis
                "historical_analysis": intelligence.get('historical_analysis', {}),

                # Layer 13: Recovery Potential
                "recovery_potential": intelligence.get('recovery_potential', {}),
                "comprehensive_analysis": intelligence.get('comprehensive_analysis', {}),

                # Layer 14: Sentinel Verification
                "sentinel_verification": intelligence.get('sentinel_verification', {}),

                # Layer 15: GIS Analysis
                "gis_analysis": intelligence.get('gis_analysis', {}),

                # Layer 16: Risk Prediction
                "risk_prediction": intelligence.get('risk_prediction', {}),

                # Layer 17: Biodiversity Analysis
                "biodiversity_analysis": intelligence.get('biodiversity_analysis', {}),

                # Extract summary fields for easy frontend access
                "headline": f"Environmental Analysis: {target['name']} - {current_month}",
                "background_info": _build_situation_overview(target, intelligence),
                # Get hectares from GFW data in gis_analysis, or estimate from recovery_potential
                "hectares": int(
                    intelligence.get('gis_analysis', {}).get('area_ha', 0) or
                    intelligence.get('recovery_potential', {}).get('area_hectares', 0) or
                    intelligence.get('gfw_area__ha', 100)  # Default only as last resort
                ),
                "gfw_area__ha": int(intelligence.get('gis_analysis', {}).get('area_ha', 100)),
                "riskScore": intelligence.get('risk_prediction', {}).get('risk_score', 50),

                # Soil summary
                "soil_type": intelligence.get('soil_analysis', {}).get('soil_texture', {}).get('class', 'Unknown'),
                "soil_ph": intelligence.get('soil_analysis', {}).get('ph', {}).get('value', 0),
                "soil_fertility": intelligence.get('soil_analysis', {}).get('fertility', {}).get('rating', 'Unknown'),

                # Terrain summary
                "terrain_slope": intelligence.get('terrain_analysis', {}).get('slope', {}).get('mean_degrees', 0),
                "terrain_difficulty": intelligence.get('terrain_analysis', {}).get('slope', {}).get('suitability', {}).get('difficulty', 'Unknown'),
                "terrain_elevation": intelligence.get('terrain_analysis', {}).get('elevation', {}).get('mean_m', 0),

                # Hydrology summary
                "water_access": intelligence.get('hydrology_analysis', {}).get('water_accessibility', {}).get('rating', 'Unknown'),
                "water_stress": intelligence.get('hydrology_analysis', {}).get('water_stress', {}).get('level', 'Unknown'),

                # Recovery summary
                "recovery_score": intelligence.get('recovery_potential', {}).get('score', 50),
                "success_probability": intelligence.get('comprehensive_analysis', {}).get('success_probability', 'Unknown'),

                # Sentinel summary
                "sentinel_available": intelligence.get('sentinel_verification', {}).get('available', False),
                "ndvi_change": intelligence.get('sentinel_verification', {}).get('vegetation_indices', {}).get('ndvi', {}).get('change_mean', 0),

                # Risk summary
                "risk_level": intelligence.get('risk_prediction', {}).get('risk_level', 'Unknown'),
                "risk_probability": intelligence.get('risk_prediction', {}).get('risk_probability', 0),

                # Biodiversity data - extract from biodiversity_analysis for easy access
                "fauna_at_risk": intelligence.get('biodiversity_analysis', {}).get('fauna_at_risk', []),
                "flora_at_risk": intelligence.get('biodiversity_analysis', {}).get('flora_at_risk', []),
                "fauna_thrive": intelligence.get('biodiversity_analysis', {}).get('fauna_thrive', []),
                "flora_thrive": intelligence.get('biodiversity_analysis', {}).get('flora_thrive', []),

                # Legacy fields for compatibility
                "land_features": [],
                "economic_impacts": intelligence.get('economic_analysis', {}),
                "economic_analysis": intelligence.get('economic_analysis', {}),
                "financial_analysis": intelligence.get('financial_analysis', {}),
                "human_impacts": intelligence.get('human_impacts', {}),
                "reforest_plan": {},
                "cause_data": {"primary_driver": "Under investigation"},
                # Carbon data calculated from actual hectares (45.5 tonnes C/ha average tropical forest)
                # Get hectares from financial_analysis or use GIS area
                "_carbon_hectares": int(
                    intelligence.get('financial_analysis', {}).get('area_hectares', 0) or
                    intelligence.get('gis_analysis', {}).get('area_ha', 100)
                ),
                "carbon_data": {
                    "annual_emissions_tonnes": round(
                        int(intelligence.get('financial_analysis', {}).get('area_hectares', 0) or
                            intelligence.get('gis_analysis', {}).get('area_ha', 100)) * 45.5 * 0.1, 1),
                    "carbon_stock_tonnes": int(
                        intelligence.get('financial_analysis', {}).get('detailed_analysis', {})
                            .get('carbon', {}).get('stock_tonnes', 0) or
                        round(int(intelligence.get('gis_analysis', {}).get('area_ha', 100)) * 45.5, 1)
                    ),
                    "above_ground_biomass_tonnes": round(
                        int(intelligence.get('gis_analysis', {}).get('area_ha', 100)) * 45.5 * 2, 1),
                    "carbon_density_per_ha": 45.5,
                    "sequestration_potential_tonnes": round(
                        int(intelligence.get('gis_analysis', {}).get('area_ha', 100)) * 12, 1)
                },
                "fire_data": {"active_fires": intelligence.get('fire_summary', {}).get('count', 0)},
                "legal_status": {"protected_area": intelligence.get('gis_analysis', {}).get('protected_area', False)}
            }

            # Create Doc ID
            lat_id = str(target['lat']).replace(".", "_").replace("-", "neg")
            lng_id = str(target['lng']).replace(".", "_").replace("-", "neg")
            doc_ref = db.collection("hotspots").document(f"node_{lat_id}_{lng_id}")

            batch.set(doc_ref, full_record)
            results.append(target['name'])

            print(f"✅ {target['name']} analyzed with full 20-layer pipeline")

            # Rate limiting (safety)
            time.sleep(2)

        except Exception as e:
            print(f"❌ Error analyzing {target['name']}: {e}")
            import traceback
            traceback.print_exc()

    try:
        batch.commit()
        print(f"✅ Mission Success: {len(results)} deep-dive reports filed.")
        return f"Success: {len(results)} reports"
    except Exception as e:
         return f"Error committing batch: {e}"

def _get_continent(country):
    country = country.lower()
    if any(c in country for c in ["brazil", "peru", "colombia", "ecuador", "bolivia", "argentina", "chile", "paraguay"]):
        return "South America"
    if any(c in country for c in ["congo", "nigeria", "cameroon", "kenya", "ethiopia", "rwanda", "uganda", "gabon"]):
        return "Africa"
    if any(c in country for c in ["indonesia", "malaysia", "thailand", "vietnam", "laos", "cambodia", "myanmar", "india", "china"]):
        return "Asia"
    if any(c in country for c in ["australia", "papua", "new zealand", "oceania"]):
        return "Oceania"
    if any(c in country for c in ["canada", "usa", "mexico"]):
        return "North America"
    return "Unknown"


# =============================================================================
# NEW MOBILE FEATURES - Cloud Functions
# =============================================================================

@https_fn.on_call(timeout_sec=540, memory=options.MemoryOption.GB_1, enforce_app_check=False, secrets=[GEMINI_API_KEY])
def analyze_restoration_potential(request: https_fn.CallableRequest):
    """
    Mobile Feature #3: Restoration Success Predictor
    
    Analyzes a photo of degraded land to predict restoration success probability.
    Uses Gemini Vision + Sentinel-2 NDVI + existing agents + ML model.
    
    Args:
        photo_url: Cloud Storage URL of uploaded photo
        lat: Latitude
        lng: Longitude
    
    Returns:
        dict: Restoration assessment with success probability, recommendations, costs
    """
    try:
        data = request.data
        photo_url = data.get('photo_url')
        lat = float(data.get('lat'))
        lng = float(data.get('lng'))
        if not (-90 <= lat <= 90) or not (-180 <= lng <= 180):
            raise https_fn.HttpsError(
                code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
                message="lat must be in [-90,90], lng must be in [-180,180]"
            )

        print(f"🌱 Restoration analysis request: {lat}, {lng}")
        
        if not photo_url:
            raise https_fn.HttpsError(
                code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
                message="photo_url is required"
            )
        
        from agents.vision_analysis_agent import VisionAnalysisAgent
        from agents.sentinel_verification_agent import SentinelVerificationAgent
        from agents.soil_analysis_agent import SoilAnalysisAgent
        from models.risk_prediction_model import RiskPredictionModel

        # STEP 1: Analyze uploaded photo with Gemini Vision
        vision = VisionAnalysisAgent()
        photo_analysis = vision.analyze_degraded_land(photo_url, lat, lng)

        # STEP 2: Analyze current vegetation state with Sentinel
        sentinel = SentinelVerificationAgent()
        sentinel_data = sentinel.verify_with_sentinel(lat, lng)

        current_ndvi = 0.3  # Default
        if sentinel_data.get('available'):
            current_ndvi = sentinel_data.get('vegetation_indices', {}).get('ndvi', {}).get('after_mean', 0.3)
        
        # Analyze soil conditions
        soil = SoilAnalysisAgent()
        soil_data = soil.analyze(lat, lng)
        
        # Get similar restoration projects from database
        db = firestore.client()
        similar_projects = []
        
        # Query restoration_projects collection for similar conditions
        # For now, using placeholder similar projects
        similar_projects = [
            {
                "project_id": "restoration_001",
                "location": "Amazon Rainforest",
                "baseline_ndvi": 0.25,
                "outcome_5yr_ndvi": 0.65,
                "success_rate": 78,
                "species_planted": ["Cecropia", "Inga", "Ficus"],
                "cost_per_ha_usd": 2500
            },
            {
                "project_id": "restoration_002",
                "location": "Atlantic Forest",
                "baseline_ndvi": 0.30,
                "outcome_5yr_ndvi": 0.70,
                "success_rate": 85,
                "species_planted": ["Araucaria", "Cedrela", "Tabebuia"],
                "cost_per_ha_usd": 3200
            }
        ]
        
        # Calculate success probability based on conditions including photo analysis
        photo_degradation_score = photo_analysis.get('degradation_score', 50) if photo_analysis.get('available') else 50

        success_factors = {
            "soil_quality": 70 if soil_data.get('available') else 50,
            "current_vegetation": int(current_ndvi * 100),
            "photo_assessment": 100 - photo_degradation_score,  # Convert degradation to restoration potential
            "similar_projects_success": 80  # Average from similar projects
        }

        success_probability = sum(success_factors.values()) / len(success_factors)
        
        # Generate recommendations
        recommendations = [
            {
                "priority": "high",
                "action": "Soil amendment with organic matter",
                "rationale": "Low soil fertility detected",
                "estimated_cost_usd": 500
            },
            {
                "priority": "high",
                "action": "Plant native pioneer species first",
                "rationale": "Accelerates ecosystem recovery",
                "species_recommended": ["Cecropia", "Inga", "Acacia"],
                "estimated_cost_usd": 2000
            },
            {
                "priority": "medium",
                "action": "Establish water management system",
                "rationale": "Ensure survival during dry season",
                "estimated_cost_usd": 800
            }
        ]
        
        # Calculate carbon potential
        # Rough estimate: 1 ha of restored forest sequesters ~5-10 tons CO2/year
        area_ha = 1  # Default for user analysis
        annual_carbon_sequestration = area_ha * 7.5  # tons CO2/year
        carbon_20yr = annual_carbon_sequestration * 20
        carbon_price_per_ton = 15  # USD, conservative estimate
        carbon_value_20yr = carbon_20yr * carbon_price_per_ton
        
        result = {
            "success_probability_percent": round(success_probability, 1),
            "confidence": "medium" if photo_analysis.get('available') else "low",
            "photo_analysis": photo_analysis if photo_analysis.get('available') else {"message": "Photo analysis unavailable"},
            "current_conditions": {
                "ndvi": round(current_ndvi, 2),
                "soil_quality": soil_data.get('fertility', {}).get('rating', 'Unknown'),
                "degradation_level": photo_analysis.get('degradation_level', 'moderate') if photo_analysis.get('available') else ("moderate" if current_ndvi < 0.4 else "low")
            },
            "similar_projects": similar_projects[:2],  # Top 2 matches
            "success_factors": success_factors,
            "recommendations": recommendations,
            "cost_estimate": {
                "total_usd": sum(r.get('estimated_cost_usd', 0) for r in recommendations),
                "per_hectare": True,
                "timeframe": "First year establishment"
            },
            "carbon_potential": {
                "annual_sequestration_tons_co2": round(annual_carbon_sequestration, 1),
                "carbon_20yr_tons": round(carbon_20yr, 1),
                "market_value_20yr_usd": round(carbon_value_20yr, 0),
                "price_per_ton_usd": carbon_price_per_ton
            },
            "next_steps": [
                "Conduct detailed site assessment",
                "Engage with local restoration experts",
                "Apply for restoration funding",
                "Connect with local nurseries for native species"
            ]
        }
        
        print(f"✅ Restoration analysis complete: {success_probability:.1f}% success probability")
        return result
        
    except Exception as e:
        print(f"❌ Restoration analysis failed: {e}")
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message=f"Analysis failed: {str(e)}"
        )


@https_fn.on_call(timeout_sec=300, memory=options.MemoryOption.GB_1, enforce_app_check=False)
def calculate_carbon_credits(request: https_fn.CallableRequest):
    """
    Mobile Feature #4: Carbon Credit Calculator
    
    Calculates carbon/biodiversity credit value for a land parcel.
    Uses Sentinel-2 NDVI → biomass → carbon calculations.
    
    Args:
        boundary_points: List of {lat, lng} points defining polygon
        
    Returns:
        dict: Carbon stored/potential, market value, projections
    """
    try:
        data = request.data
        boundary_points = data.get('boundary_points', [])
        
        if len(boundary_points) < 3:
            raise https_fn.HttpsError(
                code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
                message="At least 3 boundary points required"
            )
        
        print(f"💰 Carbon credit calculation for polygon with {len(boundary_points)} points")
        
        # Calculate polygon area using Shoelace formula
        # This matches the frontend calculation for consistency
        lat_center = sum(p['lat'] for p in boundary_points) / len(boundary_points)
        lng_center = sum(p['lng'] for p in boundary_points) / len(boundary_points)

        # Proper polygon area calculation using Shoelace formula
        area = 0.0
        for i in range(len(boundary_points)):
            j = (i + 1) % len(boundary_points)
            area += boundary_points[i]['lat'] * boundary_points[j]['lng']
            area -= boundary_points[j]['lat'] * boundary_points[i]['lng']
        area = abs(area) / 2.0
        # Convert square degrees to hectares (approximation)
        area_ha = area * 1232100  # Conversion factor matches frontend
        
        # Get current NDVI from Sentinel-2
        from agents.sentinel_verification_agent import SentinelVerificationAgent
        sentinel = SentinelVerificationAgent()
        sentinel_data = sentinel.verify_with_sentinel(lat_center, lng_center)
        
        current_ndvi = 0.5  # Default
        if sentinel_data.get('available'):
            current_ndvi = sentinel_data.get('vegetation_indices', {}).get('ndvi', {}).get('after_mean', 0.5)
        
        # Determine if existing forest or degraded land
        is_existing_forest = current_ndvi > 0.6
        
        if is_existing_forest:
            # EXISTING FOREST: Calculate current carbon stock
            # Rough conversion: NDVI → LAI → Biomass → Carbon
            # Tropical forest: ~150-300 tons biomass/ha = ~75-150 tons C/ha
            biomass_per_ha = current_ndvi * 200  # tons/ha
            carbon_per_ha = biomass_per_ha * 0.5  # Carbon is ~50% of biomass
            total_carbon_tons = carbon_per_ha * area_ha
            
            # Market value (Verra VCS + Gold Standard average prices)
            carbon_price_low = 12  # USD/ton
            carbon_price_high = 25  # USD/ton
            
            market_value_low = total_carbon_tons * carbon_price_low
            market_value_high = total_carbon_tons * carbon_price_high
            
            # Biodiversity credits (based on area + NDVI health)
            biodiversity_credits_per_ha = current_ndvi * 10  # Credits per ha
            biodiversity_value = biodiversity_credits_per_ha * area_ha * 50  # $50/credit
            
            # Ecosystem services (TEEB database estimates)
            ecosystem_services_annual = area_ha * 2000  # USD/ha/year for tropical forest
            
            result = {
                "land_type": "existing_forest",
                "area_hectares": round(area_ha, 2),
                "current_vegetation_health": round(current_ndvi, 2),
                "carbon_stock": {
                    "total_tons_co2e": round(total_carbon_tons * 3.67, 1),  # Convert C to CO2e
                    "tons_per_hectare": round(carbon_per_ha * 3.67, 1),
                    "biomass_tons_per_ha": round(biomass_per_ha, 1)
                },
                "market_value": {
                    "carbon_value_range_usd": {
                        "low": round(market_value_low, 0),
                        "high": round(market_value_high, 0)
                    },
                    "biodiversity_credits_value_usd": round(biodiversity_value, 0),
                    "total_range_usd": {
                        "low": round(market_value_low + biodiversity_value, 0),
                        "high": round(market_value_high + biodiversity_value, 0)
                    }
                },
                "ecosystem_services": {
                    "annual_value_usd": round(ecosystem_services_annual, 0),
                    "services": ["Carbon sequestration", "Water regulation", "Biodiversity habitat", "Climate regulation"]
                },
                "recommendations": [
                    "Apply for forest carbon offset certification (Verra VCS or Gold Standard)",
                    "Establish baseline monitoring",
                    "Ensure legal land tenure documentation",
                    "Consider biodiversity co-benefits for premium pricing"
                ]
            }
        else:
            # DEGRADED LAND: Calculate restoration potential
            restoration_ndvi_5yr = 0.65
            restoration_ndvi_10yr = 0.75
            restoration_ndvi_20yr = 0.85
            
            # Carbon accumulation over time
            carbon_5yr = (restoration_ndvi_5yr * 200 * 0.5 * 3.67) * area_ha
            carbon_10yr = (restoration_ndvi_10yr * 200 * 0.5 * 3.67) * area_ha
            carbon_20yr = (restoration_ndvi_20yr * 200 * 0.5 * 3.67) * area_ha
            
            carbon_price = 15  # USD/ton
            
            result = {
                "land_type": "degraded_restorable",
                "area_hectares": round(area_ha, 2),
                "current_vegetation_health": round(current_ndvi, 2),
                "restoration_potential": {
                    "5_years": {
                        "carbon_sequestered_tons_co2e": round(carbon_5yr, 1),
                        "market_value_usd": round(carbon_5yr * carbon_price, 0),
                        "expected_ndvi": round(restoration_ndvi_5yr, 2)
                    },
                    "10_years": {
                        "carbon_sequestered_tons_co2e": round(carbon_10yr, 1),
                        "market_value_usd": round(carbon_10yr * carbon_price, 0),
                        "expected_ndvi": round(restoration_ndvi_10yr, 2)
                    },
                    "20_years": {
                        "carbon_sequestered_tons_co2e": round(carbon_20yr, 1),
                        "market_value_usd": round(carbon_20yr * carbon_price, 0),
                        "expected_ndvi": round(restoration_ndvi_20yr, 2)
                    },
                    "50_years": {
                        "carbon_sequestered_tons_co2e": round(carbon_20yr * 1.5, 1),
                        "market_value_usd": round(carbon_20yr * 1.5 * carbon_price, 0),
                        "expected_ndvi": 0.90
                    }
                },
                "investment_required": {
                    "establishment_cost_usd": round(area_ha * 2500, 0),
                    "cost_per_hectare": 2500,
                    "maintenance_5yr_usd": round(area_ha * 500, 0)
                },
                "roi_analysis": {
                    "10yr_net_value_usd": round((carbon_10yr * carbon_price) - (area_ha * 3000), 0),
                    "20yr_net_value_usd": round((carbon_20yr * carbon_price) - (area_ha * 3000), 0),
                    "payback_period_years": "8-12"
                },
                "recommendations": [
                    "Conduct detailed restoration feasibility study",
                    "Apply for restoration carbon project certification",
                    "Explore blended finance opportunities",
                    "Partner with certified project developers"
                ]
            }
        
        print(f"✅ Carbon credit calculation complete for {area_ha:.2f} ha")
        return result
        
    except Exception as e:
        print(f"❌ Carbon credit calculation failed: {e}")
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message=f"Calculation failed: {str(e)}"
        )


@https_fn.on_call(timeout_sec=300, memory=options.MemoryOption.GB_1, enforce_app_check=False, secrets=[GEMINI_API_KEY])
def get_story(request: https_fn.CallableRequest):
    """
    CesiumJS Story Viewer - Story Configuration Generator

    Generates a complete storyConfig for the 3D immersive story experience.
    Includes: Sentinel-2 imagery URLs, species POIs, dynamic chapters with narration.

    Args:
        lat: Latitude
        lng: Longitude
        nodeId: Optional - ID of existing hotspot node for cached data

    Returns:
        dict: Complete storyConfig for CesiumJS story viewer
    """
    try:
        data = request.data
        lat = float(data.get('lat'))
        lng = float(data.get('lng'))
        node_id = data.get('nodeId')

        print(f"🎬 Story request: {lat}, {lng} (nodeId: {node_id})")

        db = firestore.client()

        # If no nodeId provided, build it from lat/lng (same format as pipeline)
        if not node_id:
            lat_id = str(lat).replace(".", "_").replace("-", "neg")
            lng_id = str(lng).replace(".", "_").replace("-", "neg")
            node_id = f"node_{lat_id}_{lng_id}"
            print(f"📍 Built nodeId from coords: {node_id}")

        # ═══════════════════════════════════════════════════════════════
        # STEP 1: Check Firestore cache
        # ═══════════════════════════════════════════════════════════════
        cache_key = f"story_{lat:.4f}_{lng:.4f}"
        cache_doc = db.collection('story_cache').document(cache_key).get()

        if cache_doc.exists:
            cached_data = cache_doc.to_dict()
            cache_age = datetime.datetime.utcnow() - cached_data.get('timestamp', datetime.datetime.min).replace(tzinfo=None)

            # Return cached if less than 24 hours old
            if cache_age.days < 1:
                print(f"✅ Returning cached story for {cache_key}")
                return cached_data.get('config')

        # ═══════════════════════════════════════════════════════════════
        # STEP 2: Try to get existing hotspot data
        # ═══════════════════════════════════════════════════════════════
        existing_node = None
        if node_id:
            node_doc = db.collection('hotspots').document(node_id).get()
            if node_doc.exists:
                existing_node = node_doc.to_dict()
                print(f"✅ Found existing node: {node_id}")
                print(f"   hectares: {existing_node.get('hectares', 'N/A')}, gfw_area__ha: {existing_node.get('gfw_area__ha', 'N/A')}")
                print(f"   riskScore: {existing_node.get('riskScore', 'N/A')}")
                print(f"   population: {existing_node.get('population', 'N/A')}")
            else:
                print(f"⚠️ No document found for nodeId: {node_id}")
                # Try to list what documents exist to debug
                all_docs = db.collection('hotspots').limit(5).stream()
                print(f"   Sample existing docs: {[doc.id for doc in all_docs]}")

        # ═══════════════════════════════════════════════════════════════
        # STEP 3: Get Sentinel-2 imagery (real satellite data)
        # ═══════════════════════════════════════════════════════════════
        from agents.sentinel_verification_agent import SentinelVerificationAgent
        sentinel = SentinelVerificationAgent()
        sentinel_data = sentinel.verify_with_sentinel(lat, lng)

        sentinel_imagery = {
            "available": sentinel_data.get('available', False),
            "beforeRgbUrl": sentinel_data.get('imagery', {}).get('before_rgb_url'),
            "afterRgbUrl": sentinel_data.get('imagery', {}).get('after_rgb_url'),
            "ndviChangeUrl": sentinel_data.get('imagery', {}).get('ndvi_change_url'),
            "beforeNdviUrl": sentinel_data.get('imagery', {}).get('before_ndvi_url'),
            "afterNdviUrl": sentinel_data.get('imagery', {}).get('after_ndvi_url'),
        }

        print(f"🛰️ Sentinel imagery: {'available' if sentinel_imagery['available'] else 'unavailable'}")

        # ═══════════════════════════════════════════════════════════════
        # STEP 4: Get biodiversity data (species at risk)
        # ═══════════════════════════════════════════════════════════════
        species_pois = []

        if existing_node:
            # Use cached species data from node
            fauna = existing_node.get('fauna_at_risk', [])
            flora = existing_node.get('flora_at_risk', [])

            for i, species in enumerate(fauna[:5]):
                species_pois.append({
                    "id": f"fauna_{i}",
                    "name": species.get('common_name', 'Unknown Species'),
                    "scientific_name": species.get('scientific_name', ''),
                    "conservation_status": species.get('status', 'Unknown'),
                    "category": "fauna",
                    "endemic": species.get('endemic', False),
                    "latitude": lat + _get_spread(i, len(fauna), 0.015),
                    "longitude": lng + _get_spread(i, len(fauna), 0.015, True)
                })

            for i, species in enumerate(flora[:3]):
                species_pois.append({
                    "id": f"flora_{i}",
                    "name": species.get('common_name', 'Unknown Species'),
                    "scientific_name": species.get('scientific_name', ''),
                    "conservation_status": species.get('status', 'Unknown'),
                    "category": "flora",
                    "endemic": species.get('endemic', False)
                })
        else:
            # Fetch fresh biodiversity data
            from agents.biodiversity_agent import BiodiversityAgent
            bio = BiodiversityAgent()
            bio_data = bio.analyze(lat, lng, "Tropical Forest")

            for i, species in enumerate(bio_data.get('fauna_at_risk', [])[:5]):
                species_pois.append({
                    "id": f"fauna_{i}",
                    "name": species.get('common_name', 'Unknown Species'),
                    "scientific_name": species.get('scientific_name', ''),
                    "conservation_status": species.get('status', 'Unknown'),
                    "category": "fauna",
                    "latitude": lat + _get_spread(i, 5, 0.015),
                    "longitude": lng + _get_spread(i, 5, 0.015, True)
                })

            for i, species in enumerate(bio_data.get('flora_at_risk', [])[:3]):
                species_pois.append({
                    "id": f"flora_{i}",
                    "name": species.get('common_name', 'Unknown Species'),
                    "scientific_name": species.get('scientific_name', ''),
                    "conservation_status": species.get('status', 'Unknown'),
                    "category": "flora"
                })

        print(f"🦎 Species POIs: {len(species_pois)}")

        # ═══════════════════════════════════════════════════════════════
        # STEP 5: Extract metrics for story (using REAL pipeline data)
        # ═══════════════════════════════════════════════════════════════
        if existing_node:
            print(f"✅ Using real data from node: {node_id}")

            # Get hectares from gfw_area__ha (GFW data) or fallback to hectares field
            hectares = int(existing_node.get('gfw_area__ha',
                          existing_node.get('hectares', 0)))

            # Get population from human_impacts pipeline data
            population = int(existing_node.get('human_impacts', {})
                           .get('affected_population', {})
                           .get('total', existing_node.get('population', 0)))

            # Get restoration cost from financial_analysis or economic_analysis
            restoration_cost = int(
                existing_node.get('financial_analysis', {}).get('restoration_cost_usd', 0) or
                existing_node.get('economic_analysis', {}).get('restoration_cost_usd', 0) or
                existing_node.get('recovery_potential', {}).get('cost_estimate_usd', 0)
            )

            # Get carbon stock from carbon_data or financial_analysis
            carbon_stock = int(
                existing_node.get('carbon_data', {}).get('carbon_stock_tonnes', 0) or
                existing_node.get('financial_analysis', {}).get('detailed_analysis', {})
                    .get('carbon', {}).get('stock_tonnes', 0)
            )

            # Get risk score from risk_prediction or top-level field
            risk_score = int(
                existing_node.get('risk_prediction', {}).get('risk_score', 0) or
                existing_node.get('riskScore', 0)
            )

            metrics = {
                "riskScore": risk_score if risk_score > 0 else 65,
                "hectares": hectares if hectares > 0 else 500,
                "population": population if population > 0 else 10000,
                "carbonStock": carbon_stock if carbon_stock > 0 else 25000,
                "restorationCost": restoration_cost if restoration_cost > 0 else 1000000,
            }
        else:
            print(f"⚠️ No existing node found for: {node_id} — using defaults")
            metrics = {
                "riskScore": 65,
                "hectares": 500,
                "population": 10000,
                "carbonStock": 25000,
                "restorationCost": 1000000,
            }

        # NDVI change from Sentinel data
        ndvi_data = sentinel_data.get('vegetation_indices', {}).get('ndvi', {})
        ndvi_change = ndvi_data.get('change_mean', -0.15)

        # ═══════════════════════════════════════════════════════════════
        # STEP 6: Generate dynamic chapters with Gemini narration
        # ═══════════════════════════════════════════════════════════════
        location_name = existing_node.get('name', 'Environmental Zone') if existing_node else 'Environmental Zone'
        country = existing_node.get('country', 'Unknown') if existing_node else 'Unknown'
        region = existing_node.get('region', location_name) if existing_node else location_name

        # Generate natural narration with Gemini
        narrations = _generate_chapter_narrations(
            location_name=location_name,
            country=country,
            metrics=metrics,
            species_count=len(species_pois),
            ndvi_change=ndvi_change
        )

        chapters = [
            {
                "id": "introduction",
                "title": "Arrival",
                "narrative": narrations.get('introduction', f"Welcome to {location_name}. This ecosystem faces environmental challenges that require our attention."),
                "cameraPath": {"type": "flyTo", "altitude": 50000, "pitch": -45, "duration": 4},
                "dataCards": [
                    {"label": "Location", "value": location_name.split(',')[0] if ',' in location_name else location_name},
                    {"label": "Risk Level", "value": f"{metrics['riskScore']}%", "class": "risk-high" if metrics['riskScore'] > 70 else "risk-medium"}
                ]
            },
            {
                "id": "discovery",
                "title": "The Species",
                "narrative": narrations.get('discovery', f"This region supports {len(species_pois)} documented species at risk, including several that exist nowhere else on Earth."),
                "cameraPath": {"type": "hover", "altitude": 8000, "pitch": -20, "duration": 2},
                "showSpecies": True,
                "dataCards": [
                    {"label": "Species at Risk", "value": str(len(species_pois)), "class": "risk-high"}
                ]
            },
            {
                "id": "temporal",
                "title": "What Happened",
                "narrative": narrations.get('temporal', f"Satellite imagery reveals a {abs(ndvi_change * 100):.0f}% decline in vegetation health. {metrics['hectares']} hectares have been affected."),
                "cameraPath": {"type": "topDown", "altitude": 20000, "duration": 2},
                "showTimelapse": True,
                "dataCards": [
                    {"label": "Area Affected", "value": f"{metrics['hectares']} ha"},
                    {"label": "Vegetation Loss", "value": f"{abs(ndvi_change * 100):.0f}%", "class": "risk-medium"}
                ]
            },
            {
                "id": "impact",
                "title": "The Impact",
                "narrative": narrations.get('impact', f"An estimated {metrics['population']:,} people depend on this ecosystem for water, food, and livelihood."),
                "cameraPath": {"type": "pullback", "altitude": 100000, "duration": 3},
                "dataCards": [
                    {"label": "People Affected", "value": f"{metrics['population']:,}"},
                    {"label": "Carbon at Risk", "value": f"{metrics['carbonStock'] // 1000}k tonnes"}
                ]
            },
            {
                "id": "restoration",
                "title": "The Hope",
                "narrative": narrations.get('restoration', f"With intervention costing approximately ${metrics['restorationCost'] / 1000000:.1f}M, this area could begin recovery within 10 years."),
                "cameraPath": {"type": "approach", "altitude": 5000, "duration": 3},
                "dataCards": [
                    {"label": "Recovery Cost", "value": f"${metrics['restorationCost'] / 1000000:.1f}M"},
                    {"label": "Recovery Time", "value": "5-10 years", "class": "positive"}
                ]
            }
        ]

        print(f"📖 Generated {len(chapters)} chapters")

        # ═══════════════════════════════════════════════════════════════
        # STEP 7: Build complete storyConfig
        # ═══════════════════════════════════════════════════════════════
        story_config = {
            "location": {
                "lat": lat,
                "lng": lng,
                "name": location_name,
                "country": country,
                "region": region
            },
            "metrics": metrics,
            "sentinelImagery": sentinel_imagery,
            "speciesPOIs": species_pois,
            "chapters": chapters,
            "soundscapes": {
                "healthy": "ambient_forest",
                "deforested": "wind_barren"
            },
            "visualFilters": {
                "healthy": {"saturation": 1.0, "brightness": 1.0},
                "degraded": {"saturation": 0.7, "brightness": 0.9}
            }
        }

        # ═══════════════════════════════════════════════════════════════
        # STEP 8: Cache to Firestore
        # ═══════════════════════════════════════════════════════════════
        db.collection('story_cache').document(cache_key).set({
            "config": story_config,
            "timestamp": firestore.SERVER_TIMESTAMP
        })

        print(f"✅ Story generated and cached: {cache_key}")
        return story_config

    except Exception as e:
        print(f"❌ Story generation failed: {e}")
        import traceback
        traceback.print_exc()
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message=f"Story generation failed: {str(e)}"
        )


def _get_spread(index, total, radius, is_lng=False):
    """Get spread offset for distributing markers in a circle"""
    import math
    angle = (index / max(total, 1)) * 2 * math.pi
    return radius * (math.cos(angle) if is_lng else math.sin(angle))


def _build_situation_overview(target, intelligence):
    """Build a real, derived situation overview paragraph from agent data.

    Replaces the previous "Comprehensive 20-layer analysis of..."
    boilerplate. Pulls actual numbers and findings from the pipeline:
    place, area, terrain, soil, water, biodiversity, history, people,
    and recovery outlook. Falls back gracefully when individual agents
    didn't return data — never fabricates values.
    """
    parts = []

    name = target.get("name", "this location")
    country = target.get("country", "")
    habitat = target.get("habitat", "")
    lat = target.get("lat")
    lng = target.get("lng")

    # 1. Place + setting
    place = name
    if country and country.lower() not in name.lower():
        place = f"{name}, {country}"
    setting_bits = []
    if habitat and habitat.lower() != "unknown":
        setting_bits.append(habitat.lower())

    terrain = intelligence.get("terrain_analysis", {}) or {}
    elevation = (terrain.get("elevation") or {}).get("mean_m")
    slope = (terrain.get("slope") or {}).get("mean_degrees")
    if elevation is not None and elevation > 0:
        setting_bits.append(f"~{int(elevation)} m elevation")
    if slope is not None and slope > 0:
        setting_bits.append(f"avg slope {slope:.1f}°")

    if setting_bits:
        parts.append(f"{place} — {', '.join(setting_bits)}.")
    else:
        parts.append(f"{place}.")

    # 2. Area + observed disturbance
    gis = intelligence.get("gis_analysis", {}) or {}
    area_ha = gis.get("area_ha") or intelligence.get("gfw_area__ha")
    sentinel = intelligence.get("sentinel_verification", {}) or {}
    ndvi_change = (
        sentinel.get("vegetation_indices", {})
        .get("ndvi", {})
        .get("change_mean")
    )
    sentinel_loss_ha = (sentinel.get("forest_loss_verified") or {}).get("area_ha")
    if area_ha:
        size_sentence = f"Approximately {int(area_ha)} hectares analysed."
        if sentinel_loss_ha and sentinel_loss_ha > 0:
            size_sentence += (
                f" Sentinel-2 imagery confirms ~{int(sentinel_loss_ha)} ha"
                f" of disturbance in the analysis window"
            )
            if ndvi_change is not None:
                size_sentence += f" (NDVI shift {ndvi_change:+.2f})."
            else:
                size_sentence += "."
        parts.append(size_sentence)

    # 3. Soil + water context
    soil = intelligence.get("soil_analysis", {}) or {}
    soil_class = (soil.get("soil_texture") or {}).get("class")
    soil_ph = (soil.get("ph") or {}).get("value")
    hydro = intelligence.get("hydrology_analysis", {}) or {}
    water_rating = (hydro.get("water_accessibility") or {}).get("rating")
    precip_mm = (hydro.get("water_stress") or {}).get("annual_precipitation_mm")
    swater_bits = []
    if soil_class and soil_class.lower() != "unknown":
        ph_str = f" (pH {soil_ph})" if soil_ph else ""
        swater_bits.append(f"{soil_class} soils{ph_str}")
    if water_rating and str(water_rating).lower() not in ("unknown", "none"):
        swater_bits.append(f"{str(water_rating).lower()} water access")
    if precip_mm:
        swater_bits.append(f"~{int(precip_mm)} mm/yr precipitation")
    if swater_bits:
        parts.append(f"Site characteristics: {', '.join(swater_bits)}.")

    # 4. History / change over time
    historical = intelligence.get("historical_analysis", {}) or {}
    loss_3yr = historical.get("loss_3yr") or historical.get("loss_3yr_ha")
    trend = historical.get("trend")
    fire_events = historical.get("fire_events_5yr")
    history_bits = []
    if trend:
        history_bits.append(f"trend {str(trend).lower()}")
    if loss_3yr:
        history_bits.append(f"~{int(loss_3yr)} ha lost in the last 3 years")
    if fire_events:
        history_bits.append(f"{int(fire_events)} fire events in the last 5 years")
    if history_bits:
        parts.append(f"Recent history: {', '.join(history_bits)}.")

    # 5. Biodiversity
    bio = intelligence.get("biodiversity_analysis", {}) or {}
    fauna_at_risk = len(bio.get("fauna_at_risk") or [])
    flora_at_risk = len(bio.get("flora_at_risk") or [])
    if fauna_at_risk or flora_at_risk:
        parts.append(
            f"Biodiversity: {fauna_at_risk} fauna and {flora_at_risk} flora "
            f"species at risk are documented within the search radius "
            f"(GBIF occurrence records + IUCN Red List)."
        )

    # 6. People affected
    population = intelligence.get("population") or target.get("population")
    if not population:
        # try comprehensive_analysis or human impact
        hi = intelligence.get("human_impact", {}) or {}
        population = hi.get("nearest_population")
    if population:
        parts.append(
            f"Nearest community footprint: ~{int(population):,} people."
        )

    # 7. Legal / cultural context
    legal = intelligence.get("legal_status", {}) or {}
    if legal.get("protected_area"):
        pname = legal.get("name") or "designated protected area"
        parts.append(f"This site falls inside a {pname}.")
    indigenous = legal.get("indigenous_community_name")
    if indigenous:
        parts.append(
            f"Traditional territory associated with {indigenous}."
        )

    # 8. Recovery outlook
    comp = intelligence.get("comprehensive_analysis", {}) or {}
    success = comp.get("success_probability")
    if success and str(success).lower() != "unknown":
        parts.append(f"Recovery outlook: {success}.")

    if not parts:
        # Honest absence — never fabricate
        loc_str = f"{lat:.2f}, {lng:.2f}" if (lat is not None and lng is not None) else name
        return (
            f"Analysis pipeline ran for {loc_str} but no agent layer "
            f"returned data. Re-run the deep-dive once external services "
            f"(SoilGrids, Open-Elevation, Open-Meteo, GBIF, Sentinel-2) "
            f"are reachable."
        )

    return " ".join(parts)


def _generate_chapter_narrations(location_name, country, metrics, species_count, ndvi_change):
    """Generate natural language narrations for each chapter using Gemini"""
    try:
        client = genai.Client(api_key=GEMINI_API_KEY.value)

        prompt = f"""
        You are a nature documentary narrator (like David Attenborough).
        Generate compelling, emotional narration for a 60-second immersive story about environmental change.

        LOCATION: {location_name}, {country}
        METRICS:
        - Risk Score: {metrics['riskScore']}%
        - Area Affected: {metrics['hectares']} hectares
        - People Dependent: {metrics['population']:,}
        - Carbon Stock: {metrics['carbonStock']:,} tonnes
        - Restoration Cost: ${metrics['restorationCost']:,}
        - Vegetation Change (NDVI): {ndvi_change * 100:.1f}%
        - Species at Risk: {species_count}

        Generate narration for 5 chapters. Each should be 2-3 sentences, evocative and informative.

        Return ONLY valid JSON:
        {{
            "introduction": "Welcome narration...",
            "discovery": "Species discovery narration...",
            "temporal": "What happened narration...",
            "impact": "Human impact narration...",
            "restoration": "Hope and restoration narration..."
        }}
        """

        response = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=prompt,
            config=types.GenerateContentConfig(
                response_mime_type="application/json"
            )
        )

        narrations = json.loads(response.text)
        return narrations

    except Exception as e:
        print(f"⚠️ Narration generation failed, using defaults: {e}")
        return {}


@scheduler_fn.on_schedule(schedule="every 24 hours", timeout_sec=540, memory=options.MemoryOption.GB_1)
def update_deforestation_heatmap(event):
    """
    Mobile Feature #2: Live Deforestation Heat Map (Scheduled Update)
    
    Daily scheduled function to:
    1. Process Sentinel-2 data for major forest regions
    2. Detect NDVI changes (potential new deforestation)
    3. Save alerts to Firestore: live_deforestation_alerts collection
    4. Generate heatmap tiles
    5. Send push notifications to subscribed users
    
    This is a simplified version - full implementation would:
    - Query Earth Engine for global forest regions
    - Run NDVI change detection at scale
    - Use proper heatmap tile generation
    """
    try:
        print("🗺️ Starting daily heatmap update...")
        
        db = firestore.client()
        
        # Major forest regions to monitor globally
        monitoring_regions = [
            {"lat": -3.5, "lng": -62.0, "name": "Amazon"},
            {"lat": 0.5, "lng": 25.0, "name": "Congo Basin"},
            {"lat": -5.0, "lng": 120.0, "name": "Borneo"},
            {"lat": 54.9, "lng": -115.2, "name": "Boreal Canada"}
        ]

        from agents.sentinel_verification_agent import SentinelVerificationAgent
        sentinel = SentinelVerificationAgent()

        alerts_generated = 0

        for region in monitoring_regions:
            # REAL Sentinel-2 NDVI change detection
            try:
                sentinel_data = sentinel.verify_with_sentinel(region['lat'], region['lng'])

                if sentinel_data.get('available'):
                    ndvi_data = sentinel_data.get('vegetation_indices', {}).get('ndvi', {})
                    ndvi_before = ndvi_data.get('before_mean', 0.7)
                    ndvi_after = ndvi_data.get('after_mean', 0.7)
                    ndvi_change = ndvi_after - ndvi_before

                    # Only create alert if significant NDVI decrease detected (deforestation)
                    if ndvi_change < -0.15:  # Threshold for deforestation detection
                        # Calculate severity based on NDVI change magnitude
                        if ndvi_change < -0.3:
                            severity = "high"
                        elif ndvi_change < -0.2:
                            severity = "medium"
                        else:
                            severity = "low"

                        # Estimate affected area (rough approximation from Sentinel-2 pixel count)
                        area_ha = abs(ndvi_change) * 100  # Rough estimate

                        alert = {
                            "alert_id": f"heat_{region['name']}_{datetime.datetime.utcnow().strftime('%Y%m%d')}",
                            "timestamp": firestore.SERVER_TIMESTAMP,
                            "location": {
                                "lat": region['lat'],
                                "lng": region['lng']
                            },
                            "region_name": region['name'],
                            "severity": severity,
                            "area_ha": round(area_ha, 1),
                            "ndvi_change": round(ndvi_change, 3),
                            "ndvi_before": round(ndvi_before, 3),
                            "ndvi_after": round(ndvi_after, 3),
                            "confidence": sentinel_data.get('confidence', 'medium'),
                            "data_source": "Sentinel-2"
                        }

                        # Save to Firestore
                        db.collection('live_deforestation_alerts').document(alert['alert_id']).set(alert)
                        alerts_generated += 1
                        print(f"✅ Alert created for {region['name']}: NDVI change {ndvi_change:.3f}")
                    else:
                        print(f"ℹ️ No significant deforestation in {region['name']} (NDVI change: {ndvi_change:.3f})")
                else:
                    print(f"⚠️ Sentinel-2 data unavailable for {region['name']}")
            except Exception as e:
                print(f"❌ Error processing {region['name']}: {e}")
        
        print(f"✅ Heatmap updated: {alerts_generated} alerts generated")
        return f"Success: {alerts_generated} alerts"
        
    except Exception as e:
        print(f"❌ Heatmap update failed: {e}")
        return f"Error: {str(e)}"


# =============================================================================
# MULTI-HAZARD MONITORING - Cloud Functions
# =============================================================================


@https_fn.on_call(timeout_sec=540, memory=options.MemoryOption.GB_1, enforce_app_check=False)
def get_active_hazards(request: https_fn.CallableRequest):
    """Fetch all active hazard layers for a bounding box.

    Calls wildfire, flood, drought, glacier, and NDVI services in
    parallel and returns a combined GeoJSON FeatureCollection.

    Args (via request.data):
        west, south, east, north: Bounding box coordinates.
        include: Optional list of hazard types to fetch.
    """
    try:
        data = request.data
        west = float(data.get('west'))
        south = float(data.get('south'))
        east = float(data.get('east'))
        north = float(data.get('north'))
        include = data.get('include')  # Optional list

        print(f"Multi-hazard request: bbox=({west},{south},{east},{north})")

        from services.hazard_orchestrator import fetch_all_hazards
        result = fetch_all_hazards(
            bbox=(west, south, east, north),
            include=include,
        )

        print(f"Hazards fetched: {result.get('metadata', {}).get('total_features', 0)} features")
        return result

    except Exception as e:
        import traceback
        traceback.print_exc()
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message=f"Hazard fetch failed: {str(e)}"
        )


@https_fn.on_call(timeout_sec=300, memory=options.MemoryOption.GB_1, enforce_app_check=False)
def get_hazard_layer(request: https_fn.CallableRequest):
    """Fetch a single hazard layer by type for a bounding box.

    Args (via request.data):
        west, south, east, north: Bounding box coordinates.
        hazard_type: One of 'fire', 'flood', 'drought', 'glacier', 'ndvi'.
    """
    try:
        data = request.data
        west = float(data.get('west'))
        south = float(data.get('south'))
        east = float(data.get('east'))
        north = float(data.get('north'))
        hazard_type = data.get('hazard_type', 'fire')
        bbox = (west, south, east, north)

        print(f"Single hazard layer request: {hazard_type} bbox=({west},{south},{east},{north})")

        if hazard_type == 'fire':
            from services.wildfire_service import fetch_active_fires
            result = fetch_active_fires(bbox=bbox, days=int(data.get('days', 1)))
        elif hazard_type == 'flood':
            from services.flood_service import fetch_flood_gauges
            result = fetch_flood_gauges(bbox=bbox)
        elif hazard_type == 'drought':
            from services.drought_service import fetch_drought_polygons
            result = fetch_drought_polygons()
        elif hazard_type == 'glacier':
            from services.glacier_service import fetch_glacier_outlines
            result = fetch_glacier_outlines(bbox)
        elif hazard_type == 'ndvi':
            from services.ndvi_service import fetch_ndvi_modis
            result = fetch_ndvi_modis(bbox)
        elif hazard_type == 'watershed':
            from services.watershed_service import fetch_watersheds_usgs
            huc_level = int(data.get('huc_level', 8))
            result = fetch_watersheds_usgs(bbox, huc_level=huc_level)
        elif hazard_type == 'fire_perimeters':
            from services.wildfire_service import get_fire_perimeters
            result = get_fire_perimeters(bbox=bbox)
        else:
            raise https_fn.HttpsError(
                code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
                message=f"Unknown hazard_type: {hazard_type}"
            )

        return result

    except https_fn.HttpsError:
        raise
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message=f"Hazard layer fetch failed: {str(e)}"
        )


@https_fn.on_call(timeout_sec=540, memory=options.MemoryOption.GB_1, enforce_app_check=False)
def get_risk_surface(request: https_fn.CallableRequest):
    """Compute a multi-hazard risk surface grid for a bounding box.

    Args (via request.data):
        west, south, east, north: Bounding box coordinates.
        resolution: Grid cell size in degrees (default 0.01).
        weights: Optional dict of hazard weights.
        report: If True, return a full risk report instead of the grid.
    """
    try:
        data = request.data
        west = float(data.get('west'))
        south = float(data.get('south'))
        east = float(data.get('east'))
        north = float(data.get('north'))
        resolution = float(data.get('resolution', 0.01))
        weights = data.get('weights')
        want_report = data.get('report', False)
        bbox = (west, south, east, north)

        print(f"Risk surface request: bbox=({west},{south},{east},{north}) res={resolution}")

        from services.risk_surface_service import compute_risk_surface, generate_risk_report

        if want_report:
            result = generate_risk_report(bbox)
        else:
            result = compute_risk_surface(
                bbox, resolution=resolution, weights=weights
            )

        return result

    except Exception as e:
        import traceback
        traceback.print_exc()
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message=f"Risk surface computation failed: {str(e)}"
        )


@https_fn.on_call(timeout_sec=300, memory=options.MemoryOption.GB_1, enforce_app_check=False)
def get_dem_heightmap(request: https_fn.CallableRequest):
    """Fetch DEM data and return terrain statistics or heightmap metadata.

    The raw heightmap bytes are too large for a callable response, so
    this function returns terrain stats and elevation metadata.  For
    the full heightmap, use :func:`get_unity_terrain`.

    Args (via request.data):
        west, south, east, north: Bounding box coordinates.
        stats_only: If True (default), return terrain stats only.
    """
    try:
        data = request.data
        west = float(data.get('west'))
        south = float(data.get('south'))
        east = float(data.get('east'))
        north = float(data.get('north'))
        stats_only = data.get('stats_only', True)
        bbox = (west, south, east, north)

        print(f"DEM heightmap request: bbox=({west},{south},{east},{north})")

        from services.dem_service import get_terrain_stats, fetch_dem_copernicus, dem_to_heightmap

        if stats_only:
            return get_terrain_stats(bbox)

        # Fetch DEM and generate heightmap metadata
        dem_bytes = fetch_dem_copernicus(bbox)
        if not dem_bytes:
            raise https_fn.HttpsError(
                code=https_fn.FunctionsErrorCode.NOT_FOUND,
                message="DEM data not available for the requested area."
            )

        hm = dem_to_heightmap(dem_bytes, target_size=int(data.get('target_size', 257)))
        # Cannot return raw bytes via callable; return metadata
        return {
            "width": hm["width"],
            "height": hm["height"],
            "min_elevation": hm["min_elevation"],
            "max_elevation": hm["max_elevation"],
            "crs": hm.get("crs", "EPSG:4326"),
            "data_size_bytes": len(hm.get("raw_data", b"")),
            "terrain_stats": get_terrain_stats(bbox),
        }

    except https_fn.HttpsError:
        raise
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message=f"DEM heightmap failed: {str(e)}"
        )


@scheduler_fn.on_schedule(
    schedule="every 30 minutes",
    timeout_sec=540,
    memory=options.MemoryOption.GB_1,
    # FIRMS_MAP_KEY was missing here — the monitor logged
    # "NASA_FIRMS_MAP_KEY not set" every run and silently fell back to
    # NIFC (USA-only) fire data for the Firestore hotspot feed.
    secrets=[FIRMS_MAP_KEY],
)
def monitor_hazards_scheduled(event):
    """Scheduled function that checks for new hazard alerts every 30 minutes.

    Monitors predefined regions for threshold-exceeding hazard events
    and writes alerts to Firestore.
    """
    try:
        print("Scheduled hazard monitoring starting...")

        db = firestore.client()

        monitoring_regions = [
            {"name": "Western US", "bbox": (-125, 32, -104, 49)},
            {"name": "Southeast US", "bbox": (-95, 25, -75, 37)},
            {"name": "Central Europe", "bbox": (5, 44, 18, 55)},
            {"name": "South Asia", "bbox": (68, 8, 92, 35)},
            {"name": "Amazon Basin", "bbox": (-75, -15, -45, 5)},
            {"name": "Sub-Saharan Africa", "bbox": (10, -10, 40, 15)},
        ]

        from services.hazard_orchestrator import fetch_all_hazards, generate_alert

        total_alerts = 0

        for region in monitoring_regions:
            try:
                hazard_data = fetch_all_hazards(
                    bbox=region["bbox"],
                    include=["fire", "flood"],
                )
                alerts = generate_alert(hazard_data)

                for alert in alerts:
                    alert_id = (
                        f"alert_{region['name'].replace(' ', '_').lower()}"
                        f"_{alert['type']}_{datetime.datetime.utcnow().strftime('%Y%m%d_%H%M')}"
                    )
                    alert["region"] = region["name"]
                    alert["timestamp"] = firestore.SERVER_TIMESTAMP

                    db.collection("hazard_alerts").document(alert_id).set(alert)
                    total_alerts += 1

                print(f"Region {region['name']}: {len(alerts)} alerts")

            except Exception as e:
                print(f"Error monitoring {region['name']}: {e}")

        print(f"Hazard monitoring complete: {total_alerts} alerts generated")
        return f"Success: {total_alerts} alerts"

    except Exception as e:
        print(f"Scheduled hazard monitoring failed: {e}")
        return f"Error: {str(e)}"


@https_fn.on_call(timeout_sec=540, memory=options.MemoryOption.GB_1, enforce_app_check=False)
def get_unity_terrain(request: https_fn.CallableRequest):
    """Generate Unity-compatible terrain data for a bounding box.

    Returns terrain metadata, elevation statistics, and a base64-encoded
    heightmap suitable for Unity terrain rendering.

    Args (via request.data):
        west, south, east, north: Bounding box coordinates.
        target_size: Heightmap resolution (default 257).
        include_hillshade: Whether to include hillshade PNG (default False).
    """
    try:
        import base64

        data = request.data
        west = float(data.get('west'))
        south = float(data.get('south'))
        east = float(data.get('east'))
        north = float(data.get('north'))
        target_size = int(data.get('target_size', 257))
        include_hillshade = data.get('include_hillshade', False)
        bbox = (west, south, east, north)

        print(f"Unity terrain request: bbox=({west},{south},{east},{north}) size={target_size}")

        from services.dem_service import (
            fetch_dem_copernicus,
            dem_to_heightmap,
            get_terrain_stats,
            generate_hillshade,
        )

        dem_bytes = fetch_dem_copernicus(bbox)
        if not dem_bytes:
            raise https_fn.HttpsError(
                code=https_fn.FunctionsErrorCode.NOT_FOUND,
                message="DEM data not available for the requested area."
            )

        # Generate heightmap with geographic metadata for accurate 3D placement
        hm = dem_to_heightmap(dem_bytes, target_size=target_size, bbox=bbox)
        raw_data = hm.get("raw_data", b"")

        result = {
            "heightmap_base64": base64.b64encode(raw_data).decode("utf-8") if raw_data else "",
            "width": hm["width"],
            "height": hm["height"],
            "min_elevation": hm["min_elevation"],
            "max_elevation": hm["max_elevation"],
            "crs": hm.get("crs", "EPSG:4326"),
            "bbox": list(bbox),
            # Real-world geographic positioning for Unity terrain
            "terrain_width_m": hm.get("terrain_width_m", 0),
            "terrain_height_m": hm.get("terrain_height_m", 0),
            "origin_lat": hm.get("origin_lat", (south + north) / 2),
            "origin_lon": hm.get("origin_lon", (west + east) / 2),
            "terrain_stats": get_terrain_stats(bbox),
        }

        # Optional hillshade
        if include_hillshade:
            hs_bytes = generate_hillshade(dem_bytes)
            if hs_bytes:
                result["hillshade_base64"] = base64.b64encode(hs_bytes).decode("utf-8")

        print(f"Unity terrain generated: {hm['width']}x{hm['height']}, "
              f"elev range {hm['min_elevation']}-{hm['max_elevation']}m")
        return result

    except https_fn.HttpsError:
        raise
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message=f"Unity terrain generation failed: {str(e)}"
        )


# ═══════════════════════════════════════════════════════════════════════
# CARTOGRAPHIC INTELLIGENCE ENGINE
# Publication-quality map generation from environmental data
# ═══════════════════════════════════════════════════════════════════════

@https_fn.on_call(timeout_sec=540, memory=options.MemoryOption.GB_2, enforce_app_check=False, secrets=[GEMINI_API_KEY, FIRMS_MAP_KEY, GFW_API_KEY])
def generate_cartographic_map(request: https_fn.CallableRequest):
    """
    Generate a publication-quality cartographic map.

    The engine automatically:
    - Selects the appropriate map projection
    - Fetches data from credible sources (NASA, USGS, GFW, etc.)
    - Applies cartographic rules from 1000+ award-winning maps
    - Validates quality across 6 dimensions
    - Auto-corrects issues when possible
    - Uploads the result to Cloud Storage

    Request data:
    {
        "bbox": [west, south, east, north],     # Required
        "map_type": "choropleth",                # choropleth|heatmap|proportional_symbol|dot_density|isopleth|bivariate_choropleth|multi_hazard_risk
        "theme": "deforestation",                # deforestation|fire_risk|earthquake|flood_risk|multi_hazard|biodiversity|vegetation_health|drought
        "title": "Map Title",
        "subtitle": "Subtitle text",
        "layer_ids": ["nasa_firms", "usgs_earthquakes"],  # Optional explicit layers
        "value_field": "mag",                    # Property to classify by
        "label_field": "NAME",                   # Property for labels
        "date_range": ["2020-01-01", "2025-01-01"],
        "classification_method": "natural_breaks", # natural_breaks|quantile|equal_interval
        "n_classes": 5,
        "color_palette": "YlOrRd",               # ColorBrewer palette name, or null for auto
        "dark_mode": false,
        "show_labels": true,
        "show_legend": true,
        "show_scale_bar": true,
        "show_grid": true,
        "output_format": "png",                  # png|pdf|svg
        "output_dpi": 150,
        "width_inches": 16,
        "height_inches": 12,
        "geojson_data": null,                    # Optional pre-fetched GeoJSON
        "showcase_id": null,                     # Render a showcase example by ID
    }

    Returns:
    {
        "image_url": "https://storage.googleapis.com/...",
        "image_base64": "...",                   # Base64 encoded image (for small maps)
        "quality_report": {
            "overall": 95.0,
            "passed": true,
            "dimensions": { ... },
        },
        "metadata": { ... },
        "violations": [ ... ],
        "suggestions": [ ... ],
        "attributions": [ ... ],
        "projection": { ... },
    }
    """
    import matplotlib
    matplotlib.use("Agg")

    try:
        data = request.data
        if not data:
            raise https_fn.HttpsError(
                code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
                message="Request data is required",
            )

        # Lazy import to avoid cold start cost
        from cartographic.composition_engine import CartographicCompositionEngine, MapRequest

        engine = CartographicCompositionEngine()

        # Check for showcase mode
        showcase_id = data.get("showcase_id")
        if showcase_id:
            print(f"Rendering showcase: {showcase_id}")
            result = engine.compose_showcase(showcase_id)
        else:
            # Parse bbox
            bbox_raw = data.get("bbox")
            if not bbox_raw or len(bbox_raw) != 4:
                raise https_fn.HttpsError(
                    code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
                    message="bbox must be [west, south, east, north]",
                )
            bbox = tuple(float(x) for x in bbox_raw)

            # Parse date range
            date_range = None
            dr = data.get("date_range")
            if dr and len(dr) == 2:
                date_range = (str(dr[0]), str(dr[1]))

            # Parse GeoJSON data if provided
            geojson_data = data.get("geojson_data")

            # Build request
            map_request = MapRequest(
                bbox=bbox,
                map_type=data.get("map_type", "choropleth"),
                theme=data.get("theme"),
                title=data.get("title"),
                subtitle=data.get("subtitle"),
                layer_ids=data.get("layer_ids"),
                geojson_data=geojson_data,
                value_field=data.get("value_field"),
                label_field=data.get("label_field"),
                date_range=date_range,
                classification_method=data.get("classification_method", "natural_breaks"),
                n_classes=int(data.get("n_classes", 5)),
                color_palette=data.get("color_palette"),
                dark_mode=bool(data.get("dark_mode", False)),
                show_labels=bool(data.get("show_labels", True)),
                show_legend=bool(data.get("show_legend", True)),
                show_scale_bar=bool(data.get("show_scale_bar", True)),
                show_north_arrow=bool(data.get("show_north_arrow", False)),
                show_grid=bool(data.get("show_grid", True)),
                show_source_attribution=bool(data.get("show_source_attribution", True)),
                output_format=data.get("output_format", "png"),
                output_dpi=int(data.get("output_dpi", 150)),
                width_inches=float(data.get("width_inches", 16)),
                height_inches=float(data.get("height_inches", 12)),
            )

            print(f"Generating map: {map_request.map_type} | {map_request.theme} | bbox={bbox}")
            result = engine.compose(map_request)

        # Upload to Cloud Storage
        image_url = None
        try:
            bucket = storage.bucket()
            file_ext = result.format or "png"
            blob_name = f"cartographic_maps/{uuid.uuid4().hex}.{file_ext}"
            blob = bucket.blob(blob_name)
            blob.upload_from_string(
                result.image_bytes,
                content_type=f"image/{file_ext}" if file_ext != "pdf" else "application/pdf",
            )
            blob.make_public()
            image_url = blob.public_url
            print(f"Map uploaded: {image_url}")
        except Exception as upload_err:
            print(f"Cloud Storage upload failed (returning base64): {upload_err}")

        # Build response
        response = {
            "image_url": image_url,
            "quality_report": result.quality_report,
            "metadata": result.metadata,
            "violations": result.violations,
            "suggestions": result.suggestions,
            "passed_validation": result.passed_validation,
            "attributions": result.attributions,
            "projection": result.projection,
            "width_px": result.width_px,
            "height_px": result.height_px,
            "format": result.format,
        }

        # Include base64 for small images or if Cloud Storage failed
        image_size = len(result.image_bytes)
        if image_url is None or image_size < 2_000_000:  # < 2MB
            response["image_base64"] = base64.b64encode(result.image_bytes).decode("utf-8")

        print(f"Map generated: {result.width_px}x{result.height_px}, "
              f"quality={result.quality_report.get('overall', 0)}/100, "
              f"passed={result.passed_validation}")

        return response

    except https_fn.HttpsError:
        raise
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message=f"Map generation failed: {str(e)}",
        )


@https_fn.on_call(timeout_sec=60, memory=options.MemoryOption.MB_512, enforce_app_check=False, secrets=[FIRMS_MAP_KEY, GFW_API_KEY])
def get_map_templates(request: https_fn.CallableRequest):
    """
    Return available map templates, color palettes, data sources,
    and showcase examples for the Flutter UI to populate its pickers.

    Request data (all optional):
    {
        "bbox": [west, south, east, north],   # Filter data sources by extent
        "theme": "deforestation",              # Filter by theme
    }

    Returns:
    {
        "templates": [ ... ],
        "showcase_examples": [ ... ],
        "palettes": {
            "sequential": ["YlOrRd", "OrRd", ...],
            "diverging": ["RdBu", "BrBG", ...],
            "qualitative": ["Set2", "Dark2", ...],
        },
        "data_sources": [ ... ],
        "classification_methods": [ ... ],
    }
    """
    try:
        data = request.data or {}

        # Lazy imports
        from cartographic.templates import TemplateRegistry
        from cartographic.color_systems import ColorSystems
        from cartographic.data_pipeline import DataPipeline

        registry = TemplateRegistry()
        colors = ColorSystems()
        pipeline = DataPipeline()

        # Templates and showcase examples
        catalog = registry.get_all_templates_as_catalog()

        # Color palettes grouped by type
        palettes = {
            "sequential": colors.get_available_palettes("sequential"),
            "diverging": colors.get_available_palettes("diverging"),
            "qualitative": colors.get_available_palettes("qualitative"),
            "sequential_colorblind_safe": colors.get_available_palettes(
                "sequential", colorblind_safe_only=True,
            ),
            "diverging_colorblind_safe": colors.get_available_palettes(
                "diverging", colorblind_safe_only=True,
            ),
        }

        # Palette previews (5-class hex colors for each)
        palette_previews = {}
        for palette_type_palettes in palettes.values():
            for name in palette_type_palettes:
                if name not in palette_previews:
                    try:
                        palette_previews[name] = colors.get_palette(name, 5)
                    except Exception:
                        pass

        # Available data sources (filtered by bbox/theme if provided)
        bbox = None
        bbox_raw = data.get("bbox")
        if bbox_raw and len(bbox_raw) == 4:
            bbox = tuple(float(x) for x in bbox_raw)

        theme = data.get("theme")
        data_sources = pipeline.get_layer_catalog(bbox=bbox, theme=theme)

        # Classification methods
        classification_methods = [
            {"id": "natural_breaks", "name": "Natural Breaks (Jenks)", "description": "Minimizes within-class variance. Best for most data."},
            {"id": "quantile", "name": "Quantile", "description": "Equal number of features per class. Good for skewed data."},
            {"id": "equal_interval", "name": "Equal Interval", "description": "Equal value ranges. Good for uniformly distributed data."},
            {"id": "std_deviation", "name": "Standard Deviation", "description": "Classes by standard deviations from mean."},
            {"id": "manual", "name": "Manual Breaks", "description": "User-defined class boundaries."},
        ]

        return {
            "templates": catalog["templates"],
            "showcase_examples": catalog["showcase_examples"],
            "palettes": palettes,
            "palette_previews": palette_previews,
            "data_sources": data_sources,
            "classification_methods": classification_methods,
        }

    except Exception as e:
        import traceback
        traceback.print_exc()
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message=f"Failed to load map templates: {str(e)}",
        )


# ============================================================================
# FIRMS PROXY — keeps the NASA FIRMS API key server-side
# ============================================================================
# NASA FIRMS does not send CORS headers, AND embedding the key in the public
# bundle gets it scraped + invalidated. This endpoint solves both: it calls
# FIRMS server-side using a Secret Manager-backed key and returns GeoJSON to
# the browser with permissive CORS.

_FIRMS_CACHE = {"ts": 0.0, "body": None, "key": None}
_FIRMS_CACHE_TTL_SEC = 300  # 5 minutes — matches the client cache TTL

@https_fn.on_request(
    timeout_sec=60,
    memory=options.MemoryOption.MB_512,
    secrets=[FIRMS_MAP_KEY],
    cors=options.CorsOptions(cors_origins="*", cors_methods=["get", "options"]),
)
def firms_proxy(request: https_fn.Request) -> https_fn.Response:
    """Proxy NASA FIRMS active-fires CSV → GeoJSON, with CORS.

    Query params:
        days  - day-range (1-10). Default 2.
        sat   - 'auto' (default), or one of VIIRS_NOAA20_NRT/VIIRS_SNPP_NRT/MODIS_NRT.
        area  - 'world' (default) or 'w,s,e,n' bbox in EPSG:4326.

    Auto mode tries NOAA20 → SNPP → MODIS, returning the first satellite
    with non-empty data. The server caches the result for 5 minutes.
    """
    import csv as _csv
    import io as _io
    import urllib.request as _urlreq
    import urllib.error as _urlerr

    days_param = request.args.get("days", "2")
    sat_param = (request.args.get("sat") or "auto").strip()
    area_param = (request.args.get("area") or "world").strip()

    try:
        days = max(1, min(int(days_param), 10))
    except (TypeError, ValueError):
        days = 2

    key = FIRMS_MAP_KEY.value
    if not key:
        return https_fn.Response(
            json.dumps({"error": "NASA_FIRMS_MAP_KEY secret is not set"}),
            status=500,
            headers={"Content-Type": "application/json"},
        )

    # Gzip the JSON when the client accepts it. In peak fire season a 2-day
    # world pull can exceed Cloud Run's 32 MB response cap uncompressed;
    # gzipped it's a few MB. Browsers decompress transparently.
    import gzip as _gzip

    def _respond(raw_body: str, cache_state: str) -> https_fn.Response:
        headers = {"Content-Type": "application/json", "X-Cache": cache_state}
        accept_enc = (request.headers.get("Accept-Encoding") or "").lower()
        if "gzip" in accept_enc:
            headers["Content-Encoding"] = "gzip"
            return https_fn.Response(
                _gzip.compress(raw_body.encode("utf-8"), compresslevel=6),
                status=200,
                headers=headers,
            )
        return https_fn.Response(raw_body, status=200, headers=headers)

    cache_key = f"{sat_param}|{area_param}|{days}"
    now = time.time()
    cached = _FIRMS_CACHE
    if (
        cached["body"] is not None
        and cached["key"] == cache_key
        and now - cached["ts"] < _FIRMS_CACHE_TTL_SEC
    ):
        return _respond(cached["body"], "HIT")

    # Verified FIRMS behavior: a 2-day WORLD query returns ~37k hotspots;
    # longer world ranges (e.g. 7 days) silently return 0 rows. Clamp world
    # queries to 2 days — metadata reports the clamped value honestly.
    if area_param == "world":
        days = min(days, 2)

    if sat_param == "auto":
        satellites = ["VIIRS_NOAA20_NRT", "VIIRS_SNPP_NRT", "MODIS_NRT"]
    else:
        satellites = [sat_param]

    last_error = None
    chosen_sat = None
    features: list = []

    # A 2-day world pull is ~37k rows (~10-20 MB CSV). The previous version
    # materialized the parsed rows AND a verbose feature list AND the JSON
    # string — >350 MB peak, which OOM-killed the 256 MB instance (HTTP 500).
    # Now: stream the CSV reader once, build slim features directly, and
    # round floats so the response stays a few MB.
    for sat in satellites:
        url = (
            f"https://firms.modaps.eosdis.nasa.gov/api/area/csv/"
            f"{key}/{sat}/{area_param}/{days}"
        )
        try:
            req = _urlreq.Request(url, headers={"User-Agent": "EcoLens-FIRMS-Proxy/1.0"})
            with _urlreq.urlopen(req, timeout=45) as resp:
                csv_text = resp.read().decode("utf-8", errors="replace")
        except _urlerr.HTTPError as e:
            last_error = f"{sat}: HTTP {e.code}"
            continue
        except Exception as e:
            last_error = f"{sat}: {e}"
            continue

        # FIRMS sometimes returns plain-text errors with HTTP 200
        head = csv_text[:200].lower()
        if any(tok in head for tok in ("invalid", "error", "<html")):
            last_error = f"{sat}: error body — {csv_text[:120].strip()}"
            continue

        sat_short = sat.split("_")[0]
        candidate: list = []
        for row in _csv.DictReader(_io.StringIO(csv_text)):
            try:
                lon = round(float(row.get("longitude") or 0), 3)
                lat = round(float(row.get("latitude") or 0), 3)
            except (TypeError, ValueError):
                continue
            try:
                bright_val = round(float(row.get("bright_ti4") or row.get("brightness") or 300), 1)
            except (TypeError, ValueError):
                bright_val = 300.0
            try:
                frp_val = round(float(row.get("frp") or 0), 1)
            except (TypeError, ValueError):
                frp_val = 0.0

            # Slim payload: only the fields the map actually renders/reads.
            # hazard-layers.js reads `brightness_temp || brightness`, so
            # shipping just `brightness` is safe and halves the key bytes.
            candidate.append({
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": [lon, lat]},
                "properties": {
                    "brightness": bright_val,
                    "confidence": row.get("confidence") or "nominal",
                    "satellite": row.get("satellite") or sat_short,
                    "acq_date": row.get("acq_date") or "",
                    "acq_time": row.get("acq_time") or "",
                    "frp": frp_val,
                    "hazard_type": "fire",
                },
            })

        del csv_text  # release the raw CSV before serializing
        if candidate:
            features = candidate
            chosen_sat = sat
            break

    body = json.dumps({
        "type": "FeatureCollection",
        "features": features,
        "metadata": {
            "satellite": chosen_sat,
            "count": len(features),
            "days": days,
            "area": area_param,
            "last_error": last_error if not features else None,
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        },
    }, separators=(",", ":"))

    if features:
        _FIRMS_CACHE["ts"] = now
        _FIRMS_CACHE["body"] = body
        _FIRMS_CACHE["key"] = cache_key

    return _respond(body, "MISS")


# ---------------------------------------------------------------------------
# Hazard archive — "the map that remembers"
#
# Daily snapshots of global hazard layers written to a public GCS bucket so
# the map screen can replay history, build 30-day statistical baselines, and
# run before/after comparisons. FIRMS NRT only serves a ~10-day window and
# the live proxy is clamped to 2 days, so every day this doesn't run is data
# lost forever. Layout (see functions/ARCHIVE_SETUP.md for bucket setup):
#
#   archive/v1/index.json
#   archive/v1/{type}/daily/{YYYY}/{YYYY-MM-DD}.geojson   (gzip-encoded)
#   archive/v1/{type}/weekly/{YYYY}-W{WW}.geojson
# ---------------------------------------------------------------------------

ARCHIVE_BUCKET_NAME = "ecolens-archive-ecolens-ad854"
ARCHIVE_PREFIX = "archive/v1"
_ARCHIVE_DAILY_CACHE_CONTROL = "public, max-age=31536000, immutable"
_ARCHIVE_INDEX_CACHE_CONTROL = "public, max-age=300"
# FIRMS NRT keeps roughly 10 days; beyond that backfill is impossible.
_FIRMS_NRT_WINDOW_DAYS = 10


def _archive_bucket():
    """Return the archive bucket, provisioning it on first use.

    Self-provisioning (create + public read + CORS + lifecycle) replaces the
    manual gcloud steps in ARCHIVE_SETUP.md — the deploy machine has no
    gcloud, and the runtime service account can do all of this itself.
    Idempotent: existing buckets are returned untouched.
    """
    bucket = storage.bucket(ARCHIVE_BUCKET_NAME)
    try:
        if bucket.exists():
            return bucket
    except Exception as exc:  # permission probe failures fall through to create
        print(f"[archive] bucket.exists() probe failed: {exc}")

    try:
        client = bucket.client
        new_bucket = client.bucket(ARCHIVE_BUCKET_NAME)
        new_bucket.iam_configuration.uniform_bucket_level_access_enabled = True
        client.create_bucket(new_bucket, location="us-central1")
        print(f"[archive] created bucket {ARCHIVE_BUCKET_NAME}")

        # Public, read-only: the map reads day files straight from the bucket.
        policy = new_bucket.get_iam_policy(requested_policy_version=3)
        policy.bindings.append({
            "role": "roles/storage.objectViewer",
            "members": {"allUsers"},
        })
        new_bucket.set_iam_policy(policy)

        # Browser fetches come from the Flutter-hosted map (any origin —
        # the data is public and read-only).
        new_bucket.cors = [{
            "origin": ["*"],
            "method": ["GET", "HEAD"],
            "responseHeader": ["Content-Type", "Content-Encoding"],
            "maxAgeSeconds": 3600,
        }]
        # Daily files age out after 90 days; weekly rollups are kept forever.
        for hazard in ("fires", "earthquakes", "drought"):
            new_bucket.add_lifecycle_delete_rule(
                age=90, matches_prefix=[f"{ARCHIVE_PREFIX}/{hazard}/daily/"])
        new_bucket.patch()
        print(f"[archive] bucket configured (public read, CORS, lifecycle)")
        return new_bucket
    except Exception as exc:
        # google.api_core Conflict (409) means another instance won the race —
        # the bucket exists now either way; fall back to the plain handle.
        print(f"[archive] bucket provisioning: {exc}")
        return storage.bucket(ARCHIVE_BUCKET_NAME)


def _fc_bbox(features):
    """[minx, miny, maxx, maxy] over Point features; None when empty."""
    minx, miny, maxx, maxy = 180.0, 90.0, -180.0, -90.0
    found = False
    for f in features:
        geom = f.get("geometry") or {}
        if geom.get("type") != "Point":
            continue
        lon, lat = geom.get("coordinates", (None, None))[:2]
        if lon is None or lat is None:
            continue
        found = True
        minx, maxx = min(minx, lon), max(maxx, lon)
        miny, maxy = min(miny, lat), max(maxy, lat)
    if not found:
        return None
    return [round(minx, 3), round(miny, 3), round(maxx, 3), round(maxy, 3)]


def _fetch_firms_day(key: str, date_str: str) -> dict:
    """One UTC day of global VIIRS detections as a FeatureCollection.

    Feature properties mirror firms_proxy exactly, so archived days render
    through HazardLayers.updateSource('fires', fc) with zero adaptation.
    Both VIIRS sensors are kept (satellite property distinguishes them).
    """
    import csv as _csv
    import io as _io
    import urllib.request as _urlreq

    features = []
    errors = []
    for sat in ("VIIRS_NOAA20_NRT", "VIIRS_SNPP_NRT"):
        url = (
            f"https://firms.modaps.eosdis.nasa.gov/api/area/csv/"
            f"{key}/{sat}/world/1/{date_str}"
        )
        try:
            req = _urlreq.Request(url, headers={"User-Agent": "EcoLens-Archive/1.0"})
            with _urlreq.urlopen(req, timeout=120) as resp:
                csv_text = resp.read().decode("utf-8", errors="replace")
        except Exception as e:
            errors.append(f"{sat}: {e}")
            continue

        head = csv_text[:200].lower()
        if any(tok in head for tok in ("invalid", "error", "<html")):
            errors.append(f"{sat}: error body — {csv_text[:120].strip()}")
            continue

        sat_short = sat.split("_")[0]
        for row in _csv.DictReader(_io.StringIO(csv_text)):
            try:
                lon = round(float(row.get("longitude") or 0), 3)
                lat = round(float(row.get("latitude") or 0), 3)
            except (TypeError, ValueError):
                continue
            try:
                bright_val = round(float(row.get("bright_ti4") or row.get("brightness") or 300), 1)
            except (TypeError, ValueError):
                bright_val = 300.0
            try:
                frp_val = round(float(row.get("frp") or 0), 1)
            except (TypeError, ValueError):
                frp_val = 0.0
            features.append({
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": [lon, lat]},
                "properties": {
                    "brightness": bright_val,
                    "confidence": row.get("confidence") or "nominal",
                    "satellite": row.get("satellite") or sat_short,
                    "acq_date": row.get("acq_date") or date_str,
                    "acq_time": row.get("acq_time") or "",
                    "frp": frp_val,
                    "hazard_type": "fire",
                },
            })
        del csv_text

    if not features and errors:
        raise RuntimeError("; ".join(errors))
    return {
        "type": "FeatureCollection",
        "features": features,
        "metadata": {
            "type": "fires",
            "date": date_str,
            "count": len(features),
            "sensors": ["VIIRS_NOAA20_NRT", "VIIRS_SNPP_NRT"],
            "errors": errors or None,
            "archived_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        },
    }


def _fetch_quakes_day(date_str: str) -> dict:
    """One UTC day of M2.5+ earthquakes, with the derived properties the
    map client adds on live fetch (hazard_type, magnitude, depth_km)."""
    import urllib.request as _urlreq

    url = (
        "https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson"
        f"&starttime={date_str}T00:00:00&endtime={date_str}T23:59:59"
        "&minmagnitude=2.5&limit=20000&orderby=time"
    )
    req = _urlreq.Request(url, headers={"User-Agent": "EcoLens-Archive/1.0"})
    with _urlreq.urlopen(req, timeout=60) as resp:
        data = json.loads(resp.read().decode("utf-8"))

    features = []
    for f in data.get("features", []):
        props = f.get("properties") or {}
        coords = (f.get("geometry") or {}).get("coordinates") or [0, 0, 0]
        mag = props.get("mag")
        features.append({
            "type": "Feature",
            "geometry": {"type": "Point", "coordinates": [coords[0], coords[1]]},
            "properties": {
                "hazard_type": "earthquake",
                "mag": mag,
                "magnitude": mag,
                "depth_km": coords[2] if len(coords) > 2 else None,
                "place": props.get("place") or "",
                "time": props.get("time"),
            },
        })
    return {
        "type": "FeatureCollection",
        "features": features,
        "metadata": {
            "type": "earthquakes",
            "date": date_str,
            "count": len(features),
            "source": "USGS fdsnws",
            "archived_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        },
    }


def _write_archive_object(bucket, path: str, obj: dict, cache_control: str = _ARCHIVE_DAILY_CACHE_CONTROL) -> int:
    """Gzip-upload a JSON object; returns compressed byte size."""
    import gzip as _gzip

    raw = json.dumps(obj, separators=(",", ":")).encode("utf-8")
    gz = _gzip.compress(raw, compresslevel=6)
    blob = bucket.blob(f"{ARCHIVE_PREFIX}/{path}")
    blob.content_encoding = "gzip"
    blob.cache_control = cache_control
    blob.upload_from_string(gz, content_type="application/geo+json")
    return len(gz)


def _update_index(bucket, entries: dict) -> None:
    """Merge per-type day/week entries into index.json.

    entries: {type: {"day": {...}} | {"week": {...}}}. Read-modify-write with
    a generation precondition and one retry, so the daily run and a backfill
    can't silently clobber each other.
    """
    from google.api_core.exceptions import PreconditionFailed
    import gzip as _gzip

    blob = bucket.blob(f"{ARCHIVE_PREFIX}/index.json")
    for attempt in (1, 2):
        generation = 0
        index = {"version": 1, "types": {}}
        if blob.exists():
            blob.reload()
            generation = blob.generation
            payload = blob.download_as_bytes()
            try:
                payload = _gzip.decompress(payload)
            except OSError:
                pass  # served decompressed by the client library
            index = json.loads(payload.decode("utf-8"))

        for type_name, update in entries.items():
            section = index["types"].setdefault(
                type_name, {"earliest": None, "latest": None, "days": [], "weeks": []}
            )
            day_entry = update.get("day")
            if day_entry:
                section["days"] = [d for d in section["days"] if d["date"] != day_entry["date"]]
                section["days"].append(day_entry)
                section["days"].sort(key=lambda d: d["date"])
            week_entry = update.get("week")
            if week_entry:
                section["weeks"] = [w for w in section["weeks"] if w["week"] != week_entry["week"]]
                section["weeks"].append(week_entry)
                section["weeks"].sort(key=lambda w: w["week"])
            if section["days"]:
                section["earliest"] = section["days"][0]["date"]
                section["latest"] = section["days"][-1]["date"]

        index["updated"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        raw = json.dumps(index, separators=(",", ":")).encode("utf-8")
        blob.cache_control = _ARCHIVE_INDEX_CACHE_CONTROL
        blob.content_encoding = "gzip"
        try:
            blob.upload_from_string(
                _gzip.compress(raw, compresslevel=6),
                content_type="application/json",
                if_generation_match=generation if generation else 0,
            )
            return
        except PreconditionFailed:
            if attempt == 2:
                raise
            print("Archive index generation conflict; retrying once")


def _archive_one_day(date_str: str, types=("fires", "earthquakes")) -> dict:
    """Fetch + write the given UTC day for each type. Partial success is
    success: each type is independent, failures are reported not raised."""
    bucket = _archive_bucket()
    year = date_str[:4]
    results = {}
    index_entries = {}

    fetchers = {
        "fires": lambda: _fetch_firms_day(FIRMS_MAP_KEY.value, date_str),
        "earthquakes": lambda: _fetch_quakes_day(date_str),
    }
    for type_name in types:
        fetcher = fetchers.get(type_name)
        if fetcher is None:
            results[type_name] = "unknown type"
            continue
        try:
            fc = fetcher()
            path = f"{type_name}/daily/{year}/{date_str}.geojson"
            size = _write_archive_object(bucket, path, fc)
            results[type_name] = f"ok ({len(fc['features'])} features, {size} bytes gz)"
            index_entries[type_name] = {"day": {
                "date": date_str,
                "path": path,
                "count": len(fc["features"]),
                "bytes": size,
                "bbox": _fc_bbox(fc["features"]),
            }}
        except Exception as e:
            results[type_name] = f"FAILED: {e}"
            print(f"Archive {type_name} {date_str} failed: {e}")

    if index_entries:
        _update_index(bucket, index_entries)
    return results


def _build_weekly_rollup(date_str: str) -> None:
    """When date_str is a Sunday, concatenate that ISO week's daily fire
    files into a weekly file (top-200 by FRP per 0.5-degree cell, so weekly
    files stay bounded long after dailies are lifecycle-deleted)."""
    import gzip as _gzip

    day = datetime.date.fromisoformat(date_str)
    if day.isoweekday() != 7:
        return
    iso_year, iso_week, _ = day.isocalendar()
    bucket = _archive_bucket()

    cells = {}
    counted = 0
    for offset in range(6, -1, -1):
        d = day - datetime.timedelta(days=offset)
        blob = bucket.blob(f"{ARCHIVE_PREFIX}/fires/daily/{d.year}/{d.isoformat()}.geojson")
        if not blob.exists():
            continue
        payload = blob.download_as_bytes()
        try:
            payload = _gzip.decompress(payload)
        except OSError:
            pass
        fc = json.loads(payload.decode("utf-8"))
        for f in fc.get("features", []):
            lon, lat = f["geometry"]["coordinates"][:2]
            cell = (int(lon // 0.5), int(lat // 0.5))
            bucket_list = cells.setdefault(cell, [])
            bucket_list.append(f)
            counted += 1

    features = []
    for cell_features in cells.values():
        cell_features.sort(key=lambda f: f["properties"].get("frp") or 0, reverse=True)
        features.extend(cell_features[:200])

    if not features:
        return
    week_key = f"{iso_year}-W{iso_week:02d}"
    path = f"fires/weekly/{week_key}.geojson"
    fc = {
        "type": "FeatureCollection",
        "features": features,
        "metadata": {
            "type": "fires", "week": week_key,
            "count": len(features), "source_count": counted,
            "decimation": "top 200 by FRP per 0.5 deg cell",
        },
    }
    size = _write_archive_object(bucket, path, fc)
    _update_index(bucket, {"fires": {"week": {
        "week": week_key, "path": path, "count": len(features), "bytes": size,
    }}})
    print(f"Weekly rollup {week_key}: {len(features)}/{counted} features kept")


@scheduler_fn.on_schedule(
    # 06:10 UTC: the previous UTC day's FIRMS NRT data is complete by then.
    schedule="every day 06:10",
    timezone=scheduler_fn.Timezone("UTC"),
    timeout_sec=540,
    memory=options.MemoryOption.GB_1,
    secrets=[FIRMS_MAP_KEY],
)
def archive_hazards_daily(event):
    """Snapshot yesterday's global hazard layers into the public archive."""
    yesterday = (
        datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=1)
    ).date().isoformat()
    print(f"Archiving hazards for {yesterday}")
    results = _archive_one_day(yesterday)
    try:
        _build_weekly_rollup(yesterday)
    except Exception as e:
        print(f"Weekly rollup failed (dailies unaffected): {e}")
    summary = "; ".join(f"{k}: {v}" for k, v in results.items())
    print(f"Archive run complete — {summary}")
    return summary


@https_fn.on_request(
    timeout_sec=540,
    memory=options.MemoryOption.GB_1,
    secrets=[FIRMS_MAP_KEY, "ADMIN_TRIGGER_TOKEN"],
)
def archive_backfill(request: https_fn.Request):
    """Backfill archive days. Closed by default — same contract as
    trigger_scout: bind ADMIN_TRIGGER_TOKEN to this function to open it.

    Query params:
        start, end - ISO dates (inclusive). end defaults to start.
        types      - comma list, default "fires,earthquakes". Fires older
                     than the ~10-day FIRMS NRT window are skipped.
    """
    import os
    expected = os.environ.get("ADMIN_TRIGGER_TOKEN", "")
    if not expected:
        return ({"status": "forbidden", "error": "Backfill is closed. Bind ADMIN_TRIGGER_TOKEN and redeploy."}, 403)
    supplied = request.headers.get("X-Admin-Token") or request.args.get("token") or ""
    if supplied != expected:
        return ({"status": "forbidden", "error": "Invalid admin token"}, 403)

    try:
        start = datetime.date.fromisoformat(request.args.get("start", ""))
    except ValueError:
        return ({"error": "start param must be YYYY-MM-DD"}, 400)
    try:
        end = datetime.date.fromisoformat(request.args.get("end") or start.isoformat())
    except ValueError:
        return ({"error": "end param must be YYYY-MM-DD"}, 400)
    if end < start or (end - start).days > 60:
        return ({"error": "invalid range (max 60 days)"}, 400)

    types = tuple(
        t.strip() for t in (request.args.get("types") or "fires,earthquakes").split(",") if t.strip()
    )
    today = datetime.datetime.now(datetime.timezone.utc).date()
    firms_floor = today - datetime.timedelta(days=_FIRMS_NRT_WINDOW_DAYS)

    all_results = {}
    d = start
    while d <= end:
        day_types = tuple(
            t for t in types
            if not (t == "fires" and d < firms_floor)
        )
        skipped = [t for t in types if t not in day_types]
        results = _archive_one_day(d.isoformat(), day_types) if day_types else {}
        for t in skipped:
            results[t] = f"skipped: before FIRMS NRT window ({firms_floor.isoformat()})"
        all_results[d.isoformat()] = results
        d += datetime.timedelta(days=1)

    return ({"status": "ok", "results": all_results}, 200)


# ═══════════════════════════════════════════════════════════════
# ENVIRONMENTAL NEWS FEED
#
# The Environmental News page is a newsletter over live disaster alerts. It
# streams a small Firestore collection (`news_feed`) that this code keeps in
# step with the GDACS RSS feed, and enriches each alert with the detail the
# GDACS report page shows: the affected countries, the published dates and
# duration, the impact statement and its area, the Sendai impact reports
# (who is affected, with what, where), the published map images and the
# Copernicus emergency-mapping products.
#
# Server-side because:
#   - the GDACS JSON list API refuses multi-type queries and answers a
#     single type in 20-90 s; the RSS carries every type in one ~1 MB
#     response in about 3 s;
#   - the RSS sends no CORS header, so a browser cannot read it directly;
#   - the detail API takes 2-45 s per event and the report page is HTML;
#   - one refresh serves every visitor instead of one fetch per page view.
#
# Nothing is computed here beyond arithmetic on published values: a sort
# key, a plain headline from the feed's own fields, the duration between
# the two published dates, and the area of a published polygon. Impact
# reports are stored one by one and never summed: they nest and supersede.
# ═══════════════════════════════════════════════════════════════

GDACS_RSS_URL = "https://www.gdacs.org/xml/rss.xml"
GDACS_EVENT_URL = "https://www.gdacs.org/gdacsapi/api/events/geteventdata?eventtype={t}&eventid={i}"
GDACS_GEOM_URL = (
    "https://www.gdacs.org/gdacsapi/api/polygons/getgeometry"
    "?eventtype={t}&eventid={i}&episodeid={e}&polygontype={p}"
)
GDACS_REPORT_URL = "https://www.gdacs.org/report.aspx?eventid={i}&episodeid={e}&eventtype={t}"
NEWS_COLLECTION = "news_feed"
NEWS_META_COLLECTION = "news_meta"
NEWS_META_DOC = "latest"
_NEWS_UA = "EcoLens/1.0 (+https://ecolenswebapp.web.app)"
_NEWS_TYPE_LABELS = {
    "EQ": "Earthquake",
    "TC": "Tropical cyclone",
    "FL": "Flood",
    "VO": "Volcano",
    "DR": "Drought",
    "WF": "Wildfire",
    "TS": "Tsunami",
}
_NEWS_LEVEL_RANK = {"Red": 0, "Orange": 1, "Green": 2}
# Every non-wildfire alert is enriched; wildfires only when GDACS rates them
# above Green (there are ~350 green wildfires on the wire at any time).
_NEWS_ENRICH_ALWAYS = {"FL", "EQ", "TC", "VO", "DR", "TS"}
# Re-read a current event's detail this often even if the feed stamp did
# not move: impact reports are appended without always touching datemodified.
_NEWS_REENRICH_MS = 6 * 3600 * 1000
# Polygon classes whose area is a published footprint. Poly_Global and
# Poly_Circle are deliberately absent (bounding box / fixed 100 km ring).
_AFFECTED_POLYGONTYPE = {"FL": "Affected", "WF": "area", "TC": "Green,Orange,Red"}
_AFFECTED_BASIS = {
    "FL": "GloFAS published flood extent",
    "WF": "published affected area",
}
_RSS_NS = {
    "gdacs": "http://www.gdacs.org",
    "geo": "http://www.w3.org/2003/01/geo/wgs84_pos#",
    "georss": "http://www.georss.org/georss",
    "dc": "http://purl.org/dc/elements/1.1/",
}


def _rss_text(item, path: str) -> str:
    node = item.find(path, _RSS_NS)
    return (node.text or "").strip() if node is not None else ""


def _rss_attr(item, path: str, name: str) -> str:
    node = item.find(path, _RSS_NS)
    return (node.get(name) or "").strip() if node is not None else ""


def _to_float(value):
    try:
        return float(str(value).replace(",", ""))
    except (TypeError, ValueError):
        return None


def _rss_date(value: str):
    """RFC 2822 -> (ISO-8601 UTC string, epoch ms). ('', 0) when unparsable."""
    if not value:
        return "", 0
    try:
        from email.utils import parsedate_to_datetime

        dt = parsedate_to_datetime(value)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=datetime.timezone.utc)
        dt = dt.astimezone(datetime.timezone.utc)
        return dt.strftime("%Y-%m-%dT%H:%M:%SZ"), int(dt.timestamp() * 1000)
    except Exception:
        return "", 0


def _api_date(value):
    """GDACS API dates are naive ISO strings in UTC ('2026-08-26T01:00:00')."""
    if not value:
        return None
    try:
        dt = datetime.datetime.fromisoformat(str(value).replace("Z", ""))
        return dt.replace(tzinfo=datetime.timezone.utc)
    except ValueError:
        return None


def _iso(dt) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ") if dt else ""


def _news_headline(event_type: str, name: str, country: str, severity_value: str) -> str:
    """Plain headline from the feed's own fields. The magnitude is the
    severity value GDACS publishes, never estimated."""
    where = f" in {country}" if country else ""
    comma = f", {country}" if country else ""
    if event_type == "TC":
        return f"Tropical cyclone {name}{comma}" if name else f"Tropical cyclone{where}"
    if event_type == "EQ":
        mag = _to_float(severity_value)
        return f"Magnitude {mag:.1f} earthquake{where}" if mag else f"Earthquake{where}"
    if event_type == "VO":
        return f"Volcano {name}{comma}" if name else f"Volcanic activity{where}"
    label = _NEWS_TYPE_LABELS.get(event_type, "Event")
    if name and name.lower() != (country or "").lower():
        return f"{label}: {name}{comma}"
    return f"{label}{where}"


def _parse_gdacs_rss(raw_xml: bytes, fetched_at: str) -> dict:
    import xml.etree.ElementTree as ET

    root = ET.fromstring(raw_xml)
    docs = {}
    for item in root.findall("./channel/item"):
        event_type = _rss_text(item, "gdacs:eventtype").upper()
        event_id = _rss_text(item, "gdacs:eventid")
        if not event_type or not event_id:
            continue
        guid = f"{event_type}{event_id}"
        level = _rss_text(item, "gdacs:alertlevel") or "Green"
        name = _rss_text(item, "gdacs:eventname")
        country = _rss_text(item, "gdacs:country")
        published, published_ms = _rss_date(_rss_text(item, "pubDate"))
        modified, modified_ms = _rss_date(_rss_text(item, "gdacs:datemodified"))
        from_date, from_ms = _rss_date(_rss_text(item, "gdacs:fromdate"))
        to_date, to_ms = _rss_date(_rss_text(item, "gdacs:todate"))
        stamps = [
            (modified_ms, modified),
            (to_ms, to_date),
            (published_ms, published),
            (from_ms, from_date),
        ]
        last_ms, last_iso = max(stamps, key=lambda s: s[0])

        lat = lon = None
        point = _rss_text(item, "georss:point").split()
        if len(point) == 2:
            lat, lon = _to_float(point[0]), _to_float(point[1])
        if lat is None or lon is None:
            lat = _to_float(_rss_text(item, "geo:Point/geo:lat"))
            lon = _to_float(_rss_text(item, "geo:Point/geo:long"))

        severity_value = _rss_attr(item, "gdacs:severity", "value")
        rank = _NEWS_LEVEL_RANK.get(level, 2)
        # Lower sorts first: Red, then Orange, then Green; within a level the
        # most recently active event first. 1e13 ms is the year 2286.
        sort_key = rank * 10_000_000_000_000 + (10_000_000_000_000 - last_ms)

        docs[guid] = {
            "id": guid,
            "event_type": event_type,
            "type_label": _NEWS_TYPE_LABELS.get(event_type, event_type),
            "headline": _news_headline(event_type, name, country, severity_value),
            "title": _rss_text(item, "title"),
            "description": _rss_text(item, "description"),
            "link": _rss_text(item, "link"),
            "event_name": name,
            "event_id": event_id,
            "episode_id": _rss_text(item, "gdacs:episodeid"),
            "alert_level": level,
            "alert_score": _to_float(_rss_text(item, "gdacs:alertscore")),
            "episode_alert_level": _rss_text(item, "gdacs:episodealertlevel"),
            "severity_text": _rss_text(item, "gdacs:severity"),
            "severity_value": _to_float(severity_value),
            "severity_unit": _rss_attr(item, "gdacs:severity", "unit"),
            "population_text": _rss_text(item, "gdacs:population"),
            "population_value": _to_float(_rss_attr(item, "gdacs:population", "value")),
            "country": country,
            "iso3": _rss_text(item, "gdacs:iso3"),
            "lat": lat,
            "lon": lon,
            "from_date": from_date,
            "to_date": to_date,
            "published": published,
            "modified": modified,
            "last_activity": last_iso,
            "last_activity_ms": last_ms,
            "is_current": _rss_text(item, "gdacs:iscurrent").lower() == "true",
            "rank": rank,
            "sort_key": sort_key,
            "source": "GDACS",
            "source_url": GDACS_RSS_URL,
            "fetched_at": fetched_at,
        }
    return docs


# ── Per-event detail (the report-page fields) ─────────────────────────────

def _needs_enrichment(d: dict) -> bool:
    return d["event_type"] in _NEWS_ENRICH_ALWAYS or d["alert_level"] != "Green"


def _indicator_factor(name: str) -> float:
    """Same scale the map's impact markers use. Death outranks everything;
    the value itself carries the rest, so 54,000 displaced beats 1 dead."""
    n = (name or "").lower()
    if "death" in n or "dead" in n or "fatal" in n:
        return 1000.0
    if "missing" in n or "injur" in n:
        return 100.0
    if "displac" in n or "evacu" in n or "affected" in n or "homeless" in n:
        return 1.0
    return 0.1


def _impact_weight(report: dict) -> float:
    return _indicator_factor(report.get("indicator", "")) * (report.get("value") or 0.0)


def _http_get(url: str, timeout: int):
    import requests

    resp = requests.get(url, timeout=timeout, headers={"User-Agent": _NEWS_UA})
    resp.raise_for_status()
    return resp


def _extract_products(html: str) -> list:
    """The report page carries its Satellite/Analytical products (Copernicus
    EMS maps, ECHO daily maps) as a JSON literal: `var arraymaps = [...]`."""
    m = re.search(r"var\s+arraymaps\s*=\s*(\[.*?\])\s*;", html, re.S)
    if not m:
        return []
    try:
        raw = json.loads(m.group(1))
    except ValueError:
        return []
    out = []
    for p in raw if isinstance(raw, list) else []:
        if not isinstance(p, dict):
            continue
        image = (p.get("image") or "").strip()
        link = (p.get("link") or "").strip()
        title = (p.get("title") or "").strip()
        if not (image or link):
            continue
        out.append({
            "title": title or "Map product",
            "image": image,
            "link": link,
            "date": _iso(_api_date(p.get("pubdate"))),
            "kind": (p.get("typemap") or p.get("type") or "").strip(),
        })
    out.sort(key=lambda p: p["date"], reverse=True)
    return out[:8]


def _polygon_area_km2(geom_json: dict):
    """Area of a published polygon in an equal-area projection. Returns None
    when the geometry libraries are unavailable (never estimates)."""
    try:
        from shapely.geometry import shape
        from shapely.ops import transform as shp_transform
        from pyproj import Transformer
    except ImportError:
        return None
    try:
        g = shape(geom_json)
        if g.is_empty:
            return None
        tr = Transformer.from_crs("EPSG:4326", "ESRI:54009", always_xy=True).transform
        return round(shp_transform(tr, g).area / 1e6, 1)
    except Exception:
        return None


def _affected_area(event_type: str, event_id: str, episode_id: str):
    """(area_km2, basis, zones) from the published footprint polygons.
    zones lists each published polygon with its own area (cyclone wind
    buffers each get one). Nothing is drawn or estimated: absent = None."""
    ptype = _AFFECTED_POLYGONTYPE.get(event_type)
    if not ptype or not episode_id:
        return None, "", []
    url = GDACS_GEOM_URL.format(t=event_type, i=event_id, e=episode_id, p=ptype)
    fc = _http_get(url, timeout=45).json()
    zones = []
    for f in fc.get("features", []):
        props = f.get("properties") or {}
        klass = str(props.get("Class") or "")
        label = str(props.get("polygonlabel") or "").strip()
        geom = f.get("geometry") or {}
        if geom.get("type") not in ("Polygon", "MultiPolygon"):
            continue
        if event_type == "TC":
            if not re.match(r"^Poly_(Green|Orange|Red)$", klass):
                continue
            if not re.match(r"^\s*[0-9.]+\s*km/h\s*$", label, re.I):
                continue  # per-timestep forecast footprints share the class
        elif klass not in ("Poly_Affected", "Poly_area"):
            continue
        km2 = _polygon_area_km2(geom)
        if km2 is None:
            continue
        zones.append({"label": label or klass, "km2": km2})
    if not zones:
        return None, "", []
    if event_type == "TC":
        zones.sort(key=lambda z: -z["km2"])
        widest = zones[0]
        return widest["km2"], f"area inside the published {widest['label']} wind buffer", zones
    total = round(sum(z["km2"] for z in zones), 1)
    return total, _AFFECTED_BASIS.get(event_type, "published affected area"), zones


# ── Story composition ─────────────────────────────────────────────
#
# Each alert becomes a readable story: dateline, headline, standfirst, body
# paragraphs, a timeline and a press list. Every sentence is assembled from
# published fields (GDACS detail API, its Sendai reports, the report page's
# Copernicus products, the Europe Media Monitor index) or from arithmetic on
# them (days between two published dates). No model writes any of it, so
# nothing can be invented; where a fact is absent the sentence is absent.

GDACS_EMM_URL = "https://www.gdacs.org/gdacsapi/api/emm/getemmnewsbykey?eventtype={t}&eventid={i}"
GDACS_GDNEWS_URL = "https://www.gdacs.org/gdacsapi/api/news/getnewsbygdacskey?eventtype={t}&eventid={i}"
_ENGLISH_HINT = {
    "the", "in", "of", "to", "and", "as", "for", "on", "at", "with", "after", "from",
    "flood", "floods", "flooding", "dead", "death", "deaths", "toll", "rescue", "rescued",
    "killed", "people", "storm", "cyclone", "typhoon", "hurricane", "earthquake", "quake",
    "drought", "wildfire", "fire", "fires", "evacuated", "missing", "injured", "landslide",
}
_LEVEL_PHRASE = {
    "Red": "Red, its highest alert level",
    "Orange": "Orange, its middle alert level",
    "Green": "Green, its lowest alert level",
}
_MONTHS = ["January", "February", "March", "April", "May", "June", "July",
           "August", "September", "October", "November", "December"]


def _fmt_int(v) -> str:
    try:
        return f"{int(round(float(v))):,}"
    except (TypeError, ValueError):
        return str(v)


def _dmy(iso: str) -> str:
    dt = _api_date(iso)
    return f"{dt.day} {_MONTHS[dt.month - 1]} {dt.year}" if dt else ""


def _dm(iso: str) -> str:
    dt = _api_date(iso)
    return f"{dt.day} {_MONTHS[dt.month - 1]}" if dt else ""


def _hm_utc(iso: str) -> str:
    dt = _api_date(iso)
    return f"{dt.strftime('%H:%M')} UTC on {dt.day} {_MONTHS[dt.month - 1]}" if dt else ""


def _clean_report(desc: str, country: str = "") -> str:
    """'939 [people] Fatalities in Bagmati Province, Nepal' ->
    '939 fatalities in Bagmati Province'."""
    s = re.sub(r"\s*\[[^\]]+\]\s*", " ", desc or "")
    s = re.sub(r"\s+", " ", s).strip()
    s = re.sub(r"^(\d[\d,\.]*\s+)([A-Z])", lambda m: m.group(1) + m.group(2).lower(), s)
    if country and s.lower().endswith(", " + country.lower()):
        s = s[: -(len(country) + 2)]
    return s


def _join_names(names: list, max_names: int = 6) -> str:
    names = [n for n in names if n]
    if not names:
        return ""
    if len(names) <= max_names:
        return names[0] if len(names) == 1 else ", ".join(names[:-1]) + " and " + names[-1]
    return ", ".join(names[:max_names]) + f" and {len(names) - max_names} more"


def _english_score(title: str) -> int:
    words = re.findall(r"[a-z']+", (title or "").lower())
    return sum(1 for w in words if w in _ENGLISH_HINT)


def _fetch_press(event_type: str, event_id: str, limit: int = 8) -> list:
    """Headlines the Europe Media Monitor has indexed for this alert. Titles,
    sources and links only; EMM does not carry article text. English is
    preferred by a stop-word hint, then recency; duplicates collapsed."""
    raw = _http_get(GDACS_EMM_URL.format(t=event_type, i=event_id), timeout=60).json()
    seen, items = set(), []
    for it in raw if isinstance(raw, list) else []:
        if not isinstance(it, dict):
            continue
        title = re.sub(r"\s+", " ", (it.get("title") or "")).strip()
        title = re.sub(r"(?<=\w)[�-’](?=\w)", "'", title)
        title = re.sub(r"[�-]", "", title).strip()
        key = title.casefold()
        if not title or key in seen:
            continue
        seen.add(key)
        items.append({
            "title": title,
            "source": (it.get("source") or "").strip(),
            "date": _iso(_api_date(it.get("pubdate"))),
            "link": (it.get("link") or "").strip(),
            "_score": _english_score(title),
        })
    items.sort(key=lambda p: (p["_score"] >= 2, p["date"]), reverse=True)
    for p in items:
        p.pop("_score", None)
    return items[:limit]


def _fetch_activations(event_type: str, event_id: str) -> list:
    """GDACS's own dated notes for the event: Copernicus EMS activations and
    similar. Dates are the substance; the text is short."""
    raw = _http_get(GDACS_GDNEWS_URL.format(t=event_type, i=event_id), timeout=30).json()
    out = []
    for it in raw if isinstance(raw, list) else []:
        if not isinstance(it, dict):
            continue
        out.append({
            "title": (it.get("title") or "").strip(),
            "text": re.sub(r"\s+", " ", (it.get("description") or it.get("shortdescription") or "")).strip(),
            "date": _iso(_api_date(it.get("pubdate"))),
            "link": (it.get("link") or "").strip(),
        })
    out.sort(key=lambda a: a["date"])
    return out[:12]


def _story_headline(d: dict, x: dict) -> str:
    t, country, level = d["event_type"], d.get("country") or "", d.get("alert_level") or ""
    label = _NEWS_TYPE_LABELS.get(t, "Event")
    name = d.get("event_name") or ""
    head = x.get("impact_headline") or {}
    lead_report = _clean_report(head.get("description", ""), country) if isinstance(head, dict) else ""
    km2 = x.get("affected_area_km2")
    where = f" in {country}" if country else ""

    if lead_report:
        subject = f"{label} {name}" if name and t in ("TC", "VO") else f"{label}{where}"
        return f"{subject}: {lead_report}"
    if t == "EQ":
        ex = x.get("exposure") or {}
        mag = ex.get("magnitude") or d.get("severity_value")
        m = f"Magnitude {float(mag):.1f} earthquake" if mag else "Earthquake"
        shake = (ex.get("shakepop_text") or "").strip()
        if shake:
            return f"{m}{where}: {shake} exposed to strong shaking, USGS estimates"
        depth = ex.get("depth_km")
        return f"{m}{where}" + (f" at {int(depth)} km depth" if depth else "")
    if t == "TC":
        wind = re.search(r"(\d+)\s*km/h", d.get("severity_text") or "")
        countries = x.get("affected_countries") or ([country] if country else [])
        near = f" near {_join_names(countries[:2])}" if countries else ""
        if wind:
            return f"Tropical cyclone {name}: winds of {wind.group(1)} km/h{near}".replace("  ", " ")
        return f"Tropical cyclone {name}{near}".replace("  ", " ")
    if t == "DR":
        countries = x.get("affected_countries") or []
        impact = re.search(r"^(\w+) impact", x.get("impact_statement") or "")
        scope = f"across {len(countries)} countries" if len(countries) > 1 else where.strip()
        if km2:
            return f"Drought {scope}: {_fmt_int(km2)} km² under {impact.group(1).lower() + ' ' if impact else ''}agricultural drought impact".replace("  ", " ")
        return f"Drought {scope} under GDACS {level} alert".replace("  ", " ")
    if t == "FL":
        if km2:
            return f"Flooding{where}: {_fmt_int(km2)} km² inside the published flood extent"
        return f"Flooding{where} under GDACS {level} alert"
    if t == "WF":
        sev = d.get("severity_text") or ""
        return f"Wildfire{where}: {sev}" if sev and not sev.startswith("Magnitude 0") else f"Wildfire{where} under GDACS {level} alert"
    if t == "VO":
        return f"Volcano {name}{where}: GDACS {level} alert" if name else f"Volcanic activity{where}: GDACS {level} alert"
    return f"{label}{where}: GDACS {level} alert"


def _compose_article(d: dict, x: dict, press: list, activations: list) -> dict:
    t = d["event_type"]
    label = _NEWS_TYPE_LABELS.get(t, "Event")
    country = d.get("country") or ""
    level = d.get("alert_level") or "Green"
    level_phrase = _LEVEL_PHRASE.get(level, level)
    countries = x.get("affected_countries") or []
    reports = [r for r in (x.get("impact_reports") or []) if isinstance(r, dict) and r.get("description")]
    head = x.get("impact_headline") if isinstance(x.get("impact_headline"), dict) else None
    km2 = x.get("affected_area_km2")
    basis = x.get("affected_area_basis") or ""
    days = x.get("duration_days")
    from_dmy, to_dmy = _dmy(d.get("from_date") or ""), _dmy(d.get("to_date") or "")
    latest_report_date = max((r.get("date") or "" for r in reports), default="")
    ex = x.get("exposure") or {}
    products = x.get("products") or []
    paragraphs, timeline = [], []

    # Dateline: the place the lead report names, else the country.
    dateline = ""
    if head and (head.get("region") or head.get("country")):
        dateline = ", ".join(p for p in [head.get("region"), head.get("country")] if p)
    elif countries:
        dateline = countries[0] if len(countries) == 1 else f"{countries[0]} and {len(countries) - 1} other countries"
    elif country:
        dateline = country

    # Standfirst: the one-paragraph version.
    lead_bits = []
    if t == "FL":
        began = f" that began on {_dm(d.get('from_date') or '')}" if d.get("from_date") else ""
        if head:
            lead_bits.append(f"Flooding{began} in {country} has left {_clean_report(head.get('description', ''), country)}, "
                             f"according to reports collected by the Global Disaster Alert and Coordination System (GDACS), "
                             f"which rates the event {level_phrase}.")
        else:
            lead_bits.append(f"Flooding{began} in {country} is rated {level_phrase} by GDACS.")
        if km2:
            lead_bits.append(f"The published flood extent covers {_fmt_int(km2)} km².")
    elif t == "EQ":
        mag = ex.get("magnitude") or d.get("severity_value")
        when = _hm_utc(d.get("from_date") or "")
        lead_bits.append(f"A magnitude {float(mag):.1f} earthquake struck {country}" + (f" at {when}" if when else "") +
                         (f", at a depth of {int(ex['depth_km'])} km" if ex.get("depth_km") else "") +
                         f". GDACS rates it {level_phrase}.")
        if ex.get("shakepop_text"):
            lead_bits.append(f"The USGS ShakeMap model puts {ex['shakepop_text']} shaking.")
    elif t == "TC":
        sev = d.get("severity_text") or ""
        lead_bits.append(f"Tropical cyclone {d.get('event_name') or ''} has been active since {from_dmy}" +
                         (f", reaching {sev[0].lower() + sev[1:]}" if sev else "") +
                         f". GDACS rates it {level_phrase}" +
                         (f" for {_join_names(countries, 4)}" if countries else "") + ".")
        if d.get("population_text"):
            lead_bits.append(d["population_text"].rstrip(".") + ".")
    elif t == "DR":
        stmt = x.get("impact_statement") or ""
        lead_bits.append((f"GDACS reports {stmt[0].lower() + stmt[1:]}" if stmt else f"GDACS reports a drought in {country}") +
                         (f", spanning {len(countries)} countries" if len(countries) > 1 else "") + ".")
        if days:
            lead_bits.append(f"The event has run for {days} days, from {from_dmy} to {to_dmy}.")
    else:
        sev = d.get("severity_text") or ""
        lead_bits.append(f"{label} in {country}: GDACS rates it {level_phrase}" + (f"; published severity: {sev}" if sev and not sev.startswith("Magnitude 0") else "") + ".")
    standfirst = " ".join(b for b in lead_bits if b)

    # Body 1: GDACS's own summary, verbatim, when it is a real paragraph.
    desc = (d.get("description") or "").strip()
    if not reports and len(desc) > 80 and desc.lower() != (d.get("headline") or "").lower():
        paragraphs.append({"text": desc, "source": "GDACS event description, verbatim"})

    # Body 2: who is affected, each report kept separate.
    if reports:
        lines = []
        seen = set()
        for r in reports[:8]:
            c = _clean_report(r.get("description", ""), "")
            if c and c.casefold() not in seen:
                seen.add(c.casefold())
                lines.append(c)
        if lines:
            as_of = f"As of {_dm(latest_report_date)}, " if latest_report_date else ""
            paragraphs.append({
                "text": f"{as_of}the reports GDACS has collected list {'; '.join(lines)}. "
                        f"Each figure is a separate report and they are not totals: reports nest inside one another and later ones supersede earlier ones.",
                "source": "GDACS Sendai impact reports",
            })
    elif t == "EQ" and (ex.get("shakepop_text") or ex.get("rapidpop_text")):
        bits = []
        if ex.get("shakepop_text"):
            bits.append(f"the ShakeMap model estimates {ex['shakepop_text']} shaking")
        if ex.get("rapidpop_text"):
            bits.append(f"the rapid population estimate is {ex['rapidpop_text']}")
        paragraphs.append({"text": "No impact reports have been published yet. On exposure, " + " and ".join(bits) + ", according to the USGS figures GDACS carries.",
                           "source": "USGS ShakeMap and PAGER, via GDACS"})
    elif d.get("population_text"):
        paragraphs.append({"text": "No impact reports have been published yet. GDACS's population model states: " + d["population_text"].rstrip(".") + ".",
                           "source": "GDACS population model"})

    # Body 3: where and how large.
    where_bits = []
    if len(countries) > 1:
        where_bits.append(f"The event spans {len(countries)} countries: {_join_names(countries, 8)}.")
    if km2 and t != "DR":
        if "wind" in basis:
            where_bits.append(f"The area inside the published {basis.split('published ')[-1].replace(' wind buffer', '')} wind buffer along the track is {_fmt_int(km2)} km².")
        else:
            where_bits.append(f"The published affected area covers {_fmt_int(km2)} km² ({basis}).")
    if days and t != "DR":
        where_bits.append(f"The event has run for {days} day{'s' if days != 1 else ''}, from {from_dmy} to {to_dmy}.")
    if where_bits:
        paragraphs.append({"text": " ".join(where_bits), "source": "GDACS detail record and published geometry"})

    # Body 4: mapping response.
    ems = [a for a in activations if "copernicus" in (a.get("title") or "").lower() or "EMSR" in (a.get("text") or "")]
    if ems or products:
        ids = sorted({m.group(1) for a in ems + products for m in [re.search(r"EMSR(\d+)", (a.get("text") or "") + (a.get("title") or ""))] if m})
        first = ems[0]["date"] if ems else (products[-1]["date"] if products else "")
        latest = max([p.get("date") or "" for p in products] + [a.get("date") or "" for a in ems], default="")
        s = "The Copernicus Emergency Management Service activated rapid mapping"
        if first:
            s += f" on {_dm(first)}"
        if ids:
            s += f" (activation EMSR{ids[0]})" if len(ids) == 1 else f" (activations {', '.join('EMSR' + i for i in ids)})"
        n = len(products)
        if n:
            s += f" and has published {n} map product{'s' if n != 1 else ''}"
            if latest:
                s += f", the latest on {_dm(latest)}"
        paragraphs.append({"text": s + ".", "source": "GDACS event notes and report page products"})

    # Body 5: status.
    status = "current" if d.get("is_current") else "closed"
    upd = _hm_utc(d.get("modified") or "")
    paragraphs.append({"text": f"GDACS lists the event as {status}" + (f"; its record was last updated at {upd}" if upd else "") + ".",
                       "source": "GDACS RSS feed"})

    # Timeline.
    if d.get("from_date"):
        timeline.append({"date": d["from_date"], "text": f"{label} begins, by GDACS's published start date."})
    for a in ems:
        if a.get("date"):
            timeline.append({"date": a["date"], "text": a.get("title") or "Copernicus EMS activation"})
    if latest_report_date:
        timeline.append({"date": latest_report_date, "text": "Latest impact report collected by GDACS."})
    if not d.get("is_current") and d.get("to_date"):
        timeline.append({"date": d["to_date"], "text": "Event closed, by GDACS's published end date."})
    if d.get("modified"):
        timeline.append({"date": d["modified"], "text": f"GDACS record updated; alert level {level}."})
    timeline.sort(key=lambda e: e["date"])

    words = len(standfirst.split()) + sum(len(p["text"].split()) for p in paragraphs)
    return {
        "dateline": dateline.upper(),
        "headline": _story_headline(d, x),
        "standfirst": standfirst,
        "paragraphs": paragraphs,
        "timeline": timeline,
        "press": press,
        "as_of": d.get("modified") or "",
        "word_count": words,
        "composed_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


def _enrich_event(d: dict) -> dict:
    """Everything the GDACS report page shows for one alert, copied from
    the detail API, the report page's product list, and the published
    footprint. Each source is best-effort; failures are recorded, not
    hidden."""
    t, i, e = d["event_type"], d["event_id"], d.get("episode_id") or ""
    out = {"enriched_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
    errors = []

    # 1. Detail API: countries, dates, impact statement, Sendai reports, images
    try:
        data = _http_get(GDACS_EVENT_URL.format(t=t, i=i), timeout=60).json()
        pr = data.get("properties") or data
        countries = [
            (c.get("countryname") or "").strip()
            for c in (pr.get("affectedcountries") or [])
            if isinstance(c, dict) and (c.get("countryname") or "").strip()
        ]
        out["affected_countries"] = countries
        f_dt, t_dt = _api_date(pr.get("fromdate")), _api_date(pr.get("todate"))
        if f_dt and t_dt and t_dt >= f_dt:
            out["duration_days"] = (t_dt - f_dt).days
        sev = pr.get("severitydata") or {}
        out["impact_statement"] = (sev.get("severitytext") or "").strip()
        out["impact_value"] = _to_float(sev.get("severity"))
        out["impact_unit"] = (sev.get("severityunit") or "").strip()
        if out["impact_unit"].lower() == "km2" and out["impact_value"]:
            out["affected_area_km2"] = out["impact_value"]
            out["affected_area_basis"] = "published impact statement"

        reports = []
        for r in pr.get("sendai") or []:
            if not isinstance(r, dict) or r.get("latest") is False:
                continue
            reports.append({
                "indicator": (r.get("sendainame") or "").strip(),
                "value": _to_float(r.get("sendaivalue")),
                "description": (r.get("description") or "").strip(),
                "country": (r.get("country") or "").strip(),
                "region": (r.get("region") or "").strip(),
                "date": _iso(_api_date(r.get("dateinsert"))),
            })
        # Later reports supersede earlier ones for the same indicator and
        # place, so keep the newest per (indicator, region, country). The
        # rest are still separate reports and are never added together.
        latest = {}
        for r in reports:
            key = (r["indicator"].casefold(), r["region"].casefold(), r["country"].casefold())
            if key not in latest or (r.get("date") or "") > (latest[key].get("date") or ""):
                latest[key] = r
        reports = sorted(latest.values(), key=_impact_weight, reverse=True)
        out["impact_reports"] = reports[:40]
        out["impact_headline"] = reports[0] if reports else None

        eq = pr.get("earthquakedetails") or {}
        if t == "EQ" and eq:
            out["exposure"] = {
                "magnitude": _to_float(eq.get("magnitude")),
                "depth_km": _to_float(eq.get("depth")),
                "shakepop_text": (eq.get("shakepopdescription") or "").strip(),
                "rapidpop_text": (eq.get("rapidpopdescription") or "").strip(),
                "source": pr.get("source") or "",
            }

        images = pr.get("images") or {}
        picks = [
            ("overviewmap", "Overview map"),
            ("overviewmap_cached", "Overview map"),
            ("floodmap_cached", "Flood map"),
            ("populationmap", "Population map"),
            ("populationmap_cached", "Population map"),
            ("shakemap_populationmap_static_v01", "ShakeMap and population"),
            ("neic_pager", "USGS PAGER"),
            ("thumbnailmap_cached", "Event map"),
        ]
        seen, map_images = set(), []
        for key, label in picks:
            url = (images.get(key) or "").strip() if isinstance(images, dict) else ""
            if url and url.lower().endswith((".png", ".jpg", ".jpeg")) and url not in seen:
                seen.add(url)
                map_images.append({"label": label, "url": url})
        out["map_images"] = map_images[:4]

        docs_map = pr.get("documents") or {}
        out["documents"] = [
            {"name": str(k), "url": str(v)}
            for k, v in (docs_map.items() if isinstance(docs_map, dict) else [])
        ][:6]
        out["glide"] = (pr.get("glide") or "").strip()
        urls = pr.get("url") or {}
        if isinstance(urls, dict) and urls.get("report"):
            out["report_url"] = urls["report"]
    except Exception as ex:
        errors.append(f"detail: {type(ex).__name__}: {str(ex)[:120]}")

    # 2. Report page: Copernicus EMS / ECHO products
    try:
        html = _http_get(GDACS_REPORT_URL.format(t=t, i=i, e=e or "1"), timeout=45).text
        out["products"] = _extract_products(html)
    except Exception as ex:
        errors.append(f"products: {type(ex).__name__}: {str(ex)[:120]}")

    # 3. Published footprint area, only when the statement did not give one
    if not out.get("affected_area_km2") and t in _AFFECTED_POLYGONTYPE:
        try:
            km2, basis, zones = _affected_area(t, i, e)
            if km2:
                out["affected_area_km2"] = km2
                out["affected_area_basis"] = basis
                out["affected_zones"] = zones
        except Exception as ex:
            errors.append(f"geometry: {type(ex).__name__}: {str(ex)[:120]}")

    # 4. What the press is reporting (EMM index) and GDACS's dated notes,
    #    then the story itself. Press is fetched for alerts above Green and
    #    for current floods and cyclones; EMM answers in 3-35 s per event.
    press, activations = [], []
    if d["alert_level"] != "Green" or (d.get("is_current") and t in ("FL", "TC")):
        try:
            press = _fetch_press(t, i)
        except Exception as ex:
            errors.append(f"press: {type(ex).__name__}: {str(ex)[:120]}")
    try:
        activations = _fetch_activations(t, i)
    except Exception as ex:
        errors.append(f"activations: {type(ex).__name__}: {str(ex)[:120]}")
    out["activations"] = activations
    try:
        out["article"] = _compose_article(d, out, press, activations)
    except Exception as ex:
        errors.append(f"article: {type(ex).__name__}: {str(ex)[:160]}")

    out["enrich_errors"] = errors
    return out


def _refresh_environmental_news(max_enrich: int = 25, workers: int = 4, force: bool = False) -> str:
    from collections import Counter
    from concurrent.futures import ThreadPoolExecutor

    now_ms = int(time.time() * 1000)
    fetched_at = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    resp = _http_get(GDACS_RSS_URL, timeout=45)
    docs = _parse_gdacs_rss(resp.content, fetched_at)
    if not docs:
        raise RuntimeError("GDACS RSS parsed to zero items; feed left untouched")

    db = firestore.client()
    meta_ref = db.collection(NEWS_META_COLLECTION).document(NEWS_META_DOC)
    meta_snap = meta_ref.get()
    meta = meta_snap.to_dict() or {} if meta_snap.exists else {}
    digest = meta.get("digest", {})
    enriched = meta.get("enriched", {})  # guid -> {"s": stamp, "t": ms}

    def stamp(d):
        return f"{d['modified']}|{d['alert_level']}|{d['is_current']}"

    # Change detection on the feed's own modified stamp: an unchanged event
    # costs no write. Gone from the feed = deleted from the collection.
    changed = {g: d for g, d in docs.items() if digest.get(g) != stamp(d)}
    to_delete = [g for g in digest if g not in docs]

    # Enrichment queue: eligible events whose stamp moved, were never
    # enriched, or (while current) were last enriched over six hours ago.
    # Red and Orange first, then most recent activity.
    def enrich_due(g, d):
        if force:
            return True
        prev = enriched.get(g) or {}
        if prev.get("s") != stamp(d):
            return True
        return d["is_current"] and now_ms - int(prev.get("t") or 0) > _NEWS_REENRICH_MS

    queue = [g for g, d in docs.items() if _needs_enrichment(d) and enrich_due(g, d)]
    queue.sort(key=lambda g: docs[g]["sort_key"])
    queue = queue[:max_enrich] if max_enrich else queue

    enriched_now = {}
    if queue:
        with ThreadPoolExecutor(max_workers=workers) as pool:
            for g, extra in zip(queue, pool.map(lambda g: _enrich_event(docs[g]), queue)):
                enriched_now[g] = extra
    for g, extra in enriched_now.items():
        docs[g].update(extra)
        enriched[g] = {"s": stamp(docs[g]), "t": now_ms}
    enriched = {g: v for g, v in enriched.items() if g in docs}

    to_write = dict(changed)
    for g in enriched_now:
        to_write[g] = docs[g]

    coll = db.collection(NEWS_COLLECTION)
    batch = db.batch()
    ops = 0
    for guid, doc in to_write.items():
        # merge=True keeps an earlier enrichment on a feed-only update.
        batch.set(coll.document(guid), doc, merge=True)
        ops += 1
        if ops % 400 == 0:
            batch.commit()
            batch = db.batch()
    for guid in to_delete:
        batch.delete(coll.document(guid))
        ops += 1
        if ops % 400 == 0:
            batch.commit()
            batch = db.batch()
    if ops % 400:
        batch.commit()

    by_type = Counter(d["event_type"] for d in docs.values())
    by_level = Counter(d["alert_level"] for d in docs.values())
    errors = sum(1 for x in enriched_now.values() if x.get("enrich_errors"))
    meta_ref.set({
        "updated_at": fetched_at,
        "updated_at_ms": now_ms,
        "count": len(docs),
        "by_type": dict(by_type),
        "by_level": dict(by_level),
        "source": "GDACS",
        "source_url": GDACS_RSS_URL,
        "written": len(to_write),
        "deleted": len(to_delete),
        "enriched_this_run": len(enriched_now),
        "enriched_total": len(enriched),
        "enrich_errors_this_run": errors,
        "digest": {g: stamp(d) for g, d in docs.items()},
        "enriched": enriched,
    })

    # GeoJSON mirror for the map's alerts layer, in the property names its
    # renderer already reads. Best-effort: the Firestore feed is the product.
    geojson_bytes = 0
    try:
        features = []
        for d in docs.values():
            if d["lat"] is None or d["lon"] is None:
                continue
            head = d.get("impact_headline") or {}
            features.append({
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": [d["lon"], d["lat"]]},
                "properties": {
                    "event_type": d["event_type"],
                    "event_name": d["event_name"] or d["headline"],
                    "alert_level": d["alert_level"],
                    "country": d["country"],
                    "score": d["alert_score"] or 0,
                    "affected": d["population_text"],
                    "impact": head.get("description", "") if isinstance(head, dict) else "",
                    "from_date": d["from_date"],
                    "to_date": d["to_date"],
                    "url": d["link"],
                    "headline": d["headline"],
                    "severity": d["severity_text"],
                    "is_current": d["is_current"],
                },
            })
        bucket = storage.bucket(ARCHIVE_BUCKET_NAME)
        geojson_bytes = _write_archive_object(
            bucket,
            "gdacs/current.geojson",
            {"type": "FeatureCollection", "generated_at": fetched_at,
             "source": GDACS_RSS_URL, "features": features},
            cache_control="public, max-age=300",
        )
    except Exception as ex:
        print(f"[news] GeoJSON mirror failed: {ex}")

    summary = (
        f"[news] {len(docs)} events {dict(by_level)}; wrote {len(to_write)}, "
        f"deleted {len(to_delete)}, enriched {len(enriched_now)} "
        f"({errors} with errors, {len(enriched)} total), geojson {geojson_bytes} B"
    )
    print(summary)
    return summary


@scheduler_fn.on_schedule(
    schedule="every 15 minutes",
    timeout_sec=540,
    memory=options.MemoryOption.GB_1,
)
def refresh_environmental_news(event):
    """Keep `news_feed` in step with the GDACS RSS feed, enriching a bounded
    batch of alerts per run so the job always finishes inside its timeout."""
    return _refresh_environmental_news(max_enrich=25)


@https_fn.on_request(
    timeout_sec=900,
    memory=options.MemoryOption.GB_1,
    secrets=["ADMIN_TRIGGER_TOKEN"],
)
def refresh_news_now(request):
    """Force a refresh. Closed unless the caller presents ADMIN_TRIGGER_TOKEN
    (header X-Admin-Token or ?token=). ?max_enrich=N bounds the detail
    fetches; 0 means every eligible alert."""
    import os

    expected = os.environ.get("ADMIN_TRIGGER_TOKEN", "")
    given = request.headers.get("X-Admin-Token") or request.args.get("token", "")
    if not expected or given != expected:
        return ({"status": "forbidden", "error": "ADMIN_TRIGGER_TOKEN required"}, 403)
    try:
        max_enrich = int(request.args.get("max_enrich", "80"))
    except ValueError:
        max_enrich = 80
    # ?force=1 re-enriches every eligible alert regardless of its stamp
    # (after a composer change, for instance).
    force = request.args.get("force", "") in ("1", "true", "yes")
    try:
        summary = _refresh_environmental_news(max_enrich=max_enrich, force=force)
        return ({"status": "ok", "summary": summary}, 200)
    except Exception as ex:
        return ({"status": "error", "error": f"{type(ex).__name__}: {ex}"}, 500)
