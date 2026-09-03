from datetime import datetime
from firebase.firebase_client import FirebaseClient

class IntelligenceRepository:
    def __init__(self):
        self.db = FirebaseClient.db()
        self.collection = self.db.collection("intelligence")

    def upsert_region_intelligence(
        self,
        region_id: str,
        geometry: dict,
        land_features: dict,
        biodiversity: list,
        disasters: dict,
        trends: dict,
        sources: list
    ):
        
        payload = {
            "region_id": region_id,
            "geometry": geometry,

            "land_feature_proximity": land_features,
            "biodiversity_impact": biodiversity,
            "natural_disasters": disasters,
            "trend_analysis": trends,

            "sources": sources,
            "confidence_score": self._confidence_score(sources),

            "last_updated": datetime.utcnow(),
            "status": "active"
        }

        self.collection.document(region_id).set(payload, merge=True)

        return payload

    def log_event(
        self,
        region_id: str,
        event_type: str,
        severity: str,
        details: dict
    ):
        """
        Logs time-series intelligence events
        """

        event_ref = (
            self.collection
            .document(region_id)
            .collection("events")
            .document()
        )

        event_ref.set({
            "type": event_type,
            "severity": severity,
            "details": details,
            "timestamp": datetime.utcnow()
        })

    def _confidence_score(self, sources):
        """
        Simple explainable confidence logic
        """
        base = 0.4
        increment = 0.15

        score = base + (len(set(sources)) * increment)
        return min(round(score, 2), 0.95)
