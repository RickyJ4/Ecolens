/**
 * EcoLens Story Viewer - Web Narrator
 * Uses browser's Web Speech API for narration on web platforms
 * Provides David Attenborough-style narration with British English voice
 */

const WebNarrator = {
    // State
    _initialized: false,
    _speaking: false,
    _enabled: true,
    _utterance: null,
    _voices: [],
    _selectedVoice: null,
    _onCompleteCallback: null,
    _voicesLoaded: false,
    _pendingText: null,
    _pendingCallback: null,
    _userInteracted: false,
    _hasSpeech: false, // true only if Web Speech API is available

    // Configuration for documentary-style narration
    // More natural settings - closer to 1.0 sounds less robotic
    _config: {
        rate: 0.95,      // Near-normal speed, slightly slower for clarity
        pitch: 1.0,      // Natural pitch (0.9 makes it sound robotic)
        volume: 1.0
    },

    // Preferred voice patterns - prioritize natural-sounding voices
    // Google voices are generally the most natural
    _preferredVoices: [
        'Google UK English Female',   // Very natural Google voice
        'Google UK English Male',     // Natural Google voice
        'Google US English',          // Fallback Google
        'Samantha',                   // macOS natural voice
        'Karen',                      // macOS Australian (natural)
        'Daniel',                     // macOS/iOS British
        'Microsoft Zira',             // Windows natural female
        'Microsoft David',            // Windows natural male
        'Microsoft George',           // Windows British
        'en-GB',
        'en-US',
        'en_GB'
    ],

    /**
     * Initialize the Web Speech API narrator
     */
    init() {
        if (this._initialized) return;

        console.log('[WebNarrator] === INIT START ===');

        // Check if Web Speech API is available (not in Android WebView)
        if (!('speechSynthesis' in window) || typeof window.speechSynthesis === 'undefined') {
            console.warn('[WebNarrator] Web Speech API not available (likely Android WebView)');
            this._hasSpeech = false;
            this._initialized = true; // Mark initialized so callers don't retry
            return;
        }

        this._hasSpeech = true;
        console.log('[WebNarrator] speechSynthesis available:', !!window.speechSynthesis);

        // Setup user interaction listener for browsers that require it
        this._setupInteractionListener();

        // Load voices (may be async)
        this._loadVoices();

        // Some browsers load voices asynchronously
        if (this._hasSpeech && speechSynthesis.onvoiceschanged !== undefined) {
            speechSynthesis.onvoiceschanged = () => {
                console.log('[WebNarrator] onvoiceschanged event fired');
                this._loadVoices();
            };
        }

        // Chrome sometimes needs a kick to load voices
        setTimeout(() => {
            if (!this._voicesLoaded) {
                console.log('[WebNarrator] Retrying voice load after timeout...');
                this._loadVoices();
            }
        }, 1000);

        this._initialized = true;
        console.log('[WebNarrator] === INIT COMPLETE ===');
    },

    /**
     * Setup listener for user interaction (required by some browsers)
     */
    _setupInteractionListener() {
        const markInteracted = () => {
            if (!this._userInteracted) {
                console.log('[WebNarrator] User interaction detected - speech unlocked');
                this._userInteracted = true;

                // If there's pending speech, play it now
                if (this._pendingText) {
                    console.log('[WebNarrator] Playing pending speech after interaction');
                    const text = this._pendingText;
                    const callback = this._pendingCallback;
                    this._pendingText = null;
                    this._pendingCallback = null;
                    this._doSpeak(text, callback);
                }
            }
        };

        // Listen for any user interaction
        ['click', 'touchstart', 'keydown'].forEach(event => {
            document.addEventListener(event, markInteracted, { once: false, passive: true });
        });
    },

    /**
     * Load available voices and select the best one
     */
    _loadVoices() {
        if (!this._hasSpeech) return;
        this._voices = speechSynthesis.getVoices();
        console.log(`[WebNarrator] Found ${this._voices.length} voices`);

        if (this._voices.length === 0) {
            // Voices not ready yet, will be called again via onvoiceschanged
            console.log('[WebNarrator] No voices yet, waiting for onvoiceschanged...');
            return;
        }

        this._voicesLoaded = true;

        // Log first few voices for debugging
        console.log('[WebNarrator] Available voices:');
        this._voices.slice(0, 10).forEach((v, i) => {
            console.log(`  ${i}: ${v.name} (${v.lang}) ${v.localService ? '[local]' : '[remote]'}`);
        });

        // Find the best British English voice
        this._selectedVoice = this._findBestVoice();

        if (this._selectedVoice) {
            console.log(`[WebNarrator] Selected voice: ${this._selectedVoice.name} (${this._selectedVoice.lang})`);
        } else {
            console.log('[WebNarrator] No preferred voice found, will use default');
        }
    },

    /**
     * Find the best available voice for documentary narration
     * Prioritizes natural-sounding voices (Google/cloud voices are usually better)
     */
    _findBestVoice() {
        // Separate remote (cloud) and local voices - remote usually sound more natural
        const remoteVoices = this._voices.filter(v => !v.localService);
        const localVoices = this._voices.filter(v => v.localService);

        console.log('[WebNarrator] Remote voices:', remoteVoices.length);
        console.log('[WebNarrator] Local voices:', localVoices.length);

        // First try preferred voices in remote voices (most natural)
        for (const pattern of this._preferredVoices) {
            const match = remoteVoices.find(v =>
                v.name.toLowerCase().includes(pattern.toLowerCase())
            );
            if (match) {
                console.log('[WebNarrator] Found preferred remote voice:', match.name);
                return match;
            }
        }

        // Then try preferred voices in local voices
        for (const pattern of this._preferredVoices) {
            const match = localVoices.find(v =>
                v.name.toLowerCase().includes(pattern.toLowerCase())
            );
            if (match) {
                console.log('[WebNarrator] Found preferred local voice:', match.name);
                return match;
            }
        }

        // Fallback: any remote English voice (cloud voices are more natural)
        const remoteEnglish = remoteVoices.find(v => v.lang.startsWith('en'));
        if (remoteEnglish) {
            console.log('[WebNarrator] Using remote English voice:', remoteEnglish.name);
            return remoteEnglish;
        }

        // Fallback: any British English voice
        const britishVoice = this._voices.find(v =>
            v.lang.startsWith('en-GB') || v.lang.startsWith('en_GB')
        );
        if (britishVoice) {
            console.log('[WebNarrator] Using British voice:', britishVoice.name);
            return britishVoice;
        }

        // Last resort: any English voice
        const englishVoice = this._voices.find(v => v.lang.startsWith('en'));
        if (englishVoice) {
            console.log('[WebNarrator] Using English voice:', englishVoice.name);
        }
        return englishVoice || null;
    },

    /**
     * Speak text with documentary narration style
     * @param {string} text - Text to speak
     * @param {Function} onComplete - Callback when speech finishes
     */
    speak(text, onComplete = null) {
        console.log('[WebNarrator] === SPEAK CALLED ===');
        console.log('[WebNarrator] initialized:', this._initialized);
        console.log('[WebNarrator] enabled:', this._enabled);
        console.log('[WebNarrator] voicesLoaded:', this._voicesLoaded);
        console.log('[WebNarrator] userInteracted:', this._userInteracted);
        console.log('[WebNarrator] text length:', text?.length || 0);

        if (!this._initialized || !this._enabled || !this._hasSpeech) {
            console.log('[WebNarrator] Not initialized, disabled, or no speech API — skipping');
            if (onComplete) onComplete();
            return;
        }

        if (!text || text.trim() === '') {
            console.log('[WebNarrator] Empty text, skipping');
            if (onComplete) onComplete();
            return;
        }

        // If user hasn't interacted yet, queue the speech
        if (!this._userInteracted) {
            console.log('[WebNarrator] Waiting for user interaction before speaking...');
            console.log('[WebNarrator] Queuing text for later playback');
            this._pendingText = text;
            this._pendingCallback = onComplete;

            // Show hint to user
            this._showSpeechHint();
            return;
        }

        // Actually speak
        this._doSpeak(text, onComplete);
    },

    /**
     * Show hint that user needs to interact for speech
     */
    _showSpeechHint() {
        // Check if hint already exists
        if (document.getElementById('speechHint')) return;

        const hint = document.createElement('div');
        hint.id = 'speechHint';
        hint.innerHTML = '🔊 Tap anywhere to enable narration';
        hint.style.cssText = `
            position: fixed;
            bottom: 100px;
            left: 50%;
            transform: translateX(-50%);
            background: rgba(0, 210, 106, 0.9);
            color: white;
            padding: 12px 24px;
            border-radius: 24px;
            font-size: 14px;
            font-weight: 500;
            z-index: 10000;
            pointer-events: none;
            animation: fadeInUp 0.5s ease;
            box-shadow: 0 4px 20px rgba(0, 210, 106, 0.4);
        `;

        // Add animation keyframes
        if (!document.getElementById('speechHintStyles')) {
            const style = document.createElement('style');
            style.id = 'speechHintStyles';
            style.textContent = `
                @keyframes fadeInUp {
                    from { opacity: 0; transform: translateX(-50%) translateY(20px); }
                    to { opacity: 1; transform: translateX(-50%) translateY(0); }
                }
            `;
            document.head.appendChild(style);
        }

        document.body.appendChild(hint);

        // Remove after 5 seconds
        setTimeout(() => {
            hint.remove();
        }, 5000);
    },

    /**
     * Actually perform the speech (internal)
     */
    _doSpeak(text, onComplete) {
        // Stop any current speech
        this.stop();

        console.log('[WebNarrator] _doSpeak:', text.substring(0, 50) + '...');

        // Clean the text for speech
        const cleanText = this._cleanText(text);
        console.log('[WebNarrator] Clean text length:', cleanText.length);

        // Create utterance
        this._utterance = new SpeechSynthesisUtterance(cleanText);

        // Set voice if we have a preferred one
        if (this._selectedVoice) {
            this._utterance.voice = this._selectedVoice;
            console.log('[WebNarrator] Using voice:', this._selectedVoice.name);
        } else {
            console.log('[WebNarrator] Using default system voice');
        }

        // Set speech parameters for documentary style
        this._utterance.rate = this._config.rate;
        this._utterance.pitch = this._config.pitch;
        this._utterance.volume = this._config.volume;

        console.log('[WebNarrator] Speech params:', this._config);

        // Store callback
        this._onCompleteCallback = onComplete;

        // Set up event handlers
        this._utterance.onstart = () => {
            this._speaking = true;
            console.log('[WebNarrator] ✓ Started speaking');

            // Hide the hint if visible
            const hint = document.getElementById('speechHint');
            if (hint) hint.remove();
        };

        this._utterance.onend = () => {
            this._speaking = false;
            console.log('[WebNarrator] ✓ Finished speaking');
            if (this._onCompleteCallback) {
                this._onCompleteCallback();
                this._onCompleteCallback = null;
            }
        };

        this._utterance.onerror = (event) => {
            this._speaking = false;
            console.warn('[WebNarrator] ✗ Speech error:', event.error);
            if (this._onCompleteCallback) {
                this._onCompleteCallback();
                this._onCompleteCallback = null;
            }
        };

        // Chrome has a bug where long text gets cut off - need to resume periodically
        this._startChromeBugWorkaround();

        // Speak!
        if (!this._hasSpeech) return;
        console.log('[WebNarrator] Calling speechSynthesis.speak()...');
        speechSynthesis.speak(this._utterance);
        console.log('[WebNarrator] speechSynthesis.speak() called');
        console.log('[WebNarrator] speechSynthesis.speaking:', speechSynthesis.speaking);
        console.log('[WebNarrator] speechSynthesis.pending:', speechSynthesis.pending);
    },

    /**
     * Chrome has a bug where speech stops after ~15 seconds
     * This workaround keeps it alive
     */
    _startChromeBugWorkaround() {
        // Clear any existing interval
        if (this._chromeBugInterval) {
            clearInterval(this._chromeBugInterval);
        }

        // Resume every 10 seconds to prevent Chrome from stopping
        if (!this._hasSpeech) return;
        this._chromeBugInterval = setInterval(() => {
            if (speechSynthesis.speaking && !speechSynthesis.paused) {
                speechSynthesis.pause();
                speechSynthesis.resume();
            } else if (!speechSynthesis.speaking) {
                clearInterval(this._chromeBugInterval);
            }
        }, 10000);
    },

    /**
     * Clean text for better speech synthesis
     * Optimized for natural-sounding narration
     */
    _cleanText(text) {
        return text
            // Remove markdown
            .replace(/\*\*([^*]+)\*\*/g, '$1')
            .replace(/\*([^*]+)\*/g, '$1')
            .replace(/_([^_]+)_/g, '$1')
            .replace(/`([^`]+)`/g, '$1')
            // Convert ellipsis to natural pause
            .replace(/\.\.\./g, '...')
            // Em dashes to natural pauses
            .replace(/—/g, ', ')
            .replace(/ - /g, ', ')
            // Add slight pauses after sentences for natural rhythm
            .replace(/\. /g, '. ')
            // Improve number reading
            .replace(/(\d),(\d)/g, '$1$2')  // Remove commas in numbers like 1,000
            .replace(/%/g, ' percent')
            .replace(/CO2/g, 'C O 2')
            .replace(/ ha\b/g, ' hectares')
            .replace(/ km\b/g, ' kilometers')
            .replace(/km²/g, ' square kilometers')
            .replace(/m²/g, ' square meters')
            // Clean up extra whitespace
            .replace(/\s+/g, ' ')
            .trim();
    },

    /**
     * Stop current speech
     */
    stop() {
        console.log('[WebNarrator] stop() called');
        if (this._hasSpeech && speechSynthesis.speaking) {
            speechSynthesis.cancel();
            console.log('[WebNarrator] Cancelled current speech');
        }
        if (this._chromeBugInterval) {
            clearInterval(this._chromeBugInterval);
            this._chromeBugInterval = null;
        }
        this._speaking = false;
        this._utterance = null;
        this._onCompleteCallback = null;
    },

    /**
     * Pause speech
     */
    pause() {
        if (this._hasSpeech && speechSynthesis.speaking) {
            speechSynthesis.pause();
        }
    },

    /**
     * Resume speech
     */
    resume() {
        if (this._hasSpeech && speechSynthesis.paused) {
            speechSynthesis.resume();
        }
    },

    /**
     * Toggle narration enabled state
     */
    toggle() {
        this._enabled = !this._enabled;
        if (!this._enabled) {
            this.stop();
        }
        console.log('[WebNarrator] Enabled:', this._enabled);
        return this._enabled;
    },

    /**
     * Check if currently speaking
     */
    isSpeaking() {
        return this._speaking;
    },

    /**
     * Check if narrator is available
     */
    isAvailable() {
        return 'speechSynthesis' in window;
    },

    /**
     * Check if narrator is enabled
     */
    isEnabled() {
        return this._enabled;
    },

    /**
     * Test function - call from console to verify speech works
     */
    test() {
        console.log('[WebNarrator] === TEST START ===');
        console.log('[WebNarrator] initialized:', this._initialized);
        console.log('[WebNarrator] enabled:', this._enabled);
        console.log('[WebNarrator] voicesLoaded:', this._voicesLoaded);
        console.log('[WebNarrator] voices count:', this._voices.length);
        console.log('[WebNarrator] selectedVoice:', this._selectedVoice?.name || 'none');
        console.log('[WebNarrator] userInteracted:', this._userInteracted);
        console.log('[WebNarrator] speechSynthesis available:', 'speechSynthesis' in window);

        if (!this._initialized) {
            console.log('[WebNarrator] Not initialized! Calling init()...');
            this.init();
        }

        // Force user interaction flag for testing
        this._userInteracted = true;

        const testText = "This is a test of the EcoLens narrator system.";
        console.log('[WebNarrator] Speaking test text...');
        this.speak(testText, () => {
            console.log('[WebNarrator] Test complete!');
        });
    },

    /**
     * Get debug status
     */
    getStatus() {
        return {
            initialized: this._initialized,
            enabled: this._enabled,
            voicesLoaded: this._voicesLoaded,
            voiceCount: this._voices.length,
            selectedVoice: this._selectedVoice?.name || null,
            userInteracted: this._userInteracted,
            speaking: this._speaking,
            apiAvailable: 'speechSynthesis' in window
        };
    }
};

// Make globally available
window.WebNarrator = WebNarrator;

// Auto-initialize on load
console.log('[WebNarrator] Script loaded, auto-initializing...');
WebNarrator.init();
