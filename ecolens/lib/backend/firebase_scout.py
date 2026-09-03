import firebase_admin
from firebase_admin import credentials, firestore
from google import genai
from google.genai import types
import json
import os
import time

# --- 1. FIREBASE AUTHENTICATION ---
base_dir = os.path.dirname(os.path.abspath(__file__))
# The service-account key lives OUTSIDE the repository. Point GOOGLE_APPLICATION_CREDENTIALS
# at it, or keep it at ~/.ecolens/serviceAccountKey.json. Never place it in the tree.
key_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS") or os.path.join(
    os.path.expanduser("~"), ".ecolens", "serviceAccountKey.json")
cred = credentials.Certificate(key_path)
firebase_admin.initialize_app(cred)
db = firestore.client()

# --- 2. AI AGENT INITIALIZATION ---
_gemini_key = os.environ.get("GEMINI_API_KEY")
if not _gemini_key:
    raise RuntimeError(
        "GEMINI_API_KEY environment variable is not set. "
        "Set it before running: $env:GEMINI_API_KEY='your-key' (PowerShell) "
        "or export GEMINI_API_KEY='your-key' (bash)."
    )
client = genai.Client(api_key=_gemini_key)

def run_scout_mission():
    print("🛰️ Agent EcoLens: Starting global scouting mission for Dec 2025...")
    
    # 1. STRICTER PROMPT: Demanding pure JSON without "chatting"
    prompt = (
        "Search for 5 active deforestation hotspots reported in December 2025 using Google Search. "
        "For each, find: latitude, longitude, hectares lost, and historical loss for 2021-2024. "
        "Return ONLY a raw JSON array. No markdown, no conversational text, no source footers. "
        "Schema: [{'latitude': float, 'longitude': float, 'hectares': float, 'driver': str, 'history': dict, 'tree': str}]"
    )

    try:
        response = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=prompt,
            config=types.GenerateContentConfig(
                tools=[types.Tool(google_search=types.GoogleSearch())],
                response_mime_type="application/json"
            )
        )

        # 2. MARKDOWN SANITIZER: This prevents the 'line 1 column 1' error
        raw_output = response.text.strip()
        if "```json" in raw_output:
            raw_output = raw_output.split("```json")[1].split("```")[0].strip()
        elif "```" in raw_output:
            raw_output = raw_output.split("```")[1].strip()

        if not raw_output:
            raise ValueError("The AI returned an empty response.")

        hotspots = json.loads(raw_output)
        
        # 3. PUSHING TO FIREBASE
        for spot in hotspots:
            doc_ref = db.collection("hotspots").document()
            doc_ref.set({
                "lat": spot["latitude"],
                "lng": spot["longitude"],
                "hectares": spot.get("hectares", 0.0),
                "type": spot.get("driver", "Deforestation"),
                "history": spot.get("history", {}), # For your landloss history feature
                "reforest_strategy": spot.get("tree", "Native Species"),
                "timestamp": firestore.SERVER_TIMESTAMP,
                "status": "CRITICAL" if spot.get("hectares", 0) > 10 else "MONITORING"
            })
            print(f"✅ Synced: {spot['latitude']}, {spot['longitude']} | History Found: {bool(spot.get('history'))}")

    except json.JSONDecodeError as je:
        print(f"❌ JSON Error: {je}")
        print(f"📝 Raw Output was: {response.text}") # Debugging the 'line 1' error
    except Exception as e:
        print(f"❌ Mission Failed: {e}")

if __name__ == "__main__":
    run_scout_mission()