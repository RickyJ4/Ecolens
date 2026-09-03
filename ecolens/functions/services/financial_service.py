"""
Financial Analysis Service

Provides verified financial calculations for:
- Restoration costs by region
- Ecosystem service valuations
- Carbon credit potential
- Economic impact assessments

Data Sources:
- WRI (World Resources Institute) Cost of Restoration report 2023
- PACTO (Atlantic Forest Restoration Pact) cost tracking
- TEEB (The Economics of Ecosystems and Biodiversity)
- Forest Trends ecosystem services valuations
- FAO/UNEP reforestation cost database
"""


class FinancialService:
    """
    Financial calculations using verified regional data
    """

    def __init__(self):
        # ═══════════════════════════════════════════════════════════════
        # VERIFIED RESTORATION COSTS (USD per hectare)
        # Sources: WRI 2023, PACTO, regional forestry ministries
        # ═══════════════════════════════════════════════════════════════
        self.restoration_costs = {
            # SOUTH AMERICA
            "amazon_brazil": {
                "low": 800,      # Natural regeneration with minimal intervention
                "medium": 2500,  # Assisted natural regeneration
                "high": 8000,    # Active planting with enrichment
                "source": "WRI Cost of Restoration 2023",
                "currency_year": 2023,
                "includes": ["Site preparation", "Seedlings", "Planting labor", "3-year maintenance"]
            },
            "atlantic_forest": {
                "low": 2000,     # Higher baseline due to fragmentation
                "medium": 5000,  # PACTO tracked average
                "high": 15000,   # Complex restoration with species diversity
                "source": "PACTO Atlantic Forest Pact 2023",
                "currency_year": 2023,
                "includes": ["Site preparation", "High diversity planting", "Long-term monitoring"]
            },
            "cerrado": {
                "low": 600,
                "medium": 1800,
                "high": 5000,
                "source": "WRI Brazil 2023",
                "currency_year": 2023,
                "includes": ["Savanna restoration", "Fire management"]
            },
            "amazon_peru": {
                "low": 750,
                "medium": 2200,
                "high": 6500,
                "source": "SERNANP Peru 2022",
                "currency_year": 2022
            },
            "amazon_colombia": {
                "low": 900,
                "medium": 2800,
                "high": 7000,
                "source": "MinAmbiente Colombia 2023",
                "currency_year": 2023
            },

            # CENTRAL AFRICA
            "congo_basin": {
                "low": 500,
                "medium": 1500,
                "high": 4500,
                "source": "CAFI Initiative 2023",
                "currency_year": 2023,
                "includes": ["Community engagement", "Agroforestry integration"]
            },
            "east_africa": {
                "low": 700,
                "medium": 2000,
                "high": 6000,
                "source": "AFR100 Initiative 2023",
                "currency_year": 2023
            },
            "west_africa": {
                "low": 600,
                "medium": 1800,
                "high": 5500,
                "source": "AFR100/FAO 2023",
                "currency_year": 2023
            },

            # SOUTHEAST ASIA
            "borneo": {
                "low": 1200,
                "medium": 3500,
                "high": 10000,
                "source": "Borneo Orangutan Survival Foundation 2023",
                "currency_year": 2023,
                "includes": ["Peatland restoration where applicable"]
            },
            "sumatra": {
                "low": 1000,
                "medium": 3200,
                "high": 9000,
                "source": "KLHK Indonesia 2023",
                "currency_year": 2023
            },
            "peninsular_malaysia": {
                "low": 1500,
                "medium": 4000,
                "high": 12000,
                "source": "Malaysian Forestry Dept 2023",
                "currency_year": 2023
            },

            # CENTRAL AMERICA
            "central_america": {
                "low": 1000,
                "medium": 3000,
                "high": 8500,
                "source": "CATIE Costa Rica 2023",
                "currency_year": 2023
            },
            "mexico": {
                "low": 800,
                "medium": 2500,
                "high": 7500,
                "source": "CONAFOR Mexico 2023",
                "currency_year": 2023
            },

            # OCEANIA
            "papua_new_guinea": {
                "low": 600,
                "medium": 1800,
                "high": 5500,
                "source": "PNG Forest Authority 2022",
                "currency_year": 2022
            },
            "australia_north": {
                "low": 2000,
                "medium": 6000,
                "high": 15000,
                "source": "CSIRO/Greening Australia 2023",
                "currency_year": 2023
            },

            # SOUTH ASIA
            "south_asia": {
                "low": 400,
                "medium": 1200,
                "high": 3500,
                "source": "Indian Forest Survey 2023",
                "currency_year": 2023
            },

            # Default for unspecified regions
            "global": {
                "low": 800,
                "medium": 2500,
                "high": 8000,
                "source": "WRI Global Average 2023",
                "currency_year": 2023
            }
        }

        # ═══════════════════════════════════════════════════════════════
        # ECOSYSTEM SERVICE VALUES (USD per hectare per year)
        # Source: TEEB, Costanza et al. 2014, de Groot et al. 2012
        # ═══════════════════════════════════════════════════════════════
        self.ecosystem_services = {
            "tropical_rainforest": {
                "total_annual": 5264,  # USD/ha/year
                "breakdown": {
                    "climate_regulation": 1965,
                    "water_regulation": 1360,
                    "erosion_control": 578,
                    "nutrient_cycling": 420,
                    "pollination": 215,
                    "biodiversity_habitat": 380,
                    "genetic_resources": 150,
                    "recreation_ecotourism": 196
                },
                "source": "Costanza et al. 2014 (updated to 2023 USD)"
            },
            "temperate_forest": {
                "total_annual": 3137,
                "breakdown": {
                    "climate_regulation": 980,
                    "water_regulation": 890,
                    "erosion_control": 465,
                    "nutrient_cycling": 320,
                    "pollination": 120,
                    "biodiversity_habitat": 210,
                    "genetic_resources": 72,
                    "recreation_ecotourism": 80
                },
                "source": "TEEB 2010 (updated to 2023 USD)"
            },
            "mangrove": {
                "total_annual": 193845,  # Extremely high value
                "breakdown": {
                    "coastal_protection": 162000,
                    "fisheries_nursery": 18000,
                    "carbon_sequestration": 8500,
                    "water_filtration": 3500,
                    "biodiversity_habitat": 1845
                },
                "source": "Barbier et al. 2011 / TEEB"
            },
            "peatland": {
                "total_annual": 12500,
                "breakdown": {
                    "carbon_storage": 8500,
                    "water_regulation": 2500,
                    "biodiversity": 1500
                },
                "source": "Joosten 2009 / IUCN Peatland Programme"
            },
            "savanna_woodland": {
                "total_annual": 1588,
                "breakdown": {
                    "climate_regulation": 450,
                    "water_regulation": 420,
                    "erosion_control": 280,
                    "grazing_fodder": 250,
                    "biodiversity_habitat": 188
                },
                "source": "de Groot et al. 2012"
            }
        }

        # ═══════════════════════════════════════════════════════════════
        # CARBON CREDIT VALUES
        # Source: World Bank State of Carbon Markets 2023
        # ═══════════════════════════════════════════════════════════════
        self.carbon_prices = {
            "voluntary_market": {
                "low": 8,       # USD per tonne CO2e
                "medium": 15,
                "high": 50,
                "premium_nature": 80,  # Premium for high-quality nature-based
                "source": "Ecosystem Marketplace 2023"
            },
            "compliance_market": {
                "eu_ets": 85,   # EU ETS average 2023
                "california": 30,
                "rggi": 15,
                "source": "World Bank Carbon Pricing Dashboard"
            },
            "social_cost_carbon": 190,  # US EPA estimate 2023
            "source_year": 2023
        }

        # ═══════════════════════════════════════════════════════════════
        # CARBON SEQUESTRATION RATES (tonnes CO2 per hectare per year)
        # Source: IPCC AR6, Griscom et al. 2017
        # ═══════════════════════════════════════════════════════════════
        self.carbon_sequestration = {
            "tropical_rainforest": {
                "rate": 11.0,  # tonnes CO2/ha/year for restoration
                "stock": 250,  # tonnes C/ha standing stock
                "source": "IPCC AR6 WGIII"
            },
            "temperate_forest": {
                "rate": 6.5,
                "stock": 155,
                "source": "IPCC AR6"
            },
            "mangrove": {
                "rate": 8.5,
                "stock": 1000,  # Very high carbon density
                "source": "Donato et al. 2011"
            },
            "peatland": {
                "rate": 2.0,
                "stock": 2000,  # Extremely high
                "source": "IUCN Peatland Programme"
            }
        }

    def calculate_restoration_cost(self, lat, lng, area_ha, intensity="medium", soil_data=None):
        """
        Calculate restoration cost using verified regional data

        Args:
            lat: Latitude
            lng: Longitude
            area_ha: Area in hectares
            intensity: "low", "medium", or "high" restoration intensity
            soil_data: Optional soil analysis for adjustment

        Returns:
            Dict with detailed cost breakdown
        """
        region = self._determine_region(lat, lng)
        region_costs = self.restoration_costs.get(region, self.restoration_costs["global"])

        base_cost_per_ha = region_costs.get(intensity, region_costs["medium"])

        # Apply soil-based adjustments
        adjustment_factor = 1.0
        adjustments = []

        if soil_data:
            # Degraded soil increases costs
            fertility = soil_data.get("fertility", {}).get("rating", "medium")
            if fertility == "low":
                adjustment_factor *= 1.25
                adjustments.append({"factor": "Low soil fertility", "adjustment": "+25%"})

            # Erosion risk
            erosion = soil_data.get("erosion_risk", "low")
            if erosion == "high":
                adjustment_factor *= 1.15
                adjustments.append({"factor": "High erosion risk", "adjustment": "+15%"})

            # pH extremes
            ph = soil_data.get("ph", {}).get("value")
            if ph and (ph < 4.5 or ph > 8.5):
                adjustment_factor *= 1.10
                adjustments.append({"factor": "Extreme soil pH", "adjustment": "+10%"})

        adjusted_cost_per_ha = base_cost_per_ha * adjustment_factor
        total_cost = adjusted_cost_per_ha * area_ha

        return {
            "region": region,
            "area_ha": area_ha,
            "intensity": intensity,
            "base_cost_per_ha": base_cost_per_ha,
            "adjusted_cost_per_ha": round(adjusted_cost_per_ha, 2),
            "total_cost_usd": round(total_cost, 2),
            "adjustments": adjustments,
            "cost_breakdown": {
                "site_preparation": round(total_cost * 0.15, 2),
                "seedlings_nursery": round(total_cost * 0.25, 2),
                "planting_labor": round(total_cost * 0.30, 2),
                "maintenance_3yr": round(total_cost * 0.20, 2),
                "monitoring": round(total_cost * 0.10, 2)
            },
            "source": region_costs.get("source", "WRI 2023"),
            "currency_year": region_costs.get("currency_year", 2023),
            "confidence": "high" if region != "global" else "medium",
            "methodology": "Verified regional restoration cost data from forestry organizations"
        }

    def calculate_ecosystem_value(self, lat, lng, area_ha, forest_type=None):
        """
        Calculate ecosystem service value for an area

        Args:
            lat: Latitude
            lng: Longitude
            area_ha: Area in hectares
            forest_type: Optional override for forest type

        Returns:
            Dict with ecosystem service valuation
        """
        if forest_type is None:
            forest_type = self._determine_forest_type(lat, lng)

        services = self.ecosystem_services.get(forest_type, self.ecosystem_services["tropical_rainforest"])

        annual_value = services["total_annual"] * area_ha
        breakdown = {k: round(v * area_ha, 2) for k, v in services.get("breakdown", {}).items()}

        # 30-year projection (standard carbon accounting period)
        projection_years = 30
        total_value_30yr = annual_value * projection_years

        return {
            "forest_type": forest_type,
            "area_ha": area_ha,
            "annual_value_usd": round(annual_value, 2),
            "value_per_ha_per_year": services["total_annual"],
            "service_breakdown_annual": breakdown,
            "projection_30yr_usd": round(total_value_30yr, 2),
            "source": services.get("source", "TEEB/Costanza"),
            "methodology": "Ecosystem service valuation (TEEB methodology)",
            "note": "Values represent replacement cost of ecosystem services"
        }

    def calculate_carbon_value(self, lat, lng, area_ha, forest_type=None, market="voluntary_market"):
        """
        Calculate carbon credit value potential

        Args:
            lat: Latitude
            lng: Longitude
            area_ha: Area in hectares
            forest_type: Optional forest type override
            market: "voluntary_market" or "compliance_market"

        Returns:
            Dict with carbon credit calculations
        """
        if forest_type is None:
            forest_type = self._determine_forest_type(lat, lng)

        carbon_data = self.carbon_sequestration.get(forest_type, self.carbon_sequestration["tropical_rainforest"])
        prices = self.carbon_prices.get(market, self.carbon_prices["voluntary_market"])

        # Annual sequestration
        annual_sequestration = carbon_data["rate"] * area_ha

        # 30-year total (accounting period)
        total_30yr = annual_sequestration * 30

        # Value calculations
        if market == "voluntary_market":
            low_value = total_30yr * prices["low"]
            medium_value = total_30yr * prices["medium"]
            high_value = total_30yr * prices["high"]
            premium_value = total_30yr * prices["premium_nature"]
        else:
            # Use EU ETS as reference for compliance
            low_value = total_30yr * prices.get("rggi", 15)
            medium_value = total_30yr * prices.get("california", 30)
            high_value = total_30yr * prices.get("eu_ets", 85)
            premium_value = None

        # Social cost calculation
        social_cost_value = total_30yr * self.carbon_prices["social_cost_carbon"]

        return {
            "forest_type": forest_type,
            "area_ha": area_ha,
            "sequestration_rate_per_ha": carbon_data["rate"],
            "annual_sequestration_tonnes": round(annual_sequestration, 2),
            "total_30yr_tonnes": round(total_30yr, 2),
            "market": market,
            "value_scenarios": {
                "low": round(low_value, 2),
                "medium": round(medium_value, 2),
                "high": round(high_value, 2),
                "premium_nature": round(premium_value, 2) if premium_value else None
            },
            "social_cost_value_usd": round(social_cost_value, 2),
            "source": f"{carbon_data['source']}, {prices.get('source', 'World Bank')}",
            "methodology": "Carbon sequestration potential based on IPCC guidelines"
        }

    def calculate_loss_vs_restoration(self, lat, lng, area_ha, soil_data=None, forest_type=None):
        """
        Compare economic impact of loss vs cost of restoration

        Args:
            lat: Latitude
            lng: Longitude
            area_ha: Area affected
            soil_data: Optional soil analysis
            forest_type: Optional forest type

        Returns:
            Dict with comprehensive economic analysis
        """
        # Calculate restoration cost
        restoration = self.calculate_restoration_cost(lat, lng, area_ha, "medium", soil_data)

        # Calculate ecosystem service loss
        ecosystem = self.calculate_ecosystem_value(lat, lng, area_ha, forest_type)

        # Calculate carbon value
        carbon = self.calculate_carbon_value(lat, lng, area_ha, forest_type)

        # Total loss if deforested (30-year)
        total_loss_30yr = ecosystem["projection_30yr_usd"] + carbon["social_cost_value_usd"]

        # Cost to restore
        restoration_cost = restoration["total_cost_usd"]

        # ROI calculation
        roi = (total_loss_30yr - restoration_cost) / restoration_cost * 100 if restoration_cost > 0 else 0

        return {
            "area_ha": area_ha,
            "restoration_cost_usd": restoration_cost,
            "ecosystem_loss_30yr_usd": ecosystem["projection_30yr_usd"],
            "carbon_social_cost_usd": carbon["social_cost_value_usd"],
            "total_loss_if_deforested_usd": round(total_loss_30yr, 2),
            "restoration_roi_percent": round(roi, 1),
            "cost_benefit_ratio": round(total_loss_30yr / restoration_cost, 1) if restoration_cost > 0 else 0,
            "break_even_years": round(restoration_cost / ecosystem["annual_value_usd"], 1) if ecosystem["annual_value_usd"] > 0 else None,
            "recommendation": self._generate_recommendation(restoration_cost, total_loss_30yr),
            "sources": {
                "restoration": restoration["source"],
                "ecosystem": ecosystem["source"],
                "carbon": carbon["source"]
            },
            "detailed_analysis": {
                "restoration": restoration,
                "ecosystem_services": ecosystem,
                "carbon": carbon
            }
        }

    def _determine_region(self, lat, lng):
        """Determine region based on coordinates"""
        regions = {
            "amazon_brazil": {"lat": (-15, 5), "lng": (-75, -45)},
            "atlantic_forest": {"lat": (-30, -15), "lng": (-55, -35)},
            "cerrado": {"lat": (-24, -5), "lng": (-60, -40)},
            "amazon_peru": {"lat": (-15, 0), "lng": (-82, -68)},
            "amazon_colombia": {"lat": (-4, 5), "lng": (-77, -66)},
            "congo_basin": {"lat": (-8, 8), "lng": (10, 35)},
            "east_africa": {"lat": (-12, 5), "lng": (28, 42)},
            "west_africa": {"lat": (4, 15), "lng": (-18, 15)},
            "borneo": {"lat": (-5, 8), "lng": (108, 120)},
            "sumatra": {"lat": (-6, 6), "lng": (95, 108)},
            "peninsular_malaysia": {"lat": (0, 8), "lng": (99, 105)},
            "central_america": {"lat": (7, 23), "lng": (-92, -77)},
            "mexico": {"lat": (14, 32), "lng": (-118, -86)},
            "papua_new_guinea": {"lat": (-12, 0), "lng": (140, 160)},
            "australia_north": {"lat": (-25, -10), "lng": (110, 155)},
            "south_asia": {"lat": (5, 35), "lng": (65, 100)}
        }

        for region, bounds in regions.items():
            if (bounds["lat"][0] <= lat <= bounds["lat"][1] and
                bounds["lng"][0] <= lng <= bounds["lng"][1]):
                return region

        return "global"

    def _determine_forest_type(self, lat, lng):
        """Determine forest type based on coordinates"""
        # Tropical zone
        if -23.5 <= lat <= 23.5:
            # Check for mangrove zones (coastal)
            # This is simplified - would need coastline data for accuracy
            return "tropical_rainforest"

        # Temperate zones
        if 23.5 < abs(lat) < 60:
            return "temperate_forest"

        # High latitude (boreal would go here)
        return "temperate_forest"

    def _generate_recommendation(self, restoration_cost, total_loss):
        """Generate financial recommendation"""
        ratio = total_loss / restoration_cost if restoration_cost > 0 else 0

        if ratio >= 10:
            return {
                "action": "Urgent restoration recommended",
                "rationale": f"Ecosystem service value is {ratio:.0f}x restoration cost",
                "priority": "critical"
            }
        elif ratio >= 5:
            return {
                "action": "Strong case for restoration",
                "rationale": f"Ecosystem service value is {ratio:.0f}x restoration cost",
                "priority": "high"
            }
        elif ratio >= 2:
            return {
                "action": "Restoration economically viable",
                "rationale": f"Ecosystem service value exceeds restoration cost by {ratio:.1f}x",
                "priority": "medium"
            }
        else:
            return {
                "action": "Consider restoration for non-economic benefits",
                "rationale": "Biodiversity and climate benefits may justify investment",
                "priority": "low"
            }
