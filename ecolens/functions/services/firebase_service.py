from firebase_admin import firestore
import firebase_admin

# Don't initialize here - wait until function is called
_db = None

def _get_db():
    """
    Lazy initialization of Firestore client
    Only initializes when first called, not at import time
    """
    global _db
    
    if _db is None:
        # Initialize Firebase if not already done
        if not firebase_admin._apps:
            firebase_admin.initialize_app()
        
        _db = firestore.client()
    
    return _db


def save_report(report, report_type="public"):
    """
    Save intelligence report to Firestore
    
    Args:
        report: Dictionary containing hotspot intelligence
        report_type: "public" or "scientific" or "both"
    """
    try:
        db = _get_db()  # Get client lazily
        
        hotspot_id = report.get('hotspot_id')
        
        if report_type == "both":
            # Save both public and scientific reports
            if 'public_report' in report:
                public_doc = db.collection('public_reports').document(hotspot_id)
                public_doc.set(report['public_report'])
                print(f"✅ Saved public report {hotspot_id}")
            
            if 'scientific_report' in report:
                scientific_doc = db.collection('scientific_reports').document(hotspot_id)
                scientific_doc.set(report['scientific_report'])
                print(f"✅ Saved scientific report {hotspot_id}")
            
            return True
        else:
            # Save to single collection (backward compatibility)
            collection_name = f"{report_type}_reports" if report_type in ["public", "scientific"] else "hotspots"
            doc_ref = db.collection(collection_name).document(hotspot_id)
            doc_ref.set(report)
            print(f"✅ Saved report {hotspot_id} to {collection_name}")
            return True
        
    except Exception as e:
        print(f"❌ Firestore error: {e}")
        return False


def get_report(hotspot_id):
    """
    Retrieve a report from Firestore
    
    Args:
        hotspot_id: ID of the hotspot report
    
    Returns:
        dict: Report data or None if not found
    """
    try:
        db = _get_db()
        doc_ref = db.collection('hotspots').document(hotspot_id)
        doc = doc_ref.get()
        
        if doc.exists:
            return doc.to_dict()
        return None
        
    except Exception as e:
        print(f"❌ Firestore error: {e}")
        return None


def list_recent_reports(limit=10):
    """
    List recent hotspot reports
    
    Args:
        limit: Maximum number of reports to return
    
    Returns:
        list: List of report dictionaries
    """
    try:
        db = _get_db()
        docs = db.collection('hotspots')\
                 .order_by('processed_at', direction=firestore.Query.DESCENDING)\
                 .limit(limit)\
                 .stream()
        
        reports = []
        for doc in docs:
            report = doc.to_dict()
            report['id'] = doc.id
            reports.append(report)
        
        return reports
        
    except Exception as e:
        print(f"❌ Firestore error: {e}")
        return []