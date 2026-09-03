"""
Reforestation Service

Calculates tree planting requirements and provides species recommendations
for ecosystem restoration.
"""


class ReforestationService:
    def __init__(self):
        # Native species database by habitat type
        self.native_species = {
            "Tropical Rainforest": [
                {
                    "name": "Mahogany (Swietenia macrophylla)",
                    "growth_rate": "medium",
                    "carbon_sequestration_kg_year": 22,
                    "survival_rate": 0.75,
                    "ecological_value": "high",
                    "benefits": ["Timber value", "Wildlife habitat", "Soil stabilization"]
                },
                {
                    "name": "Kapok (Ceiba pentandra)",
                    "growth_rate": "fast",
                    "carbon_sequestration_kg_year": 28,
                    "survival_rate": 0.80,
                    "ecological_value": "very high",
                    "benefits": ["Emergent canopy", "Wildlife food source", "Rapid coverage"]
                },
                {
                    "name": "Brazil Nut (Bertholletia excelsa)",
                    "growth_rate": "slow",
                    "carbon_sequestration_kg_year": 18,
                    "survival_rate": 0.70,
                    "ecological_value": "very high",
                    "benefits": ["Economic value", "Wildlife food", "Long-lived"]
                },
                {
                    "name": "Rubber Tree (Hevea brasiliensis)",
                    "growth_rate": "medium",
                    "carbon_sequestration_kg_year": 20,
                    "survival_rate": 0.78,
                    "ecological_value": "medium",
                    "benefits": ["Economic value", "Fast establishment", "Soil improvement"]
                },
                {
                    "name": "Açaí Palm (Euterpe oleracea)",
                    "growth_rate": "fast",
                    "carbon_sequestration_kg_year": 15,
                    "survival_rate": 0.85,
                    "ecological_value": "high",
                    "benefits": ["Food source", "Economic value", "Wetland restoration"]
                }
            ],
            "Central African Rainforest": [
                {
                    "name": "African Mahogany (Khaya ivorensis)",
                    "growth_rate": "medium",
                    "carbon_sequestration_kg_year": 24,
                    "survival_rate": 0.72,
                    "ecological_value": "high",
                    "benefits": ["Timber value", "Canopy structure", "Wildlife habitat"]
                },
                {
                    "name": "Iroko (Milicia excelsa)",
                    "growth_rate": "medium",
                    "carbon_sequestration_kg_year": 26,
                    "survival_rate": 0.75,
                    "ecological_value": "high",
                    "benefits": ["Durable timber", "Large canopy", "Long-lived"]
                },
                {
                    "name": "Oil Palm (Elaeis guineensis)",
                    "growth_rate": "fast",
                    "carbon_sequestration_kg_year": 18,
                    "survival_rate": 0.82,
                    "ecological_value": "medium",
                    "benefits": ["Economic value", "Fast growth", "Food source"]
                }
            ],
            "Southeast Asian Rainforest": [
                {
                    "name": "Dipterocarp species",
                    "growth_rate": "medium",
                    "carbon_sequestration_kg_year": 25,
                    "survival_rate": 0.70,
                    "ecological_value": "very high",
                    "benefits": ["Dominant canopy", "High biodiversity support", "Timber value"]
                },
                {
                    "name": "Rattan Palm (Calamus spp.)",
                    "growth_rate": "fast",
                    "carbon_sequestration_kg_year": 12,
                    "survival_rate": 0.80,
                    "ecological_value": "medium",
                    "benefits": ["Economic value", "Understory coverage", "Wildlife habitat"]
                },
                {
                    "name": "Teak (Tectona grandis)",
                    "growth_rate": "medium",
                    "carbon_sequestration_kg_year": 22,
                    "survival_rate": 0.76,
                    "ecological_value": "medium",
                    "benefits": ["High timber value", "Soil improvement", "Drought resistant"]
                }
            ]
        }
        
        # Standard planting density (trees per hectare)
        self.planting_density = {
            "high": 1100,  # Dense reforestation
            "medium": 800,  # Standard reforestation
            "low": 500     # Assisted natural regeneration
        }
    
    def calculate_requirements(self, area_ha, habitat_type, severity="medium"):
        """
        Calculate tree planting requirements
        
        Args:
            area_ha: Area to reforest in hectares
            habitat_type: Type of habitat (e.g., "Tropical Rainforest")
            severity: Degradation severity (low/medium/high)
        
        Returns:
            Dict with planting requirements and recommendations
        """
        # Determine planting density based on severity
        density_key = severity if severity in self.planting_density else "medium"
        trees_per_ha = self.planting_density[density_key]
        
        total_trees = int(area_ha * trees_per_ha)
        
        # Get species recommendations
        species_recommendations = self._get_species_recommendations(
            habitat_type, total_trees
        )
        
        # Calculate carbon sequestration potential
        carbon_potential = self._calculate_carbon_potential(
            species_recommendations, total_trees
        )
        
        # Estimate costs and timeline
        cost_estimate = self._estimate_costs(total_trees, area_ha)
        timeline = self._create_timeline(area_ha)
        
        # Assess suitability factors
        suitability = self._assess_suitability(habitat_type, severity)
        
        return {
            "total_trees_needed": total_trees,
            "area_hectares": area_ha,
            "planting_density_per_ha": trees_per_ha,
            "species_mix": species_recommendations,
            "carbon_sequestration_potential": carbon_potential,
            "cost_estimate": cost_estimate,
            "implementation_timeline": timeline,
            "suitability_assessment": suitability,
            "success_factors": self._get_success_factors(),
            "monitoring_requirements": self._get_monitoring_requirements()
        }
    
    def _get_species_recommendations(self, habitat_type, total_trees):
        """Get recommended species mix"""
        # Find matching habitat type
        species_list = None
        for key in self.native_species.keys():
            if key in habitat_type or habitat_type in key:
                species_list = self.native_species[key]
                break
        
        if not species_list:
            # Default to tropical rainforest
            species_list = self.native_species["Tropical Rainforest"]
        
        # Create species mix (diversified for resilience)
        recommendations = []
        
        for i, species in enumerate(species_list[:5]):  # Top 5 species
            # Allocate percentage based on position (higher for first species)
            if i == 0:
                percentage = 30
            elif i == 1:
                percentage = 25
            elif i == 2:
                percentage = 20
            elif i == 3:
                percentage = 15
            else:
                percentage = 10
            
            tree_count = int(total_trees * (percentage / 100))
            
            recommendations.append({
                "species": species["name"],
                "quantity": tree_count,
                "percentage": percentage,
                "growth_rate": species["growth_rate"],
                "carbon_sequestration_kg_year": species["carbon_sequestration_kg_year"],
                "survival_rate": species["survival_rate"],
                "ecological_value": species["ecological_value"],
                "benefits": species["benefits"],
                "expected_survival": int(tree_count * species["survival_rate"])
            })
        
        return recommendations
    
    def _calculate_carbon_potential(self, species_mix, total_trees):
        """Calculate carbon sequestration potential"""
        # Calculate weighted average carbon sequestration
        total_carbon_year_1 = 0
        
        for species in species_mix:
            trees = species["quantity"]
            survival = species["survival_rate"]
            carbon_per_tree = species["carbon_sequestration_kg_year"]
            
            # Year 1 carbon (accounting for survival rate)
            total_carbon_year_1 += trees * survival * carbon_per_tree
        
        # Project over time (trees sequester more as they grow)
        # Simplified model: carbon increases by 10% per year for first 10 years
        projections = {
            "year_1_kg": int(total_carbon_year_1),
            "year_5_kg": int(total_carbon_year_1 * 1.5),  # 50% increase
            "year_10_kg": int(total_carbon_year_1 * 2.5),  # 150% increase
            "year_20_kg": int(total_carbon_year_1 * 4.0),  # 300% increase
        }
        
        # Convert to tonnes
        projections_tonnes = {
            k: round(v / 1000, 2) for k, v in projections.items()
        }
        
        # Calculate CO2 equivalent (1 kg C = 3.67 kg CO2)
        co2_equivalent = {
            k: round(v * 3.67, 2) for k, v in projections_tonnes.items()
        }
        
        return {
            "carbon_sequestration_tonnes": projections_tonnes,
            "co2_equivalent_tonnes": co2_equivalent,
            "lifetime_total_tonnes_co2": int(co2_equivalent["year_20_kg"] * 2),  # Estimate 40-year lifespan
            "note": "Estimates based on average growth rates and survival"
        }
    
    def _estimate_costs(self, total_trees, area_ha):
        """Estimate reforestation costs"""
        # Cost per tree (USD) - includes seedling, planting, initial care
        cost_per_tree = 2.5
        
        # Site preparation cost per hectare
        site_prep_per_ha = 300
        
        # Monitoring and maintenance (first 3 years)
        maintenance_per_ha_year = 150
        
        tree_cost = total_trees * cost_per_tree
        site_prep = area_ha * site_prep_per_ha
        maintenance_3_years = area_ha * maintenance_per_ha_year * 3
        
        total_cost = tree_cost + site_prep + maintenance_3_years
        
        return {
            "seedling_and_planting_usd": int(tree_cost),
            "site_preparation_usd": int(site_prep),
            "maintenance_3_years_usd": int(maintenance_3_years),
            "total_estimated_cost_usd": int(total_cost),
            "cost_per_hectare_usd": int(total_cost / area_ha) if area_ha > 0 else 0,
            "cost_per_tree_usd": cost_per_tree,
            "note": "Costs vary by location, accessibility, and local labor rates"
        }
    
    def _create_timeline(self, area_ha):
        """Create implementation timeline"""
        # Estimate based on area
        if area_ha < 10:
            planting_duration = "1-2 months"
            full_establishment = "3-5 years"
        elif area_ha < 50:
            planting_duration = "3-6 months"
            full_establishment = "5-7 years"
        elif area_ha < 200:
            planting_duration = "6-12 months"
            full_establishment = "7-10 years"
        else:
            planting_duration = "1-2 years"
            full_establishment = "10-15 years"
        
        return {
            "phase_1_planning": "2-3 months (site assessment, species selection, seedling procurement)",
            "phase_2_site_preparation": "1-2 months (clearing invasives, soil preparation)",
            "phase_3_planting": planting_duration,
            "phase_4_maintenance": "3 years (watering, weeding, replanting failures)",
            "phase_5_monitoring": "Ongoing (annual assessments)",
            "full_forest_establishment": full_establishment,
            "carbon_maturity": "20-30 years (maximum carbon sequestration rate)"
        }
    
    def _assess_suitability(self, habitat_type, severity):
        """Assess site suitability for reforestation"""
        suitability_score = 75  # Base score
        
        factors = []
        
        # Adjust based on severity
        if severity == "low":
            suitability_score += 15
            factors.append("Low degradation allows for assisted natural regeneration")
        elif severity == "high":
            suitability_score -= 10
            factors.append("High degradation requires intensive restoration efforts")
        
        # Habitat-specific factors
        if "Rainforest" in habitat_type:
            factors.append("High rainfall supports rapid tree growth")
            factors.append("Rich soil biodiversity aids establishment")
        
        return {
            "suitability_score": min(100, max(0, suitability_score)),
            "rating": "excellent" if suitability_score > 85 else "good" if suitability_score > 70 else "moderate",
            "factors": factors,
            "challenges": [
                "Invasive species competition",
                "Seed predation by wildlife",
                "Drought stress during establishment",
                "Illegal logging pressure"
            ],
            "recommendations": [
                "Use native species adapted to local conditions",
                "Plant during rainy season for best survival",
                "Implement community engagement programs",
                "Establish protection measures against illegal activities"
            ]
        }
    
    def _get_success_factors(self):
        """Get key success factors"""
        return [
            "Community involvement and ownership",
            "Adequate funding for 3-5 year maintenance period",
            "Protection from grazing and illegal logging",
            "Species diversity (minimum 5 species)",
            "Proper site preparation and planting techniques",
            "Regular monitoring and adaptive management",
            "Integration with livelihood programs"
        ]
    
    def _get_monitoring_requirements(self):
        """Get monitoring requirements"""
        return {
            "frequency": {
                "year_1": "Monthly site visits",
                "year_2_3": "Quarterly assessments",
                "year_4_plus": "Annual monitoring"
            },
            "metrics": [
                "Survival rate (%)",
                "Growth rate (height, diameter)",
                "Canopy cover (%)",
                "Species diversity",
                "Wildlife return indicators",
                "Soil quality improvements",
                "Carbon stock measurements"
            ],
            "reporting": "Annual reports with photographic documentation and GPS-tagged tree measurements"
        }
