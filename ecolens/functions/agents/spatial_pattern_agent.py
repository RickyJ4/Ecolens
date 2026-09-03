"""
Spatial Pattern Analysis Agent

Uses Gemini 2.0 Flash to identify non-obvious spatial relationships,
causal patterns, and systemic insights from comprehensive environmental data.
"""

import os
from google import genai
from google.genai import types
import json
import traceback


class SpatialPatternAgent:
    def __init__(self, api_key=None):
        """Initialize Gemini client for spatial pattern analysis"""
        try:
            self.client = genai.Client(api_key=api_key or os.environ["GEMINI_API_KEY"])
            self.model = "gemini-2.5-flash"
            self.available = True
            print("✅ Spatial Pattern Agent initialized")
        except Exception as e:
            print(f"⚠️ Spatial Pattern Agent initialization failed: {e}")
            self.available = False
    
    def detect_patterns(self, comprehensive_data):
        """
        Analyze comprehensive environmental data to identify non-obvious patterns
        
        Args:
            comprehensive_data: dict containing all layers of intelligence
                (GFW, fires, soil, terrain, hydrology, biodiversity, human impacts,
                 Sentinel verification, vision analysis, proximity, trends, etc.)
        
        Returns:
            dict: Spatial pattern insights and systemic analysis
        """
        if not self.available:
            return {
                "available": False,
                "error": "Spatial pattern analysis not available",
                "message": "Gemini model not initialized"
            }
        
        try:
            # Build comprehensive data summary for AI
            data_summary = self._prepare_data_summary(comprehensive_data)
            
            # Build analysis prompt
            prompt = self._build_pattern_prompt(data_summary)
            
            # Define structured schema
            schema = {
                "type": "object",
                "properties": {
                    "causal_relationships": {
                        "type": "object",
                        "properties": {
                            "primary_enabling_factors": {
                                "type": "array",
                                "items": {
                                    "type": "object",
                                    "properties": {
                                        "factor": {"type": "string"},
                                        "mechanism": {"type": "string"},
                                        "evidence": {"type": "string"}
                                    }
                                },
                                "description": "Key factors that enabled/facilitated deforestation"
                            },
                            "infrastructure_deforestation_link": {
                                "type": "string",
                                "description": "How infrastructure relates to deforestation pattern"
                            },
                            "fire_land_use_correlation": {
                                "type": "string",
                                "description": "Relationship between fire activity and land use change"
                            },
                            "terrain_driver_relationship": {
                                "type": "string",
                                "description": "How terrain influenced the deforestation method/pattern"
                            }
                        }
                    },
                    "non_obvious_patterns": {
                        "type": "object",
                        "properties": {
                            "spatial_clustering": {
                                "type": "string",
                                "description": "Non-obvious spatial clustering or arrangement patterns"
                            },
                            "temporal_correlations": {
                                "type": "array",
                                "items": {"type": "string"},
                                "description": "Temporal patterns across different data layers"
                            },
                            "cross_layer_insights": {
                                "type": "array",
                                "items": {
                                    "type": "object",
                                    "properties": {
                                        "insight": {"type": "string"},
                                        "layers_involved": {"type": "array", "items": {"type": "string"}},
                                        "significance": {"type": "string"}
                                    }
                                },
                                "description": "Insights from combining multiple data layers"
                            },
                            "anomalies_detected": {
                                "type": "array",
                                "items": {"type": "string"},
                                "description": "Unusual patterns that don't fit expected models"
                            }
                        }
                    },
                    "systemic_insights": {
                        "type": "object",
                        "properties": {
                            "broader_dynamics": {
                                "type": "string",
                                "description": "What broader social/economic/political dynamics are at play"
                            },
                            "enforcement_governance_gaps": {
                                "type": "array",
                                "items": {"type": "string"},
                                "description": "Inferred governance or enforcement weaknesses"
                            },
                            "market_influences": {
                                "type": "string",
                                "description": "Evidence of market-driven deforestation patterns"
                            },
                            "vulnerability_factors": {
                                "type": "array",
                                "items": {"type": "string"},
                                "description": "Factors making this area vulnerable to continued loss"
                            }
                        }
                    },
                    "predictive_indicators": {
                        "type": "object",
                        "properties": {
                            "high_risk_expansion_areas": {
                                "type": "array",
                                "items": {
                                    "type": "object",
                                    "properties": {
                                        "location_description": {"type": "string"},
                                        "risk_factors": {"type": "array", "items": {"type": "string"}},
                                        "timeframe": {"type": "string"}
                                    }
                                },
                                "description": "Areas likely to experience deforestation next"
                            },
                            "early_warning_signals": {
                                "type": "array",
                                "items": {"type": "string"},
                                "description": "Patterns that suggest imminent expansion"
                            },
                            "trajectory_prediction": {
                                "type": "string",
                                "description": "Predicted trajectory if current patterns continue"
                            }
                        }
                    },
                    "intervention_opportunities": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "properties": {
                                "leverage_point": {"type": "string"},
                                "rationale": {"type": "string"},
                                "expected_impact": {"type": "string"}
                            }
                        },
                        "description": "Strategic intervention points identified from pattern analysis"
                    },
                    "confidence_assessment": {
                        "type": "object",
                        "properties": {
                            "overall_confidence": {"type": "string"},
                            "data_quality_notes": {"type": "string"},
                            "uncertainties": {"type": "array", "items": {"type": "string"}}
                        }
                    }
                },
                "required": ["causal_relationships", "non_obvious_patterns", "systemic_insights", 
                            "predictive_indicators", "intervention_opportunities"]
            }
            
            # Call Gemini for analysis
            response = self.client.models.generate_content(
                model=self.model,
                contents=prompt,
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_schema=schema,
                    temperature=0.3  # Slightly higher for creative pattern detection
                )
            )
            
            analysis = response.parsed
            
            if not analysis:
                return {
                    "available": False,
                    "error": "No analysis generated",
                    "message": "Spatial pattern model did not return analysis"
                }
            
            return {
                "available": True,
                "causal_relationships": analysis.get("causal_relationships", {}),
                "non_obvious_patterns": analysis.get("non_obvious_patterns", {}),
                "systemic_insights": analysis.get("systemic_insights", {}),
                "predictive_indicators": analysis.get("predictive_indicators", {}),
                "intervention_opportunities": analysis.get("intervention_opportunities", []),
                "confidence_assessment": analysis.get("confidence_assessment", {}),
                "metadata": {
                    "model": self.model,
                    "analysis_type": "spatial_pattern_detection",
                    "data_layers_analyzed": len(comprehensive_data)
                }
            }
        
        except Exception as e:
            print(f"❌ Spatial pattern analysis failed: {e}")
            traceback.print_exc()
            return {
                "available": False,
                "error": str(e),
                "message": "Spatial pattern analysis encountered an error"
            }
    
    def _prepare_data_summary(self, data):
        """Prepare comprehensive data summary for AI analysis"""
        
        summary = {}
        
        # Extract key information from each layer
        if 'region' in data:
            summary['location'] = {
                'region': data.get('region'),
                'area_ha': data.get('area_ha'),
                'coordinates': data.get('center', {})
            }
        
        if 'fire_summary' in data:
            summary['fire_activity'] = data['fire_summary']
        
        if 'proximity_summary' in data:
            summary['proximity'] = data['proximity_summary']
        
        if 'biodiversity_summary' in data:
            summary['biodiversity'] = data['biodiversity_summary']
        
        if 'soil' in data:
            summary['soil_conditions'] = {
                'available': data['soil'].get('available'),
                'texture': data['soil'].get('soil_texture', {}).get('class'),
                'ph': data['soil'].get('ph', {}).get('value'),
                'fertility': data['soil'].get('fertility', {})
            }
        
        if 'terrain' in data:
            summary['terrain_characteristics'] = {
                'available': data['terrain'].get('available'),
                'slope': data['terrain'].get('slope', {}).get('mean_degrees'),
                'elevation': data['terrain'].get('elevation', {})
            }
        
        if 'hydrology' in data:
            summary['water_resources'] = {
                'available': data['hydrology'].get('available'),
                'accessibility': data['hydrology'].get('water_accessibility', {}).get('rating'),
                'water_stress': data['hydrology'].get('water_stress', {})
            }
        
        if 'historical_timeline' in data:
            summary['historical_patterns'] = {
                'trend': data['historical_timeline'].get('trend_analysis', {}).get('trend'),
                'patterns': data['historical_timeline'].get('patterns_detected', [])
            }
        
        if 'human_impacts' in data:
            summary['human_dimension'] = {
                'affected_population': data['human_impacts'].get('affected_population', {}).get('total'),
                'economic_impacts': data['human_impacts'].get('economic_impacts_usd', {})
            }
        
        if 'sentinel_verification' in data and data['sentinel_verification'].get('available'):
            summary['satellite_verification'] = {
                'ndvi_change': data['sentinel_verification'].get('vegetation_indices', {}).get('ndvi', {}).get('change_mean'),
                'forest_loss_verified': data['sentinel_verification'].get('forest_loss_verified', {})
            }
        
        if 'vision_analysis' in data and data['vision_analysis'].get('available'):
            summary['visual_patterns'] = {
                'driver': data['vision_analysis'].get('driver_analysis', {}).get('primary_driver'),
                'severity': data['vision_analysis'].get('severity_assessment', {}).get('severity_level'),
                'patterns': data['vision_analysis'].get('visual_patterns', {})
            }
        
        if 'trends' in data:
            summary['trend_analysis'] = data['trends']
        
        return summary
    
    def _build_pattern_prompt(self, data_summary):
        """Build comprehensive pattern analysis prompt"""
        
        # Convert data summary to formatted JSON for readability
        data_json = json.dumps(data_summary, indent=2)
        
        prompt = f"""
You are an expert spatial analyst and environmental intelligence officer reviewing comprehensive 
multi-layered data to identify NON-OBVIOUS patterns, causal relationships, and systemic insights.

COMPREHENSIVE DATA SUMMARY:
{data_json}

YOUR MISSION:
Analyze this multi-layered intelligence to discover insights that are NOT immediately obvious 
from looking at individual data layers. Think like a detective connecting dots.

ANALYZE FOR:

1. CAUSAL RELATIONSHIPS:
   - What factors ENABLED this deforestation? (Not just the driver, but what made it possible)
   - How does infrastructure relate to the deforestation pattern?
   - Are fires natural or human-induced for land clearing?
   - How did terrain characteristics influence the method and pattern?

2. NON-OBVIOUS PATTERNS:
   - Are there spatial clustering patterns that suggest coordinated activity?
   - What temporal correlations exist across different data layers?
   - What insights emerge when combining multiple layers (e.g., soil + proximity + fires)?
   - Are there anomalies that don't fit expected patterns?

3. SYSTEMIC INSIGHTS:
   - What broader social/economic/political dynamics are driving this?
   - What governance or enforcement gaps can you infer?
   - Is this market-driven? What evidence suggests this?
   - What makes this area particularly vulnerable to continued loss?

4. PREDICTIVE INDICATORS:
   - Based on patterns, where is expansion most likely next?
   - What are the early warning signals of imminent expansion?
   - What is the predicted trajectory if patterns continue?

5. INTERVENTION OPPORTUNITIES:
   - What strategic leverage points could disrupt the deforestation pattern?
   - Where would interventions have maximum impact?

BE SPECIFIC. USE EVIDENCE. THINK SYSTEMICALLY.
Go beyond surface-level observations to identify root causes and dynamics.
"""
        return prompt
