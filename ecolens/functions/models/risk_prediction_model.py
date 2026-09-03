"""
Risk Prediction Model

Rule-based and ML-hybrid model to predict future deforestation risk.
Uses validated rule-based scoring as primary method, with optional
ML enhancement when trained on sufficient real-world data.

Risk Factors (evidence-based scoring):
- Fire activity: Major indicator of active/planned deforestation
- Road proximity: Access enables illegal logging operations
- NDVI decline: Direct evidence of vegetation loss
- Protection status: Legal barriers reduce risk
- Population pressure: Human activity correlates with forest loss
- Historical decline: Past patterns predict future risk
"""

import pickle
import os
import numpy as np
from sklearn.ensemble import RandomForestClassifier
import traceback


class RiskPredictionModel:
    def __init__(self, model_path=None):
        """
        Initialize risk prediction model
        
        Args:
            model_path: Path to pre-trained model pickle file
        """
        self.model = None
        self.feature_names = [
            'fire_count_3yr',
            'road_dist_km',
            'slope_degrees',
            'soil_drainage_score',
            'protected_dist_km',
            'settlement_dist_km',
            'historical_trend_score'
        ]
        
        if model_path and os.path.exists(model_path):
            try:
                with open(model_path, 'rb') as f:
                    self.model = pickle.load(f)
                self.available = True
                print("✅ Pre-trained risk model loaded")
            except Exception as e:
                print(f"⚠️ Failed to load model: {e}")
                self.available = False
                self._create_default_model()
        else:
            print("ℹ️ No pre-trained model found, using default model")
            self.available = True
            self._create_default_model()
    
    def _create_default_model(self):
        """Create a default model with reasonable parameters"""
        # Create model with sensible defaults
        # In production, this would be replaced with a properly trained model
        self.model = RandomForestClassifier(
            n_estimators=100,
            max_depth=10,
            min_samples_split=5,
            min_samples_leaf=2,
            random_state=42,
            class_weight='balanced'
        )
        
        # Train on synthetic data representing typical patterns
        # This is a placeholder - real model should be trained on historical GFW data
        X_train = np.array([
            # High risk: many fires, close to roads, low slope, near settlements, poor protection
            [15, 0.5, 3, 50, 25, 2, 85],
            [12, 1.0, 5, 45, 20, 3, 80],
            [20, 0.3, 2, 55, 30, 1, 90],
            # Medium risk: moderate factors
            [5, 5.0, 8, 60, 10, 8, 60],
            [7, 4.0, 10, 55, 12, 7, 65],
            [6, 6.0, 7, 50, 15, 9, 55],
            # Low risk: few fires, far from access, steep terrain, well protected
            [1, 15, 25, 40, 2, 20, 20],
            [0, 20, 30, 35, 1, 25, 15],
            [2, 18, 28, 38, 3, 22, 25]
        ])
        
        y_train = np.array([1, 1, 1, 1, 1, 1, 0, 0, 0])  # 1 = continued loss, 0 = no loss
        
        self.model.fit(X_train, y_train)
        print("ℹ️ Using default risk model (should be replaced with trained model)")

    def calculate_rule_based_risk(self, intelligence_data):
        """
        Calculate risk score using validated rule-based scoring

        This is the PRIMARY scoring method - evidence-based rules derived from
        deforestation research literature and GFW data patterns.

        Args:
            intelligence_data: Full intelligence pipeline output dict containing:
                - fire_data: Active fires and fire history
                - vegetation_health: NDVI and change data
                - protected_areas: Protection status
                - proximity: Road and settlement distances
                - population: Human pressure data
                - historical_analysis: GFW tree cover loss history

        Returns:
            dict: Risk assessment with score, level, and contributing factors
        """
        score = 0
        factors = []
        confidence_notes = []

        # FACTOR 1: FIRE ACTIVITY (+25 max)
        # Active fires are the strongest predictor of imminent deforestation
        fire_data = intelligence_data.get('fire_data', {})
        active_fires = fire_data.get('activeFires', fire_data.get('active_fires', 0))
        fire_alerts = fire_data.get('alerts', [])

        if active_fires and active_fires > 0:
            score += 25
            factors.append({
                "factor": "Active fire detection",
                "contribution": 25,
                "value": f"{active_fires} active fire(s)",
                "severity": "critical",
                "interpretation": "Active fires indicate ongoing clearing activity"
            })
        elif fire_alerts and len(fire_alerts) > 0:
            score += 15
            factors.append({
                "factor": "Recent fire alerts",
                "contribution": 15,
                "value": f"{len(fire_alerts)} recent alert(s)",
                "severity": "high",
                "interpretation": "Recent fire activity suggests clearing operations"
            })
        else:
            confidence_notes.append("No fire data available - factor excluded")

        # FACTOR 2: NDVI DECLINE (+20 max)
        # Direct measurement of vegetation health decline
        vegetation = intelligence_data.get('vegetation_health', {})
        ndvi_change = vegetation.get('ndvi_change', vegetation.get('change_percent'))
        current_ndvi = vegetation.get('current_ndvi', vegetation.get('ndvi'))

        if ndvi_change is not None:
            if ndvi_change < -20:
                score += 20
                factors.append({
                    "factor": "Severe NDVI decline",
                    "contribution": 20,
                    "value": f"{ndvi_change:.1f}% change",
                    "severity": "critical",
                    "interpretation": "Major vegetation loss detected via satellite"
                })
            elif ndvi_change < -10:
                score += 12
                factors.append({
                    "factor": "Moderate NDVI decline",
                    "contribution": 12,
                    "value": f"{ndvi_change:.1f}% change",
                    "severity": "high",
                    "interpretation": "Significant vegetation stress or loss"
                })
            elif ndvi_change < -5:
                score += 5
                factors.append({
                    "factor": "Minor NDVI decline",
                    "contribution": 5,
                    "value": f"{ndvi_change:.1f}% change",
                    "severity": "moderate",
                    "interpretation": "Some vegetation degradation observed"
                })
        elif current_ndvi is not None and current_ndvi < 0.3:
            # Low absolute NDVI indicates degraded forest
            score += 10
            factors.append({
                "factor": "Low vegetation index",
                "contribution": 10,
                "value": f"NDVI: {current_ndvi:.2f}",
                "severity": "moderate",
                "interpretation": "Sparse vegetation cover"
            })
        else:
            confidence_notes.append("No NDVI change data - factor excluded")

        # FACTOR 3: PROTECTION STATUS (+15 max)
        # Areas outside protected zones face higher risk
        protected_areas = intelligence_data.get('protected_areas', {})
        is_protected = protected_areas.get('is_protected', protected_areas.get('inside_protected'))
        protection_type = protected_areas.get('protection_type', protected_areas.get('category'))
        nearest_protected_km = protected_areas.get('nearest_distance_km',
                                                    protected_areas.get('distance_km', 999))

        if is_protected is False or (nearest_protected_km and nearest_protected_km > 20):
            score += 15
            factors.append({
                "factor": "No protected status",
                "contribution": 15,
                "value": f"Nearest protection: {nearest_protected_km:.1f}km" if nearest_protected_km < 999 else "Unprotected",
                "severity": "high",
                "interpretation": "Area lacks formal legal protection"
            })
        elif is_protected is True:
            # Protected areas get risk reduction
            score -= 10
            factors.append({
                "factor": "Protected area",
                "contribution": -10,
                "value": protection_type or "Protected",
                "severity": "protective",
                "interpretation": "Legal protection reduces deforestation risk"
            })
        else:
            confidence_notes.append("Protection status unknown - factor excluded")

        # FACTOR 4: ROAD PROXIMITY (+15 max)
        # Roads provide access for illegal logging operations
        proximity = intelligence_data.get('proximity', intelligence_data.get('infrastructure', {}))
        road_data = proximity.get('roads', proximity.get('nearest_road', {}))

        if isinstance(road_data, dict):
            road_dist = road_data.get('distance_km', road_data.get('distance', 999))
        elif isinstance(road_data, list) and road_data:
            road_dist = min([r.get('distance_km', 999) for r in road_data if isinstance(r, dict)], default=999)
        else:
            road_dist = 999

        if road_dist < 2:
            score += 15
            factors.append({
                "factor": "Very close road access",
                "contribution": 15,
                "value": f"{road_dist:.1f}km",
                "severity": "high",
                "interpretation": "Easy vehicle access enables large-scale extraction"
            })
        elif road_dist < 5:
            score += 10
            factors.append({
                "factor": "Road access nearby",
                "contribution": 10,
                "value": f"{road_dist:.1f}km",
                "severity": "moderate",
                "interpretation": "Accessible by logging vehicles"
            })
        elif road_dist < 10:
            score += 5
            factors.append({
                "factor": "Moderate road access",
                "contribution": 5,
                "value": f"{road_dist:.1f}km",
                "severity": "low",
                "interpretation": "Some accessibility via roads"
            })
        elif road_dist < 999:
            # Remote areas are better protected by inaccessibility
            pass
        else:
            confidence_notes.append("Road proximity unknown - factor excluded")

        # FACTOR 5: POPULATION PRESSURE (+10 max)
        # Human population density correlates with deforestation risk
        population = intelligence_data.get('human_impacts', intelligence_data.get('population', {}))
        affected_pop = population.get('total_affected', population.get('population_5km', 0))

        if affected_pop and affected_pop > 5000:
            score += 10
            factors.append({
                "factor": "High population pressure",
                "contribution": 10,
                "value": f"{affected_pop:,} people affected",
                "severity": "moderate",
                "interpretation": "High local population increases land pressure"
            })
        elif affected_pop and affected_pop > 1000:
            score += 6
            factors.append({
                "factor": "Moderate population pressure",
                "contribution": 6,
                "value": f"{affected_pop:,} people affected",
                "severity": "low",
                "interpretation": "Some local population pressure"
            })
        elif affected_pop and affected_pop > 0:
            score += 3
            factors.append({
                "factor": "Low population pressure",
                "contribution": 3,
                "value": f"{affected_pop:,} people affected",
                "severity": "minimal",
                "interpretation": "Limited local population"
            })
        else:
            confidence_notes.append("Population data unavailable - factor excluded")

        # FACTOR 6: HISTORICAL DEFORESTATION (+15 max)
        # Past deforestation strongly predicts future loss
        historical = intelligence_data.get('historical_analysis', intelligence_data.get('gfw_data', {}))
        tree_loss = historical.get('total_loss_ha', historical.get('tree_cover_loss_ha', 0))
        loss_trend = historical.get('trend', historical.get('loss_trend'))
        yearly_losses = historical.get('yearly_losses', [])

        if tree_loss and tree_loss > 1000:
            score += 15
            factors.append({
                "factor": "Heavy historical deforestation",
                "contribution": 15,
                "value": f"{tree_loss:,.0f} ha lost",
                "severity": "critical",
                "interpretation": "Major historical tree cover loss in area"
            })
        elif tree_loss and tree_loss > 100:
            score += 10
            factors.append({
                "factor": "Significant historical loss",
                "contribution": 10,
                "value": f"{tree_loss:,.0f} ha lost",
                "severity": "high",
                "interpretation": "Substantial historical deforestation"
            })
        elif tree_loss and tree_loss > 10:
            score += 5
            factors.append({
                "factor": "Some historical loss",
                "contribution": 5,
                "value": f"{tree_loss:,.0f} ha lost",
                "severity": "moderate",
                "interpretation": "Limited historical tree loss"
            })
        elif loss_trend == "increasing":
            score += 12
            factors.append({
                "factor": "Increasing deforestation trend",
                "contribution": 12,
                "value": "Trend: Increasing",
                "severity": "high",
                "interpretation": "Deforestation rate accelerating"
            })
        else:
            confidence_notes.append("Historical loss data unavailable - factor excluded")

        # Normalize score to 0-100 range
        score = max(0, min(100, score))

        # Determine risk level with clear thresholds
        if score >= 70:
            risk_level = "critical"
            risk_description = "Critical deforestation risk - immediate intervention recommended"
        elif score >= 50:
            risk_level = "high"
            risk_description = "High deforestation risk - enhanced monitoring required"
        elif score >= 30:
            risk_level = "moderate"
            risk_description = "Moderate deforestation risk - regular monitoring advised"
        elif score >= 15:
            risk_level = "low"
            risk_description = "Low deforestation risk - standard monitoring"
        else:
            risk_level = "minimal"
            risk_description = "Minimal deforestation risk detected"

        # Sort factors by contribution
        factors.sort(key=lambda x: abs(x['contribution']), reverse=True)

        # Calculate data completeness
        total_factors = 6
        factors_with_data = total_factors - len(confidence_notes)
        data_completeness = (factors_with_data / total_factors) * 100

        return {
            "available": True,
            "risk_score": score,
            "risk_probability": score / 100,  # Convert to probability for compatibility
            "risk_level": risk_level,
            "risk_description": risk_description,
            "confidence": "high" if data_completeness >= 80 else "medium" if data_completeness >= 50 else "low",
            "data_completeness_percent": round(data_completeness, 1),
            "contributing_factors": factors,
            "primary_risk_factors": factors[:3],  # Top 3 for summary
            "methodology": "Rule-based scoring using evidence-based deforestation risk factors",
            "confidence_notes": confidence_notes if confidence_notes else None,
            "score_breakdown": {
                "fire_activity": sum(f['contribution'] for f in factors if 'fire' in f['factor'].lower()),
                "vegetation_health": sum(f['contribution'] for f in factors if 'ndvi' in f['factor'].lower() or 'vegetation' in f['factor'].lower()),
                "protection_status": sum(f['contribution'] for f in factors if 'protect' in f['factor'].lower()),
                "accessibility": sum(f['contribution'] for f in factors if 'road' in f['factor'].lower()),
                "population_pressure": sum(f['contribution'] for f in factors if 'population' in f['factor'].lower()),
                "historical_pattern": sum(f['contribution'] for f in factors if 'historical' in f['factor'].lower() or 'trend' in f['factor'].lower())
            }
        }

    def predict_risk(self, features_dict, intelligence_data=None):
        """
        Predict deforestation risk for a location

        Uses rule-based scoring as primary method (more reliable with real data),
        with ML model available as secondary/enhancement option.

        Args:
            features_dict: Dictionary with feature values for ML model:
                {
                    'fire_count_3yr': int,
                    'road_dist_km': float,
                    'slope_degrees': float,
                    'soil_drainage_score': float (0-100),
                    'protected_dist_km': float,
                    'settlement_dist_km': float,
                    'historical_trend_score': float (0-100, higher = more loss)
                }
            intelligence_data: Full intelligence pipeline output (preferred).
                If provided, uses rule-based scoring for more accurate results.

        Returns:
            dict: Risk prediction with probability, level, and factors
        """
        # PRIMARY: Use rule-based scoring if intelligence data is available
        # This is more reliable than the ML model trained on limited synthetic data
        if intelligence_data:
            return self.calculate_rule_based_risk(intelligence_data)

        # Check if features_dict actually contains intelligence data structure
        # (sometimes full intelligence data is passed as features_dict)
        if features_dict and any(key in features_dict for key in ['fire_data', 'vegetation_health', 'protected_areas', 'proximity', 'human_impacts']):
            return self.calculate_rule_based_risk(features_dict)

        # FALLBACK: Use ML model if only basic features provided
        if not self.available or self.model is None:
            return {
                "available": False,
                "error": "Risk prediction model not available",
                "message": "Model not initialized"
            }

        try:
            # Extract and order features
            feature_values = []
            missing_features = []
            
            for feature_name in self.feature_names:
                value = features_dict.get(feature_name)
                if value is not None:
                    feature_values.append(float(value))
                else:
                    missing_features.append(feature_name)
                    # Use safe defaults
                    if 'dist' in feature_name:
                        feature_values.append(10.0)  # Default distance
                    elif 'score' in feature_name:
                        feature_values.append(50.0)  # Mid-range score
                    elif 'slope' in feature_name:
                        feature_values.append(5.0)  # Gentle slope
                    elif 'fire' in feature_name:
                        feature_values.append(0.0)  # No fires
                    else:
                        feature_values.append(50.0)
            
            # Create numpy array for prediction
            X = np.array([feature_values])
            
            # Get prediction probability
            probability = self.model.predict_proba(X)[0][1]  # Probability of class 1 (continued loss)
            
            # Determine risk level
            if probability >= 0.7:
                risk_level = "high"
                risk_description = "High probability of continued deforestation"
            elif probability >= 0.4:
                risk_level = "moderate"
                risk_description = "Moderate risk of continued deforestation"
            else:
                risk_level = "low"
                risk_description = "Low risk of continued deforestation"
            
            # Get feature importances if available
            feature_importance = {}
            if hasattr(self.model, 'feature_importances_'):
                importances = self.model.feature_importances_
                for i, name in enumerate(self.feature_names):
                    feature_importance[name] = round(float(importances[i]), 3)
            
            # Identify top risk factors
            top_factors = self._identify_top_factors(features_dict, feature_importance)
            
            # Generate recommendations
            recommendations = self._generate_recommendations(features_dict, risk_level, top_factors)
            
            return {
                "available": True,
                "risk_probability": round(float(probability), 3),
                "risk_level": risk_level,
                "risk_description": risk_description,
                "confidence": "medium" if missing_features else "high",
                "primary_risk_factors": top_factors,
                "feature_values": {name: val for name, val in zip(self.feature_names, feature_values)},
                "feature_importance": feature_importance,
                "recommendations": recommendations,
                "metadata": {
                    "model_type": "RandomForestClassifier",
                    "features_used": len(self.feature_names),
                    "missing_features": missing_features
                }
            }
        
        except Exception as e:
            print(f"❌ Risk prediction failed: {e}")
            traceback.print_exc()
            return {
                "available": False,
                "error": str(e),
                "message": "Risk prediction encountered an error"
            }
    
    def _identify_top_factors(self, features_dict, importance_dict):
        """Identify the top risk factors contributing to the prediction"""
        
        factors = []
        
        # Check fire activity
        fire_count = features_dict.get('fire_count_3yr', 0)
        if fire_count > 10:
            factors.append({
                "factor": "High fire activity",
                "value": fire_count,
                "importance": importance_dict.get('fire_count_3yr', 0),
                "interpretation": f"{fire_count} fires detected in past 3 years"
            })
        
        # Check road proximity
        road_dist = features_dict.get('road_dist_km', 999)
        if road_dist < 5:
            factors.append({
                "factor": "Close to road access",
                "value": road_dist,
                "importance": importance_dict.get('road_dist_km', 0),
                "interpretation": f"Only {road_dist:.1f} km from nearest road"
            })
        
        # Check protected area distance
        protected_dist = features_dict.get('protected_dist_km', 999)
        if protected_dist > 20:
            factors.append({
                "factor": "Far from protected areas",
                "value": protected_dist,
                "importance": importance_dict.get('protected_dist_km', 0),
                "interpretation": f"{protected_dist:.1f} km from nearest protected area"
            })
        
        # Check historical trend
        trend_score = features_dict.get('historical_trend_score', 0)
        if trend_score > 70:
            factors.append({
                "factor": "Strong historical deforestation trend",
                "value": trend_score,
                "importance": importance_dict.get('historical_trend_score', 0),
                "interpretation": f"High historical loss trend (score: {trend_score})"
            })
        
        # Check terrain accessibility
        slope = features_dict.get('slope_degrees', 0)
        if slope < 10:
            factors.append({
                "factor": "Accessible terrain",
                "value": slope,
                "importance": importance_dict.get('slope_degrees', 0),
                "interpretation": f"Gentle slope ({slope}°) makes area accessible"
            })
        
        # Sort by importance if available
        if importance_dict:
            factors.sort(key=lambda x: x['importance'], reverse=True)
        
        return factors[:5]  # Return top 5
    
    def _generate_recommendations(self, features_dict, risk_level, top_factors):
        """Generate risk mitigation recommendations"""
        
        recommendations = []
        
        if risk_level == "high":
            recommendations.append({
                "priority": "urgent",
                "action": "Immediate monitoring and intervention required",
                "rationale": "High risk prediction indicates probable continued loss"
            })
        
        # Road-based recommendations
        road_dist = features_dict.get('road_dist_km', 999)
        if road_dist < 5:
            recommendations.append({
                "priority": "high",
                "action": "Implement road checkpoint monitoring system",
                "rationale": "Proximity to roads increases illegal access risk"
            })
        
        # Fire-based recommendations
        fire_count = features_dict.get('fire_count_3yr', 0)
        if fire_count > 10:
            recommendations.append({
                "priority": "high",
                "action": "Deploy fire prevention and rapid response teams",
                "rationale": "High fire frequency suggests intentional clearing"
            })
        
        # Protection recommendations
        protected_dist = features_dict.get('protected_dist_km', 999)
        if protected_dist > 15:
            recommendations.append({
                "priority": "medium",
                "action": "Establish new protected buffer zone",
                "rationale": "Area lacks formal protection designation"
            })
        
        # Community engagement
        settlement_dist = features_dict.get('settlement_dist_km', 999)
        if settlement_dist < 10:
            recommendations.append({
                "priority": "medium",
                "action": "Engage local communities in conservation programs",
                "rationale": "Nearby settlements can be partners in protection"
            })
        
        return recommendations
