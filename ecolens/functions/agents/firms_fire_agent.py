from services.firms_service import FIRMSService
import csv
from io import StringIO

class FIRMSFireAgent:
    def __init__(self):
        self.firms = FIRMSService()

    def fetch(self, bbox):
        # Service returns list of dicts, no need to parse CSV
        raw_fires = self.firms.fetch(bbox)

        fires = []
        for row in raw_fires:
            try:
                fires.append({
                    "lat": float(row.get("latitude", 0)),
                    "lng": float(row.get("longitude", 0)),
                    "confidence": row.get("confidence", "unknown"),
                    "brightness": float(row.get("bright_ti4", 0)),
                    "date": row.get("acq_date", "")
                })
            except (ValueError, TypeError):
                continue

        return fires
