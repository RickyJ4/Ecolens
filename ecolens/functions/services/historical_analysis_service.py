"""
Historical Analysis Service - Layer 12

Analyzes historical deforestation trends and builds timeline
using existing GFW data sources.

Provides:
- Year-by-year tree cover loss timeline (2001-2024)
- Trend analysis with projections
- Pattern detection and key events
- Recovery window assessment
"""

from datetime import datetime
import numpy as np


class HistoricalAnalysisService:
    """
    Historical timeline analysis for deforestation trends
    
    Uses GFW agent for historical data and provides:
    - Timeline visualization data
    - Trend analysis
    - Future projections
    - Pattern detection
    """
    
    def __init__(self, gfw_agent):
        """
        Initialize with GFW agent for data fetching
        
        Args:
            gfw_agent: Instance of GFWIngestionAgent
        """
        self.gfw = gfw_agent

    def analyze(self, hotspot: dict, bbox: dict, fire_history: dict = None) -> dict:
        """
        Main entry point - analyze historical trends
        
        Args:
            hotspot: Current hotspot data
            bbox: Bounding box for queries
            fire_history: Optional fire data by year
            
        Returns:
            Historical analysis dict
        """
        try:
            # Build GeoJSON polygon from bbox
            geojson_polygon = self._bbox_to_geojson(bbox)
            
            # Fetch historical data from GFW
            historical_loss = self._fetch_historical_data(geojson_polygon)
            
            if not historical_loss:
                return self._get_fallback_analysis(hotspot)
            
            # Build timeline
            timeline = self._build_timeline(historical_loss, fire_history)
            
            # Calculate summary statistics
            summary = self._calculate_summary(timeline, historical_loss)
            
            # Analyze trends
            trend_analysis = self._analyze_trends(historical_loss)
            
            # Detect patterns
            patterns = self._detect_patterns(historical_loss, fire_history)
            
            # Project future
            projection = self._project_future(historical_loss, trend_analysis)
            
            # Identify key events
            key_events = self._identify_key_events(historical_loss, fire_history)
            
            # Assess recovery window
            recovery = self._assess_recovery_window(historical_loss, trend_analysis)
            
            return {
                "available": True,
                "timeline": timeline,
                "summary": summary,
                "trend_analysis": trend_analysis,
                "patterns_detected": patterns,
                "projection": projection,
                "key_events": key_events,
                "recovery_window": recovery,
                "data_source": "Global Forest Watch API (Hansen et al.)",
                "confidence": "high" if len(historical_loss) >= 5 else "medium"
            }
            
        except Exception as e:
            print(f"❌ Historical analysis error: {e}")
            return self._get_fallback_analysis(hotspot)

    def _bbox_to_geojson(self, bbox: dict) -> dict:
        """
        Convert bbox to GeoJSON polygon
        """
        return {
            "type": "Polygon",
            "coordinates": [[
                [float(bbox['min_lng']), float(bbox['min_lat'])],
                [float(bbox['max_lng']), float(bbox['min_lat'])],
                [float(bbox['max_lng']), float(bbox['max_lat'])],
                [float(bbox['min_lng']), float(bbox['max_lat'])],
                [float(bbox['min_lng']), float(bbox['min_lat'])]
            ]]
        }

    def _fetch_historical_data(self, geojson_polygon: dict) -> list:
        """
        Fetch historical tree cover loss from GFW
        """
        try:
            # Use GFW agent's historical summary method
            historical_data = self.gfw.fetch_tree_loss_summary(
                aoi_geojson=geojson_polygon,
                start_year=2001,
                end_year=2023
            )
            
            if historical_data:
                return historical_data
            
            # Fallback: try with different year range
            return self.gfw.fetch_tree_loss_summary(
                aoi_geojson=geojson_polygon,
                start_year=2015,
                end_year=2023
            ) or []
            
        except Exception as e:
            print(f"⚠️ Historical data fetch failed: {e}")
            return []

    def _build_timeline(self, historical_loss: list, fire_history: dict = None) -> list:
        """
        Build year-by-year timeline
        """
        timeline = []
        
        for entry in sorted(historical_loss, key=lambda x: x.get('umd_tree_cover_loss__year', 0)):
            year = entry.get('umd_tree_cover_loss__year')
            loss_ha = entry.get('total_loss_ha', 0)
            
            if year:
                item = {
                    "year": year,
                    "loss_ha": round(loss_ha, 1)
                }
                
                # Add fire data if available
                if fire_history and year in fire_history:
                    item["fires"] = fire_history[year]
                
                timeline.append(item)
        
        return timeline

    def _calculate_summary(self, timeline: list, historical_loss: list) -> dict:
        """
        Calculate summary statistics
        """
        if not timeline:
            return {
                "years_analyzed": 0,
                "total_loss_ha": 0,
                "average_annual_loss_ha": 0
            }
        
        years = [t['year'] for t in timeline]
        losses = [t['loss_ha'] for t in timeline]
        
        total_loss = sum(losses)
        avg_loss = total_loss / len(losses) if losses else 0
        
        # Find peak year
        if losses:
            peak_idx = losses.index(max(losses))
            peak_year = years[peak_idx]
            peak_loss = losses[peak_idx]
        else:
            peak_year = None
            peak_loss = 0
        
        return {
            "years_analyzed": len(timeline),
            "year_range": f"{min(years)}-{max(years)}" if years else "N/A",
            "total_loss_ha": round(total_loss, 1),
            "average_annual_loss_ha": round(avg_loss, 1),
            "peak_year": peak_year,
            "peak_loss_ha": round(peak_loss, 1),
            "baseline_year": min(years) if years else None
        }

    def _analyze_trends(self, historical_loss: list) -> dict:
        """
        Analyze trends using linear regression
        """
        if len(historical_loss) < 3:
            return {
                "trend": "unknown",
                "trend_slope_ha_per_year": 0,
                "urgency_level": "medium",
                "description": "Insufficient data for trend analysis"
            }
        
        # Extract and sort data
        sorted_data = sorted(historical_loss, key=lambda x: x.get('umd_tree_cover_loss__year', 0))
        years = np.array([d.get('umd_tree_cover_loss__year', 0) for d in sorted_data])
        losses = np.array([d.get('total_loss_ha', 0) for d in sorted_data])
        
        # Linear regression
        try:
            z = np.polyfit(years, losses, 1)
            trend_slope = z[0]
        except Exception:
            trend_slope = 0
        
        # Determine trend direction
        if trend_slope > 2:
            trend = "accelerating"
            urgency = "critical"
            description = f"Deforestation rate increasing by ~{trend_slope:.1f} ha/year. Urgent intervention needed."
        elif trend_slope > 0.5:
            trend = "increasing"
            urgency = "high"
            description = f"Deforestation rate increasing. ~{trend_slope:.1f} ha/year trend."
        elif trend_slope < -2:
            trend = "declining"
            urgency = "low"
            description = "Deforestation rate declining. Good opportunity for restoration."
        elif trend_slope < -0.5:
            trend = "improving"
            urgency = "medium"
            description = "Slight improvement in deforestation rates."
        else:
            trend = "stable"
            urgency = "medium"
            description = "Deforestation rate relatively stable."
        
        return {
            "trend": trend,
            "trend_slope_ha_per_year": round(trend_slope, 2),
            "urgency_level": urgency,
            "description": description
        }

    def _detect_patterns(self, historical_loss: list, fire_history: dict = None) -> list:
        """
        Detect patterns in deforestation data
        """
        patterns = []
        
        if len(historical_loss) < 3:
            return patterns
        
        sorted_data = sorted(historical_loss, key=lambda x: x.get('umd_tree_cover_loss__year', 0))
        losses = [d.get('total_loss_ha', 0) for d in sorted_data]
        years = [d.get('umd_tree_cover_loss__year', 0) for d in sorted_data]
        
        # Calculate median for comparison
        median_loss = np.median(losses)
        
        # Check for fire correlation
        if fire_history:
            fire_years = [year for year, count in fire_history.items() if count > 5]
            high_loss_years = [years[i] for i, loss in enumerate(losses) if loss > median_loss]
            
            if fire_years and high_loss_years:
                overlap = len(set(fire_years) & set(high_loss_years))
                correlation = overlap / len(high_loss_years) if high_loss_years else 0
                
                if correlation > 0.5:
                    patterns.append("Strong correlation between fire activity and deforestation")
        
        # Check for sudden increases
        for i in range(1, len(losses)):
            if losses[i] > losses[i-1] * 2 and losses[i] > median_loss:
                patterns.append(f"{years[i]}: Sudden increase detected - possible logging or clearance event")
        
        # Check for recent acceleration
        if len(losses) >= 5:
            recent_avg = np.mean(losses[-3:])
            earlier_avg = np.mean(losses[:-3])
            
            if recent_avg > earlier_avg * 1.5:
                patterns.append("Recent acceleration: Last 3 years show significantly higher loss rates")
            elif recent_avg < earlier_avg * 0.5:
                patterns.append("Recent improvement: Last 3 years show significantly lower loss rates")
        
        return patterns

    def _project_future(self, historical_loss: list, trend_analysis: dict) -> dict:
        """
        Project future loss if trend continues
        """
        if not historical_loss or trend_analysis.get('trend') == 'unknown':
            return {
                "scenario": "unknown",
                "description": "Insufficient data for projection"
            }
        
        sorted_data = sorted(historical_loss, key=lambda x: x.get('umd_tree_cover_loss__year', 0))
        current_year = max(d.get('umd_tree_cover_loss__year', 0) for d in sorted_data)
        current_loss = sorted_data[-1].get('total_loss_ha', 0) if sorted_data else 0
        
        trend_slope = trend_analysis.get('trend_slope_ha_per_year', 0)
        
        # Project to 2030
        years_ahead = 2030 - current_year
        projected_2030 = max(0, current_loss + (trend_slope * years_ahead))
        
        # Cumulative loss estimate
        cumulative = sum([
            max(0, current_loss + (trend_slope * i))
            for i in range(1, years_ahead + 1)
        ])
        
        return {
            "if_trend_continues": {
                "annual_loss_2030_ha": round(projected_2030, 1),
                "cumulative_loss_2024_2030_ha": round(cumulative, 1),
                "description": f"If current trend continues, expect ~{projected_2030:.0f} ha/year by 2030"
            },
            "urgency_assessment": self._get_urgency_message(trend_analysis.get('trend', 'unknown'))
        }

    def _get_urgency_message(self, trend: str) -> str:
        """
        Get urgency message based on trend
        """
        messages = {
            "accelerating": "CRITICAL: Intervention needed immediately to prevent irreversible loss",
            "increasing": "HIGH: Early intervention recommended before trend worsens",
            "stable": "MODERATE: Proactive protection can prevent future increases",
            "improving": "GOOD: Build on current momentum with restoration programs",
            "declining": "OPPORTUNITY: Ideal conditions for large-scale restoration"
        }
        return messages.get(trend, "Assessment pending")

    def _identify_key_events(self, historical_loss: list, fire_history: dict = None) -> list:
        """
        Identify significant events in the timeline
        """
        events = []
        
        if len(historical_loss) < 2:
            return events
        
        sorted_data = sorted(historical_loss, key=lambda x: x.get('umd_tree_cover_loss__year', 0))
        losses = [d.get('total_loss_ha', 0) for d in sorted_data]
        years = [d.get('umd_tree_cover_loss__year', 0) for d in sorted_data]
        
        # Find peak year
        peak_idx = losses.index(max(losses))
        events.append({
            "year": years[peak_idx],
            "event": "Peak deforestation year",
            "impact": f"{losses[peak_idx]:.0f} ha lost"
        })
        
        # Find significant changes
        for i in range(1, len(losses)):
            change_pct = ((losses[i] - losses[i-1]) / losses[i-1] * 100) if losses[i-1] > 0 else 0
            
            if change_pct > 100:
                events.append({
                    "year": years[i],
                    "event": "Major increase detected",
                    "impact": f"Loss rate doubled from previous year"
                })
            elif change_pct < -50:
                events.append({
                    "year": years[i],
                    "event": "Significant reduction",
                    "impact": f"Loss rate dropped by {abs(change_pct):.0f}%"
                })
        
        # Add fire events if available
        if fire_history:
            max_fire_year = max(fire_history, key=fire_history.get) if fire_history else None
            if max_fire_year and fire_history[max_fire_year] > 10:
                events.append({
                    "year": max_fire_year,
                    "event": "Major fire event",
                    "impact": f"{fire_history[max_fire_year]} fire detections"
                })
        
        # Sort by year
        events.sort(key=lambda x: x['year'])
        
        return events[:5]  # Return top 5 events

    def _assess_recovery_window(self, historical_loss: list, trend_analysis: dict) -> dict:
        """
        Assess the recovery window and difficulty
        """
        if not historical_loss:
            return {
                "degradation_duration": "unknown",
                "expected_recovery_time": "unknown",
                "difficulty_increase": "unknown"
            }
        
        sorted_data = sorted(historical_loss, key=lambda x: x.get('umd_tree_cover_loss__year', 0))
        first_year = sorted_data[0].get('umd_tree_cover_loss__year', 2015)
        last_year = sorted_data[-1].get('umd_tree_cover_loss__year', 2023)
        
        degradation_years = last_year - first_year
        total_loss = sum(d.get('total_loss_ha', 0) for d in sorted_data)
        
        # Estimate recovery time (rule of thumb: 5-10x the degradation period for full recovery)
        if degradation_years < 5:
            recovery_estimate = "15-25 years for full ecosystem recovery"
        elif degradation_years < 10:
            recovery_estimate = "30-50 years for full ecosystem recovery"
        else:
            recovery_estimate = "50+ years for full ecosystem recovery"
        
        return {
            "degradation_duration": f"{degradation_years} years ({first_year}-{last_year})",
            "total_loss_ha": round(total_loss, 1),
            "expected_recovery_time": recovery_estimate,
            "difficulty_increase": "Each year of delay increases restoration difficulty by 10-15%",
            "recommendation": "Early intervention significantly reduces long-term costs and improves success rates"
        }

    def _get_fallback_analysis(self, hotspot: dict) -> dict:
        """
        Return fallback analysis when data unavailable
        """
        pattern = hotspot.get('pattern', 'Unknown')
        
        return {
            "available": False,
            "timeline": [],
            "summary": {
                "years_analyzed": 0,
                "note": "Historical data unavailable"
            },
            "trend_analysis": {
                "trend": "unknown",
                "urgency_level": "medium",
                "description": f"Based on pattern classification: {pattern}"
            },
            "patterns_detected": [],
            "projection": {
                "scenario": "unavailable",
                "description": "Cannot project without historical data"
            },
            "key_events": [],
            "recovery_window": {
                "recommendation": "Collect baseline data before planning restoration"
            },
            "confidence": "low",
            "data_source": "Fallback (historical data unavailable)"
        }
