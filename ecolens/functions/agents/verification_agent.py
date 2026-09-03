class VerificationAgent:
    def verify(self, gfw_data, fire_data, analysis):
        confidence = 0.9

        if not gfw_data:
            confidence -= 0.4
        if not fire_data:
            confidence -= 0.2
        if not analysis:
            confidence -= 0.3

        return {
            "confidence_score": max(confidence, 0),
            "verified": confidence > 0.6
        }
