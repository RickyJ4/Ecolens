"""
Vision Analysis Agent

Uses Gemini 2.0 Flash Exp vision model to analyze satellite imagery
like a human expert, identifying patterns, drivers, and spatial context.
"""

import os
from google import genai
from google.genai import types
import traceback


class VisionAnalysisAgent:
    def __init__(self, api_key=None):
        """Initialize Gemini client for vision analysis"""
        try:
            self.client = genai.Client(api_key=api_key or os.environ["GEMINI_API_KEY"])
            self.model = "gemini-2.5-flash"
            self.available = True
            print("✅ Vision Analysis Agent initialized")
        except Exception as e:
            print(f"⚠️ Vision Analysis Agent initialization failed: {e}")
            self.available = False
    
    def analyze_imagery(self, before_url, after_url, location_context):
        """
        Analyze before/after satellite imagery using Gemini vision
        
        Args:
            before_url: URL to before image
            after_url: URL to after image
            location_context: dict with region, area_ha, coordinates, etc.
        
        Returns:
            dict: Comprehensive visual analysis report
        """
        if not self.available:
            return {
                "available": False,
                "error": "Vision analysis not available",
                "message": "Gemini vision model not initialized"
            }
        
        # Check if URLs are valid
        if not before_url or not after_url:
            return {
                "available": False,
                "error": "Missing image URLs",
                "message": "Both before and after images required for analysis"
            }
        
        try:
            # Build comprehensive prompt
            prompt = self._build_analysis_prompt(location_context)
            
            # Define structured schema for response
            schema = {
                "type": "object",
                "properties": {
                    "visual_patterns": {
                        "type": "object",
                        "properties": {
                            "clearing_pattern": {
                                "type": "string",
                                "description": "Pattern of forest clearing (e.g., linear, scattered, concentrated)"
                            },
                            "spatial_arrangement": {
                                "type": "string",
                                "description": "How the clearing is spatially organized"
                            },
                            "infrastructure_detected": {
                                "type": "array",
                                "items": {"type": "string"},
                                "description": "Visible infrastructure like roads, buildings, clearings"
                            },
                            "edge_characteristics": {
                                "type": "string",
                                "description": "Description of forest edge (sharp vs gradual transition)"
                            }
                        }
                    },
                    "driver_analysis": {
                        "type": "object",
                        "properties": {
                            "primary_driver": {
                                "type": "string",
                                "description": "Most likely cause (logging, agriculture, mining, fire, urban)"
                            },
                            "visual_evidence": {
                                "type": "array",
                                "items": {"type": "string"},
                                "description": "Specific visual clues supporting the driver identification"
                            },
                            "scale": {
                                "type": "string",
                                "description": "Scale of operation (small-scale/subsistence, medium/commercial, large/industrial)"
                            },
                            "confidence": {
                                "type": "string",
                                "description": "Confidence level in driver identification"
                            }
                        }
                    },
                    "severity_assessment": {
                        "type": "object",
                        "properties": {
                            "canopy_removal_percent": {
                                "type": "integer",
                                "description": "Estimated percentage of canopy removed (0-100)"
                            },
                            "vegetation_health_before": {
                                "type": "string",
                                "description": "Health of vegetation in before image"
                            },
                            "vegetation_health_after": {
                                "type": "string",
                                "description": "Health of vegetation in after image"
                            },
                            "secondary_impacts": {
                                "type": "array",
                                "items": {"type": "string"},
                                "description": "Secondary effects visible (soil exposure, erosion, water turbidity)"
                            },
                            "severity_level": {
                                "type": "string",
                                "description": "Overall severity (low, moderate, high, severe)"
                            }
                        }
                    },
                    "spatial_context": {
                        "type": "object",
                        "properties": {
                            "expansion_indicators": {
                                "type": "array",
                                "items": {"type": "string"},
                                "description": "Signs of likely expansion (new roads, staging areas)"
                            },
                            "adjacent_disturbances": {
                                "type": "string",
                                "description": "Evidence of disturbance in surrounding areas"
                            },
                            "isolation_connectivity": {
                                "type": "string",
                                "description": "Whether clearing is isolated or part of larger pattern"
                            },
                            "temporal_progression": {
                                "type": "string",
                                "description": "How the clearing appears to have progressed over time"
                            }
                        }
                    },
                    "expert_summary": {
                        "type": "string",
                        "description": "Concise expert summary of what happened and why"
                    }
                },
                "required": ["visual_patterns", "driver_analysis", "severity_assessment", "spatial_context", "expert_summary"]
            }
            
            # Call Gemini vision model with images
            response = self.client.models.generate_content(
                model=self.model,
                contents=[
                    types.Part.from_uri(
                        file_uri=before_url,
                        mime_type="image/png"
                    ),
                    types.Part.from_uri(
                        file_uri=after_url,
                        mime_type="image/png"
                    ),
                    prompt
                ],
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_schema=schema,
                    temperature=0.2  # Lower temperature for more consistent analysis
                )
            )
            
            analysis = response.parsed
            
            if not analysis:
                return {
                    "available": False,
                    "error": "No analysis generated",
                    "message": "Vision model did not return analysis"
                }
            
            return {
                "available": True,
                "visual_patterns": analysis.get("visual_patterns", {}),
                "driver_analysis": analysis.get("driver_analysis", {}),
                "severity_assessment": analysis.get("severity_assessment", {}),
                "spatial_context": analysis.get("spatial_context", {}),
                "expert_summary": analysis.get("expert_summary", ""),
                "metadata": {
                    "model": self.model,
                    "analysis_type": "satellite_imagery_visual_inspection",
                    "before_image": before_url,
                    "after_image": after_url
                }
            }
        
        except Exception as e:
            print(f"❌ Vision analysis failed: {e}")
            traceback.print_exc()
            return {
                "available": False,
                "error": str(e),
                "message": "Vision analysis encountered an error"
            }
    
    def _build_analysis_prompt(self, context):
        """Build detailed analysis prompt with context"""
        
        region = context.get('region', 'Unknown')
        area_ha = context.get('area_ha', 0)
        lat = context.get('lat', 0)
        lng = context.get('lng', 0)
        
        prompt = f"""
You are an expert environmental analyst reviewing satellite imagery for deforestation analysis.

LOCATION CONTEXT:
- Region: {region}
- Coordinates: {lat}, {lng}
- Estimated affected area: {area_ha} hectares
- Purpose: Environmental forensics and impact assessment

TASK:
Analyze the BEFORE and AFTER satellite images to identify:

1. VISUAL PATTERNS:
   - How is the forest clearing arranged? (linear cuts, scattered patches, concentrated zones)
   - What infrastructure is visible? (roads, buildings, staging areas)
   - How do the forest edges appear? (sharp delineation vs gradual transition)
   - What is the spatial arrangement of the disturbance?

2. DRIVER ANALYSIS:
   - What is the MOST LIKELY primary driver of deforestation?
     (Selective logging, clear-cut logging, agricultural expansion, cattle ranching, 
      mining operations, urban development, wildfire, infrastructure development)
   - What SPECIFIC VISUAL EVIDENCE supports your conclusion?
   - What is the scale of operation? (small-scale/subsistence, medium/commercial, large/industrial)
   - How confident are you in this assessment?

3. SEVERITY ASSESSMENT:
   - What percentage of forest canopy was removed? (estimate 0-100%)
   - Describe vegetation health BEFORE the event
   - Describe vegetation health AFTER the event
   - What secondary impacts are visible? (exposed soil, erosion, water turbidity, dust)
   - Overall severity level?

4. SPATIAL CONTEXT:
   - Are there signs this will expand? (new access roads, staging areas, adjacent clearing)
   - What evidence of disturbance exists in surrounding areas?
   - Is this an isolated event or part of a larger pattern?
   - How did the clearing appear to progress over time?

Provide a detailed, technical analysis as if briefing policymakers and conservation teams.
Be specific about what you observe in the imagery.
"""
        
        return prompt
