import os
from google import genai
from datetime import datetime


class AnalysisAgent:
    def __init__(self):
        self.client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])

    def analyze(self, gfw_event, fire_data, proximity, biodiversity, trends):
        """AI-powered analysis generating dual reports"""
        
        prompt = self._build_analysis_prompt(
            gfw_event, fire_data, proximity, biodiversity, trends
        )
        
        try:
            response = self.client.models.generate_content(
                model="gemini-2.5-flash",
                contents=prompt
            )
            
            analysis_text = response.text
            
            # Try to parse JSON response
            import json
            import re
            
            # Extract JSON from response (handle markdown code blocks)
            json_match = re.search(r'```json\s*(.*?)\s*```', analysis_text, re.DOTALL)
            if json_match:
                json_str = json_match.group(1)
            else:
                # Try to find JSON object directly
                json_match = re.search(r'\{.*\}', analysis_text, re.DOTALL)
                if json_match:
                    json_str = json_match.group(0)
                else:
                    json_str = analysis_text
            
            try:
                parsed_reports = json.loads(json_str)
                
                # Print analysis summary
                print("\n" + "─" * 70)
                print("📄 AI ANALYSIS COMPLETE:")
                print("─" * 70)
                if 'public_report' in parsed_reports:
                    print("✅ Public report generated")
                if 'scientific_report' in parsed_reports:
                    print("✅ Scientific report generated")
                print("─" * 70)
                
                return {
                    "public_report": parsed_reports.get('public_report', {}),
                    "scientific_report": parsed_reports.get('scientific_report', {}),
                    "raw_analysis": analysis_text,
                    "generated_at": datetime.utcnow().isoformat()
                }
            except json.JSONDecodeError as e:
                print(f"⚠️ JSON parsing failed: {e}")
                print("Using raw text response")
                
                # Fallback: return raw text
                return {
                    "public_report": {"summary": analysis_text[:500]},
                    "scientific_report": {"analysis": analysis_text},
                    "raw_analysis": analysis_text,
                    "generated_at": datetime.utcnow().isoformat(),
                    "parse_error": str(e)
                }
            
        except Exception as e:
            print(f"AI generation error: {e}")
            return {
                "public_report": {},
                "scientific_report": {},
                "error": str(e),
                "generated_at": datetime.utcnow().isoformat()
            }

    def _build_analysis_prompt(self, gfw_event, fire_data, proximity, biodiversity, trends):
        """Build comprehensive analysis prompt for dual reporting"""
        
        fire_summary = f"{len(fire_data)} active fires" if fire_data else "No fires"
        
        # Process proximity data
        proximity_text = []
        infrastructure_details = []
        if isinstance(proximity, dict):
            for category, items in proximity.items():
                if items:
                    nearest = min([item.get('distance_km', 999) for item in items])
                    proximity_text.append(f"{category}: nearest {nearest}km away")
                    
                    # Detailed infrastructure info
                    if category == 'infrastructure':
                        for item in items[:3]:  # Top 3
                            infrastructure_details.append(
                                f"{item.get('type', 'Unknown')} at {item.get('distance_km', 0):.1f}km - {item.get('impact', 'Unknown impact')}"
                            )
        
        # Species information with risk levels
        species_count = biodiversity.get('species_count', 0) if isinstance(biodiversity, dict) else 0
        habitat = biodiversity.get('habitat_type', 'Unknown') if isinstance(biodiversity, dict) else 'Unknown'
        
        # Trend information
        trend_direction = trends.get('trend_direction', 'unknown')
        severity = trends.get('severity', 'unknown')
        
        prompt = f"""You are an environmental intelligence analyst creating a comprehensive deforestation impact report.

DEFORESTATION EVENT DATA:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Region: {gfw_event.get('region')}
Area Affected: {gfw_event.get('gfw_area__ha', 0):.0f} hectares
Pattern: {gfw_event.get('pattern')}
Fire Activity: {fire_summary}

NEARBY FEATURES: {', '.join(proximity_text) if proximity_text else 'Limited data'}

INFRASTRUCTURE AT RISK:
{chr(10).join(infrastructure_details) if infrastructure_details else 'No infrastructure data available'}

BIODIVERSITY CONTEXT:
- Habitat Type: {habitat}
- Species Documented: {species_count}
- Ecosystem: Tropical forest ecosystem with high biodiversity value

HISTORICAL TREND: {trend_direction} trend, {severity} severity

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ANALYSIS REQUIREMENTS:

Generate TWO versions of this report - PUBLIC and SCIENTIFIC:

═══════════════════════════════════════════════════════════════════════════════
PUBLIC REPORT (Simplified, visual-friendly for general audience)
═══════════════════════════════════════════════════════════════════════════════

1. WHAT'S HAPPENING (2-3 sentences, simple language)
   - Describe the deforestation in plain terms
   - Mention the area size in relatable terms (e.g., "X football fields")

2. WHY IT'S HAPPENING (Primary drivers - categorize clearly)
   NATURAL CAUSES (if applicable):
   - Natural disasters (floods, landslides, wildfires)
   - Climate events
   
   HUMAN ACTIVITIES (identify specific activities):
   - Agriculture/farming expansion
   - Logging (legal or illegal)
   - Mining operations
   - Urban development
   - Infrastructure construction (roads, dams)
   
   Identify the PRIMARY DRIVER (most significant cause)

3. WHO'S AFFECTED
   - Local communities (how many people approximately)
   - Farmers and agricultural workers
   - Indigenous populations
   - Wildlife and endangered species

4. WHAT'S AT RISK
   - Infrastructure: roads, buildings, facilities (with distances)
   - Water sources and quality
   - Air quality
   - Protected areas

5. FUTURE OUTLOOK (if no action is taken)
   - 1-year prediction
   - 5-year prediction
   - Long-term consequences

6. WHAT CAN BE DONE
   - Immediate actions needed
   - Tree planting recommendations
   - Community involvement opportunities

═══════════════════════════════════════════════════════════════════════════════
SCIENTIFIC REPORT (Comprehensive technical analysis)
═══════════════════════════════════════════════════════════════════════════════

1. DEFORESTATION DRIVERS (Detailed analysis)
   A. Natural Factors:
      - Climate anomalies
      - Natural disaster correlation
      - Fire activity analysis
   
   B. Anthropogenic Factors:
      - Agricultural expansion patterns
      - Logging intensity and methods
      - Mining and extraction activities
      - Infrastructure development
      - Urban encroachment
   
   C. Primary Driver Identification:
      - Evidence-based determination
      - Confidence level (high/medium/low)
      - Contributing factors

2. INFRASTRUCTURE IMPACT ASSESSMENT
   For each infrastructure type within 20km:
   - Type and distance
   - Risk level (critical/high/medium/low)
   - Specific impacts (erosion, flooding, access disruption)
   - Estimated damage/disruption costs
   - Affected population dependent on infrastructure

3. HUMAN IMPACT ANALYSIS
   A. Affected Populations:
      - Direct impact (within 5km): estimated number
      - Indirect impact (5-20km): estimated number
      
   B. Stakeholder Breakdown:
      - Farmers: impacts on agriculture, land loss, water access
      - Workers: job losses, economic displacement
      - Indigenous communities: cultural impacts, land rights
      - Government: revenue loss, management costs
      - Downstream communities: water security, flood risk
   
   C. Economic Impacts:
      - Lost ecosystem services (USD/year)
      - Agricultural productivity loss
      - Infrastructure damage costs
      - Tourism revenue impact
      - 10-year cumulative impact

4. SPECIES RISK ASSESSMENT
   - Number of species documented in area
   - Species with IUCN risk levels (if known)
   - Habitat loss severity
   - Population decline projections
   - Ecosystem cascade effects

5. ENVIRONMENTAL PREDICTIONS
   A. 1-Year Projection:
      - Additional deforestation area (hectares)
      - Species population changes
      - Infrastructure degradation
      - Water quality impacts
   
   B. 5-Year Projection:
      - Cumulative forest loss
      - Biodiversity decline
      - Community displacement numbers
      - Economic losses
   
   C. 10-Year Projection:
      - Ecosystem collapse risk
      - Irreversible damage threshold
      - Regional climate impacts
      - Total economic cost

6. RESTORATION RECOMMENDATIONS
   - Tree planting requirements (number of trees)
   - Native species recommendations (list 3-5 species)
   - Restoration timeline
   - Success probability
   - Cost estimates

7. SEVERITY RATING
   Rate as: CRITICAL / HIGH / MEDIUM / LOW
   Justification: (2-3 sentences with specific metrics)

8. CONFIDENCE ASSESSMENT
   - Data quality: (high/medium/low)
   - Analysis confidence: (high/medium/low)
   - Limitations and uncertainties

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

FORMAT YOUR RESPONSE AS JSON:
{{
  "public_report": {{
    "whats_happening": "...",
    "why_its_happening": {{
      "natural_causes": ["..."],
      "human_activities": ["..."],
      "primary_driver": "..."
    }},
    "whos_affected": {{
      "communities": "...",
      "farmers": "...",
      "indigenous": "...",
      "wildlife": "..."
    }},
    "whats_at_risk": {{
      "infrastructure": ["..."],
      "water": "...",
      "air": "...",
      "protected_areas": "..."
    }},
    "future_outlook": {{
      "one_year": "...",
      "five_years": "...",
      "long_term": "..."
    }},
    "actions": ["...", "...", "..."]
  }},
  "scientific_report": {{
    "drivers": {{
      "natural": ["..."],
      "anthropogenic": ["..."],
      "primary_driver": "...",
      "confidence": "high/medium/low"
    }},
    "infrastructure_impacts": [
      {{"type": "...", "distance_km": 0, "risk": "...", "impact": "..."}}
    ],
    "human_impacts": {{
      "affected_population": {{"direct": 0, "indirect": 0}},
      "stakeholders": {{
        "farmers": "...",
        "workers": "...",
        "indigenous": "...",
        "government": "...",
        "downstream": "..."
      }},
      "economic_usd": {{"annual": 0, "ten_year": 0}}
    }},
    "species_risk": {{
      "species_count": 0,
      "at_risk_species": ["..."],
      "habitat_loss_severity": "...",
      "population_projections": "..."
    }},
    "predictions": {{
      "one_year": {{"area_ha": 0, "species_impact": "...", "infrastructure": "...", "water": "..."}},
      "five_years": {{"area_ha": 0, "biodiversity": "...", "displacement": 0, "economic": 0}},
      "ten_years": {{"ecosystem_collapse_risk": "...", "irreversible_damage": "...", "climate_impact": "...", "total_cost": 0}}
    }},
    "restoration": {{
      "trees_needed": 0,
      "species_recommendations": ["...", "...", "..."],
      "timeline": "...",
      "success_probability": "...",
      "cost_estimate_usd": 0
    }},
    "severity": "CRITICAL/HIGH/MEDIUM/LOW",
    "severity_justification": "...",
    "confidence": {{
      "data_quality": "high/medium/low",
      "analysis_confidence": "high/medium/low",
      "limitations": "..."
    }}
  }}
}}

Be specific, use actual numbers where possible, and provide actionable insights."""

        return prompt

    def generate_comprehensive_analysis(self, all_intelligence_data: dict) -> dict:
        """
        Layer 13: Comprehensive Gemini Analysis
        
        Synthesizes ALL collected data into:
        - Narrative site assessment
        - Recovery potential score (0-100)
        - Success probability
        - Action plan
        - Risk factors
        """
        import json
        
        try:
            prompt = self._build_comprehensive_prompt(all_intelligence_data)
            
            response = self.client.models.generate_content(
                model="gemini-2.5-flash",
                contents=prompt
            )
            
            analysis_text = response.text
            
            # Parse JSON response
            import re
            json_match = re.search(r'```json\s*(.*?)\s*```', analysis_text, re.DOTALL)
            if json_match:
                json_str = json_match.group(1)
            else:
                json_match = re.search(r'\{.*\}', analysis_text, re.DOTALL)
                json_str = json_match.group(0) if json_match else "{}"
            
            try:
                parsed = json.loads(json_str)
                
                print("\n" + "─" * 70)
                print("🧠 COMPREHENSIVE ANALYSIS COMPLETE:")
                print("─" * 70)
                print(f"   Recovery Potential: {parsed.get('recovery_potential', {}).get('score', 'N/A')}/100")
                print(f"   Success Probability: {parsed.get('success_probability', {}).get('percent', 'N/A')}%")
                print("─" * 70)
                
                return {
                    "comprehensive_assessment": parsed.get('comprehensive_assessment', ''),
                    "recovery_potential": parsed.get('recovery_potential', {}),
                    "success_probability": parsed.get('success_probability', {}),
                    "action_plan": parsed.get('action_plan', {}),
                    "risk_factors": parsed.get('risk_factors', []),
                    "generated_at": datetime.utcnow().isoformat()
                }
                
            except json.JSONDecodeError as e:
                print(f"⚠️ Comprehensive analysis JSON parsing failed: {e}")
                return self._fallback_comprehensive_analysis(all_intelligence_data)
                
        except Exception as e:
            print(f"❌ Comprehensive analysis error: {e}")
            return self._fallback_comprehensive_analysis(all_intelligence_data)

    def _build_comprehensive_prompt(self, data: dict) -> str:
        """
        Build comprehensive analysis prompt for Layer 13
        """
        # Extract key data points safely
        region = data.get('region', 'Unknown Region')
        area_ha = data.get('area_ha', 0)
        center = data.get('center', {})
        
        # Deforestation data
        loss_ha = data.get('gfw_data', {}).get('loss_ha', 0)
        driver = data.get('cause_data', {}).get('primary_driver', 'Unknown')
        
        # Biodiversity
        bio = data.get('biodiversity_summary', {})
        species_count = bio.get('species_count', 0)
        at_risk = bio.get('at_risk_species', [])
        habitat_type = bio.get('habitat_type', 'Unknown')
        
        # Physical site (new Layer 9-11 data)
        soil = data.get('soil', {})
        terrain = data.get('terrain', {})
        hydrology = data.get('hydrology', {})
        
        # Historical
        historical = data.get('historical_timeline', {})
        trend = historical.get('trend_analysis', {}).get('trend', 'unknown')
        
        # Human impact
        human = data.get('human_impacts', {})
        people_affected = human.get('affected_population', {}).get('total', 0)
        
        # Reforestation
        reforest = data.get('reforestation', {})
        trees_needed = reforest.get('total_trees_needed', 0)
        species_recs = reforest.get('species_recommendations', [])
        cost_estimate = reforest.get('cost_estimate_usd', 0)
        
        # Fire data
        fire = data.get('fire_summary', {})
        fire_count = fire.get('count', 0)
        
        prompt = f"""You are an expert environmental scientist and restoration ecologist conducting a comprehensive site assessment for NGO-grade environmental intelligence.

═══════════════════════════════════════════════════════════════════════════════
LOCATION & CONTEXT
═══════════════════════════════════════════════════════════════════════════════
Region: {region}
Coordinates: {center.get('lat', 0):.4f}, {center.get('lng', 0):.4f}
Area Affected: {area_ha} hectares
Habitat Type: {habitat_type}

═══════════════════════════════════════════════════════════════════════════════
DEFORESTATION STATUS
═══════════════════════════════════════════════════════════════════════════════
- Tree cover loss: {loss_ha} hectares
- Primary driver: {driver}
- Historical trend: {trend}
- Fire activity: {fire_count} recent detections

═══════════════════════════════════════════════════════════════════════════════
PHYSICAL SITE CHARACTERISTICS
═══════════════════════════════════════════════════════════════════════════════
SOIL:
- Texture: {soil.get('soil_texture', {}).get('class', 'Unknown')}
- pH: {soil.get('ph', {}).get('value', 'Unknown')}
- Fertility: {soil.get('fertility', {}).get('level', 'unknown')}
- Water retention: {soil.get('water_retention', {}).get('level', 'unknown')}

TERRAIN:
- Elevation: {terrain.get('elevation', {}).get('mean_m', 'Unknown')}m average
- Slope: {terrain.get('slope', {}).get('mean_degrees', 'Unknown')}° average
- Difficulty: {terrain.get('slope', {}).get('suitability', {}).get('difficulty', 'unknown')}
- Erosion risk: {terrain.get('slope', {}).get('suitability', {}).get('erosion_risk', 'unknown')}

WATER:
- Distance to water: {hydrology.get('water_features', {}).get('nearest_water', {}).get('distance_km', 'Unknown')} km
- Water access: {hydrology.get('water_accessibility', {}).get('rating', 'unknown')}
- Water stress: {hydrology.get('water_stress', {}).get('baseline_stress', 'unknown')}

═══════════════════════════════════════════════════════════════════════════════
BIODIVERSITY & HUMAN IMPACT
═══════════════════════════════════════════════════════════════════════════════
- Species documented: {species_count}
- Species at risk: {len(at_risk)}
- People affected: {people_affected}

═══════════════════════════════════════════════════════════════════════════════
RESTORATION PROPOSAL
═══════════════════════════════════════════════════════════════════════════════
- Trees needed: {trees_needed}
- Species: {', '.join([s.get('species', '') for s in species_recs[:5]])}
- Estimated cost: ${cost_estimate:,}

═══════════════════════════════════════════════════════════════════════════════
YOUR ANALYSIS TASK
═══════════════════════════════════════════════════════════════════════════════

Provide a comprehensive assessment in JSON format:

1. COMPREHENSIVE ASSESSMENT (250-350 words): Narrative synthesis of the site

2. RECOVERY POTENTIAL SCORE (0-100):
   - Soil Quality (20 pts max): excellent=15-20, adequate=10-15, poor=0-10
   - Terrain Suitability (20 pts max): gentle=15-20, moderate=10-15, steep=0-10
   - Water Availability (15 pts max): excellent=12-15, moderate=6-12, poor=0-6
   - Degradation Severity (15 pts max): light(<30%)=12-15, moderate=6-12, severe=0-6
   - Threat Level (15 pts max): low=12-15, moderate=6-12, high=0-6
   - Biodiversity Value (15 pts max): high=12-15, moderate=6-12, low=0-6

3. SUCCESS PROBABILITY (%): Estimate restoration success with proper techniques

4. ACTION PLAN: Phase 1 (prep), Phase 2 (planting), Phase 3 (monitoring)

5. RISK FACTORS: Top 3 risks with mitigations

RETURN ONLY THIS JSON (no other text):
{{
  "comprehensive_assessment": "Detailed narrative assessment...",
  "recovery_potential": {{
    "score": 72,
    "rating": "Good",
    "breakdown": {{
      "soil_quality": 15,
      "terrain_suitability": 14,
      "water_availability": 11,
      "degradation_severity": 12,
      "threat_level": 10,
      "biodiversity_value": 10
    }},
    "justification": "Brief explanation citing specific factors..."
  }},
  "success_probability": {{
    "percent": 75,
    "explanation": "Brief explanation...",
    "favorable_factors": ["factor1", "factor2"],
    "challenges": ["challenge1", "challenge2"]
  }},
  "action_plan": {{
    "phase_1_site_prep": ["action1", "action2"],
    "phase_2_planting": ["action1", "action2"],
    "phase_3_monitoring": ["action1", "action2"]
  }},
  "risk_factors": [
    {{"risk": "description", "severity": "high/medium/low", "mitigation": "strategy"}},
    {{"risk": "description", "severity": "high/medium/low", "mitigation": "strategy"}},
    {{"risk": "description", "severity": "high/medium/low", "mitigation": "strategy"}}
  ]
}}

Be analytical. Use the data provided. Your assessment guides real restoration investments."""

        return prompt

    def _fallback_comprehensive_analysis(self, data: dict) -> dict:
        """
        Fallback when Gemini analysis fails
        """
        # Calculate basic recovery score from available data
        score = 50  # Baseline
        
        soil = data.get('soil', {})
        terrain = data.get('terrain', {})
        hydrology = data.get('hydrology', {})
        
        # Adjust based on soil
        if soil.get('fertility', {}).get('level') == 'high':
            score += 10
        elif soil.get('fertility', {}).get('level') == 'low':
            score -= 10
        
        # Adjust based on terrain
        slope = terrain.get('slope', {}).get('mean_degrees', 15)
        if slope < 10:
            score += 10
        elif slope > 25:
            score -= 15
        
        # Adjust based on water
        water_rating = hydrology.get('water_accessibility', {}).get('rating', 'moderate')
        if water_rating == 'excellent':
            score += 10
        elif water_rating == 'poor':
            score -= 10
        
        # Clamp score
        score = max(0, min(100, score))
        
        # Determine rating
        if score >= 80:
            rating = "Excellent"
        elif score >= 65:
            rating = "Good"
        elif score >= 50:
            rating = "Fair"
        else:
            rating = "Poor"
        
        return {
            "comprehensive_assessment": "Automated assessment based on available data. Gemini analysis unavailable.",
            "recovery_potential": {
                "score": score,
                "rating": rating,
                "breakdown": {
                    "note": "Simplified calculation - detailed breakdown unavailable"
                },
                "justification": f"Score of {score}/100 based on soil, terrain, and water accessibility data."
            },
            "success_probability": {
                "percent": int(score * 0.8),  # Conservative estimate
                "explanation": "Estimated from recovery potential score",
                "favorable_factors": ["Data collection complete"],
                "challenges": ["Detailed AI analysis unavailable"]
            },
            "action_plan": {
                "phase_1_site_prep": ["Conduct ground survey", "Prepare soil amendments"],
                "phase_2_planting": ["Plant during optimal season", "Use recommended species"],
                "phase_3_monitoring": ["Quarterly satellite monitoring", "Annual ground verification"]
            },
            "risk_factors": [
                {"risk": "Unknown factors", "severity": "medium", "mitigation": "Conduct detailed site survey"}
            ],
            "generated_at": datetime.utcnow().isoformat(),
            "fallback": True
        }