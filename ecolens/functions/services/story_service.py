"""
Immersive Environmental Story Generation Service

High-end storytelling engine for the CesiumJS AR viewer.
Generates multi-sensory, temporally-aware, interactive narrative experiences.

Features:
- Dynamic Sensory Orchestration (audio, visual filters, haptics)
- Temporal Branching (past/present/future state comparisons)
- Spatial POIs for Species (AR coordinate placement)
- Emotional Tone Mapping (severity-based language adaptation)
- Gaze Triggers & Interactive Anchors
- Procedural Environment Variables (weather, lighting, atmosphere)
"""

import math
import random
from datetime import datetime, timezone
from typing import Dict, List, Any, Optional, Tuple


class StoryService:
    """
    High-end immersive storytelling service for environmental intelligence data.
    Transforms raw data into multi-sensory, interactive AR experiences.
    """

    def __init__(self):
        self._init_soundscapes()
        self._init_visual_filters()
        self._init_tone_engine()
        self._init_chapter_templates()
        self._init_narrator_system()
        self._init_discovery_system()
        self._init_musical_journey()
        self._init_personalization_engine()
        self._init_silent_hunt_system()
        self._init_ecosystem_simulation()
        self._init_immersive_interactions()

    # ═══════════════════════════════════════════════════════════════
    # INITIALIZATION
    # ═══════════════════════════════════════════════════════════════

    def _init_soundscapes(self):
        """Initialize audio soundscape library for different environmental states"""
        self.soundscapes = {
            # Healthy forest states
            "pristine_dawn": {
                "file": "soundscapes/pristine_rainforest_dawn.mp3",
                "layers": ["bird_chorus", "distant_stream", "wind_canopy"],
                "volume": 0.8,
                "loop": True,
                "crossfade_duration": 3.0
            },
            "pristine_day": {
                "file": "soundscapes/dense_rainforest_day.mp3",
                "layers": ["cicadas", "bird_calls", "monkey_howl_distant"],
                "volume": 0.75,
                "loop": True,
                "crossfade_duration": 2.5
            },
            "pristine_dusk": {
                "file": "soundscapes/rainforest_dusk.mp3",
                "layers": ["frog_chorus", "nightjar", "wind_leaves"],
                "volume": 0.7,
                "loop": True,
                "crossfade_duration": 3.5
            },
            "pristine_night": {
                "file": "soundscapes/rainforest_night.mp3",
                "layers": ["insects", "owl", "distant_jaguar"],
                "volume": 0.6,
                "loop": True,
                "crossfade_duration": 4.0
            },
            # Degraded states
            "degraded_sparse": {
                "file": "soundscapes/sparse_forest_wind.mp3",
                "layers": ["wind_exposed", "few_birds", "silence_gaps"],
                "volume": 0.5,
                "loop": True,
                "crossfade_duration": 2.0
            },
            "degraded_edge": {
                "file": "soundscapes/forest_edge_machinery.mp3",
                "layers": ["chainsaw_distant", "truck_rumble", "stressed_birds"],
                "volume": 0.6,
                "loop": True,
                "crossfade_duration": 1.5
            },
            # Crisis states
            "active_burning": {
                "file": "soundscapes/forest_fire_crackle.mp3",
                "layers": ["fire_crackle", "falling_trees", "smoke_wind"],
                "volume": 0.85,
                "loop": True,
                "crossfade_duration": 1.0
            },
            "active_clearing": {
                "file": "soundscapes/logging_operation.mp3",
                "layers": ["chainsaw_close", "falling_timber", "machinery"],
                "volume": 0.8,
                "loop": True,
                "crossfade_duration": 1.2
            },
            "aftermath_silent": {
                "file": "soundscapes/deforested_silence.mp3",
                "layers": ["wind_barren", "rare_bird", "eerie_quiet"],
                "volume": 0.4,
                "loop": True,
                "crossfade_duration": 3.0
            },
            # Emotional moments
            "moment_revelation": {
                "file": "soundscapes/revelation_sting.mp3",
                "layers": ["bass_drone", "rising_tension"],
                "volume": 0.7,
                "loop": False,
                "crossfade_duration": 0.5
            },
            "moment_hope": {
                "file": "soundscapes/hope_restoration.mp3",
                "layers": ["gentle_piano", "returning_birds", "rain_gentle"],
                "volume": 0.65,
                "loop": True,
                "crossfade_duration": 2.0
            }
        }

    def _init_visual_filters(self):
        """Initialize visual filter presets for different environmental states"""
        self.visual_filters = {
            # Healthy states
            "pristine": {
                "saturation": 1.2,
                "brightness": 1.0,
                "contrast": 1.05,
                "haze_intensity": 0.1,
                "haze_color": "#e8f4e8",
                "vignette": 0.1,
                "color_grade": "lush_tropical",
                "particle_system": "light_spores"
            },
            "healthy_morning": {
                "saturation": 1.15,
                "brightness": 1.1,
                "contrast": 1.0,
                "haze_intensity": 0.25,
                "haze_color": "#fffde8",
                "vignette": 0.05,
                "color_grade": "golden_hour",
                "particle_system": "morning_mist"
            },
            # Stressed states
            "stressed": {
                "saturation": 0.9,
                "brightness": 0.95,
                "contrast": 1.1,
                "haze_intensity": 0.2,
                "haze_color": "#f5e6d3",
                "vignette": 0.2,
                "color_grade": "muted_warm",
                "particle_system": "dust_light"
            },
            "degraded": {
                "saturation": 0.7,
                "brightness": 0.9,
                "contrast": 1.15,
                "haze_intensity": 0.35,
                "haze_color": "#d4c4a8",
                "vignette": 0.3,
                "color_grade": "desaturated_brown",
                "particle_system": "dust_heavy"
            },
            # Crisis states
            "burning": {
                "saturation": 0.6,
                "brightness": 0.8,
                "contrast": 1.3,
                "haze_intensity": 0.7,
                "haze_color": "#8b4513",
                "vignette": 0.4,
                "color_grade": "fire_apocalypse",
                "particle_system": "ash_embers"
            },
            "smoke_heavy": {
                "saturation": 0.4,
                "brightness": 0.6,
                "contrast": 0.9,
                "haze_intensity": 0.85,
                "haze_color": "#666666",
                "vignette": 0.5,
                "color_grade": "gray_apocalypse",
                "particle_system": "thick_smoke"
            },
            "devastated": {
                "saturation": 0.3,
                "brightness": 0.75,
                "contrast": 1.2,
                "haze_intensity": 0.3,
                "haze_color": "#a89080",
                "vignette": 0.45,
                "color_grade": "bleached_death",
                "particle_system": "ash_settle"
            },
            # Temporal states
            "past_memory": {
                "saturation": 0.85,
                "brightness": 1.05,
                "contrast": 0.95,
                "haze_intensity": 0.15,
                "haze_color": "#ffe4c4",
                "vignette": 0.25,
                "color_grade": "sepia_memory",
                "particle_system": "light_spores",
                "film_grain": 0.1
            },
            "future_predicted": {
                "saturation": 0.8,
                "brightness": 0.85,
                "contrast": 1.1,
                "haze_intensity": 0.4,
                "haze_color": "#c0a080",
                "vignette": 0.35,
                "color_grade": "ominous_future",
                "particle_system": "digital_glitch",
                "chromatic_aberration": 0.02
            },
            # Hope/restoration
            "hope_dawn": {
                "saturation": 1.1,
                "brightness": 1.15,
                "contrast": 1.0,
                "haze_intensity": 0.2,
                "haze_color": "#fffaf0",
                "vignette": 0.1,
                "color_grade": "hopeful_warm",
                "particle_system": "pollen_light"
            }
        }

    def _init_tone_engine(self):
        """Initialize emotional tone templates based on severity levels"""
        self.tone_templates = {
            # Severity levels: calm (0-20), concerned (21-40), urgent (41-60), critical (61-80), crisis (81-100)
            "arrival": {
                "calm": "Welcome to {location_name}. {hectares:,} hectares of forest stand resilient here, a testament to nature's endurance.",
                "concerned": "You've arrived at {location_name}. {hectares:,} hectares of forest face mounting pressure from encroaching development.",
                "urgent": "Before you lies {location_name}. {hectares:,} hectares of irreplaceable forest are slipping away, one day at a time.",
                "critical": "You are witnessing {location_name}. {hectares:,} hectares of forest are in the balance—every moment counts.",
                "crisis": "This is {location_name}. What remains of {hectares:,} hectares is vanishing before our eyes. You are here as a witness."
            },
            "land": {
                "calm": "This thriving ecosystem stores {carbon_stock:,} tonnes of carbon—the equivalent of {car_equivalent:,} cars off the road for a year. A natural treasure.",
                "concerned": "Beneath this canopy, {carbon_stock:,} tonnes of carbon are locked away. That's {car_equivalent:,} cars worth of emissions—for now.",
                "urgent": "The carbon vault here holds {carbon_stock:,} tonnes. If released, it would equal {car_equivalent:,} cars driving for a year. The clock is ticking.",
                "critical": "{carbon_stock:,} tonnes of carbon are stored in these trees. When they fall, it's like putting {car_equivalent:,} cars back on the road. Permanently.",
                "crisis": "What took millennia to store—{carbon_stock:,} tonnes of carbon—is being released in months. {car_equivalent:,} cars' worth of destruction. Irreversible."
            },
            "species": {
                "calm": "{species_count} unique species call this forest home, including several found nowhere else on Earth. They thrive in harmony.",
                "concerned": "{species_count} species documented here are beginning to feel the pressure. Their ancient home is changing faster than they can adapt.",
                "urgent": "{species_count} species are at risk of losing their only home. Some have been here for millions of years. They have nowhere else to go.",
                "critical": "{species_count} species face extinction if this destruction continues. Their evolutionary journey—millions of years—could end in our lifetime.",
                "crisis": "{species_count} species are in their final stand. When this forest falls, they fall with it. Forever. We are witnessing the end of their story."
            },
            "happened": {
                "calm": "Satellite data shows this region remains largely intact. Current risk level: {risk_score}%.",
                "concerned": "Satellite imagery reveals early signs of encroachment. Risk level has climbed to {risk_score}%.",
                "urgent": "The satellite tells a stark story: deforestation is accelerating. Risk level: {risk_score}%. The pattern is unmistakable.",
                "critical": "What you're seeing took years to grow and weeks to destroy. Risk level: {risk_score}%. The damage is spreading.",
                "crisis": "The before and after are almost unrecognizable. Risk level: {risk_score}%. This is not a natural process. This is devastation."
            },
            "impact": {
                "calm": "Approximately {population:,} people live in harmony with this forest, drawing water, food, and livelihood from its abundance.",
                "concerned": "An estimated {population:,} people depend on this ecosystem. As the forest changes, so do their lives.",
                "urgent": "{population:,} people are watching their way of life disappear. Their water sources are drying. Their food forests are shrinking.",
                "critical": "{population:,} lives hang in the balance. When the forest goes, so does their water, their food, their medicine, their future.",
                "crisis": "{population:,} people face displacement. Generations of knowledge, culture, and community—erased along with the trees they call home."
            },
            "hope": {
                "calm": "With continued protection, this forest will thrive for generations. Small investments now yield massive returns.",
                "concerned": "An investment of ${restoration_cost_millions:.1f}M could secure this forest's future. Recovery could begin within {recovery_years} years.",
                "urgent": "There is still hope. ${restoration_cost_millions:.1f}M invested now could turn the tide. {recovery_years} years to see the first signs of recovery.",
                "critical": "The window is closing, but not closed. ${restoration_cost_millions:.1f}M and {recovery_years} years of commitment could save what remains.",
                "crisis": "Even now, even here—hope persists. ${restoration_cost_millions:.1f}M. {recovery_years} years. It's not too late. But it will be soon."
            }
        }

    def _init_chapter_templates(self):
        """Initialize chapter structure with full sensory and interaction config"""
        self.chapter_config = {
            "arrival": {
                "title": "Arrival",
                "camera_action": "flyTo",
                "duration_seconds": 12,
                "haptic_pattern": "gentle_pulse",
                "transition_in": "fade_from_black",
                "transition_out": "dissolve"
            },
            "land": {
                "title": "The Land",
                "camera_action": "orbit",
                "duration_seconds": 15,
                "haptic_pattern": "heartbeat_slow",
                "transition_in": "dissolve",
                "transition_out": "dissolve"
            },
            "species": {
                "title": "The Species",
                "camera_action": "hover_explore",
                "duration_seconds": 20,
                "haptic_pattern": "flutter",
                "transition_in": "dissolve",
                "transition_out": "dissolve"
            },
            "happened": {
                "title": "What Happened",
                "camera_action": "timelapse_orbit",
                "duration_seconds": 18,
                "haptic_pattern": "tension_build",
                "transition_in": "flash_white",
                "transition_out": "dissolve"
            },
            "impact": {
                "title": "The Impact",
                "camera_action": "pullback_reveal",
                "duration_seconds": 15,
                "haptic_pattern": "heavy_single",
                "transition_in": "dissolve",
                "transition_out": "dissolve"
            },
            "hope": {
                "title": "The Hope",
                "camera_action": "restoration_vision",
                "duration_seconds": 18,
                "haptic_pattern": "rising_pulse",
                "transition_in": "dissolve",
                "transition_out": "fade_to_white"
            }
        }

    def _init_narrator_system(self):
        """
        Initialize the AI narrator system with voice profiles, scripts, and delivery configs.
        The narrator is the guiding voice that explains what's happening in each scene.
        """
        # Narrator voice profiles - different emotional deliveries
        self.narrator_voices = {
            "david_attenborough": {
                "id": "narrator_david",
                "name": "The Observer",
                "description": "Calm, authoritative, documentary-style narration",
                "voiceId": "en-GB-Neural2-D",  # Google Cloud TTS
                "pitch": -2.0,
                "speakingRate": 0.92,
                "style": "documentary",
                "emotionalRange": ["wonder", "concern", "hope", "gravity"],
                "pauseTiming": "measured"
            },
            "passionate_advocate": {
                "id": "narrator_advocate",
                "name": "The Advocate",
                "description": "Passionate, urgent, emotionally engaged narration",
                "voiceId": "en-US-Neural2-J",
                "pitch": 0.0,
                "speakingRate": 1.05,
                "style": "passionate",
                "emotionalRange": ["urgency", "anger", "determination", "hope"],
                "pauseTiming": "emphatic"
            },
            "local_witness": {
                "id": "narrator_witness",
                "name": "The Witness",
                "description": "Personal, intimate, first-person perspective",
                "voiceId": "en-US-Neural2-A",
                "pitch": 1.0,
                "speakingRate": 0.95,
                "style": "intimate",
                "emotionalRange": ["sadness", "nostalgia", "resilience", "love"],
                "pauseTiming": "reflective"
            },
            "scientist": {
                "id": "narrator_scientist",
                "name": "The Scientist",
                "description": "Precise, factual, data-driven narration with gravitas",
                "voiceId": "en-US-Neural2-I",
                "pitch": -1.0,
                "speakingRate": 0.98,
                "style": "analytical",
                "emotionalRange": ["precision", "concern", "determination", "clarity"],
                "pauseTiming": "deliberate"
            }
        }

        # SSML markup templates for emphasis and pacing
        self.ssml_templates = {
            "pause_short": '<break time="300ms"/>',
            "pause_medium": '<break time="600ms"/>',
            "pause_long": '<break time="1200ms"/>',
            "pause_dramatic": '<break time="2000ms"/>',
            "emphasis_strong": '<emphasis level="strong">{text}</emphasis>',
            "emphasis_moderate": '<emphasis level="moderate">{text}</emphasis>',
            "slow_reveal": '<prosody rate="slow">{text}</prosody>',
            "whisper": '<prosody volume="soft" rate="slow">{text}</prosody>',
            "urgent": '<prosody rate="fast" pitch="+2st">{text}</prosody>',
            "solemn": '<prosody rate="slow" pitch="-2st">{text}</prosody>'
        }

        # Chapter-specific narrator scripts with timing cues
        self.narrator_scripts = {
            "arrival": {
                "calm": {
                    "script": [
                        {"text": "Welcome.", "timing": 0.0, "duration": 1.5, "style": "warm"},
                        {"text": "You are about to enter {location_name}.", "timing": 2.0, "duration": 3.0, "style": "inviting"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 5.0, "type": "pause"},
                        {"text": "Here, {hectares:,} hectares of ancient forest stand as they have for millennia.", "timing": 5.6, "duration": 4.5, "style": "reverent"},
                        {"text": "A living archive of evolution.", "timing": 10.5, "duration": 2.0, "style": "wonder"}
                    ],
                    "totalDuration": 12.5
                },
                "concerned": {
                    "script": [
                        {"text": "You've arrived.", "timing": 0.0, "duration": 1.5, "style": "measured"},
                        {"text": "This is {location_name}.", "timing": 2.0, "duration": 2.0, "style": "serious"},
                        {"text": "[PAUSE_SHORT]", "timing": 4.0, "type": "pause"},
                        {"text": "{hectares:,} hectares of forest", "timing": 4.3, "duration": 2.5, "style": "emphasis"},
                        {"text": "under mounting pressure.", "timing": 7.0, "duration": 2.0, "style": "concern"},
                        {"text": "What you're about to witness is both beautiful", "timing": 9.5, "duration": 3.0, "style": "measured"},
                        {"text": "and precarious.", "timing": 12.5, "duration": 1.5, "style": "gravity"}
                    ],
                    "totalDuration": 14.0
                },
                "urgent": {
                    "script": [
                        {"text": "Look around you.", "timing": 0.0, "duration": 1.5, "style": "direct"},
                        {"text": "This is {location_name}.", "timing": 2.0, "duration": 2.0, "style": "gravity"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 4.0, "type": "pause"},
                        {"text": "What remains of it.", "timing": 4.6, "duration": 2.0, "style": "solemn"},
                        {"text": "{hectares:,} hectares—", "timing": 7.0, "duration": 1.5, "style": "emphasis"},
                        {"text": "shrinking every day.", "timing": 8.5, "duration": 2.0, "style": "urgent"},
                        {"text": "[PAUSE_SHORT]", "timing": 10.5, "type": "pause"},
                        {"text": "Your witness matters now more than ever.", "timing": 11.0, "duration": 3.0, "style": "appeal"}
                    ],
                    "totalDuration": 14.0
                },
                "critical": {
                    "script": [
                        {"text": "Stop.", "timing": 0.0, "duration": 1.0, "style": "commanding"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 1.0, "type": "pause"},
                        {"text": "Take this in.", "timing": 1.6, "duration": 1.5, "style": "direct"},
                        {"text": "This is {location_name}—", "timing": 3.5, "duration": 2.0, "style": "gravity"},
                        {"text": "or what's left of it.", "timing": 5.5, "duration": 2.0, "style": "solemn"},
                        {"text": "[PAUSE_LONG]", "timing": 7.5, "type": "pause"},
                        {"text": "{hectares:,} hectares hanging by a thread.", "timing": 8.7, "duration": 3.5, "style": "emphasis"},
                        {"text": "Every moment counts.", "timing": 12.5, "duration": 2.0, "style": "urgent"}
                    ],
                    "totalDuration": 14.5
                },
                "crisis": {
                    "script": [
                        {"text": "[PAUSE_LONG]", "timing": 0.0, "type": "pause"},
                        {"text": "This was {location_name}.", "timing": 1.2, "duration": 2.5, "style": "solemn"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 3.7, "type": "pause"},
                        {"text": "What you see is what remains.", "timing": 4.3, "duration": 3.0, "style": "gravity"},
                        {"text": "{hectares:,} hectares.", "timing": 7.5, "duration": 2.0, "style": "whisper"},
                        {"text": "Vanishing before your eyes.", "timing": 9.5, "duration": 2.5, "style": "haunting"},
                        {"text": "[PAUSE_DRAMATIC]", "timing": 12.0, "type": "pause"},
                        {"text": "You are here as a witness.", "timing": 14.0, "duration": 2.5, "style": "solemn"},
                        {"text": "Remember what you see.", "timing": 16.5, "duration": 2.0, "style": "appeal"}
                    ],
                    "totalDuration": 18.5
                }
            },
            "land": {
                "calm": {
                    "script": [
                        {"text": "Beneath your feet, and all around you,", "timing": 0.0, "duration": 3.0, "style": "wonder"},
                        {"text": "this forest holds secrets older than human memory.", "timing": 3.5, "duration": 4.0, "style": "reverent"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 7.5, "type": "pause"},
                        {"text": "{carbon_stock:,} tonnes of carbon—", "timing": 8.1, "duration": 2.5, "style": "emphasis"},
                        {"text": "captured and stored over centuries.", "timing": 10.6, "duration": 2.5, "style": "measured"},
                        {"text": "That's equivalent to taking {car_equivalent:,} cars off the road.", "timing": 13.5, "duration": 4.0, "style": "illustration"},
                        {"text": "For an entire year.", "timing": 17.5, "duration": 2.0, "style": "emphasis"}
                    ],
                    "totalDuration": 19.5
                },
                "concerned": {
                    "script": [
                        {"text": "Look closer at this land.", "timing": 0.0, "duration": 2.0, "style": "inviting"},
                        {"text": "It's not just trees.", "timing": 2.5, "duration": 1.5, "style": "measured"},
                        {"text": "[PAUSE_SHORT]", "timing": 4.0, "type": "pause"},
                        {"text": "It's a carbon vault.", "timing": 4.3, "duration": 2.0, "style": "emphasis"},
                        {"text": "{carbon_stock:,} tonnes locked away,", "timing": 6.5, "duration": 3.0, "style": "measured"},
                        {"text": "keeping our atmosphere in balance.", "timing": 9.5, "duration": 2.5, "style": "concern"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 12.0, "type": "pause"},
                        {"text": "{car_equivalent:,} cars' worth of carbon.", "timing": 12.6, "duration": 3.0, "style": "gravity"},
                        {"text": "For now, it stays in the trees.", "timing": 16.0, "duration": 2.5, "style": "concern"},
                        {"text": "For now.", "timing": 18.5, "duration": 1.5, "style": "warning"}
                    ],
                    "totalDuration": 20.0
                },
                "urgent": {
                    "script": [
                        {"text": "Every tree you see is a carbon bank.", "timing": 0.0, "duration": 3.0, "style": "direct"},
                        {"text": "[PAUSE_SHORT]", "timing": 3.0, "type": "pause"},
                        {"text": "{carbon_stock:,} tonnes of carbon,", "timing": 3.3, "duration": 2.5, "style": "emphasis"},
                        {"text": "centuries in the making.", "timing": 6.0, "duration": 2.0, "style": "measured"},
                        {"text": "When a tree falls,", "timing": 8.5, "duration": 1.5, "style": "gravity"},
                        {"text": "that carbon releases—immediately.", "timing": 10.0, "duration": 2.5, "style": "urgent"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 12.5, "type": "pause"},
                        {"text": "Like putting {car_equivalent:,} cars back on the road.", "timing": 13.1, "duration": 3.5, "style": "illustration"},
                        {"text": "The math is simple.", "timing": 17.0, "duration": 1.5, "style": "direct"},
                        {"text": "The stakes are not.", "timing": 18.5, "duration": 2.0, "style": "gravity"}
                    ],
                    "totalDuration": 20.5
                },
                "critical": {
                    "script": [
                        {"text": "What took centuries to build", "timing": 0.0, "duration": 2.5, "style": "solemn"},
                        {"text": "can be destroyed in hours.", "timing": 2.5, "duration": 2.0, "style": "gravity"},
                        {"text": "[PAUSE_LONG]", "timing": 4.5, "type": "pause"},
                        {"text": "{carbon_stock:,} tonnes of carbon.", "timing": 5.7, "duration": 3.0, "style": "emphasis"},
                        {"text": "The equivalent of {car_equivalent:,} cars.", "timing": 9.0, "duration": 3.0, "style": "measured"},
                        {"text": "Driving.", "timing": 12.0, "duration": 0.8, "style": "staccato"},
                        {"text": "For a year.", "timing": 13.0, "duration": 1.2, "style": "staccato"},
                        {"text": "Every year.", "timing": 14.2, "duration": 1.2, "style": "staccato"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 15.4, "type": "pause"},
                        {"text": "Once it's in the atmosphere,", "timing": 16.0, "duration": 2.5, "style": "solemn"},
                        {"text": "it doesn't come back.", "timing": 18.5, "duration": 2.0, "style": "finality"}
                    ],
                    "totalDuration": 20.5
                },
                "crisis": {
                    "script": [
                        {"text": "[PAUSE_MEDIUM]", "timing": 0.0, "type": "pause"},
                        {"text": "You're standing in what was once a carbon fortress.", "timing": 0.6, "duration": 4.0, "style": "solemn"},
                        {"text": "[PAUSE_LONG]", "timing": 4.6, "type": "pause"},
                        {"text": "The walls are falling.", "timing": 5.8, "duration": 2.5, "style": "gravity"},
                        {"text": "{carbon_stock:,} tonnes.", "timing": 8.5, "duration": 2.0, "style": "whisper"},
                        {"text": "Rising into the sky.", "timing": 10.5, "duration": 2.0, "style": "haunting"},
                        {"text": "Becoming the air your grandchildren will breathe.", "timing": 13.0, "duration": 4.0, "style": "solemn"},
                        {"text": "[PAUSE_DRAMATIC]", "timing": 17.0, "type": "pause"},
                        {"text": "{car_equivalent:,} cars.", "timing": 19.0, "duration": 2.0, "style": "finality"},
                        {"text": "Forever.", "timing": 21.0, "duration": 2.0, "style": "haunting"}
                    ],
                    "totalDuration": 23.0
                }
            },
            "species": {
                "calm": {
                    "script": [
                        {"text": "Listen.", "timing": 0.0, "duration": 1.0, "style": "inviting"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 1.0, "type": "pause"},
                        {"text": "That call you hear?", "timing": 1.6, "duration": 2.0, "style": "wonder"},
                        {"text": "It's been echoing through these trees for millions of years.", "timing": 4.0, "duration": 4.0, "style": "reverent"},
                        {"text": "[PAUSE_SHORT]", "timing": 8.0, "type": "pause"},
                        {"text": "{species_count} unique species make their home here.", "timing": 8.3, "duration": 3.5, "style": "measured"},
                        {"text": "Some found nowhere else on Earth.", "timing": 12.0, "duration": 3.0, "style": "emphasis"},
                        {"text": "They evolved here.", "timing": 15.5, "duration": 2.0, "style": "wonder"},
                        {"text": "They belong here.", "timing": 17.5, "duration": 2.0, "style": "reverent"}
                    ],
                    "totalDuration": 19.5
                },
                "concerned": {
                    "script": [
                        {"text": "Around you,", "timing": 0.0, "duration": 1.5, "style": "measured"},
                        {"text": "life is adapting.", "timing": 1.5, "duration": 1.5, "style": "concern"},
                        {"text": "[PAUSE_SHORT]", "timing": 3.0, "type": "pause"},
                        {"text": "Or trying to.", "timing": 3.3, "duration": 1.5, "style": "gravity"},
                        {"text": "{species_count} documented species call this home.", "timing": 5.0, "duration": 3.5, "style": "measured"},
                        {"text": "Their ancient rhythms are changing.", "timing": 9.0, "duration": 3.0, "style": "concern"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 12.0, "type": "pause"},
                        {"text": "Faster than evolution can follow.", "timing": 12.6, "duration": 3.0, "style": "gravity"},
                        {"text": "This isn't natural selection.", "timing": 16.0, "duration": 2.5, "style": "direct"},
                        {"text": "This is something else entirely.", "timing": 18.5, "duration": 2.5, "style": "warning"}
                    ],
                    "totalDuration": 21.0
                },
                "urgent": {
                    "script": [
                        {"text": "Pay attention.", "timing": 0.0, "duration": 1.5, "style": "direct"},
                        {"text": "What you're seeing may not exist in a decade.", "timing": 2.0, "duration": 3.5, "style": "urgent"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 5.5, "type": "pause"},
                        {"text": "{species_count} species.", "timing": 6.1, "duration": 2.0, "style": "emphasis"},
                        {"text": "Millions of years of evolution.", "timing": 8.5, "duration": 2.5, "style": "gravity"},
                        {"text": "Reduced to numbers in a database.", "timing": 11.0, "duration": 3.0, "style": "solemn"},
                        {"text": "[PAUSE_SHORT]", "timing": 14.0, "type": "pause"},
                        {"text": "They're running out of options.", "timing": 14.3, "duration": 2.5, "style": "urgent"},
                        {"text": "And running out of time.", "timing": 17.0, "duration": 2.5, "style": "finality"}
                    ],
                    "totalDuration": 19.5
                },
                "critical": {
                    "script": [
                        {"text": "These are the last of their kind.", "timing": 0.0, "duration": 3.0, "style": "solemn"},
                        {"text": "[PAUSE_LONG]", "timing": 3.0, "type": "pause"},
                        {"text": "{species_count} species.", "timing": 4.2, "duration": 2.0, "style": "whisper"},
                        {"text": "Facing extinction.", "timing": 6.5, "duration": 2.0, "style": "gravity"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 8.5, "type": "pause"},
                        {"text": "Their ancestors survived ice ages.", "timing": 9.1, "duration": 3.0, "style": "measured"},
                        {"text": "Meteor impacts.", "timing": 12.5, "duration": 1.5, "style": "emphasis"},
                        {"text": "Continental drift.", "timing": 14.0, "duration": 1.5, "style": "emphasis"},
                        {"text": "[PAUSE_SHORT]", "timing": 15.5, "type": "pause"},
                        {"text": "They may not survive us.", "timing": 15.8, "duration": 3.0, "style": "haunting"}
                    ],
                    "totalDuration": 18.8
                },
                "crisis": {
                    "script": [
                        {"text": "[PAUSE_DRAMATIC]", "timing": 0.0, "type": "pause"},
                        {"text": "Silence.", "timing": 2.0, "duration": 1.5, "style": "whisper"},
                        {"text": "[PAUSE_LONG]", "timing": 3.5, "type": "pause"},
                        {"text": "Where there once was a symphony,", "timing": 4.7, "duration": 3.0, "style": "solemn"},
                        {"text": "there is now silence.", "timing": 8.0, "duration": 2.5, "style": "haunting"},
                        {"text": "{species_count} species.", "timing": 11.0, "duration": 2.0, "style": "gravity"},
                        {"text": "Some you've never heard of.", "timing": 13.5, "duration": 2.5, "style": "measured"},
                        {"text": "Now you never will.", "timing": 16.0, "duration": 2.5, "style": "finality"},
                        {"text": "[PAUSE_DRAMATIC]", "timing": 18.5, "type": "pause"},
                        {"text": "Extinction is forever.", "timing": 20.5, "duration": 2.5, "style": "solemn"}
                    ],
                    "totalDuration": 23.0
                }
            },
            "happened": {
                "calm": {
                    "script": [
                        {"text": "Change comes slowly to forests.", "timing": 0.0, "duration": 3.0, "style": "measured"},
                        {"text": "Or it used to.", "timing": 3.5, "duration": 1.5, "style": "concern"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 5.0, "type": "pause"},
                        {"text": "Our satellites have been watching.", "timing": 5.6, "duration": 2.5, "style": "direct"},
                        {"text": "Current risk level: {risk_score}%.", "timing": 8.5, "duration": 3.0, "style": "measured"},
                        {"text": "[PAUSE_SHORT]", "timing": 11.5, "type": "pause"},
                        {"text": "Low, for now.", "timing": 11.8, "duration": 2.0, "style": "cautious"},
                        {"text": "But borders are moving closer.", "timing": 14.0, "duration": 2.5, "style": "warning"}
                    ],
                    "totalDuration": 16.5
                },
                "concerned": {
                    "script": [
                        {"text": "The satellites don't lie.", "timing": 0.0, "duration": 2.5, "style": "direct"},
                        {"text": "[PAUSE_SHORT]", "timing": 2.5, "type": "pause"},
                        {"text": "Week after week, the images arrive.", "timing": 2.8, "duration": 3.0, "style": "measured"},
                        {"text": "And week after week,", "timing": 6.0, "duration": 2.0, "style": "building"},
                        {"text": "the green fades.", "timing": 8.0, "duration": 2.0, "style": "gravity"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 10.0, "type": "pause"},
                        {"text": "Risk level: {risk_score}%.", "timing": 10.6, "duration": 2.5, "style": "emphasis"},
                        {"text": "And rising.", "timing": 13.5, "duration": 1.5, "style": "warning"}
                    ],
                    "totalDuration": 15.0
                },
                "urgent": {
                    "script": [
                        {"text": "Watch.", "timing": 0.0, "duration": 1.0, "style": "commanding"},
                        {"text": "[PAUSE_SHORT]", "timing": 1.0, "type": "pause"},
                        {"text": "This is what happened.", "timing": 1.3, "duration": 2.0, "style": "gravity"},
                        {"text": "Year after year.", "timing": 3.5, "duration": 1.5, "style": "measured"},
                        {"text": "Cut after cut.", "timing": 5.0, "duration": 1.5, "style": "staccato"},
                        {"text": "Fire after fire.", "timing": 6.5, "duration": 1.5, "style": "staccato"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 8.0, "type": "pause"},
                        {"text": "The pattern is unmistakable.", "timing": 8.6, "duration": 2.5, "style": "direct"},
                        {"text": "Risk level: {risk_score}%.", "timing": 11.5, "duration": 2.5, "style": "emphasis"},
                        {"text": "This is not natural.", "timing": 14.5, "duration": 2.0, "style": "gravity"},
                        {"text": "This is a choice.", "timing": 16.5, "duration": 2.0, "style": "accusation"}
                    ],
                    "totalDuration": 18.5
                },
                "critical": {
                    "script": [
                        {"text": "Before.", "timing": 0.0, "duration": 1.5, "style": "measured"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 1.5, "type": "pause"},
                        {"text": "After.", "timing": 2.1, "duration": 1.5, "style": "gravity"},
                        {"text": "[PAUSE_LONG]", "timing": 3.6, "type": "pause"},
                        {"text": "This took years to grow.", "timing": 4.8, "duration": 2.5, "style": "solemn"},
                        {"text": "Weeks to destroy.", "timing": 7.5, "duration": 2.0, "style": "emphasis"},
                        {"text": "[PAUSE_SHORT]", "timing": 9.5, "type": "pause"},
                        {"text": "Risk level: {risk_score}%.", "timing": 9.8, "duration": 2.5, "style": "measured"},
                        {"text": "The damage is spreading.", "timing": 12.5, "duration": 2.5, "style": "urgent"},
                        {"text": "Like an infection.", "timing": 15.0, "duration": 2.0, "style": "gravity"},
                        {"text": "And we know who's responsible.", "timing": 17.5, "duration": 2.5, "style": "accusation"}
                    ],
                    "totalDuration": 20.0
                },
                "crisis": {
                    "script": [
                        {"text": "[PAUSE_DRAMATIC]", "timing": 0.0, "type": "pause"},
                        {"text": "This was a forest.", "timing": 2.0, "duration": 2.5, "style": "whisper"},
                        {"text": "[PAUSE_LONG]", "timing": 4.5, "type": "pause"},
                        {"text": "Before and after are almost unrecognizable.", "timing": 5.7, "duration": 4.0, "style": "solemn"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 9.7, "type": "pause"},
                        {"text": "Risk level: {risk_score}%.", "timing": 10.3, "duration": 2.5, "style": "finality"},
                        {"text": "Maximum.", "timing": 13.0, "duration": 1.5, "style": "gravity"},
                        {"text": "[PAUSE_SHORT]", "timing": 14.5, "type": "pause"},
                        {"text": "This is not an environmental issue.", "timing": 14.8, "duration": 3.0, "style": "direct"},
                        {"text": "This is devastation.", "timing": 18.0, "duration": 2.5, "style": "haunting"},
                        {"text": "This is loss.", "timing": 20.5, "duration": 2.0, "style": "solemn"},
                        {"text": "This is now.", "timing": 22.5, "duration": 2.0, "style": "urgent"}
                    ],
                    "totalDuration": 24.5
                }
            },
            "impact": {
                "calm": {
                    "script": [
                        {"text": "People live here.", "timing": 0.0, "duration": 2.0, "style": "measured"},
                        {"text": "Not beside the forest.", "timing": 2.5, "duration": 2.0, "style": "emphasis"},
                        {"text": "Within it.", "timing": 4.5, "duration": 1.5, "style": "reverent"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 6.0, "type": "pause"},
                        {"text": "Approximately {population:,} people.", "timing": 6.6, "duration": 3.0, "style": "measured"},
                        {"text": "Drawing water from these rivers.", "timing": 10.0, "duration": 2.5, "style": "illustration"},
                        {"text": "Medicine from these plants.", "timing": 12.5, "duration": 2.5, "style": "illustration"},
                        {"text": "Life from this land.", "timing": 15.0, "duration": 2.0, "style": "reverent"}
                    ],
                    "totalDuration": 17.0
                },
                "concerned": {
                    "script": [
                        {"text": "For the {population:,} people who call this home,", "timing": 0.0, "duration": 3.5, "style": "measured"},
                        {"text": "the forest isn't scenery.", "timing": 4.0, "duration": 2.0, "style": "direct"},
                        {"text": "It's survival.", "timing": 6.0, "duration": 1.5, "style": "gravity"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 7.5, "type": "pause"},
                        {"text": "Their water comes from these streams.", "timing": 8.1, "duration": 2.5, "style": "measured"},
                        {"text": "Their food grows in this soil.", "timing": 11.0, "duration": 2.5, "style": "measured"},
                        {"text": "[PAUSE_SHORT]", "timing": 13.5, "type": "pause"},
                        {"text": "As the forest changes,", "timing": 13.8, "duration": 2.0, "style": "concern"},
                        {"text": "so do their lives.", "timing": 16.0, "duration": 2.0, "style": "gravity"}
                    ],
                    "totalDuration": 18.0
                },
                "urgent": {
                    "script": [
                        {"text": "{population:,} people are watching their way of life disappear.", "timing": 0.0, "duration": 4.0, "style": "urgent"},
                        {"text": "[PAUSE_SHORT]", "timing": 4.0, "type": "pause"},
                        {"text": "The streams that gave them water?", "timing": 4.3, "duration": 2.5, "style": "direct"},
                        {"text": "Drying.", "timing": 7.0, "duration": 1.0, "style": "staccato"},
                        {"text": "The forests that gave them food?", "timing": 8.0, "duration": 2.5, "style": "direct"},
                        {"text": "Shrinking.", "timing": 10.5, "duration": 1.0, "style": "staccato"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 11.5, "type": "pause"},
                        {"text": "Generation after generation lived in balance with this land.", "timing": 12.1, "duration": 4.0, "style": "measured"},
                        {"text": "That balance is breaking.", "timing": 16.5, "duration": 2.5, "style": "gravity"}
                    ],
                    "totalDuration": 19.0
                },
                "critical": {
                    "script": [
                        {"text": "{population:,} lives hang in the balance.", "timing": 0.0, "duration": 3.5, "style": "gravity"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 3.5, "type": "pause"},
                        {"text": "When the forest goes,", "timing": 4.1, "duration": 2.0, "style": "measured"},
                        {"text": "so does their water.", "timing": 6.1, "duration": 1.5, "style": "staccato"},
                        {"text": "Their food.", "timing": 7.8, "duration": 1.0, "style": "staccato"},
                        {"text": "Their medicine.", "timing": 8.8, "duration": 1.0, "style": "staccato"},
                        {"text": "Their future.", "timing": 10.0, "duration": 1.5, "style": "finality"},
                        {"text": "[PAUSE_LONG]", "timing": 11.5, "type": "pause"},
                        {"text": "This isn't about trees.", "timing": 12.7, "duration": 2.5, "style": "direct"},
                        {"text": "This is about people.", "timing": 15.5, "duration": 2.5, "style": "emphasis"},
                        {"text": "Real people.", "timing": 18.0, "duration": 1.5, "style": "gravity"},
                        {"text": "Losing everything.", "timing": 19.5, "duration": 2.0, "style": "solemn"}
                    ],
                    "totalDuration": 21.5
                },
                "crisis": {
                    "script": [
                        {"text": "[PAUSE_LONG]", "timing": 0.0, "type": "pause"},
                        {"text": "{population:,} people.", "timing": 1.2, "duration": 2.0, "style": "whisper"},
                        {"text": "Facing displacement.", "timing": 3.5, "duration": 2.0, "style": "gravity"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 5.5, "type": "pause"},
                        {"text": "Generations of knowledge.", "timing": 6.1, "duration": 2.5, "style": "solemn"},
                        {"text": "Traditions.", "timing": 9.0, "duration": 1.5, "style": "measured"},
                        {"text": "Stories.", "timing": 10.5, "duration": 1.5, "style": "measured"},
                        {"text": "Erased.", "timing": 12.0, "duration": 1.5, "style": "finality"},
                        {"text": "[PAUSE_DRAMATIC]", "timing": 13.5, "type": "pause"},
                        {"text": "Along with the trees they call home.", "timing": 15.5, "duration": 3.5, "style": "haunting"},
                        {"text": "[PAUSE_LONG]", "timing": 19.0, "type": "pause"},
                        {"text": "Where will they go?", "timing": 20.2, "duration": 2.5, "style": "appeal"}
                    ],
                    "totalDuration": 22.7
                }
            },
            "hope": {
                "calm": {
                    "script": [
                        {"text": "There is good news.", "timing": 0.0, "duration": 2.0, "style": "warm"},
                        {"text": "[PAUSE_SHORT]", "timing": 2.0, "type": "pause"},
                        {"text": "This forest can be protected.", "timing": 2.3, "duration": 2.5, "style": "hopeful"},
                        {"text": "With continued care, it will thrive for generations.", "timing": 5.0, "duration": 3.5, "style": "measured"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 8.5, "type": "pause"},
                        {"text": "Small investments now yield massive returns.", "timing": 9.1, "duration": 3.5, "style": "emphasis"},
                        {"text": "In carbon.", "timing": 13.0, "duration": 1.0, "style": "measured"},
                        {"text": "In biodiversity.", "timing": 14.0, "duration": 1.5, "style": "measured"},
                        {"text": "In life.", "timing": 15.5, "duration": 1.5, "style": "hopeful"}
                    ],
                    "totalDuration": 17.0
                },
                "concerned": {
                    "script": [
                        {"text": "Here's what we know.", "timing": 0.0, "duration": 2.0, "style": "direct"},
                        {"text": "[PAUSE_SHORT]", "timing": 2.0, "type": "pause"},
                        {"text": "An investment of ${restoration_cost_millions:.1f} million", "timing": 2.3, "duration": 3.0, "style": "measured"},
                        {"text": "could secure this forest's future.", "timing": 5.5, "duration": 2.5, "style": "hopeful"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 8.0, "type": "pause"},
                        {"text": "Within {recovery_years} years,", "timing": 8.6, "duration": 2.0, "style": "measured"},
                        {"text": "we could see the first signs of recovery.", "timing": 10.6, "duration": 3.0, "style": "hope"},
                        {"text": "[PAUSE_SHORT]", "timing": 13.6, "type": "pause"},
                        {"text": "The question isn't whether it's possible.", "timing": 14.0, "duration": 3.0, "style": "direct"},
                        {"text": "It's whether we choose to act.", "timing": 17.0, "duration": 2.5, "style": "appeal"}
                    ],
                    "totalDuration": 19.5
                },
                "urgent": {
                    "script": [
                        {"text": "Listen carefully.", "timing": 0.0, "duration": 1.5, "style": "direct"},
                        {"text": "There is still hope.", "timing": 2.0, "duration": 2.0, "style": "emphasis"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 4.0, "type": "pause"},
                        {"text": "${restoration_cost_millions:.1f} million invested now", "timing": 4.6, "duration": 3.0, "style": "measured"},
                        {"text": "could turn the tide.", "timing": 8.0, "duration": 2.0, "style": "hopeful"},
                        {"text": "[PAUSE_SHORT]", "timing": 10.0, "type": "pause"},
                        {"text": "{recovery_years} years to see the first green shoots of recovery.", "timing": 10.3, "duration": 4.0, "style": "measured"},
                        {"text": "But only if we start now.", "timing": 15.0, "duration": 2.5, "style": "urgent"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 17.5, "type": "pause"},
                        {"text": "Not tomorrow.", "timing": 18.1, "duration": 1.5, "style": "emphasis"},
                        {"text": "Now.", "timing": 19.6, "duration": 1.5, "style": "commanding"}
                    ],
                    "totalDuration": 21.1
                },
                "critical": {
                    "script": [
                        {"text": "The window is closing.", "timing": 0.0, "duration": 2.5, "style": "gravity"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 2.5, "type": "pause"},
                        {"text": "But not closed.", "timing": 3.1, "duration": 2.0, "style": "hope"},
                        {"text": "[PAUSE_SHORT]", "timing": 5.1, "type": "pause"},
                        {"text": "${restoration_cost_millions:.1f} million.", "timing": 5.4, "duration": 2.0, "style": "measured"},
                        {"text": "{recovery_years} years of commitment.", "timing": 7.5, "duration": 2.5, "style": "measured"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 10.0, "type": "pause"},
                        {"text": "That's what it takes to save what remains.", "timing": 10.6, "duration": 3.5, "style": "direct"},
                        {"text": "[PAUSE_SHORT]", "timing": 14.1, "type": "pause"},
                        {"text": "The choice is ours.", "timing": 14.4, "duration": 2.0, "style": "gravity"},
                        {"text": "The moment is now.", "timing": 16.5, "duration": 2.0, "style": "urgent"},
                        {"text": "And time is running out.", "timing": 18.5, "duration": 2.5, "style": "appeal"}
                    ],
                    "totalDuration": 21.0
                },
                "crisis": {
                    "script": [
                        {"text": "[PAUSE_DRAMATIC]", "timing": 0.0, "type": "pause"},
                        {"text": "Even now.", "timing": 2.0, "duration": 1.5, "style": "whisper"},
                        {"text": "Even here.", "timing": 3.5, "duration": 1.5, "style": "whisper"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 5.0, "type": "pause"},
                        {"text": "Hope persists.", "timing": 5.6, "duration": 2.0, "style": "hope"},
                        {"text": "[PAUSE_LONG]", "timing": 7.6, "type": "pause"},
                        {"text": "${restoration_cost_millions:.1f} million.", "timing": 8.8, "duration": 2.0, "style": "measured"},
                        {"text": "{recovery_years} years.", "timing": 11.0, "duration": 1.5, "style": "measured"},
                        {"text": "[PAUSE_SHORT]", "timing": 12.5, "type": "pause"},
                        {"text": "It's not too late.", "timing": 12.8, "duration": 2.5, "style": "hope"},
                        {"text": "[PAUSE_MEDIUM]", "timing": 15.3, "type": "pause"},
                        {"text": "But it will be.", "timing": 15.9, "duration": 2.0, "style": "gravity"},
                        {"text": "Soon.", "timing": 18.0, "duration": 1.5, "style": "warning"},
                        {"text": "[PAUSE_DRAMATIC]", "timing": 19.5, "type": "pause"},
                        {"text": "What will you do with what you've witnessed?", "timing": 21.5, "duration": 3.5, "style": "appeal"}
                    ],
                    "totalDuration": 25.0
                }
            }
        }

        # Pronunciation guide for difficult location names
        self.pronunciation_guide = {
            "Xingu": "shin-GOO",
            "Yanomami": "yah-noh-MAH-mee",
            "Kayapó": "kai-ah-POH",
            "Cerrado": "seh-RAH-doo",
            "Pantanal": "pan-tah-NAHL",
            "Borneo": "BOR-nee-oh",
            "Sumatra": "soo-MAH-trah",
            "Kalimantan": "kah-lee-MAHN-tahn",
            "Papua": "PAH-poo-ah",
            "Madagascar": "mad-ah-GAS-kar",
            "Congolese": "kahn-goh-LEEZ"
        }

    def _init_discovery_system(self):
        """
        Initialize the Discovery & Exploration system with secrets, achievements,
        and non-linear exploration paths that reward curiosity.
        """
        # Discoverable secrets hidden throughout the experience
        self.secrets = {
            "hidden_species": {
                "id": "secret_hidden_species",
                "name": "The Unseen",
                "description": "Discover a species so rare, it's never been filmed",
                "rarity": "legendary",
                "triggerCondition": "gaze_at_dark_corner_30s",
                "reward": {
                    "badge": "badges/the_unseen.png",
                    "title": "Biodiversity Detective",
                    "unlocks": "night_vision_mode"
                },
                "occurrence": 0.05  # 5% of locations have this
            },
            "ancient_tree": {
                "id": "secret_ancient_tree",
                "name": "The Elder",
                "description": "Find a tree older than human civilization",
                "rarity": "epic",
                "triggerCondition": "gaze_at_largest_tree_20s",
                "reward": {
                    "badge": "badges/the_elder.png",
                    "title": "Ancient Witness",
                    "unlocks": "tree_ring_visualization"
                },
                "occurrence": 0.15
            },
            "water_source": {
                "id": "secret_water_source",
                "name": "The Spring",
                "description": "Discover the hidden spring that feeds this forest",
                "rarity": "rare",
                "triggerCondition": "follow_water_sound_to_source",
                "reward": {
                    "badge": "badges/the_spring.png",
                    "title": "Water Finder",
                    "unlocks": "hydrology_overlay"
                },
                "occurrence": 0.25
            },
            "sunrise_moment": {
                "id": "secret_sunrise",
                "name": "First Light",
                "description": "Witness the exact moment of sunrise in the forest",
                "rarity": "epic",
                "triggerCondition": "be_present_at_sunrise",
                "reward": {
                    "badge": "badges/first_light.png",
                    "title": "Dawn Watcher",
                    "unlocks": "golden_hour_mode"
                },
                "occurrence": 0.10  # Depends on local time
            },
            "full_story": {
                "id": "secret_full_story",
                "name": "The Complete Picture",
                "description": "Experience every chapter and interaction",
                "rarity": "common",
                "triggerCondition": "complete_all_chapters_and_interactions",
                "reward": {
                    "badge": "badges/complete_picture.png",
                    "title": "True Witness",
                    "unlocks": "director_commentary"
                },
                "occurrence": 1.0  # Always available
            },
            "species_collector": {
                "id": "secret_collector",
                "name": "Field Researcher",
                "description": "Discover and catalog all species in this location",
                "rarity": "rare",
                "triggerCondition": "view_all_species_pois",
                "reward": {
                    "badge": "badges/field_researcher.png",
                    "title": "Field Researcher",
                    "unlocks": "scientific_data_mode"
                },
                "occurrence": 1.0
            },
            "time_traveler": {
                "id": "secret_time_traveler",
                "name": "Temporal Explorer",
                "description": "Visit all time periods in the temporal slider",
                "rarity": "common",
                "triggerCondition": "visit_all_temporal_states",
                "reward": {
                    "badge": "badges/time_traveler.png",
                    "title": "Time Traveler",
                    "unlocks": "custom_time_period"
                },
                "occurrence": 1.0
            },
            "silent_witness": {
                "id": "secret_silent",
                "name": "Silent Witness",
                "description": "Spend 5 minutes in complete stillness, just observing",
                "rarity": "epic",
                "triggerCondition": "no_interaction_5_minutes",
                "reward": {
                    "badge": "badges/silent_witness.png",
                    "title": "Silent Witness",
                    "unlocks": "meditation_mode"
                },
                "occurrence": 1.0
            }
        }

        # Achievement categories
        self.achievements = {
            "explorer": {
                "name": "Explorer",
                "levels": [
                    {"name": "Curious", "threshold": 1, "badge": "explorer_1"},
                    {"name": "Adventurer", "threshold": 5, "badge": "explorer_2"},
                    {"name": "Pathfinder", "threshold": 15, "badge": "explorer_3"},
                    {"name": "Trailblazer", "threshold": 30, "badge": "explorer_4"},
                    {"name": "Legend", "threshold": 50, "badge": "explorer_5"}
                ],
                "metric": "locations_visited"
            },
            "species_spotter": {
                "name": "Species Spotter",
                "levels": [
                    {"name": "Novice", "threshold": 5, "badge": "spotter_1"},
                    {"name": "Observer", "threshold": 25, "badge": "spotter_2"},
                    {"name": "Naturalist", "threshold": 75, "badge": "spotter_3"},
                    {"name": "Expert", "threshold": 150, "badge": "spotter_4"},
                    {"name": "Master", "threshold": 300, "badge": "spotter_5"}
                ],
                "metric": "species_discovered"
            },
            "time_witness": {
                "name": "Time Witness",
                "levels": [
                    {"name": "Observer", "threshold": 10, "badge": "time_1"},
                    {"name": "Historian", "threshold": 30, "badge": "time_2"},
                    {"name": "Chronicler", "threshold": 60, "badge": "time_3"},
                    {"name": "Archivist", "threshold": 100, "badge": "time_4"}
                ],
                "metric": "temporal_transitions"
            },
            "action_taker": {
                "name": "Action Taker",
                "levels": [
                    {"name": "Aware", "threshold": 1, "badge": "action_1"},
                    {"name": "Engaged", "threshold": 3, "badge": "action_2"},
                    {"name": "Advocate", "threshold": 10, "badge": "action_3"},
                    {"name": "Champion", "threshold": 25, "badge": "action_4"}
                ],
                "metric": "actions_taken"
            }
        }

        # Easter eggs - delightful surprises
        self.easter_eggs = {
            "look_up": {
                "trigger": "look_straight_up_10s",
                "response": "A shooting star streaks across the canopy gap",
                "effect": "particle_shooting_star",
                "soundEffect": "sounds/magical/shooting_star.mp3"
            },
            "rain_dance": {
                "trigger": "spin_360_three_times",
                "response": "Gentle rain begins to fall",
                "effect": "weather_light_rain",
                "soundEffect": "sounds/nature/rain_start.mp3"
            },
            "bird_call": {
                "trigger": "make_whistle_sound",
                "response": "A bird responds to your call",
                "effect": "bird_flyby",
                "soundEffect": "sounds/animals/bird_response.mp3"
            },
            "butterfly_effect": {
                "trigger": "remain_perfectly_still_60s",
                "response": "A butterfly lands on your virtual hand",
                "effect": "butterfly_landing",
                "soundEffect": "sounds/nature/wing_flutter.mp3"
            }
        }

        # Exploration paths - different ways to experience the story
        self.exploration_paths = {
            "scientist": {
                "name": "The Researcher's Path",
                "description": "Focus on data, statistics, and scientific analysis",
                "emphasis": ["land", "happened"],
                "style": "analytical",
                "narrator": "scientist",
                "unlocks_at_level": 1
            },
            "storyteller": {
                "name": "The Storyteller's Path",
                "description": "Focus on narrative, emotion, and human connection",
                "emphasis": ["arrival", "impact", "hope"],
                "style": "emotional",
                "narrator": "passionate_advocate",
                "unlocks_at_level": 1
            },
            "naturalist": {
                "name": "The Naturalist's Path",
                "description": "Focus on species, ecosystems, and biodiversity",
                "emphasis": ["species"],
                "style": "documentary",
                "narrator": "david_attenborough",
                "unlocks_at_level": 5
            },
            "free_explorer": {
                "name": "Free Exploration",
                "description": "No guidance—discover at your own pace",
                "emphasis": [],
                "style": "minimal",
                "narrator": None,
                "unlocks_at_level": 10
            }
        }

    def _init_musical_journey(self):
        """
        Initialize the generative emotional soundtrack system.
        Music that adapts to location, emotion, and user interactions.
        """
        # Musical themes and motifs
        self.musical_themes = {
            "main_theme": {
                "name": "Earth's Breath",
                "baseTrack": "music/themes/earths_breath.mp3",
                "bpm": 60,
                "key": "Am",
                "mood": "contemplative",
                "instruments": ["strings", "woodwinds", "ambient_pads"]
            },
            "hope_theme": {
                "name": "Rising Light",
                "baseTrack": "music/themes/rising_light.mp3",
                "bpm": 72,
                "key": "C",
                "mood": "hopeful",
                "instruments": ["piano", "strings", "choir"]
            },
            "danger_theme": {
                "name": "Falling Shadows",
                "baseTrack": "music/themes/falling_shadows.mp3",
                "bpm": 80,
                "key": "Dm",
                "mood": "tense",
                "instruments": ["low_strings", "percussion", "synth"]
            },
            "nature_theme": {
                "name": "Wild Pulse",
                "baseTrack": "music/themes/wild_pulse.mp3",
                "bpm": 55,
                "key": "G",
                "mood": "organic",
                "instruments": ["ethnic_percussion", "woodwinds", "nature_samples"]
            },
            "loss_theme": {
                "name": "Echoes of Green",
                "baseTrack": "music/themes/echoes_of_green.mp3",
                "bpm": 48,
                "key": "Em",
                "mood": "melancholic",
                "instruments": ["solo_cello", "ambient_pads", "distant_choir"]
            }
        }

        # Dynamic music layers that can be mixed
        self.music_layers = {
            "base_drone": {
                "file": "music/layers/base_drone_{key}.mp3",
                "role": "foundation",
                "always_on": True,
                "volume_range": [0.3, 0.5]
            },
            "rhythmic_pulse": {
                "file": "music/layers/rhythmic_pulse_{mood}.mp3",
                "role": "energy",
                "trigger": "movement_detected",
                "volume_range": [0.0, 0.4]
            },
            "melodic_fragments": {
                "file": "music/layers/melodic_fragments_{theme}.mp3",
                "role": "emotion",
                "trigger": "chapter_transition",
                "volume_range": [0.0, 0.6]
            },
            "nature_harmonics": {
                "file": "music/layers/nature_harmonics.mp3",
                "role": "organic",
                "trigger": "species_interaction",
                "volume_range": [0.2, 0.5]
            },
            "tension_build": {
                "file": "music/layers/tension_build.mp3",
                "role": "drama",
                "trigger": "risk_reveal",
                "volume_range": [0.0, 0.7]
            },
            "resolution": {
                "file": "music/layers/resolution.mp3",
                "role": "catharsis",
                "trigger": "hope_chapter",
                "volume_range": [0.4, 0.8]
            }
        }

        # Emotional arcs - how music evolves through the experience
        self.emotional_arcs = {
            "standard": {
                "name": "The Journey",
                "stages": [
                    {"chapter": "arrival", "theme": "main_theme", "intensity": 0.4, "layers": ["base_drone", "nature_harmonics"]},
                    {"chapter": "land", "theme": "nature_theme", "intensity": 0.5, "layers": ["base_drone", "melodic_fragments"]},
                    {"chapter": "species", "theme": "nature_theme", "intensity": 0.6, "layers": ["base_drone", "nature_harmonics", "melodic_fragments"]},
                    {"chapter": "happened", "theme": "danger_theme", "intensity": 0.8, "layers": ["base_drone", "tension_build", "rhythmic_pulse"]},
                    {"chapter": "impact", "theme": "loss_theme", "intensity": 0.7, "layers": ["base_drone", "melodic_fragments"]},
                    {"chapter": "hope", "theme": "hope_theme", "intensity": 0.9, "layers": ["base_drone", "resolution", "melodic_fragments"]}
                ]
            },
            "crisis": {
                "name": "The Reckoning",
                "stages": [
                    {"chapter": "arrival", "theme": "loss_theme", "intensity": 0.6, "layers": ["base_drone", "tension_build"]},
                    {"chapter": "land", "theme": "danger_theme", "intensity": 0.7, "layers": ["base_drone", "rhythmic_pulse", "tension_build"]},
                    {"chapter": "species", "theme": "loss_theme", "intensity": 0.8, "layers": ["base_drone", "melodic_fragments"]},
                    {"chapter": "happened", "theme": "danger_theme", "intensity": 1.0, "layers": ["base_drone", "tension_build", "rhythmic_pulse"]},
                    {"chapter": "impact", "theme": "loss_theme", "intensity": 0.9, "layers": ["base_drone", "melodic_fragments", "tension_build"]},
                    {"chapter": "hope", "theme": "hope_theme", "intensity": 0.7, "layers": ["base_drone", "resolution"]}
                ]
            },
            "calm": {
                "name": "The Sanctuary",
                "stages": [
                    {"chapter": "arrival", "theme": "nature_theme", "intensity": 0.3, "layers": ["base_drone", "nature_harmonics"]},
                    {"chapter": "land", "theme": "nature_theme", "intensity": 0.4, "layers": ["base_drone", "melodic_fragments"]},
                    {"chapter": "species", "theme": "nature_theme", "intensity": 0.5, "layers": ["base_drone", "nature_harmonics", "melodic_fragments"]},
                    {"chapter": "happened", "theme": "main_theme", "intensity": 0.4, "layers": ["base_drone", "melodic_fragments"]},
                    {"chapter": "impact", "theme": "main_theme", "intensity": 0.5, "layers": ["base_drone", "nature_harmonics"]},
                    {"chapter": "hope", "theme": "hope_theme", "intensity": 0.6, "layers": ["base_drone", "resolution", "nature_harmonics"]}
                ]
            }
        }

        # Stingers - short musical punctuation for key moments
        self.stingers = {
            "revelation": {
                "file": "music/stingers/revelation.mp3",
                "duration": 3.5,
                "trigger": "data_reveal"
            },
            "heartbreak": {
                "file": "music/stingers/heartbreak.mp3",
                "duration": 4.0,
                "trigger": "loss_statistic"
            },
            "discovery": {
                "file": "music/stingers/discovery.mp3",
                "duration": 2.5,
                "trigger": "species_found"
            },
            "hope_rising": {
                "file": "music/stingers/hope_rising.mp3",
                "duration": 5.0,
                "trigger": "hope_moment"
            },
            "call_to_action": {
                "file": "music/stingers/call_to_action.mp3",
                "duration": 6.0,
                "trigger": "final_moment"
            }
        }

    def _init_personalization_engine(self):
        """
        Initialize the adaptive storytelling personalization engine.
        Learns user preferences and adapts the experience accordingly.
        """
        # User preference dimensions
        self.preference_dimensions = {
            "pacing": {
                "name": "Experience Pace",
                "range": [0.5, 2.0],  # 0.5 = contemplative, 2.0 = rapid
                "default": 1.0,
                "learned_from": ["time_spent_per_chapter", "skip_rate", "replay_rate"]
            },
            "data_depth": {
                "name": "Data Affinity",
                "range": [0.0, 1.0],  # 0 = story-focused, 1 = data-focused
                "default": 0.5,
                "learned_from": ["stat_interaction_rate", "chart_view_time", "data_tooltip_opens"]
            },
            "emotional_intensity": {
                "name": "Emotional Preference",
                "range": [0.0, 1.0],  # 0 = factual, 1 = emotional
                "default": 0.6,
                "learned_from": ["story_completion_rate", "community_content_time", "hope_chapter_time"]
            },
            "exploration_style": {
                "name": "Exploration Style",
                "range": [0.0, 1.0],  # 0 = guided, 1 = free
                "default": 0.5,
                "learned_from": ["off_path_exploration", "anchor_discovery_rate", "tutorial_skip_rate"]
            },
            "species_interest": {
                "name": "Species Interest",
                "range": [0.0, 1.0],
                "default": 0.5,
                "learned_from": ["species_poi_time", "species_card_expansions", "species_sound_plays"]
            }
        }

        # Adaptive content rules
        self.adaptation_rules = {
            "high_data_affinity": {
                "condition": lambda prefs: prefs.get("data_depth", 0.5) > 0.7,
                "adjustments": {
                    "narrator": "scientist",
                    "stat_display": "expanded",
                    "chart_auto_show": True,
                    "precision": "detailed"
                }
            },
            "high_emotional": {
                "condition": lambda prefs: prefs.get("emotional_intensity", 0.6) > 0.75,
                "adjustments": {
                    "narrator": "passionate_advocate",
                    "music_intensity_boost": 0.2,
                    "pause_extension": 1.3,
                    "haptic_intensity_boost": 0.15
                }
            },
            "fast_pace": {
                "condition": lambda prefs: prefs.get("pacing", 1.0) > 1.5,
                "adjustments": {
                    "narrator_speed": 1.15,
                    "transition_speed": 1.3,
                    "auto_advance": True,
                    "skip_optional_content": True
                }
            },
            "contemplative": {
                "condition": lambda prefs: prefs.get("pacing", 1.0) < 0.7,
                "adjustments": {
                    "narrator_speed": 0.9,
                    "pause_extension": 1.5,
                    "meditation_prompts": True,
                    "ambient_enhancement": True
                }
            },
            "explorer": {
                "condition": lambda prefs: prefs.get("exploration_style", 0.5) > 0.7,
                "adjustments": {
                    "guided_prompts": "minimal",
                    "hidden_content_hints": True,
                    "achievement_notifications": True,
                    "map_always_visible": True
                }
            },
            "species_enthusiast": {
                "condition": lambda prefs: prefs.get("species_interest", 0.5) > 0.7,
                "adjustments": {
                    "species_pois_priority": True,
                    "species_sounds_auto": True,
                    "species_detail_expanded": True,
                    "taxonomic_info": True
                }
            }
        }

        # Session memory - what to remember between sessions
        self.session_memory = {
            "persistent": [
                "locations_visited",
                "species_discovered",
                "achievements_earned",
                "secrets_found",
                "total_time_spent",
                "actions_taken"
            ],
            "temporary": [
                "current_chapter",
                "current_preferences",
                "current_emotional_state"
            ]
        }

        # Return visitor enhancements
        self.return_visitor_content = {
            "updates": {
                "trigger": "location_revisited",
                "content": "Since your last visit, {changes_summary}",
                "narrator_style": "update"
            },
            "progress": {
                "trigger": "session_start",
                "content": "Welcome back. You've witnessed {locations_count} locations and discovered {species_count} species.",
                "narrator_style": "warm"
            },
            "new_discoveries": {
                "trigger": "new_content_available",
                "content": "New discoveries await in locations you've visited before.",
                "narrator_style": "mysterious"
            }
        }

    def _init_silent_hunt_system(self):
        """
        Initialize "The Silent Hunt" - a world-first proximity-driven species interaction system.

        As the user approaches a species:
        - Ambient sounds quiet down
        - Animal breathing/movement sounds increase
        - Moving too fast or tapping loudly causes the animal to flee
        - If habitat is fragmented, the animal has nowhere to run - teaching the lesson
        """
        # Species behavior profiles - how each animal reacts to human presence
        self.species_behaviors = {
            "jaguar": {
                "id": "jaguar",
                "category": "apex_predator",
                "flightDistance": 150,  # meters - distance at which it becomes alert
                "panicDistance": 50,    # meters - distance at which it flees
                "speedSensitivity": 0.8,  # How sensitive to fast movement (0-1)
                "noiseSensitivity": 0.6,  # How sensitive to loud sounds (0-1)
                "curiosityFactor": 0.4,   # Chance to approach rather than flee
                "sounds": {
                    "distant": "sounds/animals/jaguar_distant_growl.mp3",
                    "alert": "sounds/animals/jaguar_alert_huff.mp3",
                    "breathing": "sounds/animals/jaguar_breathing_close.mp3",
                    "flee": "sounds/animals/jaguar_retreat_rustle.mp3",
                    "vanish": "sounds/animals/silence_ominous.mp3"
                },
                "animations": {
                    "idle": "jaguar_rest",
                    "alert": "jaguar_ears_perk",
                    "curious": "jaguar_sniff",
                    "flee": "jaguar_sprint",
                    "vanish": "jaguar_fade_despair"
                },
                "habitatRequirement": 500  # Minimum hectares needed to survive
            },
            "macaw": {
                "id": "macaw",
                "category": "bird",
                "flightDistance": 80,
                "panicDistance": 20,
                "speedSensitivity": 0.9,
                "noiseSensitivity": 0.7,
                "curiosityFactor": 0.6,
                "sounds": {
                    "distant": "sounds/animals/macaw_distant_call.mp3",
                    "alert": "sounds/animals/macaw_warning_screech.mp3",
                    "breathing": "sounds/animals/macaw_wing_flutter.mp3",
                    "flee": "sounds/animals/macaw_fly_away.mp3",
                    "vanish": "sounds/animals/feathers_fall.mp3"
                },
                "animations": {
                    "idle": "macaw_preen",
                    "alert": "macaw_head_tilt",
                    "curious": "macaw_hop",
                    "flee": "macaw_take_flight",
                    "vanish": "macaw_cage_fade"
                },
                "habitatRequirement": 100
            },
            "sloth": {
                "id": "sloth",
                "category": "mammal_slow",
                "flightDistance": 30,
                "panicDistance": 5,
                "speedSensitivity": 0.3,
                "noiseSensitivity": 0.4,
                "curiosityFactor": 0.8,
                "sounds": {
                    "distant": "sounds/animals/sloth_leaves_rustle.mp3",
                    "alert": "sounds/animals/sloth_soft_call.mp3",
                    "breathing": "sounds/animals/sloth_slow_breath.mp3",
                    "flee": "sounds/animals/sloth_slow_climb.mp3",
                    "vanish": "sounds/animals/branch_crack_fall.mp3"
                },
                "animations": {
                    "idle": "sloth_hang",
                    "alert": "sloth_look",
                    "curious": "sloth_reach",
                    "flee": "sloth_climb",
                    "vanish": "sloth_tree_fall"
                },
                "habitatRequirement": 50
            },
            "monkey": {
                "id": "monkey",
                "category": "primate",
                "flightDistance": 60,
                "panicDistance": 15,
                "speedSensitivity": 0.7,
                "noiseSensitivity": 0.8,
                "curiosityFactor": 0.7,
                "sounds": {
                    "distant": "sounds/animals/monkey_distant_howl.mp3",
                    "alert": "sounds/animals/monkey_alarm_call.mp3",
                    "breathing": "sounds/animals/monkey_chatter.mp3",
                    "flee": "sounds/animals/monkey_branch_swing.mp3",
                    "vanish": "sounds/animals/silence_forest_edge.mp3"
                },
                "animations": {
                    "idle": "monkey_groom",
                    "alert": "monkey_stand",
                    "curious": "monkey_approach",
                    "flee": "monkey_leap",
                    "vanish": "monkey_trapped"
                },
                "habitatRequirement": 200
            },
            "frog": {
                "id": "frog",
                "category": "amphibian",
                "flightDistance": 10,
                "panicDistance": 2,
                "speedSensitivity": 0.95,
                "noiseSensitivity": 0.9,
                "curiosityFactor": 0.2,
                "sounds": {
                    "distant": "sounds/animals/frog_chorus.mp3",
                    "alert": "sounds/animals/frog_single_croak.mp3",
                    "breathing": "sounds/animals/frog_throat_pulse.mp3",
                    "flee": "sounds/animals/frog_splash.mp3",
                    "vanish": "sounds/animals/pond_dry_crack.mp3"
                },
                "animations": {
                    "idle": "frog_breathe",
                    "alert": "frog_inflate",
                    "curious": "frog_hop_forward",
                    "flee": "frog_leap",
                    "vanish": "frog_desiccate"
                },
                "habitatRequirement": 20
            },
            "default": {
                "id": "default",
                "category": "generic",
                "flightDistance": 50,
                "panicDistance": 15,
                "speedSensitivity": 0.6,
                "noiseSensitivity": 0.6,
                "curiosityFactor": 0.5,
                "sounds": {
                    "distant": "sounds/animals/generic_rustle.mp3",
                    "alert": "sounds/animals/generic_alert.mp3",
                    "breathing": "sounds/animals/generic_presence.mp3",
                    "flee": "sounds/animals/generic_flee.mp3",
                    "vanish": "sounds/animals/silence_empty.mp3"
                },
                "animations": {
                    "idle": "generic_idle",
                    "alert": "generic_alert",
                    "curious": "generic_curious",
                    "flee": "generic_flee",
                    "vanish": "generic_vanish"
                },
                "habitatRequirement": 100
            }
        }

        # Proximity zones and their effects
        self.proximity_zones = {
            "distant": {
                "rangeMultiplier": [2.0, 999],  # Beyond 2x flight distance
                "ambientVolume": 1.0,
                "animalVolume": 0.1,
                "visualEffect": None,
                "animalState": "idle",
                "narratorTrigger": None
            },
            "aware": {
                "rangeMultiplier": [1.0, 2.0],  # 1-2x flight distance
                "ambientVolume": 0.8,
                "animalVolume": 0.3,
                "visualEffect": "subtle_highlight",
                "animalState": "alert",
                "narratorTrigger": "species_aware"
            },
            "close": {
                "rangeMultiplier": [0.5, 1.0],  # 0.5-1x flight distance
                "ambientVolume": 0.5,
                "animalVolume": 0.6,
                "visualEffect": "focus_depth",
                "animalState": "alert",
                "narratorTrigger": "species_close"
            },
            "intimate": {
                "rangeMultiplier": [0.2, 0.5],  # Very close
                "ambientVolume": 0.2,
                "animalVolume": 0.9,
                "visualEffect": "intimate_vignette",
                "animalState": "curious",
                "narratorTrigger": "species_intimate"
            },
            "connection": {
                "rangeMultiplier": [0, 0.2],  # Almost touching
                "ambientVolume": 0.05,
                "animalVolume": 1.0,
                "visualEffect": "connection_glow",
                "animalState": "curious",
                "narratorTrigger": "species_connection",
                "achievement": "species_whisperer"
            }
        }

        # Movement thresholds that trigger flee response
        self.movement_thresholds = {
            "speed_slow": 0.5,      # m/s - walking pace
            "speed_medium": 1.5,    # m/s - fast walk
            "speed_fast": 3.0,      # m/s - running
            "speed_panic": 5.0,     # m/s - sprint (always triggers flee)

            "noise_soft": 0.2,      # Normalized noise level
            "noise_medium": 0.5,
            "noise_loud": 0.8,
            "noise_sudden": 0.95    # Sudden loud noise (tap)
        }

        # Narrator lines for The Silent Hunt
        self.hunt_narration = {
            "species_aware": {
                "text": "It knows you're here. Move slowly.",
                "style": "whisper",
                "duration": 3.0
            },
            "species_close": {
                "text": "You can hear it breathing now. Be still.",
                "style": "whisper",
                "duration": 3.5
            },
            "species_intimate": {
                "text": "Remarkable. Most humans never get this close.",
                "style": "reverent",
                "duration": 4.0
            },
            "species_connection": {
                "text": "For a moment, you exist in its world. This is what we're fighting to protect.",
                "style": "emotional",
                "duration": 5.0
            },
            "species_fled": {
                "text": "It's gone. In the wild, they have endless forest to disappear into.",
                "style": "measured",
                "duration": 4.0
            },
            "species_vanished": {
                "text": "It tried to flee... but there's nowhere left to go. This is what habitat fragmentation looks like.",
                "style": "grave",
                "duration": 6.0
            },
            "species_trapped": {
                "text": "Watch carefully. When the forest fragments, animals become trapped in ever-shrinking islands of green.",
                "style": "educational",
                "duration": 5.5
            }
        }

    def _init_ecosystem_simulation(self):
        """
        Initialize the ecosystem simulation system.
        Shows interconnections between species and how removing one affects others.
        """
        # Food web relationships
        self.food_web = {
            "jaguar": {
                "role": "apex_predator",
                "preyOn": ["monkey", "sloth", "tapir", "deer", "peccary"],
                "predators": [],
                "symbioticWith": [],
                "dependsOn": ["forest_cover", "prey_population"],
                "populationImpact": 0.9,  # How much its loss affects ecosystem
                "extinctionCascade": ["prey_overpopulation", "vegetation_overgrazing"]
            },
            "monkey": {
                "role": "seed_disperser",
                "preyOn": ["fruit", "insects", "leaves"],
                "predators": ["jaguar", "harpy_eagle"],
                "symbioticWith": ["fruit_trees"],
                "dependsOn": ["fruit_trees", "canopy_connectivity"],
                "populationImpact": 0.8,
                "extinctionCascade": ["tree_reproduction_decline", "forest_regeneration_halt"]
            },
            "macaw": {
                "role": "seed_disperser",
                "preyOn": ["seeds", "fruit", "nuts"],
                "predators": ["harpy_eagle"],
                "symbioticWith": ["brazil_nut_tree"],
                "dependsOn": ["nesting_cavities", "fruit_trees"],
                "populationImpact": 0.7,
                "extinctionCascade": ["nut_tree_decline", "nutrient_distribution_fail"]
            },
            "frog": {
                "role": "indicator_species",
                "preyOn": ["insects", "larvae"],
                "predators": ["birds", "snakes"],
                "symbioticWith": ["bromeliad"],
                "dependsOn": ["water_quality", "humidity", "leaf_litter"],
                "populationImpact": 0.6,
                "extinctionCascade": ["insect_population_surge", "disease_spread"]
            },
            "bee": {
                "role": "pollinator",
                "preyOn": ["nectar", "pollen"],
                "predators": ["birds", "dragonfly"],
                "symbioticWith": ["flowering_plants", "orchids"],
                "dependsOn": ["flower_availability", "nesting_sites"],
                "populationImpact": 0.95,
                "extinctionCascade": ["pollination_collapse", "fruit_failure", "mass_extinction"]
            },
            "earthworm": {
                "role": "decomposer",
                "preyOn": ["dead_matter", "leaf_litter"],
                "predators": ["birds", "mammals"],
                "symbioticWith": ["soil_bacteria", "fungi"],
                "dependsOn": ["soil_moisture", "organic_matter"],
                "populationImpact": 0.85,
                "extinctionCascade": ["soil_degradation", "nutrient_cycle_halt", "plant_death"]
            }
        }

        # Chain reaction scenarios
        self.chain_reactions = {
            "deforestation_small": {
                "trigger": "hectares_lost < 100",
                "effects": [
                    {"species": "frog", "population_change": -0.15, "delay_days": 30},
                    {"species": "monkey", "population_change": -0.10, "delay_days": 60},
                    {"species": "macaw", "population_change": -0.08, "delay_days": 90}
                ],
                "visualize": "ripple_effect_small"
            },
            "deforestation_medium": {
                "trigger": "hectares_lost 100-500",
                "effects": [
                    {"species": "frog", "population_change": -0.40, "delay_days": 14},
                    {"species": "monkey", "population_change": -0.30, "delay_days": 30},
                    {"species": "macaw", "population_change": -0.25, "delay_days": 45},
                    {"species": "jaguar", "population_change": -0.20, "delay_days": 90}
                ],
                "visualize": "ripple_effect_medium"
            },
            "deforestation_severe": {
                "trigger": "hectares_lost > 500",
                "effects": [
                    {"species": "frog", "population_change": -0.80, "delay_days": 7},
                    {"species": "monkey", "population_change": -0.60, "delay_days": 14},
                    {"species": "macaw", "population_change": -0.55, "delay_days": 21},
                    {"species": "jaguar", "population_change": -0.50, "delay_days": 30},
                    {"species": "bee", "population_change": -0.40, "delay_days": 45},
                    {"ecosystem": "pollination", "function_change": -0.60, "delay_days": 60}
                ],
                "visualize": "cascade_collapse"
            },
            "apex_predator_loss": {
                "trigger": "jaguar_extinct",
                "effects": [
                    {"species": "monkey", "population_change": 0.50, "delay_days": 180},
                    {"species": "deer", "population_change": 0.60, "delay_days": 120},
                    {"ecosystem": "vegetation", "damage_change": 0.40, "delay_days": 365},
                    {"ecosystem": "tree_regeneration", "function_change": -0.50, "delay_days": 730}
                ],
                "visualize": "trophic_cascade"
            },
            "pollinator_collapse": {
                "trigger": "bee_population < 20%",
                "effects": [
                    {"ecosystem": "fruit_production", "function_change": -0.80, "delay_days": 30},
                    {"species": "monkey", "population_change": -0.50, "delay_days": 90},
                    {"species": "macaw", "population_change": -0.60, "delay_days": 90},
                    {"ecosystem": "forest_regeneration", "function_change": -0.90, "delay_days": 365}
                ],
                "visualize": "pollination_web_collapse"
            }
        }

        # Interactive ecosystem elements
        self.ecosystem_interactions = {
            "seed_dispersal": {
                "name": "Seed Dispersal Journey",
                "description": "Follow a seed from fruit to forest floor",
                "trigger": "gaze_at_fruit_tree",
                "duration": 15,
                "steps": [
                    {"action": "monkey_eats_fruit", "visual": "particle_seeds_stomach", "narration": "The seed begins its journey."},
                    {"action": "monkey_travels", "visual": "path_trail", "narration": "Carried far from the parent tree."},
                    {"action": "seed_deposited", "visual": "seed_glow_ground", "narration": "Deposited with natural fertilizer."},
                    {"action": "seedling_grows", "visual": "time_lapse_growth", "narration": "A new tree begins. This is how forests spread."}
                ],
                "lesson": "Without seed dispersers, forests cannot regenerate."
            },
            "carbon_breath": {
                "name": "Carbon Breathing",
                "description": "Visualize the forest breathing CO2",
                "trigger": "gaze_at_canopy",
                "duration": 20,
                "steps": [
                    {"action": "co2_particles_visible", "visual": "particle_co2_red", "narration": "Carbon dioxide surrounds us - invisible but everywhere."},
                    {"action": "leaves_absorb", "visual": "particles_pulled_to_leaves", "narration": "Watch as the leaves pull it in."},
                    {"action": "oxygen_release", "visual": "particle_o2_blue", "narration": "Oxygen flows out - the air you're breathing right now."},
                    {"action": "carbon_stored", "visual": "trunk_pulse_green", "narration": "The carbon is locked away in wood, roots, soil. For centuries."},
                    {"action": "tree_cut", "visual": "carbon_explosion", "narration": "When a tree falls, all that carbon returns to the sky instantly."}
                ],
                "lesson": "Every tree is a carbon bank. Cutting one is a withdrawal we can't afford."
            },
            "water_cycle": {
                "name": "The Forest's Water",
                "description": "Follow water through the ecosystem",
                "trigger": "gaze_at_stream",
                "duration": 25,
                "steps": [
                    {"action": "rain_falls", "visual": "particle_rain", "narration": "Rain falls on the canopy."},
                    {"action": "canopy_intercepts", "visual": "water_spread_leaves", "narration": "The canopy catches it, slowing its fall."},
                    {"action": "water_descends", "visual": "drip_path_visible", "narration": "Slowly it descends, branch to branch."},
                    {"action": "roots_absorb", "visual": "root_glow_blue", "narration": "Roots drink deep, storing water for dry months."},
                    {"action": "transpiration", "visual": "mist_rise_leaves", "narration": "Trees breathe out moisture - creating their own rain."},
                    {"action": "cloud_forms", "visual": "cloud_particle_rise", "narration": "This moisture rises, forms clouds, falls again."},
                    {"action": "deforested_contrast", "visual": "split_screen_dry", "narration": "Without trees, water rushes away. The cycle breaks."}
                ],
                "lesson": "The Amazon creates 50% of its own rainfall. No forest, no rain."
            },
            "root_network": {
                "name": "The Wood Wide Web",
                "description": "See how trees communicate underground",
                "trigger": "gaze_at_forest_floor",
                "duration": 18,
                "steps": [
                    {"action": "surface_fade", "visual": "transparency_ground", "narration": "Beneath your feet lies a hidden network."},
                    {"action": "roots_appear", "visual": "root_network_glow", "narration": "Tree roots intertwined with fungal threads."},
                    {"action": "signal_pulse", "visual": "pulse_root_to_root", "narration": "Trees share nutrients through this network."},
                    {"action": "mother_tree", "visual": "large_tree_hub_glow", "narration": "Older trees - 'mother trees' - feed the young."},
                    {"action": "warning_signal", "visual": "red_pulse_spread", "narration": "When one tree is attacked, it warns the others."},
                    {"action": "network_cut", "visual": "connections_sever", "narration": "Fragmentation severs these connections. Isolated trees struggle."}
                ],
                "lesson": "A forest is not a collection of trees. It's a single organism."
            },
            "predator_prey": {
                "name": "Balance of Power",
                "description": "See how predators maintain forest health",
                "trigger": "gaze_at_jaguar_poi",
                "duration": 20,
                "steps": [
                    {"action": "jaguar_hunts", "visual": "jaguar_stalk_animation", "narration": "The jaguar hunts - not for cruelty, but for balance."},
                    {"action": "prey_population_shown", "visual": "deer_dots_many", "narration": "Without predators, herbivore populations explode."},
                    {"action": "overgrazing_shown", "visual": "vegetation_depleting", "narration": "Too many grazers devastate young trees."},
                    {"action": "forest_decline", "visual": "forest_thinning", "narration": "The forest can't regenerate."},
                    {"action": "jaguar_returns", "visual": "balance_restore_animation", "narration": "One jaguar can protect thousands of hectares - just by existing."}
                ],
                "lesson": "Apex predators aren't just wildlife - they're forest architects."
            }
        }

    def _init_immersive_interactions(self):
        """
        Initialize additional world-first immersive interaction systems.
        """
        # Day/Night wildlife changes
        self.time_based_wildlife = {
            "dawn": {
                "activeSpecies": ["macaw", "monkey", "toucan", "howler"],
                "sounds": "dawn_chorus",
                "visibility": 0.7,
                "specialEvent": {
                    "name": "Dawn Chorus",
                    "description": "The forest awakens with thousands of voices",
                    "effect": "audio_crescendo"
                }
            },
            "day": {
                "activeSpecies": ["monkey", "macaw", "butterfly", "hummingbird", "iguana"],
                "sounds": "day_activity",
                "visibility": 1.0,
                "specialEvent": None
            },
            "dusk": {
                "activeSpecies": ["bat_early", "frog", "nightjar", "firefly"],
                "sounds": "dusk_transition",
                "visibility": 0.6,
                "specialEvent": {
                    "name": "Firefly Emergence",
                    "description": "Watch as thousands of fireflies light up the understory",
                    "effect": "firefly_particles"
                }
            },
            "night": {
                "activeSpecies": ["jaguar", "owl", "bat", "frog", "tapir", "ocelot"],
                "sounds": "night_forest",
                "visibility": 0.3,
                "specialEvent": {
                    "name": "Jaguar's Hour",
                    "description": "The apex predator emerges to hunt",
                    "effect": "night_vision_pulse"
                }
            }
        }

        # Weather impact on behavior
        self.weather_wildlife_impact = {
            "rain_light": {
                "activity_modifier": 0.8,
                "species_behavior": {
                    "monkey": "seek_shelter",
                    "frog": "increased_activity",
                    "macaw": "reduced_flight"
                },
                "visual": "rain_particle_light",
                "audio": "rain_on_leaves"
            },
            "rain_heavy": {
                "activity_modifier": 0.4,
                "species_behavior": {
                    "monkey": "huddled_shelter",
                    "frog": "breeding_activity",
                    "jaguar": "opportunistic_hunting"
                },
                "visual": "rain_particle_heavy",
                "audio": "rain_thunderstorm"
            },
            "drought": {
                "activity_modifier": 0.6,
                "species_behavior": {
                    "all": "water_seeking",
                    "frog": "dormancy",
                    "jaguar": "concentrated_at_water"
                },
                "visual": "haze_dry_dust",
                "audio": "crackle_dry_leaves",
                "lesson": "Drought concentrates wildlife at water sources - making them vulnerable"
            },
            "fire_smoke": {
                "activity_modifier": 0.2,
                "species_behavior": {
                    "all": "flee_or_perish",
                    "bird": "mass_exodus",
                    "slow_species": "trapped"
                },
                "visual": "smoke_haze_thick",
                "audio": "distant_fire_crackle",
                "lesson": "Fire doesn't just burn trees - it destroys entire animal populations"
            }
        }

        # Symbiotic relationship discoveries
        self.symbiosis_discoveries = {
            "fig_and_wasp": {
                "name": "The Fig's Secret",
                "species": ["strangler_fig", "fig_wasp"],
                "trigger": "gaze_at_fig_tree",
                "description": "A relationship 80 million years in the making",
                "visualization": "wasp_lifecycle_in_fig",
                "narration": [
                    "This fig tree only opens its flowers to one species of wasp.",
                    "The wasp can only reproduce inside this fig.",
                    "If one disappears, so does the other.",
                    "80 million years of co-evolution, endangered in decades."
                ],
                "data_connection": "flora_at_risk"
            },
            "brazil_nut_and_bee": {
                "name": "The Orchid Bee Connection",
                "species": ["brazil_nut_tree", "orchid_bee"],
                "trigger": "gaze_at_brazil_nut",
                "description": "Only one bee can unlock the brazil nut flower",
                "visualization": "bee_pollination_process",
                "narration": [
                    "The Brazil nut flower is locked - literally.",
                    "Only the orchid bee is strong enough to open it.",
                    "No bee, no pollination. No pollination, no nuts.",
                    "No nuts, no income for thousands of forest families."
                ],
                "data_connection": "economic_impact"
            },
            "cecropia_and_ant": {
                "name": "The Ant Guardians",
                "species": ["cecropia_tree", "azteca_ant"],
                "trigger": "gaze_at_cecropia",
                "description": "A tree that employs an ant army",
                "visualization": "ant_colony_defense",
                "narration": [
                    "This tree provides food and shelter for a colony of ants.",
                    "In return, the ants attack anything that threatens the tree.",
                    "They even cut vines that try to climb it.",
                    "It's a contract written over millions of years."
                ],
                "data_connection": "biodiversity_index"
            },
            "sloth_and_algae": {
                "name": "Living Camouflage",
                "species": ["sloth", "algae", "moth"],
                "trigger": "close_approach_sloth",
                "description": "A sloth's fur is its own ecosystem",
                "visualization": "sloth_fur_zoom",
                "narration": [
                    "Look closely at the sloth's fur.",
                    "Green algae grows here - providing camouflage.",
                    "Moths live only in this fur, nowhere else on Earth.",
                    "One sloth carries an entire micro-ecosystem."
                ],
                "data_connection": "species_interdependence"
            }
        }

        # User action consequences
        self.action_consequences = {
            "virtual_tree_plant": {
                "trigger": "tap_restoration_zone",
                "immediate": {
                    "visual": "seedling_sprout_animation",
                    "audio": "soil_dig_plant",
                    "haptic": "soft_pulse"
                },
                "time_lapse": [
                    {"years": 1, "visual": "sapling_1m", "narration": "One year: A fragile sapling."},
                    {"years": 5, "visual": "young_tree_5m", "narration": "Five years: A young tree providing shade."},
                    {"years": 10, "visual": "tree_10m_birds", "narration": "Ten years: Birds nest here now."},
                    {"years": 25, "visual": "tree_25m_ecosystem", "narration": "Twenty-five years: A whole ecosystem."},
                    {"years": 50, "visual": "tree_50m_canopy", "narration": "Fifty years: Reaching the canopy, storing tonnes of carbon."}
                ],
                "data_impact": {
                    "carbon_offset": 0.5,  # tonnes per tree over 50 years
                    "species_supported": 3
                }
            },
            "virtual_donate": {
                "trigger": "tap_donate_button",
                "visualization": {
                    "type": "protection_shield_expand",
                    "narration": "Your contribution expands the protected zone."
                },
                "impact_display": {
                    "hectares_protected_per_dollar": 0.01,
                    "species_protected": "calculated_from_density"
                }
            }
        }

        # Emotional moments - designed to create lasting impact
        self.emotional_moments = {
            "last_of_species": {
                "trigger": "species_population == 1",
                "visual": "spotlight_single_animal",
                "audio": "solo_heartbeat",
                "narration": "This is the last one. The very last. When it goes, the species goes forever.",
                "duration": 10,
                "aftermath": "silhouette_fade_to_extinction"
            },
            "baby_discovery": {
                "trigger": "approach_nest_or_den",
                "visual": "reveal_babies",
                "audio": "baby_animal_sounds",
                "narration": "New life. Born into a world that may not have room for them.",
                "duration": 8,
                "data_tie": "reproduction_rate"
            },
            "elder_tree_death": {
                "trigger": "approach_logged_area",
                "visual": "stump_rings_count",
                "audio": "silence_then_chainsaw_echo",
                "narration": "This tree was here before your great-grandparents were born. It took 200 years to grow. Minutes to fall.",
                "duration": 12,
                "data_tie": "deforestation_rate"
            },
            "dawn_of_hope": {
                "trigger": "complete_hope_chapter",
                "visual": "sunrise_over_restored_area",
                "audio": "dawn_chorus_full",
                "narration": "This is what recovery looks like. It's possible. But only if we act.",
                "duration": 15,
                "data_tie": "restoration_potential"
            }
        }

        # Data-driven dramatic reveals
        self.data_revelations = {
            "real_time_loss": {
                "trigger": "enter_happened_chapter",
                "calculation": "hectares_lost_since_session_start",
                "template": "Since you started this experience {minutes} minutes ago, {hectares_lost} hectares of rainforest have been lost globally.",
                "visual": "counter_tick_up",
                "audio": "ominous_tick"
            },
            "personal_footprint": {
                "trigger": "enter_impact_chapter",
                "calculation": "user_country_import_data",
                "template": "Your country imports {import_value} worth of products linked to deforestation each year.",
                "visual": "map_trade_routes",
                "source": "external_trade_data"
            },
            "what_if_projection": {
                "trigger": "future_temporal_state",
                "calculation": "project_from_trend",
                "template": "At current rates, this entire forest will be gone by {extinction_year}.",
                "visual": "forest_fade_timelapse",
                "audio": "countdown_tension"
            },
            "species_clock": {
                "trigger": "view_endangered_species",
                "calculation": "extinction_probability",
                "template": "Scientists estimate a {probability}% chance this species will be extinct by {year}.",
                "visual": "species_ghost_fade",
                "audio": "clock_ticking"
            }
        }

    # ═══════════════════════════════════════════════════════════════
    # MAIN STORY GENERATION
    # ═══════════════════════════════════════════════════════════════

    def generate_story(self, intelligence_node: Dict[str, Any]) -> Dict[str, Any]:
        """
        Generate a complete immersive story from an IntelligenceNode.

        Returns a comprehensive story object with:
        - Sensory orchestration (audio, visual, haptic)
        - Temporal states (past, present, future)
        - Spatially-placed species POIs
        - Tone-adapted narratives
        - Interactive gaze triggers
        - Environmental atmosphere data
        """
        try:
            # Extract core location data
            lat = intelligence_node.get('lat', 0)
            lng = intelligence_node.get('lng', 0)
            name = intelligence_node.get('headline', 'Environmental Hotspot')
            country = intelligence_node.get('country', '')
            region = intelligence_node.get('region', '')
            location_name = f"{region}, {country}" if region and country else name

            # Core metrics
            hectares = intelligence_node.get('hectares', 100)
            risk_score = intelligence_node.get('riskScore', intelligence_node.get('risk_score', 50))
            population = self._extract_population(intelligence_node)

            # Carbon data
            carbon_data = intelligence_node.get('carbon_data', {})
            carbon_stock = carbon_data.get('carbon_stock_tonnes', hectares * 45)
            car_equivalent = int(carbon_stock * 3.67 / 4.6)

            # Species data
            fauna_at_risk = intelligence_node.get('fauna_at_risk', [])
            flora_at_risk = intelligence_node.get('flora_at_risk', [])
            species_count = len(fauna_at_risk) + len(flora_at_risk)

            # Financial & recovery data
            restoration_cost = self._calculate_restoration_cost(intelligence_node, hectares)
            restoration_cost_millions = restoration_cost / 1_000_000
            recovery_years = self._estimate_recovery_time(intelligence_node)

            # Calculate loss rate
            loss_rate_data = self._calculate_loss_rate_detailed(intelligence_node)

            # Determine emotional severity level
            severity = self._calculate_severity(risk_score, loss_rate_data)

            # Build story context for templates
            story_context = {
                "location_name": location_name,
                "hectares": hectares,
                "carbon_stock": int(carbon_stock),
                "car_equivalent": car_equivalent,
                "species_count": species_count,
                "risk_score": int(risk_score),
                "population": population,
                "restoration_cost_millions": restoration_cost_millions,
                "recovery_years": recovery_years
            }

            # Generate all story components
            environment = self._generate_environment(intelligence_node, lat, lng)
            temporal_states = self._generate_temporal_states(intelligence_node, hectares, risk_score)
            species_pois = self._generate_species_pois(fauna_at_risk, flora_at_risk, lat, lng)
            chapters = self._generate_immersive_chapters(story_context, severity, risk_score, environment)
            interactive_anchors = self._generate_interactive_anchors(risk_score, species_pois)

            # Generate enhanced features
            narrator_data = self._generate_narrator(story_context, severity, location_name)
            discovery_content = self._generate_discovery_content(lat, lng, species_count)
            musical_journey = self._generate_musical_journey(severity, risk_score)
            personalization = self._generate_personalization_config()

            # Generate world-first immersive systems
            silent_hunt = self._generate_silent_hunt(fauna_at_risk, hectares, risk_score, environment)
            ecosystem_sim = self._generate_ecosystem_simulation(fauna_at_risk, flora_at_risk, hectares, risk_score)
            immersive_systems = self._generate_immersive_systems(
                intelligence_node, severity, species_count, environment
            )

            # Build complete story data
            story_data = {
                "id": intelligence_node.get('id', f"story_{lat}_{lng}"),
                "version": "2.0",
                "created_at": datetime.now(timezone.utc).isoformat(),

                # Location
                "location": {
                    "lat": lat,
                    "lng": lng,
                    "name": location_name,
                    "country": country,
                    "region": region
                },

                # Core metrics
                "metrics": {
                    "name": location_name,
                    "riskScore": int(risk_score),
                    "severity": severity,
                    "hectares": hectares,
                    "population": population,
                    "carbonStock": int(carbon_stock),
                    "restorationCost": int(restoration_cost),
                    "lossRate": loss_rate_data,
                    "communities": self._estimate_communities(population)
                },

                # Environmental atmosphere
                "environment": environment,

                # Temporal branching (past/present/future)
                "temporalStates": temporal_states,

                # Spatially-placed species
                "speciesPOIs": species_pois,
                "endemicCount": sum(1 for s in fauna_at_risk if s.get('endemic', False)),

                # Immersive chapters with sensory config
                "chapters": chapters,

                # Interactive triggers
                "interactiveAnchors": interactive_anchors,

                # Narrator system with full voiceover scripts
                "narrator": narrator_data,

                # Discovery & exploration features
                "discovery": discovery_content,

                # Generative emotional soundtrack
                "musicalJourney": musical_journey,

                # Personalization & adaptive settings
                "personalization": personalization,

                # World-first: The Silent Hunt proximity system
                "silentHunt": silent_hunt,

                # Ecosystem simulation & chain reactions
                "ecosystemSimulation": ecosystem_sim,

                # Immersive interaction systems
                "immersiveSystems": immersive_systems,

                # Global sensory defaults
                "defaultSensory": self._get_default_sensory(risk_score, environment),

                # Source data references
                "sources": {
                    "carbon": "IPCC AR6 Guidelines",
                    "population": "WorldPop 2020",
                    "restoration": "WRI Cost of Restoration 2023",
                    "species": "IUCN Red List 2024"
                }
            }

            return {
                "success": True,
                "story": story_data
            }

        except Exception as e:
            print(f"Story generation failed: {e}")
            import traceback
            traceback.print_exc()
            return {
                "success": False,
                "error": str(e)
            }

    # ═══════════════════════════════════════════════════════════════
    # ENVIRONMENTAL ATMOSPHERE GENERATION
    # ═══════════════════════════════════════════════════════════════

    def _generate_environment(self, node: Dict, lat: float, lng: float) -> Dict[str, Any]:
        """
        Generate procedural environment variables for realistic AR rendering.
        Includes weather, lighting, atmospheric conditions based on location.
        """
        # Calculate local time at location (approximate from longitude)
        utc_now = datetime.now(timezone.utc)
        local_offset_hours = lng / 15  # 15 degrees per hour
        local_hour = (utc_now.hour + local_offset_hours) % 24

        # Determine time of day
        if 5 <= local_hour < 7:
            time_of_day = "dawn"
        elif 7 <= local_hour < 10:
            time_of_day = "morning"
        elif 10 <= local_hour < 16:
            time_of_day = "midday"
        elif 16 <= local_hour < 18:
            time_of_day = "afternoon"
        elif 18 <= local_hour < 20:
            time_of_day = "dusk"
        else:
            time_of_day = "night"

        # Calculate sun angle
        sun_elevation = self._calculate_sun_elevation(lat, lng, utc_now)
        sun_azimuth = self._calculate_sun_azimuth(lat, lng, utc_now)

        # Terrain and canopy data
        terrain = node.get('terrain_analysis', node.get('terrainAnalysis', {}))
        hydrology = node.get('hydrology_analysis', node.get('hydrologyAnalysis', {}))

        # Base humidity from water access
        water_access = node.get('water_access', 'Medium')
        base_humidity = {"Very High": 0.95, "High": 0.85, "Medium": 0.70, "Low": 0.55, "Very Low": 0.40}.get(water_access, 0.70)

        # Adjust humidity for time of day
        humidity_modifier = {"dawn": 1.15, "morning": 1.05, "midday": 0.85, "afternoon": 0.90, "dusk": 1.0, "night": 1.1}
        humidity = min(1.0, base_humidity * humidity_modifier.get(time_of_day, 1.0))

        # Canopy density from forest health
        risk_score = node.get('riskScore', node.get('risk_score', 50))
        base_canopy = 0.9 if risk_score < 30 else 0.7 if risk_score < 60 else 0.4 if risk_score < 80 else 0.15
        canopy_density = max(0.05, base_canopy * random.uniform(0.9, 1.1))

        # Temperature estimation (tropical baseline with altitude adjustment)
        elevation = terrain.get('elevation', {}).get('mean_m', 200)
        base_temp_c = 28 - (elevation / 150)  # ~6.5°C per 1000m
        temp_modifier = {"dawn": -4, "morning": -2, "midday": 3, "afternoon": 1, "dusk": -1, "night": -5}
        temperature_c = base_temp_c + temp_modifier.get(time_of_day, 0) + random.uniform(-1, 1)

        # Wind conditions
        base_wind = 2.0 if canopy_density > 0.7 else 4.0 if canopy_density > 0.4 else 8.0
        wind_speed_ms = base_wind * random.uniform(0.7, 1.3)
        wind_direction = random.uniform(0, 360)

        # Cloud cover (tropical = often cloudy)
        cloud_cover = random.uniform(0.3, 0.8) if 10 <= local_hour < 16 else random.uniform(0.1, 0.5)

        # Precipitation probability
        precip_probability = humidity * cloud_cover * 0.8

        # Visibility based on conditions
        if node.get('fire_data', {}).get('active_fires', 0) > 0:
            visibility_km = random.uniform(1, 5)
            air_quality = "hazardous"
        elif humidity > 0.9:
            visibility_km = random.uniform(3, 8)
            air_quality = "misty"
        else:
            visibility_km = random.uniform(10, 25)
            air_quality = "clear"

        # Fog density (early morning/evening in humid conditions)
        fog_density = 0
        if time_of_day in ["dawn", "dusk"] and humidity > 0.8:
            fog_density = (humidity - 0.8) * 5  # 0 to 1 scale

        return {
            "timeOfDay": time_of_day,
            "localHour": round(local_hour, 1),

            "sun": {
                "elevation": round(sun_elevation, 2),
                "azimuth": round(sun_azimuth, 2),
                "intensity": max(0, min(1, sun_elevation / 60)) if sun_elevation > 0 else 0
            },

            "atmosphere": {
                "humidity": round(humidity, 2),
                "temperatureC": round(temperature_c, 1),
                "pressureHpa": round(1013 - (elevation / 8.5), 1),
                "airQuality": air_quality,
                "visibilityKm": round(visibility_km, 1)
            },

            "weather": {
                "cloudCover": round(cloud_cover, 2),
                "precipitationProbability": round(precip_probability, 2),
                "windSpeedMs": round(wind_speed_ms, 1),
                "windDirection": round(wind_direction, 0),
                "fogDensity": round(fog_density, 2)
            },

            "terrain": {
                "elevationM": elevation,
                "slope": terrain.get('slope', {}).get('mean_degrees', 5),
                "canopyDensity": round(canopy_density, 2),
                "understoryDensity": round(canopy_density * 0.8, 2)
            },

            "lighting": {
                "ambientIntensity": self._calculate_ambient_intensity(time_of_day, cloud_cover),
                "directionalIntensity": max(0, sun_elevation / 90) * (1 - cloud_cover * 0.5),
                "colorTemperatureK": self._get_color_temperature(time_of_day),
                "shadowSoftness": cloud_cover * 0.8 + 0.2
            }
        }

    def _calculate_sun_elevation(self, lat: float, lng: float, utc_time: datetime) -> float:
        """Calculate sun elevation angle (simplified)"""
        day_of_year = utc_time.timetuple().tm_yday
        declination = 23.45 * math.sin(math.radians(360 / 365 * (day_of_year - 81)))

        local_hour = (utc_time.hour + lng / 15) % 24
        hour_angle = 15 * (local_hour - 12)

        lat_rad = math.radians(lat)
        dec_rad = math.radians(declination)
        hour_rad = math.radians(hour_angle)

        elevation = math.degrees(math.asin(
            math.sin(lat_rad) * math.sin(dec_rad) +
            math.cos(lat_rad) * math.cos(dec_rad) * math.cos(hour_rad)
        ))
        return elevation

    def _calculate_sun_azimuth(self, lat: float, lng: float, utc_time: datetime) -> float:
        """Calculate sun azimuth angle (simplified)"""
        local_hour = (utc_time.hour + lng / 15) % 24
        # Simple approximation: east at sunrise, south at noon, west at sunset
        if local_hour < 6:
            return 90 + (local_hour / 6) * 45
        elif local_hour < 12:
            return 135 + ((local_hour - 6) / 6) * 45
        elif local_hour < 18:
            return 180 + ((local_hour - 12) / 6) * 90
        else:
            return 270 + ((local_hour - 18) / 6) * 90

    def _calculate_ambient_intensity(self, time_of_day: str, cloud_cover: float) -> float:
        """Calculate ambient light intensity"""
        base = {
            "dawn": 0.3, "morning": 0.7, "midday": 1.0,
            "afternoon": 0.85, "dusk": 0.4, "night": 0.05
        }.get(time_of_day, 0.5)
        return base * (1 - cloud_cover * 0.3)

    def _get_color_temperature(self, time_of_day: str) -> int:
        """Get color temperature in Kelvin based on time"""
        return {
            "dawn": 3000, "morning": 4500, "midday": 5500,
            "afternoon": 5000, "dusk": 3500, "night": 4000
        }.get(time_of_day, 5000)

    # ═══════════════════════════════════════════════════════════════
    # TEMPORAL BRANCHING
    # ═══════════════════════════════════════════════════════════════

    def _generate_temporal_states(self, node: Dict, current_hectares: float, risk_score: float) -> Dict[str, Any]:
        """
        Generate past, present, and predicted future states for temporal comparison.
        Enables "time slider" functionality in the AR experience.
        """
        history = node.get('yearlyHistory', node.get('history', {}))
        trend_direction = node.get('trendDirection', node.get('trends', {}).get('direction', 'STABLE'))
        trend_percent = node.get('trendChangePercent', node.get('trends', {}).get('change_percent', 5))
        forecast_2026 = node.get('forecast2026', node.get('trends', {}).get('forecast_2026', 0))

        # Past state (10 years ago or earliest available)
        past_year = None
        past_hectares = current_hectares * 1.3  # Default: 30% more forest
        past_risk = max(10, risk_score - 25)

        if history:
            sorted_years = sorted(history.keys())
            if sorted_years:
                past_year = int(sorted_years[0])
                # Estimate past forest cover from cumulative loss
                total_loss = sum(history.values())
                past_hectares = current_hectares + total_loss * 0.5  # Rough estimate

        # Current state
        current_year = datetime.now().year

        # Future predictions (5 and 10 years)
        future_5yr = self._predict_future_state(current_hectares, risk_score, trend_percent, 5)
        future_10yr = self._predict_future_state(current_hectares, risk_score, trend_percent, 10)

        return {
            "past": {
                "year": past_year or (current_year - 10),
                "label": f"{past_year or (current_year - 10)} - The Forest Before",
                "hectares": round(past_hectares, 0),
                "forestCover": min(1.0, past_hectares / (current_hectares * 1.5)),
                "riskScore": past_risk,
                "canopyDensity": 0.9,
                "visualFilter": "past_memory",
                "soundscape": "pristine_day",
                "description": f"In {past_year or (current_year - 10)}, this forest covered an estimated {int(past_hectares):,} hectares. The canopy was dense, the ecosystem intact."
            },
            "present": {
                "year": current_year,
                "label": f"{current_year} - Today",
                "hectares": round(current_hectares, 0),
                "forestCover": current_hectares / (past_hectares if past_hectares > 0 else current_hectares),
                "riskScore": risk_score,
                "canopyDensity": max(0.1, 0.9 - (risk_score / 100) * 0.7),
                "visualFilter": self._get_visual_filter_for_risk(risk_score),
                "soundscape": self._get_soundscape_for_risk(risk_score),
                "description": f"Today, {int(current_hectares):,} hectares remain. Risk level: {int(risk_score)}%."
            },
            "future5yr": {
                "year": current_year + 5,
                "label": f"{current_year + 5} - If Trends Continue",
                **future_5yr,
                "visualFilter": "future_predicted",
                "soundscape": future_5yr["soundscape"],
                "description": future_5yr["description"]
            },
            "future10yr": {
                "year": current_year + 10,
                "label": f"{current_year + 10} - Projected Future",
                **future_10yr,
                "visualFilter": "future_predicted",
                "soundscape": future_10yr["soundscape"],
                "description": future_10yr["description"]
            },
            "timelineMarkers": self._generate_timeline_markers(history, current_year)
        }

    def _predict_future_state(self, current_hectares: float, risk_score: float, trend_percent: float, years: int) -> Dict:
        """Predict future forest state based on trends"""
        # Exponential decay model
        annual_loss_rate = min(0.15, (risk_score / 100) * 0.1 + trend_percent / 100 * 0.5)
        predicted_hectares = current_hectares * ((1 - annual_loss_rate) ** years)
        predicted_risk = min(100, risk_score + years * 2 * (trend_percent / 10))
        predicted_canopy = max(0.05, 0.9 - (predicted_risk / 100) * 0.85)

        if predicted_hectares < current_hectares * 0.3:
            soundscape = "aftermath_silent"
            description = f"At current rates, only {int(predicted_hectares):,} hectares may remain. The silence would be deafening."
        elif predicted_hectares < current_hectares * 0.6:
            soundscape = "degraded_sparse"
            description = f"Projections show {int(predicted_hectares):,} hectares remaining—fragmented, struggling, but not yet gone."
        else:
            soundscape = "degraded_edge"
            description = f"An estimated {int(predicted_hectares):,} hectares could persist, though increasingly stressed."

        return {
            "hectares": round(predicted_hectares, 0),
            "forestCover": predicted_hectares / current_hectares if current_hectares > 0 else 0,
            "riskScore": round(predicted_risk, 0),
            "canopyDensity": round(predicted_canopy, 2),
            "soundscape": soundscape,
            "description": description
        }

    def _generate_timeline_markers(self, history: Dict, current_year: int) -> List[Dict]:
        """Generate timeline markers for the scrubber UI"""
        markers = []

        if history:
            for year, loss in sorted(history.items()):
                markers.append({
                    "year": int(year),
                    "type": "historical",
                    "value": loss,
                    "label": f"{year}: {int(loss):,} ha lost"
                })

        # Add current year marker
        markers.append({
            "year": current_year,
            "type": "present",
            "value": None,
            "label": "Today"
        })

        # Add future markers
        for offset in [5, 10]:
            markers.append({
                "year": current_year + offset,
                "type": "prediction",
                "value": None,
                "label": f"{current_year + offset} (Projected)"
            })

        return sorted(markers, key=lambda x: x["year"])

    # ═══════════════════════════════════════════════════════════════
    # SPATIAL SPECIES POIs
    # ═══════════════════════════════════════════════════════════════

    def _generate_species_pois(self, fauna: List[Dict], flora: List[Dict], center_lat: float, center_lng: float) -> List[Dict]:
        """
        Generate spatially-placed species Points of Interest for AR rendering.
        Each species gets precise offset coordinates for placement around the user.
        """
        species_pois = []
        poi_index = 0

        # Icon and 3D model mapping
        fauna_assets = {
            'jaguar': {'icon': '🐆', 'model': 'models/jaguar.glb', 'scale': 1.2},
            'puma': {'icon': '🐆', 'model': 'models/puma.glb', 'scale': 1.0},
            'eagle': {'icon': '🦅', 'model': 'models/eagle.glb', 'scale': 0.8},
            'hawk': {'icon': '🦅', 'model': 'models/hawk.glb', 'scale': 0.6},
            'macaw': {'icon': '🦜', 'model': 'models/macaw.glb', 'scale': 0.5},
            'parrot': {'icon': '🦜', 'model': 'models/parrot.glb', 'scale': 0.4},
            'monkey': {'icon': '🐒', 'model': 'models/monkey.glb', 'scale': 0.7},
            'orangutan': {'icon': '🦧', 'model': 'models/orangutan.glb', 'scale': 1.1},
            'gorilla': {'icon': '🦍', 'model': 'models/gorilla.glb', 'scale': 1.3},
            'elephant': {'icon': '🐘', 'model': 'models/elephant.glb', 'scale': 2.0},
            'tiger': {'icon': '🐅', 'model': 'models/tiger.glb', 'scale': 1.1},
            'sloth': {'icon': '🦥', 'model': 'models/sloth.glb', 'scale': 0.6},
            'turtle': {'icon': '🐢', 'model': 'models/turtle.glb', 'scale': 0.4},
            'frog': {'icon': '🐸', 'model': 'models/frog.glb', 'scale': 0.15},
            'snake': {'icon': '🐍', 'model': 'models/snake.glb', 'scale': 0.8},
            'butterfly': {'icon': '🦋', 'model': 'models/butterfly.glb', 'scale': 0.1},
            'default': {'icon': '🦁', 'model': 'models/generic_animal.glb', 'scale': 0.8}
        }

        flora_assets = {
            'tree': {'icon': '🌳', 'model': 'models/tree_tropical.glb', 'scale': 3.0},
            'palm': {'icon': '🌴', 'model': 'models/palm.glb', 'scale': 2.5},
            'orchid': {'icon': '🌺', 'model': 'models/orchid.glb', 'scale': 0.3},
            'fern': {'icon': '🌿', 'model': 'models/fern.glb', 'scale': 0.5},
            'flower': {'icon': '🌸', 'model': 'models/flower.glb', 'scale': 0.2},
            'default': {'icon': '🌱', 'model': 'models/plant_generic.glb', 'scale': 0.4}
        }

        # Process fauna - place in semicircle around viewer
        for i, animal in enumerate(fauna[:6]):
            name = animal.get('common_name', animal.get('name', 'Unknown'))
            status = animal.get('status', animal.get('conservation_status', 'Vulnerable'))
            name_lower = name.lower()

            # Find matching asset
            asset = fauna_assets['default']
            for key, val in fauna_assets.items():
                if key in name_lower:
                    asset = val
                    break

            # Calculate position in semicircle (front 180°)
            angle = math.radians(-90 + (180 / max(1, len(fauna[:6]) - 1)) * i) if len(fauna) > 1 else 0
            distance = 0.0015 + random.uniform(0, 0.0005)  # ~150-200m in degrees

            offset_lat = center_lat + distance * math.cos(angle)
            offset_lng = center_lng + distance * math.sin(angle) / math.cos(math.radians(center_lat))

            # Height offset based on species type (birds higher, ground animals lower)
            height_m = 2.0  # Default ground level
            if any(bird in name_lower for bird in ['eagle', 'hawk', 'macaw', 'parrot', 'bird', 'owl']):
                height_m = 15.0 + random.uniform(0, 10)
            elif any(tree_dweller in name_lower for tree_dweller in ['monkey', 'sloth', 'orangutan']):
                height_m = 8.0 + random.uniform(0, 7)

            species_pois.append({
                "id": f"species_poi_{poi_index}",
                "type": "fauna",
                "name": name,
                "scientificName": animal.get('scientific_name', ''),
                "status": status,
                "endemic": animal.get('endemic', False),
                "population": animal.get('population_estimate', None),

                "position": {
                    "lat": round(offset_lat, 6),
                    "lng": round(offset_lng, 6),
                    "heightM": round(height_m, 1),
                    "offsetFromCenter": {
                        "latDelta": round(offset_lat - center_lat, 6),
                        "lngDelta": round(offset_lng - center_lng, 6)
                    }
                },

                "display": {
                    "icon": asset['icon'],
                    "model3d": asset['model'],
                    "scale": asset['scale'],
                    "lookAtCamera": True,
                    "animationLoop": "idle",
                    "shadowEnabled": True
                },

                "interaction": {
                    "gazeDuration": 2.0,
                    "onGaze": "expand_info",
                    "onTap": "play_call",
                    "soundEffect": f"sounds/animals/{name_lower.replace(' ', '_')}.mp3",
                    "infoCard": self._generate_species_info_card(animal, "fauna")
                }
            })
            poi_index += 1

        # Process flora - place behind fauna
        for i, plant in enumerate(flora[:4]):
            name = plant.get('common_name', plant.get('name', 'Unknown'))
            status = plant.get('status', plant.get('conservation_status', 'Vulnerable'))
            name_lower = name.lower()

            # Find matching asset
            asset = flora_assets['default']
            for key, val in flora_assets.items():
                if key in name_lower:
                    asset = val
                    break

            # Place behind fauna (further out, different angles)
            angle = math.radians(-135 + (90 / max(1, len(flora[:4]) - 1)) * i) if len(flora) > 1 else math.radians(-90)
            distance = 0.002 + random.uniform(0, 0.001)  # ~200-300m

            offset_lat = center_lat + distance * math.cos(angle)
            offset_lng = center_lng + distance * math.sin(angle) / math.cos(math.radians(center_lat))

            species_pois.append({
                "id": f"species_poi_{poi_index}",
                "type": "flora",
                "name": name,
                "scientificName": plant.get('scientific_name', ''),
                "status": status,
                "endemic": plant.get('endemic', False),

                "position": {
                    "lat": round(offset_lat, 6),
                    "lng": round(offset_lng, 6),
                    "heightM": 0,
                    "offsetFromCenter": {
                        "latDelta": round(offset_lat - center_lat, 6),
                        "lngDelta": round(offset_lng - center_lng, 6)
                    }
                },

                "display": {
                    "icon": asset['icon'],
                    "model3d": asset['model'],
                    "scale": asset['scale'],
                    "lookAtCamera": False,
                    "animationLoop": "sway",
                    "shadowEnabled": True
                },

                "interaction": {
                    "gazeDuration": 2.5,
                    "onGaze": "expand_info",
                    "onTap": "highlight",
                    "soundEffect": "sounds/nature/leaves_rustle.mp3",
                    "infoCard": self._generate_species_info_card(plant, "flora")
                }
            })
            poi_index += 1

        return species_pois

    def _generate_species_info_card(self, species: Dict, species_type: str) -> Dict:
        """Generate detailed info card for species POI interaction"""
        name = species.get('common_name', species.get('name', 'Unknown'))
        status = species.get('status', species.get('conservation_status', 'Vulnerable'))

        # Status color and urgency
        status_colors = {
            'Critically Endangered': '#8B0000',
            'Endangered': '#FF0000',
            'Vulnerable': '#FF8C00',
            'Near Threatened': '#FFD700',
            'Least Concern': '#00AA00'
        }

        threat_descriptions = {
            'Critically Endangered': f"The {name} teeters on the brink of extinction. Every individual counts.",
            'Endangered': f"The {name} faces a very high risk of extinction in the wild.",
            'Vulnerable': f"The {name} is likely to become endangered unless threats are addressed.",
            'Near Threatened': f"The {name} is close to qualifying for a threatened category.",
            'Least Concern': f"The {name} is currently stable, but habitat loss remains a concern."
        }

        return {
            "title": name,
            "subtitle": species.get('scientific_name', ''),
            "statusLabel": status,
            "statusColor": status_colors.get(status, '#888888'),
            "population": species.get('population_estimate'),
            "endemic": species.get('endemic', False),
            "endemicLabel": "Found only here" if species.get('endemic') else None,
            "threatDescription": threat_descriptions.get(status, f"The {name} faces uncertain times ahead."),
            "habitatConnection": f"When this forest is lost, the {name} loses its home—forever." if species_type == "fauna" else f"The {name} is essential to this ecosystem's health.",
            "actionPrompt": "Learn how you can help protect this species."
        }

    # ═══════════════════════════════════════════════════════════════
    # IMMERSIVE CHAPTER GENERATION
    # ═══════════════════════════════════════════════════════════════

    def _generate_immersive_chapters(self, context: Dict, severity: str, risk_score: float, environment: Dict) -> List[Dict]:
        """
        Generate chapters with full sensory orchestration, tone-adapted narratives,
        and interactive elements.
        """
        chapters = []

        for chapter_id, config in self.chapter_config.items():
            # Get tone-adapted narrative
            tone_templates = self.tone_templates.get(chapter_id, {})
            narrative = tone_templates.get(severity, tone_templates.get('concerned', ''))

            try:
                description = narrative.format(**context)
            except (KeyError, ValueError):
                description = narrative

            # Determine sensory config based on chapter and risk
            sensory = self._get_chapter_sensory(chapter_id, risk_score, environment)

            chapters.append({
                "id": chapter_id,
                "number": len(chapters) + 1,
                "title": config["title"],
                "description": description,
                "severity": severity,

                # Camera
                "camera": {
                    "action": config["camera_action"],
                    "durationSeconds": config["duration_seconds"],
                    "transitionIn": config["transition_in"],
                    "transitionOut": config["transition_out"]
                },

                # Sensory orchestration
                "sensory": sensory,

                # Haptic feedback
                "haptic": {
                    "pattern": config["haptic_pattern"],
                    "intensity": self._get_haptic_intensity(severity)
                },

                # Gaze triggers for this chapter
                "gazeTriggers": self._get_chapter_gaze_triggers(chapter_id, risk_score)
            })

        return chapters

    def _get_chapter_sensory(self, chapter_id: str, risk_score: float, environment: Dict) -> Dict:
        """Get sensory configuration for a specific chapter"""
        time_of_day = environment.get("timeOfDay", "midday")

        # Chapter-specific soundscape selection
        soundscape_map = {
            "arrival": "pristine_dawn" if risk_score < 40 else "degraded_edge" if risk_score < 70 else "aftermath_silent",
            "land": "pristine_day" if risk_score < 50 else "degraded_sparse",
            "species": "pristine_day" if risk_score < 40 else "degraded_sparse" if risk_score < 70 else "aftermath_silent",
            "happened": "moment_revelation",
            "impact": "degraded_edge" if risk_score < 60 else "active_clearing" if risk_score < 80 else "aftermath_silent",
            "hope": "moment_hope"
        }

        # Chapter-specific visual filter
        filter_map = {
            "arrival": "healthy_morning" if risk_score < 40 else "stressed" if risk_score < 60 else "degraded",
            "land": "pristine" if risk_score < 50 else "stressed",
            "species": "pristine" if risk_score < 40 else "stressed" if risk_score < 70 else "degraded",
            "happened": "degraded" if risk_score < 60 else "burning" if risk_score < 80 else "devastated",
            "impact": "stressed" if risk_score < 50 else "degraded" if risk_score < 70 else "devastated",
            "hope": "hope_dawn"
        }

        soundscape_key = soundscape_map.get(chapter_id, "pristine_day")
        filter_key = filter_map.get(chapter_id, "stressed")

        return {
            "audio": {
                **self.soundscapes.get(soundscape_key, self.soundscapes["pristine_day"]),
                "voiceoverEnabled": True,
                "musicVolume": 0.3
            },
            "visual": {
                **self.visual_filters.get(filter_key, self.visual_filters["stressed"]),
                "depthOfField": chapter_id in ["species", "hope"],
                "motionBlur": chapter_id == "happened"
            }
        }

    def _get_haptic_intensity(self, severity: str) -> float:
        """Get haptic feedback intensity based on severity"""
        return {
            "calm": 0.2,
            "concerned": 0.4,
            "urgent": 0.6,
            "critical": 0.8,
            "crisis": 1.0
        }.get(severity, 0.5)

    def _get_chapter_gaze_triggers(self, chapter_id: str, risk_score: float) -> List[Dict]:
        """Get gaze-triggered events for a chapter"""
        triggers = []

        if chapter_id == "species":
            triggers.append({
                "target": "any_species_poi",
                "gazeDuration": 2.0,
                "action": "show_species_detail",
                "hapticFeedback": "light_tap"
            })

        if chapter_id == "happened":
            triggers.append({
                "target": "deforested_area",
                "gazeDuration": 3.0,
                "action": "play_timelapse",
                "hapticFeedback": "tension_rumble"
            })
            if risk_score > 60:
                triggers.append({
                    "target": "stump_model",
                    "gazeDuration": 2.5,
                    "action": "show_logging_stats",
                    "hapticFeedback": "heavy_pulse"
                })

        if chapter_id == "impact":
            triggers.append({
                "target": "community_marker",
                "gazeDuration": 2.0,
                "action": "show_community_story",
                "hapticFeedback": "gentle_pulse"
            })

        if chapter_id == "hope":
            triggers.append({
                "target": "restoration_zone",
                "gazeDuration": 2.0,
                "action": "play_restoration_vision",
                "hapticFeedback": "rising_hope"
            })

        return triggers

    # ═══════════════════════════════════════════════════════════════
    # INTERACTIVE ANCHORS
    # ═══════════════════════════════════════════════════════════════

    def _generate_interactive_anchors(self, risk_score: float, species_pois: List[Dict]) -> List[Dict]:
        """
        Generate interactive anchor points that respond to user gaze and actions.
        These make the story reactive rather than linear.
        """
        anchors = []

        # Species interaction anchors (from POIs)
        for poi in species_pois:
            anchors.append({
                "id": f"anchor_{poi['id']}",
                "type": "species",
                "position": poi["position"],
                "triggerRadius": 0.001,  # ~100m in degrees
                "gazeThreshold": poi["interaction"]["gazeDuration"],
                "actions": {
                    "onGazeEnter": "highlight_species",
                    "onGazeHold": poi["interaction"]["onGaze"],
                    "onGazeExit": "fade_highlight",
                    "onTap": poi["interaction"]["onTap"]
                },
                "linkedChapter": "species"
            })

        # Environmental story anchors
        if risk_score > 50:
            anchors.append({
                "id": "anchor_stump",
                "type": "environmental",
                "position": {"offsetAngle": 45, "distance": 0.001},
                "triggerRadius": 0.0008,
                "gazeThreshold": 3.0,
                "actions": {
                    "onGazeEnter": "show_ring_count",
                    "onGazeHold": "play_chapter",
                    "targetChapter": "happened"
                },
                "visualMarker": {
                    "model": "models/tree_stump.glb",
                    "pulseWhenActive": True
                },
                "linkedChapter": "happened"
            })

        if risk_score > 70:
            anchors.append({
                "id": "anchor_machinery",
                "type": "threat",
                "position": {"offsetAngle": -60, "distance": 0.002},
                "triggerRadius": 0.001,
                "gazeThreshold": 2.5,
                "actions": {
                    "onGazeEnter": "engine_rumble",
                    "onGazeHold": "show_deforestation_rate"
                },
                "visualMarker": {
                    "model": "models/logging_truck.glb",
                    "animation": "idle_rumble"
                },
                "linkedChapter": "happened"
            })

        # Community anchor
        anchors.append({
            "id": "anchor_community",
            "type": "human",
            "position": {"offsetAngle": 90, "distance": 0.0015},
            "triggerRadius": 0.001,
            "gazeThreshold": 2.0,
            "actions": {
                "onGazeEnter": "community_voices",
                "onGazeHold": "play_chapter",
                "targetChapter": "impact"
            },
            "visualMarker": {
                "model": "models/village_marker.glb",
                "pulseWhenActive": True
            },
            "linkedChapter": "impact"
        })

        # Hope/restoration anchor
        anchors.append({
            "id": "anchor_sapling",
            "type": "hope",
            "position": {"offsetAngle": 0, "distance": 0.0005},
            "triggerRadius": 0.0006,
            "gazeThreshold": 2.0,
            "actions": {
                "onGazeEnter": "seedling_glow",
                "onGazeHold": "grow_animation",
                "onTap": "donate_prompt"
            },
            "visualMarker": {
                "model": "models/seedling.glb",
                "animation": "grow_loop"
            },
            "linkedChapter": "hope"
        })

        return anchors

    # ═══════════════════════════════════════════════════════════════
    # NARRATOR GENERATION
    # ═══════════════════════════════════════════════════════════════

    def _generate_narrator(self, context: Dict, severity: str, location_name: str) -> Dict[str, Any]:
        """
        Generate complete narrator configuration with voiceover scripts,
        timing cues, and pronunciation guides for the entire experience.
        """
        # Select narrator voice based on severity
        narrator_key = self._select_narrator_voice(severity)
        narrator_voice = self.narrator_voices.get(narrator_key, self.narrator_voices["david_attenborough"])

        # Generate pronunciation guide for this location
        location_pronunciation = self._get_pronunciation(location_name)

        # Build chapter-by-chapter voiceover scripts
        chapter_voiceovers = {}
        total_duration = 0

        for chapter_id in self.chapter_config.keys():
            script_data = self.narrator_scripts.get(chapter_id, {}).get(severity, {})
            if not script_data:
                # Fallback to concerned level
                script_data = self.narrator_scripts.get(chapter_id, {}).get("concerned", {"script": [], "totalDuration": 0})

            # Format script with context values
            formatted_script = self._format_narrator_script(script_data.get("script", []), context)

            chapter_voiceovers[chapter_id] = {
                "script": formatted_script,
                "totalDuration": script_data.get("totalDuration", 15),
                "ssml": self._build_ssml(formatted_script, narrator_voice),
                "cuePoints": self._extract_cue_points(formatted_script)
            }
            total_duration += script_data.get("totalDuration", 15)

        return {
            "voice": narrator_voice,
            "chapterVoiceovers": chapter_voiceovers,
            "totalNarrationDuration": total_duration,
            "pronunciationGuide": location_pronunciation,

            "settings": {
                "autoAdvance": True,
                "allowSkip": True,
                "subtitlesEnabled": True,
                "voiceoverEnabled": True,
                "backgroundMusicDuck": 0.3  # Duck music to 30% during narration
            },

            "accessibility": {
                "transcriptAvailable": True,
                "signLanguageOverlay": False,
                "audioDescriptionAvailable": True,
                "slowNarrationOption": True
            }
        }

    def _select_narrator_voice(self, severity: str) -> str:
        """Select appropriate narrator voice based on severity"""
        voice_mapping = {
            "calm": "david_attenborough",
            "concerned": "david_attenborough",
            "urgent": "passionate_advocate",
            "critical": "passionate_advocate",
            "crisis": "local_witness"
        }
        return voice_mapping.get(severity, "david_attenborough")

    def _get_pronunciation(self, location_name: str) -> Dict[str, str]:
        """Get pronunciation guide for location and related terms"""
        guide = {}
        for term, pronunciation in self.pronunciation_guide.items():
            if term.lower() in location_name.lower():
                guide[term] = pronunciation
        return guide

    def _format_narrator_script(self, script: List[Dict], context: Dict) -> List[Dict]:
        """Format narrator script with context values"""
        formatted = []
        for item in script:
            new_item = item.copy()
            if "text" in new_item and new_item.get("type") != "pause":
                try:
                    new_item["text"] = new_item["text"].format(**context)
                except (KeyError, ValueError):
                    pass  # Keep original if formatting fails
            formatted.append(new_item)
        return formatted

    def _build_ssml(self, script: List[Dict], voice: Dict) -> str:
        """Build SSML markup for text-to-speech synthesis"""
        ssml_parts = ['<speak>']

        for item in script:
            if item.get("type") == "pause":
                pause_type = item["text"].replace("[", "").replace("]", "").lower()
                ssml_parts.append(self.ssml_templates.get(pause_type, '<break time="500ms"/>'))
            else:
                text = item.get("text", "")
                style = item.get("style", "normal")

                if style == "emphasis":
                    text = f'<emphasis level="strong">{text}</emphasis>'
                elif style == "whisper":
                    text = f'<prosody volume="soft" rate="slow">{text}</prosody>'
                elif style == "urgent":
                    text = f'<prosody rate="fast" pitch="+1st">{text}</prosody>'
                elif style == "solemn":
                    text = f'<prosody rate="slow" pitch="-1st">{text}</prosody>'
                elif style == "gravity":
                    text = f'<prosody rate="slow" pitch="-2st"><emphasis level="moderate">{text}</emphasis></prosody>'
                elif style == "wonder":
                    text = f'<prosody pitch="+1st">{text}</prosody>'
                elif style == "staccato":
                    text = f'<prosody rate="x-slow">{text}</prosody><break time="200ms"/>'

                ssml_parts.append(text)

        ssml_parts.append('</speak>')
        return ' '.join(ssml_parts)

    def _extract_cue_points(self, script: List[Dict]) -> List[Dict]:
        """Extract timing cue points for synchronization"""
        cues = []
        for item in script:
            if item.get("type") != "pause" and "timing" in item:
                cues.append({
                    "time": item["timing"],
                    "duration": item.get("duration", 2.0),
                    "text": item.get("text", "")[:50],  # First 50 chars for preview
                    "style": item.get("style", "normal")
                })
        return cues

    # ═══════════════════════════════════════════════════════════════
    # DISCOVERY & EXPLORATION GENERATION
    # ═══════════════════════════════════════════════════════════════

    def _generate_discovery_content(self, lat: float, lng: float, species_count: int) -> Dict[str, Any]:
        """
        Generate discovery content, secrets, and exploration features
        for this specific location.
        """
        # Determine which secrets are available at this location
        available_secrets = []
        for secret_id, secret in self.secrets.items():
            # Use deterministic randomness based on location
            location_seed = hash(f"{lat:.4f}_{lng:.4f}_{secret_id}")
            random.seed(location_seed)
            if random.random() < secret.get("occurrence", 0.5):
                available_secrets.append({
                    "id": secret["id"],
                    "name": secret["name"],
                    "rarity": secret["rarity"],
                    "hint": self._generate_secret_hint(secret),
                    "triggerCondition": secret["triggerCondition"],
                    "reward": secret["reward"]
                })

        # Reset random seed
        random.seed()

        # Determine available easter eggs
        available_easter_eggs = [
            {
                "id": egg_id,
                "trigger": egg["trigger"],
                "response": egg["response"],
                "effect": egg["effect"]
            }
            for egg_id, egg in self.easter_eggs.items()
        ]

        # Calculate location-specific achievements
        location_achievements = {
            "explorer": {
                "progress_contribution": 1,
                "description": "Visited this location"
            },
            "species_spotter": {
                "progress_contribution": species_count,
                "description": f"Discovered {species_count} species here"
            }
        }

        return {
            "secrets": available_secrets,
            "secretCount": len(available_secrets),

            "easterEggs": available_easter_eggs,

            "achievements": location_achievements,

            "explorationPaths": self.exploration_paths,

            "completionTracking": {
                "chapters": list(self.chapter_config.keys()),
                "species_count": species_count,
                "interactions_available": ["temporal_slider", "species_pois", "anchors"],
                "estimated_full_exploration_minutes": 15 + (species_count * 2)
            },

            "replayValue": {
                "alternateNarrators": list(self.narrator_voices.keys()),
                "alternateExplorationPaths": list(self.exploration_paths.keys()),
                "hiddenContentPercentage": len(available_secrets) * 10,
                "seasonalContent": self._get_seasonal_content()
            }
        }

    def _generate_secret_hint(self, secret: Dict) -> str:
        """Generate a cryptic hint for a secret"""
        hints = {
            "hidden_species": "Look where the light doesn't reach...",
            "ancient_tree": "The oldest among them stands taller than time...",
            "water_source": "Follow the sound of life's beginning...",
            "sunrise_moment": "Be here when the world awakens...",
            "full_story": "Every story has a beginning, middle, and end...",
            "species_collector": "Some creatures only reveal themselves to the patient...",
            "time_traveler": "Past, present, future—all are here...",
            "silent_witness": "Sometimes the greatest discovery comes from stillness..."
        }
        return hints.get(secret["id"].replace("secret_", ""), "Something hidden awaits...")

    def _get_seasonal_content(self) -> Dict:
        """Get seasonal content variations"""
        month = datetime.now().month
        if month in [3, 4, 5]:
            season = "spring"
            theme = "renewal"
        elif month in [6, 7, 8]:
            season = "summer"
            theme = "abundance"
        elif month in [9, 10, 11]:
            season = "autumn"
            theme = "transition"
        else:
            season = "winter"
            theme = "dormancy"

        return {
            "currentSeason": season,
            "thematicFocus": theme,
            "specialContent": f"seasonal/{season}_overlay.json"
        }

    # ═══════════════════════════════════════════════════════════════
    # MUSICAL JOURNEY GENERATION
    # ═══════════════════════════════════════════════════════════════

    def _generate_musical_journey(self, severity: str, risk_score: float) -> Dict[str, Any]:
        """
        Generate the adaptive musical soundtrack configuration
        for the entire experience.
        """
        # Select emotional arc based on severity
        if severity in ["crisis", "critical"]:
            arc_key = "crisis"
        elif severity == "calm":
            arc_key = "calm"
        else:
            arc_key = "standard"

        emotional_arc = self.emotional_arcs[arc_key]

        # Build chapter-by-chapter music configuration
        chapter_music = {}
        for stage in emotional_arc["stages"]:
            chapter_id = stage["chapter"]
            theme = self.musical_themes[stage["theme"]]

            chapter_music[chapter_id] = {
                "theme": stage["theme"],
                "themeDetails": theme,
                "intensity": stage["intensity"],
                "activeLayers": stage["layers"],
                "layerConfigs": {
                    layer: self.music_layers[layer]
                    for layer in stage["layers"]
                    if layer in self.music_layers
                },
                "transitionType": "crossfade",
                "transitionDuration": 2.0
            }

        # Determine which stingers are relevant
        relevant_stingers = []
        if risk_score > 60:
            relevant_stingers.append(self.stingers["heartbreak"])
            relevant_stingers.append(self.stingers["revelation"])
        if risk_score < 40:
            relevant_stingers.append(self.stingers["discovery"])
        relevant_stingers.append(self.stingers["hope_rising"])
        relevant_stingers.append(self.stingers["call_to_action"])

        return {
            "emotionalArc": {
                "name": emotional_arc["name"],
                "key": arc_key
            },

            "chapterMusic": chapter_music,

            "stingers": relevant_stingers,

            "globalSettings": {
                "masterVolume": 0.7,
                "duckDuringNarration": True,
                "duckLevel": 0.3,
                "crossfadeDuration": 2.0,
                "spatialAudio": True,
                "binauralEnabled": True
            },

            "interactionResponses": {
                "species_gaze": {
                    "action": "add_layer",
                    "layer": "nature_harmonics",
                    "fadeIn": 1.0
                },
                "temporal_transition": {
                    "action": "theme_shift",
                    "transitionDuration": 1.5
                },
                "anchor_activation": {
                    "action": "play_stinger",
                    "stinger": "discovery"
                },
                "risk_reveal": {
                    "action": "add_layer",
                    "layer": "tension_build",
                    "fadeIn": 0.5
                }
            },

            "dynamicMixing": {
                "enabled": True,
                "basedOn": ["user_movement", "gaze_direction", "chapter_progress"],
                "responsiveness": 0.7  # How quickly music responds to changes
            }
        }

    # ═══════════════════════════════════════════════════════════════
    # PERSONALIZATION GENERATION
    # ═══════════════════════════════════════════════════════════════

    def _generate_personalization_config(self) -> Dict[str, Any]:
        """
        Generate personalization configuration for adaptive storytelling.
        This defines how the experience adapts to user preferences.
        """
        return {
            "preferenceDimensions": self.preference_dimensions,

            "adaptationRules": {
                rule_id: {
                    "description": self._describe_adaptation_rule(rule_id),
                    "adjustments": rule["adjustments"]
                }
                for rule_id, rule in self.adaptation_rules.items()
            },

            "sessionMemory": self.session_memory,

            "returnVisitorContent": self.return_visitor_content,

            "learningConfig": {
                "enabled": True,
                "minSessionsForAdaptation": 2,
                "preferenceSmoothingFactor": 0.3,  # How quickly preferences update
                "explicitFeedbackWeight": 2.0,  # Weight given to explicit user feedback
                "implicitFeedbackWeight": 1.0   # Weight given to behavioral signals
            },

            "onboarding": {
                "showPreferenceQuestions": True,
                "questions": [
                    {
                        "id": "pacing_pref",
                        "question": "How would you like to experience this story?",
                        "options": [
                            {"label": "Take my time—let me absorb everything", "value": 0.6},
                            {"label": "A balanced experience", "value": 1.0},
                            {"label": "Show me the highlights", "value": 1.5}
                        ],
                        "maps_to": "pacing"
                    },
                    {
                        "id": "content_pref",
                        "question": "What interests you most?",
                        "options": [
                            {"label": "The science and data", "value": {"data_depth": 0.8}},
                            {"label": "The stories and impact", "value": {"emotional_intensity": 0.8}},
                            {"label": "The wildlife and nature", "value": {"species_interest": 0.8}},
                            {"label": "A bit of everything", "value": {}}
                        ],
                        "maps_to": "multiple"
                    }
                ]
            },

            "accessibilityOptions": {
                "reducedMotion": False,
                "highContrast": False,
                "screenReaderOptimized": False,
                "cognitiveSimplification": False,
                "extendedTimings": False
            }
        }

    def _describe_adaptation_rule(self, rule_id: str) -> str:
        """Generate human-readable description of adaptation rule"""
        descriptions = {
            "high_data_affinity": "User shows strong interest in data and statistics",
            "high_emotional": "User responds well to emotional content",
            "fast_pace": "User prefers a quicker experience",
            "contemplative": "User enjoys taking time to reflect",
            "explorer": "User enjoys discovering content on their own",
            "species_enthusiast": "User shows particular interest in wildlife"
        }
        return descriptions.get(rule_id, "Adaptive behavior based on user preferences")

    # ═══════════════════════════════════════════════════════════════
    # THE SILENT HUNT - PROXIMITY-DRIVEN SPECIES INTERACTION
    # ═══════════════════════════════════════════════════════════════

    def _generate_silent_hunt(self, fauna: List[Dict], hectares: float, risk_score: float, environment: Dict) -> Dict[str, Any]:
        """
        Generate The Silent Hunt configuration - world-first proximity-driven
        species interaction where distance, speed, and noise affect animal behavior.

        Key mechanics:
        - Approaching species quiets ambient sounds, increases animal sounds
        - Moving too fast or making noise causes animal to flee
        - If habitat is fragmented (high risk), fleeing animals have nowhere to go
        """
        huntable_species = []
        time_of_day = environment.get("timeOfDay", "day")

        for animal in fauna[:6]:  # Max 6 huntable species
            name = animal.get('common_name', animal.get('name', 'Unknown')).lower()
            status = animal.get('status', 'Vulnerable')

            # Find behavior profile
            behavior = self.species_behaviors.get("default").copy()
            for key in self.species_behaviors:
                if key in name:
                    behavior = self.species_behaviors[key].copy()
                    break

            # Adjust behavior based on conservation status
            status_modifiers = {
                'Critically Endangered': {'flightDistance': 1.5, 'curiosityFactor': 0.3},
                'Endangered': {'flightDistance': 1.3, 'curiosityFactor': 0.4},
                'Vulnerable': {'flightDistance': 1.1, 'curiosityFactor': 0.5},
                'Near Threatened': {'flightDistance': 1.0, 'curiosityFactor': 0.6},
                'Least Concern': {'flightDistance': 0.8, 'curiosityFactor': 0.7}
            }
            mod = status_modifiers.get(status, {})
            behavior['flightDistance'] = int(behavior['flightDistance'] * mod.get('flightDistance', 1.0))
            behavior['curiosityFactor'] = behavior['curiosityFactor'] * mod.get('curiosityFactor', 1.0)

            # Adjust for time of day
            if time_of_day == "night":
                if behavior.get('category') in ['apex_predator']:
                    behavior['curiosityFactor'] *= 1.5  # Predators bolder at night
                else:
                    behavior['flightDistance'] *= 1.3  # Prey more nervous

            # Calculate habitat fragmentation impact
            habitat_intact = hectares >= behavior.get('habitatRequirement', 100)
            fragmentation_severity = min(1.0, risk_score / 100)

            # Determine escape options
            if not habitat_intact or fragmentation_severity > 0.7:
                escape_outcome = "vanish"  # Animal has nowhere to flee
                escape_narration = self.hunt_narration["species_vanished"]
            elif fragmentation_severity > 0.4:
                escape_outcome = "trapped"  # Limited escape routes
                escape_narration = self.hunt_narration["species_trapped"]
            else:
                escape_outcome = "flee"  # Normal escape
                escape_narration = self.hunt_narration["species_fled"]

            huntable_species.append({
                "id": animal.get('id', name.replace(' ', '_')),
                "name": animal.get('common_name', animal.get('name', 'Unknown')),
                "scientificName": animal.get('scientific_name', ''),
                "conservationStatus": status,

                "behavior": {
                    "flightDistanceM": behavior['flightDistance'],
                    "panicDistanceM": behavior['panicDistance'],
                    "speedSensitivity": behavior['speedSensitivity'],
                    "noiseSensitivity": behavior['noiseSensitivity'],
                    "curiosityFactor": round(behavior['curiosityFactor'], 2),
                    "category": behavior.get('category', 'generic')
                },

                "sounds": behavior['sounds'],
                "animations": behavior['animations'],

                "habitatStatus": {
                    "requiredHectares": behavior.get('habitatRequirement', 100),
                    "availableHectares": hectares,
                    "isIntact": habitat_intact,
                    "fragmentationSeverity": round(fragmentation_severity, 2)
                },

                "escapeOutcome": {
                    "type": escape_outcome,
                    "narration": escape_narration,
                    "lesson": self._get_fragmentation_lesson(escape_outcome)
                }
            })

        return {
            "enabled": True,
            "version": "1.0",

            "species": huntable_species,

            "proximityZones": self.proximity_zones,
            "movementThresholds": self.movement_thresholds,

            "audioMixing": {
                "ambientTrack": environment.get("soundscape", "pristine_day"),
                "transitionSpeed": 0.5,  # How fast audio mixes change
                "spatialAudio": True,
                "binauralEnabled": True,
                "heartbeatAtClose": True
            },

            "visualEffects": {
                "focusBlurEnabled": True,
                "vignetteOnIntimate": True,
                "particleTrailOnFlee": True,
                "ghostFadeOnVanish": True
            },

            "hapticFeedback": {
                "heartbeatPulseNearby": True,
                "sharpPulseOnFlee": True,
                "prolongedVibrationOnVanish": True
            },

            "narration": self.hunt_narration,

            "achievements": {
                "species_whisperer": {
                    "requirement": "reach_connection_zone",
                    "badge": "badges/species_whisperer.png",
                    "title": "Species Whisperer"
                },
                "silent_observer": {
                    "requirement": "observe_3_species_without_fleeing",
                    "badge": "badges/silent_observer.png",
                    "title": "Silent Observer"
                },
                "witness_to_loss": {
                    "requirement": "witness_vanish_event",
                    "badge": "badges/witness_to_loss.png",
                    "title": "Witness to Loss"
                }
            },

            "tutorial": {
                "enabled": True,
                "steps": [
                    {"message": "Move slowly to approach wildlife.", "trigger": "first_aware_zone"},
                    {"message": "The quieter you are, the closer you can get.", "trigger": "first_close_zone"},
                    {"message": "Sudden movements will startle them.", "trigger": "first_flee_event"}
                ]
            }
        }

    def _get_fragmentation_lesson(self, outcome: str) -> str:
        """Get educational lesson based on flee outcome"""
        lessons = {
            "flee": "In intact forests, animals have escape routes. Connectivity is survival.",
            "trapped": "Fragmented forests create islands. Animals run out of places to hide.",
            "vanish": "When habitat shrinks below critical thresholds, there's nowhere left to go. This is extinction in real-time."
        }
        return lessons.get(outcome, "")

    # ═══════════════════════════════════════════════════════════════
    # ECOSYSTEM SIMULATION GENERATION
    # ═══════════════════════════════════════════════════════════════

    def _generate_ecosystem_simulation(self, fauna: List[Dict], flora: List[Dict], hectares: float, risk_score: float) -> Dict[str, Any]:
        """
        Generate ecosystem simulation data showing interconnections
        and chain reactions in the forest ecosystem.
        """
        # Build species present list
        species_present = []
        for animal in fauna:
            name = animal.get('common_name', animal.get('name', '')).lower()
            for key in self.food_web:
                if key in name:
                    species_present.append(key)
                    break

        # Calculate active chain reactions based on risk
        active_reactions = []
        if risk_score >= 70:
            active_reactions.append(self.chain_reactions["deforestation_severe"])
        elif risk_score >= 40:
            active_reactions.append(self.chain_reactions["deforestation_medium"])
        elif risk_score >= 20:
            active_reactions.append(self.chain_reactions["deforestation_small"])

        # Check for apex predator loss
        apex_present = any(s in species_present for s in ["jaguar", "puma", "tiger"])
        if not apex_present and hectares < 500:
            active_reactions.append(self.chain_reactions["apex_predator_loss"])

        # Build interactive relationships
        interactive_relationships = {}
        for species_id in species_present:
            if species_id in self.food_web:
                web = self.food_web[species_id]
                interactive_relationships[species_id] = {
                    "role": web["role"],
                    "connections": {
                        "preys_on": [p for p in web["preyOn"] if p in species_present or p in ["fruit", "insects", "nectar"]],
                        "predators": [p for p in web["predators"] if p in species_present],
                        "symbiotic": web["symbioticWith"]
                    },
                    "ecosystem_impact": web["populationImpact"],
                    "if_extinct": web["extinctionCascade"]
                }

        # Generate available ecosystem interactions
        available_interactions = []
        for interaction_id, interaction in self.ecosystem_interactions.items():
            # Check if relevant species are present
            available_interactions.append({
                "id": interaction_id,
                "name": interaction["name"],
                "description": interaction["description"],
                "trigger": interaction["trigger"],
                "durationSeconds": interaction["duration"],
                "steps": interaction["steps"],
                "lesson": interaction["lesson"]
            })

        # Find relevant symbiotic discoveries
        relevant_symbiosis = []
        for symbiosis_id, symbiosis in self.symbiosis_discoveries.items():
            relevant_symbiosis.append({
                "id": symbiosis_id,
                "name": symbiosis["name"],
                "species": symbiosis["species"],
                "trigger": symbiosis["trigger"],
                "description": symbiosis["description"],
                "narration": symbiosis["narration"],
                "dataConnection": symbiosis["data_connection"]
            })

        return {
            "enabled": True,

            "foodWeb": {
                "speciesPresent": species_present,
                "relationships": interactive_relationships,
                "visualizationType": "network_graph"
            },

            "chainReactions": {
                "active": active_reactions,
                "potential": list(self.chain_reactions.keys())
            },

            "interactiveExperiences": available_interactions,

            "symbioticDiscoveries": relevant_symbiosis,

            "ecosystemHealth": {
                "biodiversityIndex": len(species_present) / 10,  # Normalized 0-1
                "trophicBalance": 0.8 if apex_present else 0.4,
                "fragmentationRisk": risk_score / 100,
                "overallHealth": max(0, 1 - (risk_score / 100) + (len(species_present) / 20))
            },

            "visualization": {
                "showFoodWebOnDemand": True,
                "animateChainReactions": True,
                "highlightSymbiosis": True,
                "pulseConnections": True
            }
        }

    # ═══════════════════════════════════════════════════════════════
    # IMMERSIVE SYSTEMS GENERATION
    # ═══════════════════════════════════════════════════════════════

    def _generate_immersive_systems(self, node: Dict, severity: str, species_count: int, environment: Dict) -> Dict[str, Any]:
        """
        Generate configuration for all immersive interaction systems
        including time-based wildlife, weather impacts, and emotional moments.
        """
        time_of_day = environment.get("timeOfDay", "day")
        risk_score = node.get('riskScore', node.get('risk_score', 50))
        hectares = node.get('hectares', 100)

        # Get current time wildlife config
        time_wildlife = self.time_based_wildlife.get(
            "night" if time_of_day == "night" else "dusk" if time_of_day == "dusk" else "dawn" if time_of_day == "dawn" else "day"
        )

        # Determine weather state
        humidity = environment.get("atmosphere", {}).get("humidity", 0.7)
        fire_active = node.get('fire_data', {}).get('active_fires', 0) > 0

        if fire_active:
            weather_state = "fire_smoke"
        elif humidity > 0.9:
            weather_state = "rain_heavy"
        elif humidity > 0.75:
            weather_state = "rain_light"
        elif humidity < 0.4:
            weather_state = "drought"
        else:
            weather_state = None

        weather_impact = self.weather_wildlife_impact.get(weather_state) if weather_state else None

        # Determine active emotional moments
        active_moments = []

        # Check for last of species
        fauna = node.get('fauna_at_risk', [])
        for animal in fauna:
            if animal.get('population_estimate', 1000) <= 10:
                active_moments.append({
                    "type": "last_of_species",
                    "species": animal.get('common_name', 'Unknown'),
                    "config": self.emotional_moments["last_of_species"]
                })

        # Always include dawn of hope at end
        active_moments.append({
            "type": "dawn_of_hope",
            "trigger": "complete_hope_chapter",
            "config": self.emotional_moments["dawn_of_hope"]
        })

        # Elder tree death if high deforestation
        if risk_score > 60:
            active_moments.append({
                "type": "elder_tree_death",
                "trigger": "approach_logged_area",
                "config": self.emotional_moments["elder_tree_death"]
            })

        # Generate data revelations
        current_year = datetime.now().year
        yearly_history = node.get('yearlyHistory', {})
        recent_loss = sum(yearly_history.get(str(y), 0) for y in range(current_year - 5, current_year + 1))

        # Calculate extinction year projection
        if recent_loss > 0 and hectares > 0:
            years_to_zero = hectares / (recent_loss / 5) if recent_loss > 0 else 999
            extinction_year = current_year + int(years_to_zero)
        else:
            extinction_year = current_year + 100

        data_revelations = {
            "realTimeLoss": {
                **self.data_revelations["real_time_loss"],
                "calculation": {
                    "globalLossRateHaPerMinute": 10,  # ~5 million ha/year globally
                    "showSinceSessionStart": True
                }
            },
            "whatIfProjection": {
                **self.data_revelations["what_if_projection"],
                "calculatedYear": extinction_year,
                "currentHectares": hectares,
                "annualLossRate": recent_loss / 5 if recent_loss > 0 else 0
            },
            "speciesClock": {
                **self.data_revelations["species_clock"],
                "speciesAtRisk": species_count,
                "averageExtinctionProbability": min(95, risk_score + 20)
            }
        }

        # User action consequences
        action_consequences = {
            "virtualTreePlant": {
                **self.action_consequences["virtual_tree_plant"],
                "localizedImpact": {
                    "hectaresPerTree": 0.001,  # 100 trees = 0.1 ha
                    "carbonOffsetTonnes": 0.5,
                    "speciesBenefited": min(3, species_count)
                }
            },
            "virtualDonate": {
                **self.action_consequences["virtual_donate"],
                "localizedImpact": {
                    "costPerHectare": node.get('reforest_plan', {}).get('cost_per_hectare_usd', 2500),
                    "hectaresNeeded": hectares,
                    "totalCost": node.get('reforest_plan', {}).get('estimated_cost_usd', hectares * 2500)
                }
            }
        }

        return {
            "timeBasedWildlife": {
                "currentTimeOfDay": time_of_day,
                "config": time_wildlife,
                "transitionSchedule": {
                    "dawn": "05:30",
                    "day": "07:00",
                    "dusk": "18:00",
                    "night": "20:00"
                }
            },

            "weatherImpact": {
                "currentState": weather_state,
                "config": weather_impact,
                "allStates": list(self.weather_wildlife_impact.keys())
            },

            "emotionalMoments": {
                "active": active_moments,
                "allMoments": list(self.emotional_moments.keys())
            },

            "dataRevelations": data_revelations,

            "actionConsequences": action_consequences,

            "interactionModes": {
                "gestureControls": {
                    "swipeToTravel": True,
                    "pinchToZoomTime": True,
                    "holdToReveal": True,
                    "shakeToReset": True
                },
                "voiceCommands": {
                    "enabled": False,  # Future feature
                    "commands": ["show species", "what happened", "show hope"]
                },
                "gazeInteraction": {
                    "enabled": True,
                    "dwellTimeMs": 2000,
                    "highlightOnHover": True
                }
            },

            "accessibilityFeatures": {
                "audioDescriptions": True,
                "hapticGuidance": True,
                "simplifiedMode": False,
                "highContrastMarkers": False
            }
        }

    # ═══════════════════════════════════════════════════════════════
    # HELPER METHODS
    # ═══════════════════════════════════════════════════════════════

    def _extract_population(self, node: Dict) -> int:
        """Extract population from various possible locations in data"""
        population = node.get('population', 0)
        if population == 0:
            human_impacts = node.get('human_impacts', {})
            affected = human_impacts.get('affected_population', {})
            population = affected.get('total', 0)
        if population == 0:
            # Try GIS overlay analysis
            gis = node.get('gis_analysis', {})
            overlay = gis.get('overlay_analysis', {})
            pop_impact = overlay.get('population_impact', {})
            population = pop_impact.get('estimated_population_in_buffer', 0)
        return population

    def _calculate_restoration_cost(self, node: Dict, hectares: float) -> float:
        """Calculate or retrieve restoration cost"""
        financial = node.get('financial_analysis', {})
        cost = financial.get('restoration_cost_usd', 0)
        if cost == 0:
            reforest = node.get('reforest_plan', {})
            cost = reforest.get('estimated_cost_usd', 0)
        if cost == 0:
            cost = hectares * 2500  # Default $2500/ha
        return cost

    def _estimate_recovery_time(self, node: Dict) -> str:
        """Estimate recovery time based on data"""
        recovery = node.get('recovery_potential', {})
        score = recovery.get('score', 50)
        if score > 70:
            return "3-5"
        elif score > 50:
            return "5-10"
        elif score > 30:
            return "10-15"
        else:
            return "15-25"

    def _calculate_loss_rate_detailed(self, node: Dict) -> Dict:
        """Calculate detailed loss rate from historical data"""
        history = node.get('yearlyHistory', node.get('history', {}))

        if not history or len(history) < 2:
            return {
                "available": False,
                "display": "N/A",
                "annualPercent": None,
                "totalLoss": None,
                "trend": "unknown"
            }

        try:
            years = sorted(history.keys())
            first_year = years[0]
            last_year = years[-1]
            first_val = history[first_year]
            last_val = history[last_year]
            years_diff = int(last_year) - int(first_year)

            if first_val and years_diff > 0:
                total_loss = sum(history.values())
                annual_avg = total_loss / years_diff
                change_percent = (annual_avg / (first_val + 0.001)) * 100

                # Determine trend
                recent_years = sorted(history.keys())[-3:]
                recent_losses = [history[y] for y in recent_years]
                if len(recent_losses) >= 2:
                    if recent_losses[-1] > recent_losses[0] * 1.1:
                        trend = "accelerating"
                    elif recent_losses[-1] < recent_losses[0] * 0.9:
                        trend = "decelerating"
                    else:
                        trend = "steady"
                else:
                    trend = "unknown"

                return {
                    "available": True,
                    "display": f"{abs(change_percent):.1f}%/yr",
                    "annualPercent": round(change_percent, 2),
                    "totalLoss": round(total_loss, 0),
                    "annualAverage": round(annual_avg, 0),
                    "period": f"{first_year}-{last_year}",
                    "trend": trend
                }
        except Exception:
            pass

        return {
            "available": False,
            "display": "N/A",
            "annualPercent": None,
            "totalLoss": None,
            "trend": "unknown"
        }

    def _calculate_severity(self, risk_score: float, loss_rate: Dict) -> str:
        """Calculate emotional severity level for tone adaptation"""
        # Base on risk score
        if risk_score >= 80:
            base_severity = "crisis"
        elif risk_score >= 60:
            base_severity = "critical"
        elif risk_score >= 40:
            base_severity = "urgent"
        elif risk_score >= 20:
            base_severity = "concerned"
        else:
            base_severity = "calm"

        # Escalate if loss rate is accelerating
        if loss_rate.get("trend") == "accelerating":
            severity_order = ["calm", "concerned", "urgent", "critical", "crisis"]
            current_idx = severity_order.index(base_severity)
            return severity_order[min(current_idx + 1, len(severity_order) - 1)]

        return base_severity

    def _get_visual_filter_for_risk(self, risk_score: float) -> str:
        """Get visual filter preset based on risk score"""
        if risk_score >= 80:
            return "devastated"
        elif risk_score >= 60:
            return "degraded"
        elif risk_score >= 40:
            return "stressed"
        else:
            return "pristine"

    def _get_soundscape_for_risk(self, risk_score: float) -> str:
        """Get soundscape based on risk score"""
        if risk_score >= 80:
            return "aftermath_silent"
        elif risk_score >= 60:
            return "degraded_edge"
        elif risk_score >= 40:
            return "degraded_sparse"
        else:
            return "pristine_day"

    def _get_default_sensory(self, risk_score: float, environment: Dict) -> Dict:
        """Get default sensory configuration"""
        return {
            "audio": self.soundscapes.get(self._get_soundscape_for_risk(risk_score)),
            "visual": self.visual_filters.get(self._get_visual_filter_for_risk(risk_score)),
            "voiceoverLanguage": "en-US",
            "subtitlesEnabled": True,
            "hapticEnabled": True
        }

    def _estimate_communities(self, population: int) -> int:
        """Estimate number of communities from population"""
        if population <= 0:
            return 0
        return max(1, int(population / 750))
