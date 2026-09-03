import requests
from datetime import datetime, timedelta


class TrendAnalysisService:
    """
    Analyzes deforestation trends using historical GFW data
    
    Provides:
    - Historical deforestation rates
    - Trend direction (accelerating/stable/declining)
    - Future projections based on current trajectory
    """
    
    def __init__(self, gfw_agent):
        self.gfw = gfw_agent
    
    def analyze_trends(self, hotspot, center, bbox):
        """
        Analyze historical trends and project future scenarios
        
        Args:
            hotspot: Current hotspot data
            center: Center coordinates
            bbox: Bounding box
        
        Returns:
            Trend analysis with projections
        """
        try:
            # Get historical tree loss data
            historical_loss = self.gfw.fetch_tree_loss_summary(
                aoi_geojson={"type": "Polygon", "coordinates": [[
                    [bbox['min_lng'], bbox['min_lat']],
                    [bbox['max_lng'], bbox['min_lat']],
                    [bbox['max_lng'], bbox['max_lat']],
                    [bbox['min_lng'], bbox['max_lat']],
                    [bbox['min_lng'], bbox['min_lat']]
                ]]},
                start_year=2018,
                end_year=2023
            )
            
            # Analyze pattern
            pattern = hotspot.get('pattern', '')
            area_ha = hotspot.get('gfw_area__ha', 0)
            
            trends = self._calculate_trends(historical_loss, pattern, area_ha)
            
            return trends
            
        except Exception as e:
            print(f"Error in trend analysis: {e}")
            return self._get_fallback_trends(hotspot)
    
    def _calculate_trends(self, historical_loss, pattern, current_area):
        """Calculate trends from historical data"""
        
        if not historical_loss or len(historical_loss) == 0:
            return self._pattern_based_trends(pattern, current_area)
        
        # Calculate year-over-year changes
        years = sorted([entry.get('umd_tree_cover_loss__year') for entry in historical_loss])
        losses = [entry.get('total_loss_ha', 0) for entry in sorted(historical_loss, key=lambda x: x.get('umd_tree_cover_loss__year', 0))]
        
        if len(losses) < 2:
            return self._pattern_based_trends(pattern, current_area)
        
        # Calculate trend
        recent_avg = sum(losses[-3:]) / len(losses[-3:]) if len(losses) >= 3 else losses[-1]
        earlier_avg = sum(losses[:3]) / len(losses[:3]) if len(losses) >= 3 else losses[0]
        
        if recent_avg > earlier_avg * 1.5:
            direction = "accelerating"
            severity = "critical"
        elif recent_avg > earlier_avg * 1.1:
            direction = "increasing"
            severity = "high"
        elif recent_avg < earlier_avg * 0.7:
            direction = "declining"
            severity = "medium"
        else:
            direction = "stable"
            severity = "medium"
        
        # Project future
        avg_annual_loss = recent_avg
        
        return {
            "trend_direction": direction,
            "severity": severity,
            "historical_data": {
                "years_analyzed": f"{min(years)}-{max(years)}",
                "total_loss_ha": sum(losses),
                "average_annual_loss_ha": avg_annual_loss,
                "year_over_year_data": historical_loss
            },
            "projection_no_intervention": {
                "1_year": f"Estimated additional loss: {avg_annual_loss:.0f} ha",
                "5_years": f"Estimated total loss: {avg_annual_loss * 5:.0f} ha",
                "10_years": f"Estimated total loss: {avg_annual_loss * 10:.0f} ha",
                "methodology": "Linear projection based on recent average"
            },
            "restoration_potential": self._assess_restoration_potential(direction, severity)
        }
    
    def _pattern_based_trends(self, pattern, area_ha):
        """Fallback: Use pattern classification when historical data unavailable"""
        
        trend_map = {
            "Intensifying": {
                "direction": "accelerating",
                "severity": "critical",
                "projection_1y": area_ha * 0.3,
                "projection_5y": area_ha * 1.5,
                "restoration": "medium - window closing"
            },
            "New": {
                "direction": "emerging",
                "severity": "high",
                "projection_1y": area_ha * 0.5,
                "projection_5y": area_ha * 2,
                "restoration": "high - early intervention opportunity"
            },
            "Persistent": {
                "direction": "ongoing",
                "severity": "medium-high",
                "projection_1y": area_ha * 0.15,
                "projection_5y": area_ha * 0.75,
                "restoration": "medium - requires sustained effort"
            },
            "Diminishing": {
                "direction": "declining",
                "severity": "medium",
                "projection_1y": area_ha * 0.05,
                "projection_5y": area_ha * 0.25,
                "restoration": "high - suitable for reforestation"
            },
            "Sporadic": {
                "direction": "intermittent",
                "severity": "medium",
                "projection_1y": area_ha * 0.1,
                "projection_5y": area_ha * 0.5,
                "restoration": "variable"
            }
        }
        
        for key, values in trend_map.items():
            if key in pattern:
                return {
                    "trend_direction": values["direction"],
                    "severity": values["severity"],
                    "historical_context": f"Classified as {pattern} by GFW",
                    "projection_no_intervention": {
                        "1_year": f"Estimated {values['projection_1y']:.0f} ha at risk",
                        "5_years": f"Estimated {values['projection_5y']:.0f} ha at risk",
                        "note": "Projections based on pattern classification"
                    },
                    "restoration_potential": values["restoration"]
                }
        
        return self._get_fallback_trends({"pattern": pattern, "gfw_area__ha": area_ha})
    
    def _assess_restoration_potential(self, direction, severity):
        """Assess restoration potential based on trends"""
        if direction == "declining":
            return "high - positive trajectory, suitable for restoration programs"
        elif direction == "stable" or direction == "intermittent":
            return "medium - requires intervention to prevent resumption"
        elif direction == "increasing":
            return "medium-low - intervention needed before restoration"
        else:  # accelerating
            return "low - immediate protection required before restoration can begin"
    
    def _get_fallback_trends(self, hotspot):
        """Fallback when no data available"""
        return {
            "trend_direction": "unknown",
            "severity": "medium",
            "historical_context": "Insufficient historical data for trend analysis",
            "projection_no_intervention": {
                "note": "Unable to project - requires historical data"
            },
            "restoration_potential": "requires assessment"
        }