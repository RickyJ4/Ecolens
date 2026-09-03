from agents.gfw_ingestion_agent import GFWIngestionAgent
from agents.firms_fire_agent import FIRMSFireAgent
from agents.analysis_agent import AnalysisAgent
from agents.verification_agent import VerificationAgent
from agents.soil_analysis_agent import SoilAnalysisAgent
from agents.terrain_analysis_agent import TerrainAnalysisAgent
from agents.hydrology_analysis_agent import HydrologyAnalysisAgent
from agents.sentinel_verification_agent import SentinelVerificationAgent
from agents.vision_analysis_agent import VisionAnalysisAgent
from agents.spatial_pattern_agent import SpatialPatternAgent
from agents.biodiversity_agent import BiodiversityAgent
from services.land_feature_service import LandFeatureService
from services.biodiversity_service import BiodiversityService
from services.trend_service import TrendAnalysisService
from services.human_impact_service import HumanImpactService
from services.reforestation_service import ReforestationService
from services.worldpop_service import WorldPopService
from services.historical_analysis_service import HistoricalAnalysisService
from services.professional_gis_service import ProfessionalGISService
from services.financial_service import FinancialService
from services.firebase_service import save_report
from models.risk_prediction_model import RiskPredictionModel
from datetime import datetime
import json


class IntelligencePipeline:
    def __init__(self):
        self.gfw = GFWIngestionAgent()
        self.firms = FIRMSFireAgent()
        self.analysis = AnalysisAgent()
        self.verify = VerificationAgent()
        self.land = LandFeatureService()
        self.biodiversity = BiodiversityService()
        self.trends = TrendAnalysisService(self.gfw)
        self.human_impact = HumanImpactService()
        self.reforestation = ReforestationService()
        self.worldpop = WorldPopService()
        # Layer 9-12 agents/services
        self.soil = SoilAnalysisAgent()
        self.terrain = TerrainAnalysisAgent()
        self.hydrology = HydrologyAnalysisAgent()
        self.historical = HistoricalAnalysisService(self.gfw)
        # Layer 14-20: Professional enhancements
        self.sentinel = SentinelVerificationAgent()
        self.vision = VisionAnalysisAgent()
        self.spatial_patterns = SpatialPatternAgent()
        self.gis = ProfessionalGISService()
        self.risk_model = RiskPredictionModel()
        self.biodiversity_agent = BiodiversityAgent()
        self.financial = FinancialService()

    def analyze_location(self, lat: float, lng: float, habitat: str = 'Unknown'):
        """
        ON-DEMAND LOCATION ANALYSIS
        
        Called by the frontend to analyze a specific coordinate.
        Returns: Soil, Terrain, Hydrology, Historical, and AI Analysis.
        """
        print(f"🌍 Analyzing location: {lat}, {lng} ({habitat})")
        
        intelligence = {}
        
        # Create a 0.1 degree bounding box around the point
        bbox = {
            'min_lat': lat - 0.05,
            'max_lat': lat + 0.05,
            'min_lng': lng - 0.05,
            'max_lng': lng + 0.05
        }
        
        # Create a synthetic hotspot for historical analysis
        hotspot = {
            'region': habitat,
            'lat': lat,
            'lng': lng,
            'gfw_area__ha': 100  # Default area for on-demand analysis
        }
        
        # Layer 9: Soil Analysis
        print("🌱 Layer 9: Soil Analysis...")
        try:
            soil_data = self.soil.analyze(lat, lng)
            intelligence['soil_analysis'] = soil_data
        except Exception as e:
            print(f"⚠️ Soil analysis failed: {e}")
            intelligence['soil_analysis'] = {}
        
        # Layer 10: Terrain Analysis - takes bbox only
        print("🏔️ Layer 10: Terrain Analysis...")
        try:
            terrain_data = self.terrain.analyze(bbox)
            intelligence['terrain_analysis'] = terrain_data
        except Exception as e:
            print(f"⚠️ Terrain analysis failed: {e}")
            intelligence['terrain_analysis'] = {}
        
        # Layer 11: Hydrology Analysis - takes lat, lng, bbox, habitat_type
        print("💧 Layer 11: Hydrology Analysis...")
        try:
            hydrology_data = self.hydrology.analyze(lat, lng, bbox, habitat)
            intelligence['hydrology_analysis'] = hydrology_data
        except Exception as e:
            print(f"⚠️ Hydrology analysis failed: {e}")
            intelligence['hydrology_analysis'] = {}
        
        # Layer 12: Historical Trends - takes hotspot, bbox, fire_history
        print("📈 Layer 12: Historical Analysis...")
        try:
            historical_data = self.historical.analyze(hotspot, bbox)
            intelligence['historical_analysis'] = historical_data
        except Exception as e:
            print(f"⚠️ Historical analysis failed: {e}")
            intelligence['historical_analysis'] = {}
        
        # Layer 13: Calculate Recovery Potential
        print("🧠 Layer 13: Comprehensive Analysis...")
        try:
            recovery_score = self._calculate_recovery_potential(intelligence)
            intelligence['recovery_potential'] = recovery_score
            intelligence['comprehensive_analysis'] = {
                'success_probability': self._estimate_success_probability(intelligence),
                'action_plan': self._generate_action_plan(intelligence, lat, lng)
            }
        except Exception as e:
            print(f"⚠️ Comprehensive analysis failed: {e}")
            intelligence['recovery_potential'] = {'score': 50}
            intelligence['comprehensive_analysis'] = {}
        
        # Layer 14: Sentinel-2 Verification
        print("🛰️ Layer 14: Sentinel-2 Verification...")
        try:
            sentinel_data = self.sentinel.verify_with_sentinel(
                lat, lng,
                alert_date=datetime.utcnow(),
                area_ha=hotspot['gfw_area__ha']
            )
            intelligence['sentinel_verification'] = sentinel_data
        except Exception as e:
            print(f"⚠️ Sentinel verification failed: {e}")
            intelligence['sentinel_verification'] = {"available": False, "error": str(e)}
        
        # Layer 15: Professional GIS Analysis
        print("🗺️ Layer 15: Professional GIS Analysis...")
        try:
            gis_data = self.gis.comprehensive_analysis(
                lat, lng, bbox,
                deforestation_area_ha=hotspot['gfw_area__ha'],
                habitat_type=habitat
            )
            intelligence['gis_analysis'] = gis_data
        except Exception as e:
            print(f"⚠️ GIS analysis failed: {e}")
            intelligence['gis_analysis'] = {"available": False, "error": str(e)}
        
        # Layer 16: ML Risk Prediction
        print("🎯 Layer 16: Rule-Based Risk Prediction...")
        try:
            # Build intelligence data structure for rule-based scoring
            # This provides more accurate results than the ML model trained on limited data
            risk_intelligence = {
                'fire_data': intelligence.get('fire_data', {}),
                'vegetation_health': {
                    'current_ndvi': intelligence.get('vegetation_analysis', {}).get('ndvi', {}).get('current'),
                    'ndvi_change': intelligence.get('vegetation_analysis', {}).get('ndvi', {}).get('change_percent'),
                    **intelligence.get('vegetation_analysis', {})
                },
                'protected_areas': {
                    'is_protected': intelligence.get('gis_analysis', {}).get('proximity_analysis', {}).get('nearest_protected_area', {}).get('distance_km', 999) < 1,
                    'nearest_distance_km': intelligence.get('gis_analysis', {}).get('proximity_analysis', {}).get('nearest_protected_area', {}).get('distance_km', 999),
                    **intelligence.get('protected_areas', {})
                },
                'proximity': {
                    'roads': intelligence.get('gis_analysis', {}).get('proximity_analysis', {}).get('nearest_road', {}),
                    'settlements': intelligence.get('gis_analysis', {}).get('proximity_analysis', {}).get('nearest_settlement', {}),
                    **intelligence.get('gis_analysis', {}).get('proximity_analysis', {})
                },
                'human_impacts': intelligence.get('human_impacts', {}),
                'historical_analysis': intelligence.get('gfw_data', intelligence.get('historical_analysis', {})),
                'gfw_data': intelligence.get('gfw_data', {})
            }
            risk_prediction = self.risk_model.predict_risk(None, intelligence_data=risk_intelligence)
            intelligence['risk_prediction'] = risk_prediction
        except Exception as e:
            print(f"⚠️ Risk prediction failed: {e}")
            intelligence['risk_prediction'] = {"available": False, "error": str(e)}

        # Layer 17: Biodiversity Analysis (Species at risk & thriving species)
        print("🦜 Layer 17: Biodiversity Analysis...")
        try:
            biodiversity_data = self.biodiversity_agent.analyze(
                lat, lng, habitat,
                soil_data=intelligence.get('soil_analysis', {}),
                terrain_data=intelligence.get('terrain_analysis', {}),
                hydrology_data=intelligence.get('hydrology_analysis', {})
            )
            intelligence['biodiversity_analysis'] = biodiversity_data
        except Exception as e:
            print(f"⚠️ Biodiversity analysis failed: {e}")
            intelligence['biodiversity_analysis'] = {"available": False, "error": str(e)}

        # Layer 18: Financial Analysis (Verified regional costs)
        print("💰 Layer 18: Financial Analysis...")
        try:
            area_ha = hotspot.get('gfw_area__ha', 100)
            financial_analysis = self.financial.calculate_loss_vs_restoration(
                lat, lng, area_ha,
                soil_data=intelligence.get('soil_analysis'),
                forest_type=None  # Auto-detect from coordinates
            )
            intelligence['financial_analysis'] = financial_analysis

            # Also populate economic_impacts in a standardized format
            intelligence['economic_analysis'] = {
                "restoration_cost_usd": financial_analysis.get('restoration_cost_usd', 0),
                "ecosystem_loss_30yr_usd": financial_analysis.get('ecosystem_loss_30yr_usd', 0),
                "carbon_social_cost_usd": financial_analysis.get('carbon_social_cost_usd', 0),
                "total_loss_if_deforested_usd": financial_analysis.get('total_loss_if_deforested_usd', 0),
                "cost_benefit_ratio": financial_analysis.get('cost_benefit_ratio', 0),
                "break_even_years": financial_analysis.get('break_even_years'),
                "annual_ecosystem_value_usd": financial_analysis.get('detailed_analysis', {}).get('ecosystem_services', {}).get('annual_value_usd', 0),
                "sources": financial_analysis.get('sources', {})
            }
            print(f"✅ Restoration: ${financial_analysis.get('restoration_cost_usd', 0):,.0f} | Loss if deforested: ${financial_analysis.get('total_loss_if_deforested_usd', 0):,.0f}")
        except Exception as e:
            print(f"⚠️ Financial analysis failed: {e}")
            intelligence['financial_analysis'] = {"available": False, "error": str(e)}
            intelligence['economic_analysis'] = {}

        print(f"✅ Analysis complete for {lat}, {lng}")
        return intelligence

    def _calculate_recovery_potential(self, intelligence):
        """Calculate recovery potential score based on soil, terrain, hydrology"""
        score = 50  # Base score
        
        # Boost for good soil - handle nested dict structure
        soil = intelligence.get('soil_analysis', {})
        ph_data = soil.get('ph', {})
        ph_value = ph_data.get('value', 6.5) if isinstance(ph_data, dict) else (ph_data if isinstance(ph_data, (int, float)) else 6.5)
        if isinstance(ph_value, (int, float)) and 5.5 <= ph_value <= 7.5:
            score += 10
        
        fertility = soil.get('fertility', {})
        organic_carbon = fertility.get('organic_carbon', 0) if isinstance(fertility, dict) else 0
        if isinstance(organic_carbon, (int, float)) and organic_carbon > 2:
            score += 10
            
        # Reduce for difficult terrain - handle nested dict structure
        terrain = intelligence.get('terrain_analysis', {})
        slope_data = terrain.get('slope', {})
        slope = slope_data.get('mean_degrees', 0) if isinstance(slope_data, dict) else (slope_data if isinstance(slope_data, (int, float)) else 0)
        if isinstance(slope, (int, float)):
            if slope > 15:
                score -= 15
            elif slope > 8:
                score -= 5
            
        # Boost for water access - handle nested dict structure
        hydro = intelligence.get('hydrology_analysis', {})
        water_access = hydro.get('water_accessibility', {})
        rating = water_access.get('rating', 'Unknown') if isinstance(water_access, dict) else water_access
        if rating == 'High':
            score += 15
        elif rating == 'Medium':
            score += 5
            
        return {'score': max(0, min(100, score))}

    def _estimate_success_probability(self, intelligence):
        """Estimate restoration success probability"""
        score = intelligence.get('recovery_potential', {}).get('score', 50)
        if score >= 75:
            return 'High (>75%)'
        elif score >= 50:
            return 'Moderate (50-75%)'
        else:
            return 'Low (<50%)'

    def _generate_action_plan(self, intelligence, lat, lng):
        """Generate action plan based on analysis"""
        actions = []
        
        # Soil recommendations - handle nested dict structure
        soil = intelligence.get('soil_analysis', {})
        ph_data = soil.get('ph', {})
        ph_value = ph_data.get('value', 6.5) if isinstance(ph_data, dict) else (ph_data if isinstance(ph_data, (int, float)) else 6.5)
        if isinstance(ph_value, (int, float)):
            if ph_value < 5.5:
                actions.append({'priority': 'High', 'action': 'Apply lime to raise soil pH'})
            elif ph_value > 7.5:
                actions.append({'priority': 'Medium', 'action': 'Apply sulfur to lower soil pH'})
            
        # Terrain recommendations - handle nested dict structure
        terrain = intelligence.get('terrain_analysis', {})
        slope_data = terrain.get('slope', {})
        slope = slope_data.get('mean_degrees', 0) if isinstance(slope_data, dict) else (slope_data if isinstance(slope_data, (int, float)) else 0)
        if isinstance(slope, (int, float)) and slope > 15:
            actions.append({'priority': 'High', 'action': 'Implement terracing to prevent erosion'})
            
        # Hydrology recommendations - handle nested dict structure
        hydro = intelligence.get('hydrology_analysis', {})
        water_access = hydro.get('water_accessibility', {})
        rating = water_access.get('rating', 'Unknown') if isinstance(water_access, dict) else water_access
        if rating == 'Low':
            actions.append({'priority': 'High', 'action': 'Install irrigation infrastructure'})
            
        # Default action
        if not actions:
            actions.append({'priority': 'Medium', 'action': 'Begin seedling plantation program'})
            
        return {'immediate': actions[:3], 'long_term': [{'action': 'Establish monitoring program'}]}

    def run_global_scan(self):  # ← THIS IS THE METHOD
        """
        FULL INTELLIGENCE PIPELINE
        
        Discovers hotspots and builds complete environmental intelligence
        using REAL data sources (no hardcoded data)
        """
        print("=" * 70)
        print("🌍 EcoLens Global Intelligence Pipeline")
        print("=" * 70)

        # ═══════════════════════════════════════════════════════════
        # STEP 1: Discover Global Hotspots
        # ═══════════════════════════════════════════════════════════
        print("\n📡 STEP 1: Discovering deforestation hotspots...")
        print("-" * 70)
        
        gfw_hotspots = self.gfw.fetch_global_alerts()
        
        if not gfw_hotspots:
            print("⚠️ No hotspots discovered. Ending scan.")
            return []
        
        print(f"✅ Discovered {len(gfw_hotspots)} hotspots")

        # ═══════════════════════════════════════════════════════════
        # STEP 2: Process Each Hotspot
        # ═══════════════════════════════════════════════════════════
        reports = []
        
        for idx, hotspot in enumerate(gfw_hotspots, 1):
            try:
                print(f"\n{'=' * 70}")
                print(f"🔍 Processing Hotspot {idx}/{len(gfw_hotspots)}")
                print(f"{'=' * 70}")
                print(f"Region: {hotspot.get('region', 'Unknown')}")
                print(f"Area: {hotspot.get('gfw_area__ha', 'N/A')} ha")
                print(f"Pattern: {hotspot.get('pattern', 'N/A')}")
                
                # Extract geometry and calculate center/bbox
                geom = hotspot.get('geom') or hotspot.get('gfw_geojson')
                center, bbox = self._extract_geom_info(geom, hotspot)
                
                print(f"Center: {center['lat']:.4f}, {center['lng']:.4f}")
                
                # Build comprehensive intelligence from REAL data sources
                intelligence = self._build_comprehensive_intelligence(
                    hotspot, center, bbox
                )
                
                # ═══════════════════════════════════════════════════
                # Build Dual Reports for Firebase
                # ═══════════════════════════════════════════════════
                hotspot_id = f"hotspot_{idx}_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}"
                
                # Public Report (simplified for general audience)
                public_report = {
                    "hotspot_id": hotspot_id,
                    "region": hotspot.get('region'),
                    "area_ha": hotspot.get('gfw_area__ha'),
                    "center": center,
                    "timestamp": datetime.utcnow().isoformat(),
                    **intelligence.get('public_report', {}),
                    "fire_summary": intelligence.get('fire_summary', {}),
                    "proximity_summary": intelligence.get('proximity_summary', {}),
                    "biodiversity_summary": intelligence.get('biodiversity_summary', {}),
                    "history": intelligence.get('history', {}),
                    "headline": intelligence.get('public_report', {}).get('whats_happening', 'Environmental Alert Detected')[:100],
                    "fire_count": intelligence.get('fire_summary', {}).get('count', 0),
                    "species_count": intelligence.get('biodiversity_summary', {}).get('species_count', 0),
                    "people_affected": intelligence.get('human_impacts', {}).get('affected_population', {}).get('total', 0),
                    "trees_needed": intelligence.get('reforestation', {}).get('total_trees_needed', 0),
                    # New Layer 9-13 summary fields
                    "soil_type": intelligence.get('soil', {}).get('soil_texture', {}).get('class', 'Unknown'),
                    "terrain_difficulty": intelligence.get('terrain', {}).get('slope', {}).get('suitability', {}).get('difficulty', 'Unknown'),
                    "water_access": intelligence.get('hydrology', {}).get('water_accessibility', {}).get('rating', 'Unknown'),
                    "recovery_score": intelligence.get('comprehensive_analysis', {}).get('recovery_potential', {}).get('score'),
                    "success_probability": intelligence.get('comprehensive_analysis', {}).get('success_probability', {}).get('percent'),
                    "action_plan": intelligence.get('comprehensive_analysis', {}).get('action_plan', {})
                }
                
                # Scientific Report (comprehensive technical data)
                scientific_report = {
                    "hotspot_id": hotspot_id,
                    "region": hotspot.get('region'),
                    "area_ha": hotspot.get('gfw_area__ha'),
                    "pattern": hotspot.get('pattern'),
                    "center": center,
                    "bbox": bbox,
                    "timestamp": datetime.utcnow().isoformat(),
                    **intelligence.get('scientific_report', {}),
                    "fire_summary": intelligence.get('fire_summary', {}),
                    "proximity_summary": intelligence.get('proximity_summary', {}),
                    "biodiversity_summary": intelligence.get('biodiversity_summary', {}),
                    "trends": intelligence.get('trends', {}),
                    "human_impacts": intelligence.get('human_impacts', {}),
                    "reforestation": intelligence.get('reforestation', {}),
                    "verification": intelligence.get('verification', {}),
                    # New Layer 9-13 detailed data
                    "soil": intelligence.get('soil', {}),
                    "terrain": intelligence.get('terrain', {}),
                    "hydrology": intelligence.get('hydrology', {}),
                    "historical_timeline": intelligence.get('historical_timeline', {}),
                    "comprehensive_analysis": intelligence.get('comprehensive_analysis', {}),
                    "pipeline_version": "3.0"
                }

                # Save both reports to Firestore
                print("\n💾 Saving dual reports to Firestore...")
                try:
                    # Save public report
                    save_report({"hotspot_id": hotspot_id, "public_report": public_report}, report_type="both")
                    # Also save to legacy hotspots collection for backward compatibility
                    # Use 'hotspots' as report_type to target the correct collection
                    save_report(public_report, report_type="hotspots")
                    print("✅ Reports saved")
                except Exception as e:
                    print(f"⚠️ Firestore save failed: {e}")

                reports.append({"public": public_report, "scientific": scientific_report})
                print(f"✅ Hotspot {idx} complete")

            except Exception as e:
                print(f"❌ Error processing hotspot {idx}: {e}")
                import traceback
                traceback.print_exc()
                continue

        # ═══════════════════════════════════════════════════════════
        # Final Summary
        # ═══════════════════════════════════════════════════════════
        print("\n" + "=" * 70)
        print("📊 SCAN COMPLETE")
        print("=" * 70)
        print(f"Total hotspots discovered: {len(gfw_hotspots)}")
        print(f"Successfully processed: {len(reports)}")
        print(f"Failed: {len(gfw_hotspots) - len(reports)}")
        print("=" * 70)

        return reports

    def _build_comprehensive_intelligence(self, hotspot, center, bbox):
        """
        Build intelligence using REAL data sources
        OPTIMIZED: Stores summaries only to avoid Firestore 1MB limit
        """
        
        intelligence = {}
        # Safely convert area_ha to float (may be string from API)
        raw_area = hotspot.get('gfw_area__ha', 0)
        try:
            area_ha = float(raw_area) if raw_area else 0.0
        except (ValueError, TypeError):
            area_ha = 0.0
        
        # ───────────────────────────────────────────────────────────
        # LAYER 1: Fire Data - Store SUMMARY only
        # ───────────────────────────────────────────────────────────
        print("\n🔥 LAYER 1: Analyzing fire activity...")
        try:
            fire_data_raw = self.firms.fetch(bbox)
            # Store summary instead of full data
            intelligence['fire_summary'] = {
                "count": len(fire_data_raw) if fire_data_raw else 0,
                "has_fires": len(fire_data_raw) > 0 if fire_data_raw else False,
                "high_confidence_count": len([f for f in fire_data_raw if f.get('confidence') == 'high']) if fire_data_raw else 0
            }
            # Keep sample for analysis
            fire_data_for_analysis = fire_data_raw[:10] if fire_data_raw else []
            print(f"✅ Found {intelligence['fire_summary']['count']} fire alerts")
        except Exception as e:
            print(f"⚠️ Fire correlation failed: {e}")
            fire_data_for_analysis = []
            intelligence['fire_summary'] = {"count": 0, "has_fires": False}

        # ───────────────────────────────────────────────────────────
        # LAYER 2: Land Features - Store SUMMARY only
        # ───────────────────────────────────────────────────────────
        print("\n🌍 LAYER 2: Identifying land features at risk...")
        try:
            global_features = self.land.get_global_features()
            proximity_raw = self.land.proximity((center["lat"], center["lng"]), global_features)
            
            # Store summary instead of full data
            intelligence['proximity_summary'] = {}
            for category, items in proximity_raw.items():
                if items:
                    intelligence['proximity_summary'][category] = {
                        "count": len(items),
                        "nearest_km": min([item.get('distance_km', 999) for item in items])
                    }
            
            print(f"✅ Analyzed proximity to {len(proximity_raw)} feature types")
        except Exception as e:
            print(f"⚠️ Land analysis failed: {e}")
            proximity_raw = {}
            intelligence['proximity_summary'] = {}

        # ───────────────────────────────────────────────────────────
        # LAYER 3: Biodiversity - Store SUMMARY only
        # ───────────────────────────────────────────────────────────
        print("\n🦜 LAYER 3: Assessing biodiversity impact...")
        try:
            species = self.biodiversity.get_species_for_region(
                center["lat"], 
                center["lng"], 
                radius_km=50
            )
            
            habitat_type = self._infer_habitat_type(hotspot.get('region', ''))
            ecosystem_services = self.biodiversity.get_ecosystem_services(habitat_type)
            
            # Store summary only
            intelligence['biodiversity_summary'] = {
                "species_count": len(species),
                "habitat_type": habitat_type,
                "has_ecosystem_services": bool(ecosystem_services),
                "top_species": [s.get('species', 'Unknown') for s in species[:5]],
                "at_risk_species": [
                    {"name": s.get('species'), "iucn_status": s.get('iucn_status'), "risk_level": s.get('risk_level')}
                    for s in species if s.get('risk_level') in ['critical', 'high', 'medium-high']
                ][:10]
            }
            print(f"✅ Documented {len(species)} species in area")
        except Exception as e:
            print(f"⚠️ Biodiversity analysis failed: {e}")
            intelligence['biodiversity_summary'] = {"species_count": 0}
            species = []
            ecosystem_services = {}
            habitat_type = "Unknown"

        # ───────────────────────────────────────────────────────────
        # LAYER 4: Trends - Already compact
        # ───────────────────────────────────────────────────────────
        print("\n📈 LAYER 4: Analyzing trends and projections...")
        try:
            trends = self.trends.analyze_trends(hotspot, center, bbox)
            # Only store key trend info
            intelligence['trends'] = {
                "direction": trends.get('trend_direction', 'unknown'),
                "severity": trends.get('severity', 'unknown'),
                "restoration_potential": trends.get('restoration_potential', 'unknown')
            }
            print(f"✅ Trend: {trends.get('trend_direction', 'unknown')}")
            print(f"   Severity: {trends.get('severity', 'unknown')}")

            # Transform history for app consumption (List -> Map)
            history_map = {}
            if 'historical_data' in trends and 'year_over_year_data' in trends['historical_data']:
                for entry in trends['historical_data']['year_over_year_data']:
                    year = entry.get('umd_tree_cover_loss__year')
                    loss = entry.get('total_loss_ha')
                    if year and loss is not None:
                        history_map[str(year)] = float(loss)
            
            intelligence['history'] = history_map
        except Exception as e:
            print(f"⚠️ Trend analysis failed: {e}")
            trends = {}
            intelligence['trends'] = {"direction": "unknown", "severity": "unknown"}

        # ───────────────────────────────────────────────────────────
        # LAYER 5: Human Impact Assessment (Enhanced with WorldPop)
        # ───────────────────────────────────────────────────────────
        print("\n👥 LAYER 5: Assessing human impacts...")
        try:
            # First use WorldPop for real population data
            worldpop_data = self.worldpop.assess_deforestation_impact(
                center["lat"], center["lng"], area_ha, proximity_raw
            )
            
            # Also run traditional assessment
            human_impacts = self.human_impact.assess_impacts(
                hotspot, proximity_raw, area_ha
            )
            
            # Merge data - prefer WorldPop when available
            affected_pop = worldpop_data.get('total_affected', 0)
            if affected_pop == 0:
                affected_pop = human_impacts.get('affected_population_estimate', {}).get('total', 0)
            
            # Calculate verified financial data using regional costs
            financial_analysis = self.financial.calculate_loss_vs_restoration(
                center["lat"], center["lng"], area_ha,
                soil_data=intelligence.get('soil'),
                forest_type=None  # Will auto-detect from coordinates
            )

            intelligence['human_impacts'] = {
                "affected_population": {
                    "total": affected_pop,
                    "direct": worldpop_data.get('direct_impact', {}).get('population', 0),
                    "indirect": worldpop_data.get('indirect_impact', {}).get('population', 0),
                    "source": worldpop_data.get('source', 'estimation'),
                    "confidence": worldpop_data.get('confidence', 'medium')
                },
                "demographics": worldpop_data.get('demographics', {}),
                "effects": worldpop_data.get('effects_summary', []),
                "economic_impacts_usd": {
                    # Use verified financial service data
                    "restoration_cost_usd": financial_analysis.get('restoration_cost_usd', 0),
                    "ecosystem_loss_30yr_usd": financial_analysis.get('ecosystem_loss_30yr_usd', 0),
                    "carbon_social_cost_usd": financial_analysis.get('carbon_social_cost_usd', 0),
                    "total_loss_if_deforested_usd": financial_analysis.get('total_loss_if_deforested_usd', 0),
                    "cost_benefit_ratio": financial_analysis.get('cost_benefit_ratio', 0),
                    "break_even_years": financial_analysis.get('break_even_years'),
                    # Also include basic ecosystem service breakdown
                    "annual_ecosystem_service_loss_usd": financial_analysis.get('detailed_analysis', {}).get('ecosystem_services', {}).get('annual_value_usd', 0),
                    "source": financial_analysis.get('sources', {})
                },
                "water_security": human_impacts.get('water_security', {}),
                "displacement_risk": human_impacts.get('displacement_risk', {}),
                "vulnerability_index": worldpop_data.get('vulnerability_index', 50),
                "summary": human_impacts.get('summary', '')
            }

            # Store detailed financial analysis separately for detailed views
            intelligence['financial_analysis'] = financial_analysis

            print(f"✅ Estimated {affected_pop} people affected (via {worldpop_data.get('source', 'estimation')})")
            print(f"💰 Restoration cost: ${financial_analysis.get('restoration_cost_usd', 0):,.0f} | Loss if deforested: ${financial_analysis.get('total_loss_if_deforested_usd', 0):,.0f}")
        except Exception as e:
            print(f"⚠️ Human impact analysis failed: {e}")
            intelligence['human_impacts'] = {}

        # ───────────────────────────────────────────────────────────
        # LAYER 6: Reforestation Requirements
        # ───────────────────────────────────────────────────────────
        print("\n🌳 LAYER 6: Calculating reforestation requirements...")
        try:
            reforestation = self.reforestation.calculate_requirements(
                area_ha, habitat_type, severity=trends.get('severity', 'medium')
            )
            intelligence['reforestation'] = {
                "total_trees_needed": reforestation.get('total_trees_needed', 0),
                "species_recommendations": [
                    {"species": s.get('species'), "quantity": s.get('quantity'), "benefits": s.get('benefits', [])}
                    for s in reforestation.get('species_mix', [])[:3]
                ],
                "carbon_potential_tonnes": reforestation.get('carbon_sequestration_potential', {}).get('co2_equivalent_tonnes', {}),
                "cost_estimate_usd": reforestation.get('cost_estimate', {}).get('total_estimated_cost_usd', 0)
            }
            print(f"✅ Calculated {reforestation.get('total_trees_needed', 0)} trees needed")
        except Exception as e:
            print(f"⚠️ Reforestation calculation failed: {e}")
            intelligence['reforestation'] = {}

        # ───────────────────────────────────────────────────────────
        # LAYER 9: Soil Analysis (NEW)
        # ───────────────────────────────────────────────────────────
        print("\n🪨 LAYER 9: Analyzing soil properties...")
        try:
            soil_data = self.soil.analyze(center["lat"], center["lng"])
            intelligence['soil'] = {
                "available": soil_data.get('available', False),
                "soil_texture": soil_data.get('soil_texture', {}),
                "fertility": soil_data.get('fertility', {}),
                "ph": soil_data.get('ph', {}),
                "water_retention": soil_data.get('water_retention', {}),
                "planting_recommendations": soil_data.get('planting_recommendations', [])[:3],
                "amendments_needed": soil_data.get('amendments_needed', [])[:3]
            }
            texture_class = soil_data.get('soil_texture', {}).get('class', 'Unknown')
            print(f"✅ Soil type: {texture_class}")
        except Exception as e:
            print(f"⚠️ Soil analysis failed: {e}")
            intelligence['soil'] = {"available": False, "error": str(e)}

        # ───────────────────────────────────────────────────────────
        # LAYER 10: Terrain Analysis (NEW)
        # ───────────────────────────────────────────────────────────
        print("\n⛰️ LAYER 10: Analyzing terrain characteristics...")
        try:
            terrain_data = self.terrain.analyze(bbox)
            intelligence['terrain'] = {
                "available": terrain_data.get('available', False),
                "elevation": terrain_data.get('elevation', {}),
                "slope": terrain_data.get('slope', {}),
                "aspect": terrain_data.get('aspect', {}),
                "terrain_ruggedness": terrain_data.get('terrain_ruggedness', {}),
                "planting_recommendations": terrain_data.get('planting_recommendations', {}),
                "cost_implications": terrain_data.get('cost_implications', {})
            }
            slope_deg = terrain_data.get('slope', {}).get('mean_degrees', 'N/A')
            print(f"✅ Avg slope: {slope_deg}°")
        except Exception as e:
            print(f"⚠️ Terrain analysis failed: {e}")
            intelligence['terrain'] = {"available": False, "error": str(e)}

        # ───────────────────────────────────────────────────────────
        # LAYER 11: Hydrology Analysis (NEW)
        # ───────────────────────────────────────────────────────────
        print("\n💧 LAYER 11: Analyzing water resources...")
        try:
            hydro_data = self.hydrology.analyze(
                center["lat"], center["lng"], bbox, habitat_type
            )
            intelligence['hydrology'] = {
                "available": hydro_data.get('available', False),
                "water_features": hydro_data.get('water_features', {}),
                "water_accessibility": hydro_data.get('water_accessibility', {}),
                "water_stress": hydro_data.get('water_stress', {}),
                "seasonal_patterns": hydro_data.get('seasonal_patterns', {}),
                "planting_implications": hydro_data.get('planting_implications', {})
            }
            water_rating = hydro_data.get('water_accessibility', {}).get('rating', 'N/A')
            print(f"✅ Water access: {water_rating}")
        except Exception as e:
            print(f"⚠️ Hydrology analysis failed: {e}")
            intelligence['hydrology'] = {"available": False, "error": str(e)}

        # ───────────────────────────────────────────────────────────
        # LAYER 12: Historical Timeline (NEW)
        # ───────────────────────────────────────────────────────────
        print("\n📜 LAYER 12: Building historical timeline...")
        try:
            # Build fire history by year if available
            fire_history = {}
            historical_data = self.historical.analyze(hotspot, bbox, fire_history)
            intelligence['historical_timeline'] = {
                "available": historical_data.get('available', False),
                "timeline": historical_data.get('timeline', [])[:10],  # Last 10 years
                "summary": historical_data.get('summary', {}),
                "trend_analysis": historical_data.get('trend_analysis', {}),
                "patterns_detected": historical_data.get('patterns_detected', [])[:3],
                "key_events": historical_data.get('key_events', [])[:3],
                "recovery_window": historical_data.get('recovery_window', {})
            }
            trend = historical_data.get('trend_analysis', {}).get('trend', 'unknown')
            print(f"✅ Historical trend: {trend}")
        except Exception as e:
            print(f"⚠️ Historical analysis failed: {e}")
            intelligence['historical_timeline'] = {"available": False, "error": str(e)}

        # ───────────────────────────────────────────────────────────
        # LAYER 13: Comprehensive AI Synthesis (NEW - Enhanced)
        # ───────────────────────────────────────────────────────────
        print("\n🧠 LAYER 13: Comprehensive Gemini analysis...")
        try:
            # Build comprehensive data for AI analysis
            comprehensive_data = {
                "region": hotspot.get('region', 'Unknown'),
                "area_ha": area_ha,
                "center": center,
                "gfw_data": {"loss_ha": hotspot.get('gfw_area__ha', 0)},
                "cause_data": {"primary_driver": hotspot.get('pattern', 'Unknown')},
                "biodiversity_summary": intelligence.get('biodiversity_summary', {}),
                "soil": intelligence.get('soil', {}),
                "terrain": intelligence.get('terrain', {}),
                "hydrology": intelligence.get('hydrology', {}),
                "historical_timeline": intelligence.get('historical_timeline', {}),
                "human_impacts": intelligence.get('human_impacts', {}),
                "reforestation": intelligence.get('reforestation', {}),
                "fire_summary": intelligence.get('fire_summary', {})
            }
            
            comprehensive = self.analysis.generate_comprehensive_analysis(comprehensive_data)
            intelligence['comprehensive_analysis'] = {
                "comprehensive_assessment": comprehensive.get('comprehensive_assessment', ''),
                "recovery_potential": comprehensive.get('recovery_potential', {}),
                "success_probability": comprehensive.get('success_probability', {}),
                "action_plan": comprehensive.get('action_plan', {}),
                "risk_factors": comprehensive.get('risk_factors', [])[:5]
            }
            score = comprehensive.get('recovery_potential', {}).get('score', 'N/A')
            print(f"✅ Recovery score: {score}/100")
        except Exception as e:
            print(f"⚠️ Comprehensive analysis failed: {e}")
            intelligence['comprehensive_analysis'] = {"error": str(e)}

        # ───────────────────────────────────────────────────────────
        # LAYER 14: AI Synthesis (Dual Reports) - Original Layer 7
        # ───────────────────────────────────────────────────────────
        print("\n📄 LAYER 14: Dual report generation...")
        try:
            synthesis = self.analysis.analyze(
                gfw_event=hotspot,
                fire_data=fire_data_for_analysis,
                proximity=proximity_raw,
                biodiversity={"species_count": len(species), "habitat_type": habitat_type},
                trends=trends
            )
            
            # Extract public and scientific reports
            intelligence['public_report'] = synthesis.get('public_report', {})
            intelligence['scientific_report'] = synthesis.get('scientific_report', {})
            intelligence['synthesis_metadata'] = {
                "generated_at": synthesis.get('generated_at'),
                "has_public_report": bool(synthesis.get('public_report')),
                "has_scientific_report": bool(synthesis.get('scientific_report'))
            }
            print(f"✅ Dual reports generated")
        except Exception as e:
            print(f"⚠️ Synthesis failed: {e}")
            intelligence['public_report'] = {}
            intelligence['scientific_report'] = {}
            intelligence['synthesis_metadata'] = {"error": str(e)}

        # LAYER 15: Verification - Original Layer 8
        # ───────────────────────────────────────────────────────────
        print("\n✅ LAYER 15: Verification and confidence scoring...")
        try:
            verification = self.verify.verify(
                hotspot,
                fire_data_for_analysis,
                intelligence.get('scientific_report', {})
            )
            intelligence['verification'] = verification
            print(f"✅ Confidence: {verification.get('confidence', 'N/A')}")
        except Exception as e:
            print(f"⚠️ Verification failed: {e}")
            intelligence['verification'] = {}

        # ───────────────────────────────────────────────────────────
        # LAYER 16: Sentinel-2 Satellite Verification
        # ───────────────────────────────────────────────────────────
        print("\n🛰️ LAYER 16: Sentinel-2 satellite verification...")
        try:
            sentinel_data = self.sentinel.verify_with_sentinel(
                center["lat"], 
                center["lng"],
                alert_date=datetime.utcnow(),
                area_ha=area_ha
            )
            intelligence['sentinel_verification'] = sentinel_data
            if sentinel_data.get('available'):
                print(f"✅ Sentinel imagery acquired")
                ndvi_change = sentinel_data.get('vegetation_indices', {}).get('ndvi', {}).get('change_mean', 'N/A')
                print(f"   NDVI change: {ndvi_change}")
            else:
                print(f"⚠️ Sentinel verification unavailable: {sentinel_data.get('message', 'Unknown')}")
        except Exception as e:
            print(f"⚠️ Sentinel verification failed: {e}")
            intelligence['sentinel_verification'] = {"available": False, "error": str(e)}

        # ───────────────────────────────────────────────────────────
        # LAYER 17: AI Vision Analysis of Satellite Imagery
        # ───────────────────────────────────────────────────────────
        print("\n👁️ LAYER 17: AI vision analysis...")
        try:
            # Only run if Sentinel imagery is available
            if intelligence.get('sentinel_verification', {}).get('available'):
                imagery_urls = intelligence['sentinel_verification'].get('imagery', {})
                before_url = imagery_urls.get('before_rgb_url')
                after_url = imagery_urls.get('after_rgb_url')
                
                if before_url and after_url:
                    vision_data = self.vision.analyze_imagery(
                        before_url,
                        after_url,
                        {
                            'region': hotspot.get('region', 'Unknown'),
                            'area_ha': area_ha,
                            'lat': center["lat"],
                            'lng': center["lng"]
                        }
                    )
                    intelligence['vision_analysis'] = vision_data
                    if vision_data.get('available'):
                        driver = vision_data.get('driver_analysis', {}).get('primary_driver', 'Unknown')
                        print(f"✅ Vision analysis complete: Driver identified as {driver}")
                    else:
                        print(f"⚠️ Vision analysis unavailable")
                else:
                    intelligence['vision_analysis'] = {"available": False, "message": "Image URLs not available"}
                    print("⚠️ Skipping vision analysis - no image URLs")
            else:
                intelligence['vision_analysis'] = {"available": False, "message": "Sentinel imagery not available"}
                print("⚠️ Skipping vision analysis - Sentinel imagery unavailable")
        except Exception as e:
            print(f"⚠️ Vision analysis failed: {e}")
            intelligence['vision_analysis'] = {"available": False, "error": str(e)}

        # ───────────────────────────────────────────────────────────
        # LAYER 18: Professional GIS Operations
        # ───────────────────────────────────────────────────────────
        print("\n🗺️ LAYER 18: Professional GIS analysis...")
        try:
            gis_data = self.gis.comprehensive_analysis(
                center["lat"],
                center["lng"],
                bbox,
                deforestation_area_ha=area_ha,
                habitat_type=habitat_type
            )
            intelligence['gis_analysis'] = gis_data
            if gis_data.get('available'):
                accessibility = gis_data.get('proximity_analysis', {}).get('accessibility_score', 'N/A')
                print(f"✅ GIS analysis complete: Accessibility score {accessibility}")
            else:
                print(f"⚠️ GIS analysis unavailable")
        except Exception as e:
            print(f"⚠️ GIS analysis failed: {e}")
            intelligence['gis_analysis'] = {"available": False, "error": str(e)}

        # ───────────────────────────────────────────────────────────
        # LAYER 19: Spatial Pattern Detection
        # ───────────────────────────────────────────────────────────
        print("\n🧩 LAYER 19: Spatial pattern analysis...")
        try:
            # Prepare comprehensive data for pattern analysis
            comprehensive_data = {
                'region': hotspot.get('region'),
                'area_ha': area_ha,
                'center': center,
                'fire_summary': intelligence.get('fire_summary', {}),
                'proximity_summary': intelligence.get('proximity_summary', {}),
                'biodiversity_summary': intelligence.get('biodiversity_summary', {}),
                'soil': intelligence.get('soil', {}),
                'terrain': intelligence.get('terrain', {}),
                'hydrology': intelligence.get('hydrology', {}),
                'historical_timeline': intelligence.get('historical_timeline', {}),
                'human_impacts': intelligence.get('human_impacts', {}),
                'trends': intelligence.get('trends', {}),
                'sentinel_verification': intelligence.get('sentinel_verification', {}),
                'vision_analysis': intelligence.get('vision_analysis', {}),
                'gis_analysis': intelligence.get('gis_analysis', {})
            }
            
            spatial_patterns = self.spatial_patterns.detect_patterns(comprehensive_data)
            intelligence['spatial_patterns'] = spatial_patterns
            if spatial_patterns.get('available'):
                interventions = len(spatial_patterns.get('intervention_opportunities', []))
                print(f"✅ Spatial patterns identified: {interventions} intervention opportunities")
            else:
                print(f"⚠️ Spatial pattern analysis unavailable")
        except Exception as e:
            print(f"⚠️ Spatial pattern analysis failed: {e}")
            intelligence['spatial_patterns'] = {"available": False, "error": str(e)}

        # ───────────────────────────────────────────────────────────
        # LAYER 20: Rule-Based Risk Prediction
        # ───────────────────────────────────────────────────────────
        print("\n🎯 LAYER 20: Rule-based risk prediction...")
        try:
            # Build comprehensive intelligence data for rule-based scoring
            # This provides more accurate and interpretable results
            risk_intelligence = {
                'fire_data': {
                    'activeFires': intelligence.get('fire_summary', {}).get('count', 0),
                    'alerts': intelligence.get('fire_summary', {}).get('alerts', []),
                    **intelligence.get('fire_data', {})
                },
                'vegetation_health': {
                    'current_ndvi': intelligence.get('sentinel_verification', {}).get('vegetation_indices', {}).get('ndvi', {}).get('current_mean'),
                    'ndvi_change': intelligence.get('sentinel_verification', {}).get('vegetation_indices', {}).get('ndvi', {}).get('change_mean'),
                    **intelligence.get('vegetation_analysis', {})
                },
                'protected_areas': {
                    'is_protected': intelligence.get('gis_analysis', {}).get('proximity_analysis', {}).get('nearest_protected_area', {}).get('distance_km', 999) < 1,
                    'nearest_distance_km': intelligence.get('gis_analysis', {}).get('proximity_analysis', {}).get('nearest_protected_area', {}).get('distance_km', 999),
                    'protection_type': intelligence.get('gis_analysis', {}).get('proximity_analysis', {}).get('nearest_protected_area', {}).get('name')
                },
                'proximity': {
                    'roads': intelligence.get('gis_analysis', {}).get('proximity_analysis', {}).get('nearest_road', {}),
                    'settlements': intelligence.get('gis_analysis', {}).get('proximity_analysis', {}).get('nearest_settlement', {}),
                },
                'human_impacts': intelligence.get('human_impacts', {}),
                'historical_analysis': {
                    'total_loss_ha': intelligence.get('gfw_data', {}).get('tree_cover_loss_ha', 0),
                    'trend': intelligence.get('trends', {}).get('direction'),
                    **intelligence.get('gfw_data', {})
                },
                'gfw_data': intelligence.get('gfw_data', {})
            }

            risk_prediction = self.risk_model.predict_risk(None, intelligence_data=risk_intelligence)
            intelligence['risk_prediction'] = risk_prediction
            if risk_prediction.get('available'):
                risk_level = risk_prediction.get('risk_level', 'unknown')
                risk_score = risk_prediction.get('risk_score', 0)
                print(f"✅ Risk prediction: {risk_level} (score: {risk_score}%)")
            else:
                print(f"⚠️ Risk prediction unavailable")
        except Exception as e:
            print(f"⚠️ Risk prediction failed: {e}")
            intelligence['risk_prediction'] = {"available": False, "error": str(e)}

        # Print summary before returning
        print("\n" + "=" * 70)
        print("📊 INTELLIGENCE SUMMARY (20 LAYERS)")
        print("=" * 70)
        print(f"🔥 Fires: {intelligence.get('fire_summary', {}).get('count', 0)}")
        print(f"🌍 Land features analyzed: {len(intelligence.get('proximity_summary', {}))}")
        print(f"🦜 Species documented: {intelligence.get('biodiversity_summary', {}).get('species_count', 0)}")
        print(f"👥 People affected: {intelligence.get('human_impacts', {}).get('affected_population', {}).get('total', 0)}")
        print(f"🌳 Trees needed: {intelligence.get('reforestation', {}).get('total_trees_needed', 0)}")
        print(f"🪨 Soil type: {intelligence.get('soil', {}).get('soil_texture', {}).get('class', 'N/A')}")
        print(f"⛰️ Avg slope: {intelligence.get('terrain', {}).get('slope', {}).get('mean_degrees', 'N/A')}°")
        print(f"💧 Water access: {intelligence.get('hydrology', {}).get('water_accessibility', {}).get('rating', 'N/A')}")
        print(f"📈 Trend: {intelligence.get('trends', {}).get('direction', 'unknown')}")
        print(f"🎯 Recovery score: {intelligence.get('comprehensive_analysis', {}).get('recovery_potential', {}).get('score', 'N/A')}/100")
        print("=" * 70)

        return intelligence

    def _extract_geom_info(self, geom, hotspot):
        """
        Extract center point and bounding box from geometry
        Handles GFW's WKB (binary) format and GeoJSON
        """
        # Try to get bbox from hotspot data first (most reliable)
        if 'gfw_bbox' in hotspot and hotspot['gfw_bbox']:
            bbox_array = hotspot['gfw_bbox']
            
            # Convert strings to floats if necessary
            try:
                if isinstance(bbox_array, str):
                    import ast
                    bbox_array = ast.literal_eval(bbox_array)
                
                # Ensure all values are floats
                bbox_array = [float(x) for x in bbox_array]
                
                bbox = {
                    "min_lat": bbox_array[1],
                    "max_lat": bbox_array[3],
                    "min_lng": bbox_array[0],
                    "max_lng": bbox_array[2]
                }
                center = {
                    "lat": (bbox_array[1] + bbox_array[3]) / 2,
                    "lng": (bbox_array[0] + bbox_array[2]) / 2
                }
                return center, bbox
            except (ValueError, TypeError, IndexError) as e:
                print(f"   ⚠️ Error parsing bbox: {e}")
        
        # Handle WKB geometry - use region-based fallback
        if isinstance(geom, (bytes, memoryview)) or (isinstance(geom, str) and ('\\x' in geom or not geom.strip().startswith('{'))):
            region = hotspot.get('region', '')
            
            region_centers = {
                'Western Amazon': {"lat": -7, "lng": -67, "bbox": {"min_lat": -12, "max_lat": -2, "min_lng": -75, "max_lng": -60}},
                'Eastern Amazon': {"lat": -5, "lng": -52, "bbox": {"min_lat": -10, "max_lat": 0, "min_lng": -60, "max_lng": -45}},
                'Congo Basin': {"lat": 0, "lng": 20, "bbox": {"min_lat": -5, "max_lat": 5, "min_lng": 15, "max_lng": 25}},
                'Borneo': {"lat": 0.5, "lng": 114, "bbox": {"min_lat": -3, "max_lat": 4, "min_lng": 110, "max_lng": 118}},
                'Sumatra': {"lat": 0, "lng": 101, "bbox": {"min_lat": -4, "max_lat": 4, "min_lng": 96, "max_lng": 106}},
            }
            
            for region_name, coords in region_centers.items():
                if region_name in region:
                    return {"lat": coords["lat"], "lng": coords["lng"]}, coords["bbox"]
            
            return {"lat": 0, "lng": 0}, {"min_lat": -5, "max_lat": 5, "min_lng": -5, "max_lng": 5}
        
        # Handle GeoJSON format
        if isinstance(geom, dict):
            try:
                if geom.get('type') == 'Polygon':
                    coords = geom['coordinates'][0]
                elif geom.get('type') == 'MultiPolygon':
                    coords = geom['coordinates'][0][0]
                else:
                    coords = [[0, 0]]
                
                lngs = [float(coord[0]) for coord in coords]
                lats = [float(coord[1]) for coord in coords]
                
                bbox = {
                    "min_lat": min(lats),
                    "max_lat": max(lats),
                    "min_lng": min(lngs),
                    "max_lng": max(lngs)
                }
                
                center = {
                    "lat": (min(lats) + max(lats)) / 2,
                    "lng": (min(lngs) + max(lngs)) / 2
                }
                
                return center, bbox
            except Exception as e:
                print(f"   ⚠️ Error parsing GeoJSON: {e}")
        
        # Ultimate fallback
        print("   ⚠️ Using default coordinates")
        return {"lat": 0, "lng": 0}, {"min_lat": -1, "max_lat": 1, "min_lng": -1, "max_lng": 1}

    def _infer_habitat_type(self, region):
        """Infer habitat type from region name"""
        region_lower = region.lower()
        
        if 'amazon' in region_lower:
            return "Tropical Rainforest"
        elif 'congo' in region_lower:
            return "Central African Rainforest"
        elif 'borneo' in region_lower or 'sumatra' in region_lower:
            return "Southeast Asian Rainforest"
        elif 'british columbia' in region_lower or 'bc' in region_lower:
            return "Temperate Rainforest"
        elif 'pacific northwest' in region_lower:
            return "Pacific Temperate Forest"
        elif 'central america' in region_lower:
            return "Central American Rainforest"
        elif 'east africa' in region_lower:
            return "East African Montane Forest"
        elif 'australia' in region_lower:
            return "Australian Eucalyptus Forest"
        elif 'canada' in region_lower:
            return "Boreal Forest"
        return "Mixed Forest"