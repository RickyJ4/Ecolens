"""
Human Impact Assessment Service

Analyzes the human impacts of deforestation including:
- Affected populations
- Economic impacts
- Stakeholder categorization
- Water security
- Displacement risks
"""


class HumanImpactService:
    def __init__(self):
        # Population density estimates per km² for different regions
        self.region_population_density = {
            "Amazon": 5,  # People per km²
            "Congo": 15,
            "Borneo": 25,
            "Sumatra": 120,
            "Southeast Asia": 100
        }
    
    def assess_impacts(self, hotspot, proximity_data, area_ha):
        """
        Assess human impacts from deforestation
        
        Args:
            hotspot: Hotspot data with region information
            proximity_data: Proximity to settlements and infrastructure
            area_ha: Area affected in hectares
        
        Returns:
            Dict with human impact assessment
        """
        region = hotspot.get('region', '')
        
        # Calculate affected population
        affected_population = self._estimate_affected_population(
            region, proximity_data, area_ha
        )
        
        # Categorize impacts by stakeholder
        stakeholder_impacts = self._categorize_stakeholder_impacts(
            proximity_data, area_ha, affected_population
        )
        
        # Calculate economic impacts
        economic_impacts = self._calculate_economic_impacts(
            region, area_ha, proximity_data
        )
        
        # Assess water security
        water_security = self._assess_water_security(proximity_data)
        
        # Evaluate displacement risks
        displacement_risk = self._evaluate_displacement_risk(
            proximity_data, affected_population
        )
        
        return {
            "affected_population_estimate": affected_population,
            "stakeholder_impacts": stakeholder_impacts,
            "economic_impacts": economic_impacts,
            "water_security": water_security,
            "displacement_risk": displacement_risk,
            "summary": self._generate_summary(
                affected_population, stakeholder_impacts, economic_impacts
            )
        }
    
    def _estimate_affected_population(self, region, proximity_data, area_ha):
        """Estimate population affected by deforestation"""
        # Get settlements within impact zone
        settlements = proximity_data.get('settlements', [])
        
        if not settlements:
            return {
                "direct": 0,
                "indirect": 0,
                "total": 0,
                "confidence": "low"
            }
        
        # Calculate based on proximity
        direct_impact = 0  # Within 5km
        indirect_impact = 0  # 5-20km
        
        # Get population density for region
        density = self.region_population_density.get(
            next((k for k in self.region_population_density.keys() if k in region), "Amazon"),
            10
        )
        
        for settlement in settlements:
            distance = settlement.get('distance_km', 999)
            
            if distance < 5:
                # Direct impact: assume settlement population affected
                # Estimate: 500-5000 people per settlement based on distance
                pop = max(500, int(5000 * (1 - distance/5)))
                direct_impact += pop
            elif distance < 20:
                # Indirect impact: ecosystem services, water, air quality
                pop = max(200, int(2000 * (1 - distance/20)))
                indirect_impact += pop
        
        # Also consider area-based population estimate
        area_km2 = area_ha / 100
        area_population = int(area_km2 * density)
        
        total = max(direct_impact + indirect_impact, area_population)
        
        return {
            "direct": direct_impact,
            "indirect": indirect_impact,
            "total": total,
            "confidence": "medium" if settlements else "low",
            "methodology": "Based on settlement proximity and regional population density"
        }
    
    def _categorize_stakeholder_impacts(self, proximity_data, area_ha, population_data):
        """Categorize impacts by stakeholder type"""
        impacts = {
            "farmers": {
                "affected": True,
                "severity": "high",
                "description": "Loss of agricultural land and soil degradation",
                "estimated_affected": int(population_data['total'] * 0.4),  # 40% farmers
                "impacts": [
                    "Reduced crop yields from soil erosion",
                    "Loss of arable land",
                    "Decreased water availability for irrigation",
                    "Increased pest pressure"
                ]
            },
            "indigenous_communities": {
                "affected": True,
                "severity": "critical",
                "description": "Habitat loss and cultural displacement",
                "estimated_affected": int(population_data['total'] * 0.15),  # 15% indigenous
                "impacts": [
                    "Loss of traditional lands and resources",
                    "Disruption of cultural practices",
                    "Reduced access to medicinal plants",
                    "Forced migration"
                ]
            },
            "workers": {
                "affected": True,
                "severity": "medium",
                "description": "Job losses in forestry and related sectors",
                "estimated_affected": int(population_data['total'] * 0.25),  # 25% workers
                "impacts": [
                    "Loss of sustainable forestry jobs",
                    "Reduced tourism employment",
                    "Decreased fishing opportunities",
                    "Economic instability"
                ]
            },
            "government": {
                "affected": True,
                "severity": "high",
                "description": "Revenue loss and increased management costs",
                "impacts": [
                    "Reduced tax revenue from sustainable industries",
                    "Increased disaster management costs",
                    "Loss of carbon credit potential",
                    "International pressure and sanctions risk"
                ]
            },
            "downstream_communities": {
                "affected": True,
                "severity": "medium-high",
                "description": "Water quality and availability impacts",
                "estimated_affected": int(population_data['total'] * 1.5),  # Multiplier for downstream
                "impacts": [
                    "Reduced water quality from sedimentation",
                    "Increased flood risk",
                    "Decreased dry season water flow",
                    "Impact on fisheries"
                ]
            }
        }
        
        return impacts
    
    def _calculate_economic_impacts(self, region, area_ha, proximity_data):
        """Calculate economic impacts"""
        # Economic value estimates (USD per hectare per year)
        ecosystem_service_value = 2000  # Conservative estimate
        timber_value = 500  # Lost sustainable timber revenue
        carbon_value = 100  # Carbon sequestration value
        tourism_value = 50  # Ecotourism potential
        
        annual_loss = area_ha * (
            ecosystem_service_value + 
            timber_value + 
            carbon_value + 
            tourism_value
        )
        
        # Calculate infrastructure damage risk
        infrastructure = proximity_data.get('infrastructure', [])
        infrastructure_risk = 0
        
        for infra in infrastructure:
            if infra.get('distance_km', 999) < 10:
                # Roads, facilities at risk
                infrastructure_risk += 50000  # Estimated repair/replacement cost
        
        return {
            "annual_ecosystem_service_loss_usd": int(area_ha * ecosystem_service_value),
            "lost_sustainable_timber_revenue_usd": int(area_ha * timber_value),
            "lost_carbon_sequestration_value_usd": int(area_ha * carbon_value),
            "lost_tourism_potential_usd": int(area_ha * tourism_value),
            "total_annual_loss_usd": int(annual_loss),
            "infrastructure_damage_risk_usd": infrastructure_risk,
            "ten_year_projection_usd": int(annual_loss * 10),
            "note": "Conservative estimates based on global ecosystem service valuations"
        }
    
    def _assess_water_security(self, proximity_data):
        """Assess water security impacts"""
        rivers = proximity_data.get('rivers', [])
        
        if not rivers:
            return {
                "risk_level": "unknown",
                "impacts": ["Insufficient data on nearby water sources"]
            }
        
        nearest_river = min(rivers, key=lambda x: x.get('distance_km', 999)) if rivers else None
        
        if not nearest_river:
            return {"risk_level": "unknown", "impacts": []}
        
        distance = nearest_river.get('distance_km', 999)
        
        if distance < 5:
            risk = "critical"
            impacts = [
                "Direct sedimentation of water sources",
                "Severe water quality degradation",
                "Increased flood risk during rainy season",
                "Reduced dry season water flow",
                "Impact on aquatic ecosystems"
            ]
        elif distance < 15:
            risk = "high"
            impacts = [
                "Watershed degradation",
                "Increased erosion and sedimentation",
                "Altered water flow patterns",
                "Reduced water filtration capacity"
            ]
        else:
            risk = "medium"
            impacts = [
                "Regional watershed effects",
                "Long-term water cycle disruption"
            ]
        
        return {
            "risk_level": risk,
            "nearest_water_source_km": distance,
            "water_source_name": nearest_river.get('type', 'Unknown'),
            "impacts": impacts
        }
    
    def _evaluate_displacement_risk(self, proximity_data, population_data):
        """Evaluate displacement risk"""
        settlements = proximity_data.get('settlements', [])
        
        if not settlements:
            return {
                "risk_level": "low",
                "estimated_displaced": 0,
                "factors": []
            }
        
        # Check for high-risk settlements (very close)
        high_risk_settlements = [s for s in settlements if s.get('distance_km', 999) < 3]
        
        if high_risk_settlements:
            risk = "high"
            displaced = int(population_data['direct'] * 0.3)  # 30% may be displaced
            factors = [
                "Settlements within critical impact zone",
                "Loss of agricultural land",
                "Water source contamination",
                "Increased natural disaster risk"
            ]
        elif len([s for s in settlements if s.get('distance_km', 999) < 10]) > 0:
            risk = "medium"
            displaced = int(population_data['direct'] * 0.1)  # 10% may be displaced
            factors = [
                "Degraded living conditions",
                "Economic hardship",
                "Resource scarcity"
            ]
        else:
            risk = "low"
            displaced = 0
            factors = ["Settlements outside immediate impact zone"]
        
        return {
            "risk_level": risk,
            "estimated_displaced": displaced,
            "factors": factors,
            "timeframe": "1-5 years" if risk == "high" else "5-10 years"
        }
    
    def _generate_summary(self, population_data, stakeholder_impacts, economic_impacts):
        """Generate human-readable summary"""
        total_affected = population_data['total']
        annual_loss = economic_impacts['total_annual_loss_usd']
        
        summary = f"Approximately {total_affected:,} people are estimated to be affected by this deforestation event. "
        summary += f"Annual economic losses are projected at ${annual_loss:,} USD, "
        summary += f"with a 10-year cumulative impact of ${economic_impacts['ten_year_projection_usd']:,} USD. "
        
        # Identify most affected stakeholder
        most_affected = max(
            [(k, v) for k, v in stakeholder_impacts.items() if 'estimated_affected' in v],
            key=lambda x: x[1].get('estimated_affected', 0),
            default=(None, None)
        )
        
        if most_affected[0]:
            summary += f"The most affected group is {most_affected[0].replace('_', ' ')}, "
            summary += f"with an estimated {most_affected[1]['estimated_affected']:,} individuals impacted."
        
        return summary
