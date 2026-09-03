def build_report(raw_data, analysis, verification):
    return {
        "source": "Global Forest Watch",
        "raw_data": raw_data,
        "analysis": analysis,
        "verification": verification,
        "status": "verified" if verification["analysis_consistent"] else "flagged"
    }
