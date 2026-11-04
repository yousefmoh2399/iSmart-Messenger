/**
 * iSmart Dynamic Island - Client Renderer & State Machine (Apple / Nova Grade Ultra)
 * Fully compatible with Windows 7 (32-bit), 10, and 11.
 * Features calm Apple acoustic chime sound engine, interactive audio scrubbing & speeds,
 * in-island mini chat with quick responses, search & category filtering, and live call activity.
 */

(function () {
  // State definitions and exact window dimensions (Apple Fluid Architecture)
  const WINDOW_WIDTH = 440;
  const STATE_DIMENSIONS = {
    idle: { width: 260, height: 42, winWidth: 264, winHeight: 44 },
    welcome: { width: 390, height: 110, winWidth: 440, winHeight: 124 },
    notification: { width: 400, height: 92, winWidth: 440, winHeight: 106 },
    reply: { width: 410, height: 175, winWidth: 440, winHeight: 190 },
    chats: { width: 420, height: 430, winWidth: 440, winHeight: 446 },
    chatview: { width: 420, height: 480, winWidth: 440, winHeight: 496 },
    audio: { width: 410, height: 72, winWidth: 440, winHeight: 86 },
    call: { width: 390, height: 72, winWidth: 440, winHeight: 86 },
    progress: { width: 380, height: 80, winWidth: 440, winHeight: 96 },
    settings: { width: 420, height: 460, winWidth: 440, winHeight: 476 },
  };

  let currentState = "idle";
  let activeNotification = null;
  let activeChat = null;
  let activeAudioState = null;
  let activeCallState = null;
  let callTimerInterval = null;
  let dismissTimer = null;
  let isHovered = false;
  let cachedChats = [];
  let currentChatFilterTab = "all";
  let chatSearchQuery = "";
  let currentAudioSpeed = "1.0x";
  let currentUserId = null;
  const mediaCache = new Map();
  const conversationMessagesCache = new Map();
  let currentUserName = null;

  let currentSettings = {
    enabled: true,
    privacyMode: "full",
    theme: "obsidian",
    soundEnabled: true,
    startMinimizedOnBoot: true,
    yOffset: 0,
  };

  // DOM Elements
  const capsule = document.getElementById("island-capsule");
  const views = {
    idle: document.getElementById("view-idle"),
    welcome: document.getElementById("view-welcome"),
    notification: document.getElementById("view-notification"),
    reply: document.getElementById("view-reply"),
    chats: document.getElementById("view-chats"),
    chatview: document.getElementById("view-chatview"),
    audio: document.getElementById("view-audio"),
    call: document.getElementById("view-call"),
    progress: document.getElementById("view-progress"),
    settings: document.getElementById("view-settings"),
  };

  // Clock & Badge
  const clockEl = document.getElementById("idle-clock");
  const unreadBadge = document.getElementById("idle-unread-badge");

  // Welcome elements
  const welcomeUserEl = document.getElementById("welcome-user-name");
  const welcomeAvatarEl = document.getElementById("welcome-avatar");
  const welcomeAvatarFallback = document.getElementById("welcome-avatar-fallback");

  // Notification elements
  const notifAvatar = document.getElementById("notif-avatar");
  const notifSender = document.getElementById("notif-sender");
  const notifTime = document.getElementById("notif-time");
  const notifText = document.getElementById("notif-text");

  // Reply elements
  const replyAvatar = document.getElementById("reply-avatar");
  const replySender = document.getElementById("reply-sender-name");
  const replyQuoteSender = document.getElementById("reply-quote-sender");
  const replyQuoteText = document.getElementById("reply-quote-text");
  const replyInput = document.getElementById("reply-text-input");
  const replySubmitBtn = document.getElementById("reply-submit-btn");
  const replyStatus = document.getElementById("reply-status-text");

  // Chats list, search & filter
  const chatsContainer = document.getElementById("chats-items-container");
  const chatsSearchInput = document.getElementById("chats-search-input");
  const chatsSearchClear = document.getElementById("chats-search-clear");
  const tabFilterAll = document.getElementById("tab-filter-all");
  const tabFilterUnread = document.getElementById("tab-filter-unread");
  const tabFilterGroups = document.getElementById("tab-filter-groups");

  // Mini Chatview elements
  const chatviewAvatar = document.getElementById("chatview-avatar");
  const chatviewAvatarFallback = document.getElementById("chatview-avatar-fallback");
  const chatviewTargetName = document.getElementById("chatview-target-name");
  const chatviewStatusText = document.getElementById("chatview-status-text");
  const chatviewMessagesContainer = document.getElementById("chatview-messages");
  const chatviewInput = document.getElementById("chatview-text-input");
  const chatviewSendBtn = document.getElementById("chatview-send-btn");

  // Audio elements
  const audioAvatar = document.getElementById("audio-avatar");
  const audioAvatarFallback = document.getElementById("audio-avatar-fallback");
  const audioSender = document.getElementById("audio-sender");
  const audioTime = document.getElementById("audio-time");
  const audioPlayPauseBtn = document.getElementById("audio-play-pause-btn");
  const audioPlayIcon = document.getElementById("audio-play-icon");
  const audioPauseIcon = document.getElementById("audio-pause-icon");
  const audioSpeedBtn = document.getElementById("audio-speed-btn");
  const audioProgressScrubber = document.getElementById("audio-progress-scrubber");
  const audioProgressBar = document.getElementById("audio-progress-bar");

  // Call elements
  const callAvatar = document.getElementById("call-avatar");
  const callAvatarFallback = document.getElementById("call-avatar-fallback");
  const callCallerName = document.getElementById("call-caller-name");
  const callStatusLabel = document.getElementById("call-status-label");
  const callAcceptBtn = document.getElementById("call-accept-btn");
  const callDeclineBtn = document.getElementById("call-decline-btn");

  // Progress elements
  const progressLabel = document.getElementById("progress-label");
  const progressPercent = document.getElementById("progress-percent");
  const progressBarFill = document.getElementById("progress-bar-fill");

  // Settings elements
  const toggleEnabled = document.getElementById("setting-toggle-enabled");
  const toggleBootHidden = document.getElementById("setting-toggle-boot-hidden");
  const selectPrivacy = document.getElementById("setting-privacy-select");
  const selectPosition = document.getElementById("setting-position-select");
  const toggleSound = document.getElementById("setting-toggle-sound");
  const themeDots = document.querySelectorAll(".theme-dot");
  const btnPreviewSound = document.getElementById("btn-preview-sound");
  const btnTestNotif = document.getElementById("btn-test-notification");
  const btnTestAudio = document.getElementById("btn-test-audio");
  const btnTestCall = document.getElementById("btn-test-call");

  // =========================================================================
  // Calm Apple-Grade Acoustic Synthesizer (Serene Glass Bell & Marimba)
  // =========================================================================
  let audioCtx = null;
  function getAudioContext() {
    if (!audioCtx) {
      const AudioContextClass = window.AudioContext || window.webkitAudioContext;
      if (AudioContextClass) {
        audioCtx = new AudioContextClass();
      }
    }
    if (audioCtx && audioCtx.state === "suspended") {
      audioCtx.resume();
    }
    return audioCtx;
  }

  /**
   * Serene Apple Glass Bell Notification Chime
   * Two harmonious sine waves with warm lowpass filtering and natural exponential decay.
   * Super soft, gentle attack (zero sharp click), silky relaxation tone.
   */
  function playAppleChime() {
    if (!currentSettings.soundEnabled) return;
    try {
      const ctx = getAudioContext();
      if (!ctx) return;
      const now = ctx.currentTime;

      // Master lowpass filter to remove any harsh treble (warm Apple acoustics)
      const filter = ctx.createBiquadFilter();
      filter.type = "lowpass";
      filter.frequency.setValueAtTime(1400, now);
      filter.Q.setValueAtTime(0.7, now);
      filter.connect(ctx.destination);

      // Note 1: Foundation Tone - E5 (659.25 Hz)
      const osc1 = ctx.createOscillator();
      const gain1 = ctx.createGain();
      osc1.type = "sine";
      osc1.frequency.setValueAtTime(659.25, now);

      gain1.gain.setValueAtTime(0.0001, now);
      gain1.gain.exponentialRampToValueAtTime(0.12, now + 0.018);
      gain1.gain.exponentialRampToValueAtTime(0.0001, now + 0.55);

      osc1.connect(gain1);
      gain1.connect(filter);
      osc1.start(now);
      osc1.stop(now + 0.56);

      // Note 2: Harmonious Glass Marimba - B5 (987.77 Hz), offset by 75ms
      const osc2 = ctx.createOscillator();
      const gain2 = ctx.createGain();
      osc2.type = "sine";
      osc2.frequency.setValueAtTime(987.77, now + 0.075);

      gain2.gain.setValueAtTime(0.0001, now);
      gain2.gain.setValueAtTime(0.0001, now + 0.075);
      gain2.gain.exponentialRampToValueAtTime(0.15, now + 0.095);
      gain2.gain.exponentialRampToValueAtTime(0.0001, now + 0.75);

      osc2.connect(gain2);
      gain2.connect(filter);
      osc2.start(now + 0.075);
      osc2.stop(now + 0.76);

      // Note 3: Ambient Glass Shimmer - E6 (1318.5 Hz, ultra subtle)
      const osc3 = ctx.createOscillator();
      const gain3 = ctx.createGain();
      osc3.type = "sine";
      osc3.frequency.setValueAtTime(1318.5, now + 0.08);

      gain3.gain.setValueAtTime(0.0001, now);
      gain3.gain.setValueAtTime(0.0001, now + 0.08);
      gain3.gain.exponentialRampToValueAtTime(0.025, now + 0.098);
      gain3.gain.exponentialRampToValueAtTime(0.0001, now + 0.65);

      osc3.connect(gain3);
      gain3.connect(filter);
      osc3.start(now + 0.08);
      osc3.stop(now + 0.66);
    } catch (_) {}
  }

  /**
   * Tactile iOS Haptic Tock (Gentle Wooden / Water Drop Pop on Sent)
   */
  function playSentPop() {
    if (!currentSettings.soundEnabled) return;
    try {
      const ctx = getAudioContext();
      if (!ctx) return;
      const now = ctx.currentTime;

      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = "sine";
      // Gentle downward frequency slide
      osc.frequency.setValueAtTime(320, now);
      osc.frequency.exponentialRampToValueAtTime(150, now + 0.038);

      gain.gain.setValueAtTime(0.0001, now);
      gain.gain.linearRampToValueAtTime(0.07, now + 0.006);
      gain.gain.exponentialRampToValueAtTime(0.0001, now + 0.048);

      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(now);
      osc.stop(now + 0.05);
    } catch (_) {}
  }

  /**
   * Gentle Apple-style error buzz for rejected or failed sends
   */
  function playErrorBuzz() {
    if (!currentSettings.soundEnabled) return;
    try {
      const ctx = getAudioContext();
      if (!ctx) return;
      const now = ctx.currentTime;
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = "sawtooth";
      osc.frequency.setValueAtTime(140, now);
      osc.frequency.setValueAtTime(110, now + 0.08);
      gain.gain.setValueAtTime(0.0001, now);
      gain.gain.linearRampToValueAtTime(0.06, now + 0.01);
      gain.gain.exponentialRampToValueAtTime(0.0001, now + 0.22);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(now);
      osc.stop(now + 0.22);
    } catch (_) {}
  }

  /**
   * Calm Success Glass Ping (Progress completed)
   */
  function playSuccessChime() {
    if (!currentSettings.soundEnabled) return;
    try {
      const ctx = getAudioContext();
      if (!ctx) return;
      const now = ctx.currentTime;

      const filter = ctx.createBiquadFilter();
      filter.type = "lowpass";
      filter.frequency.setValueAtTime(1500, now);
      filter.connect(ctx.destination);

      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = "sine";
      osc.frequency.setValueAtTime(880, now);
      osc.frequency.exponentialRampToValueAtTime(1318.5, now + 0.09);

      gain.gain.setValueAtTime(0.0001, now);
      gain.gain.exponentialRampToValueAtTime(0.09, now + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.0001, now + 0.55);

      osc.connect(gain);
      gain.connect(filter);
      osc.start(now);
      osc.stop(now + 0.56);
    } catch (_) {}
  }

  // =========================================================================
  // Avatar Safe Image Setter (Zero Broken Images)
  // =========================================================================
  function setSafeAvatar(imgEl, fallbackEl, url, fallbackInitial = "") {
    if (!imgEl) return;
    if (fallbackEl && fallbackInitial) fallbackEl.textContent = fallbackInitial;

    if (!url || typeof url !== "string" || !url.trim() || url.includes("undefined")) {
      imgEl.style.display = "none";
      if (fallbackEl) fallbackEl.style.display = "flex";
      return;
    }

    const trimmedUrl = url.trim();

    if (trimmedUrl.startsWith("data:")) {
      imgEl.src = trimmedUrl;
      imgEl.style.display = "block";
      if (fallbackEl) fallbackEl.style.display = "none";
      return;
    }

    if (mediaCache.has(trimmedUrl)) {
      const cached = mediaCache.get(trimmedUrl);
      if (cached) {
        imgEl.src = cached;
        imgEl.style.display = "block";
        if (fallbackEl) fallbackEl.style.display = "none";
        return;
      } else {
        imgEl.style.display = "none";
        if (fallbackEl) fallbackEl.style.display = "flex";
        return;
      }
    }

    if (window.islandBridge?.fetchMedia) {
      window.islandBridge.fetchMedia(trimmedUrl).then((res) => {
        if (res && res.success && res.dataUri) {
          mediaCache.set(trimmedUrl, res.dataUri);
          imgEl.src = res.dataUri;
          imgEl.style.display = "block";
          if (fallbackEl) fallbackEl.style.display = "none";
        } else {
          mediaCache.set(trimmedUrl, null);
          imgEl.style.display = "none";
          if (fallbackEl) fallbackEl.style.display = "flex";
        }
      }).catch(() => {
        imgEl.style.display = "none";
        if (fallbackEl) fallbackEl.style.display = "flex";
      });
    } else {
      imgEl.style.display = "block";
      imgEl.src = trimmedUrl;
      imgEl.onerror = () => {
        imgEl.style.display = "none";
        if (fallbackEl) fallbackEl.style.display = "flex";
      };
      imgEl.onload = () => {
        if (fallbackEl) fallbackEl.style.display = "none";
      };
    }
  }

  function getInitial(name) {
    if (!name || typeof name !== "string") return "👤";
    const trimmed = name.trim();
    return trimmed.length > 0 ? trimmed.charAt(0).toUpperCase() : "👤";
  }

  // =========================================================================
  // State Transition Machine
  // =========================================================================
  // State Transition Machine (Apple Spring Physics & Zero-Jitter Expansion)
  // =========================================================================
  let collapseTimer = null;

  function setMode(mode, data = {}) {
    if (!STATE_DIMENSIONS[mode]) mode = "idle";
    const previousState = currentState;
    currentState = mode;

    if (dismissTimer) {
      clearTimeout(dismissTimer);
      dismissTimer = null;
    }

    if (collapseTimer) {
      clearTimeout(collapseTimer);
      collapseTimer = null;
    }

    if (callTimerInterval) {
      clearInterval(callTimerInterval);
      callTimerInterval = null;
    }

    const prevDim = STATE_DIMENSIONS[previousState] || { width: 260, height: 42, winWidth: 264, winHeight: 44 };
    const targetDim = STATE_DIMENSIONS[mode] || { width: 260, height: 42, winWidth: 264, winHeight: 44 };

    if (mode !== "idle") {
      try { window.focus(); } catch (_) {}
    }

    if (mode === "idle" && previousState !== "idle") {
      // COLLAPSE FLOW: Morph capsule back into idle notch first, then adjust OS window
      capsule.className = "island-capsule state-idle is-collapsing";
      capsule.style.width = targetDim.width + "px";
      capsule.style.height = targetDim.height + "px";

      Object.keys(views).forEach((key) => {
        if (views[key]) {
          views[key].classList.toggle("active", key === "idle");
        }
      });

      const onCollapseEnd = (e) => {
        if (e && e.target !== capsule) return;
        if (e && e.propertyName !== "height" && e.propertyName !== "width") return;
        capsule.removeEventListener("transitionend", onCollapseEnd);
        if (collapseTimer) {
          clearTimeout(collapseTimer);
          collapseTimer = null;
        }

        if (currentState === "idle") {
          capsule.classList.remove("is-collapsing");
          if (window.islandBridge?.resizeWindow) {
            window.islandBridge.resizeWindow(targetDim.winWidth || 264, targetDim.winHeight || 44);
          }
        }
      };

      capsule.addEventListener("transitionend", onCollapseEnd);
      collapseTimer = setTimeout(onCollapseEnd, 380);
    } else {
      // EXPAND / MORPH FLOW
      capsule.classList.remove("is-collapsing");

      // Expand window bounds immediately so capsule can blossom downwards smoothly
      const targetWinHeight = Math.max(prevDim.winHeight || 44, targetDim.winHeight);
      const targetWinWidth = targetDim.winWidth || WINDOW_WIDTH;
      if (window.islandBridge?.resizeWindow) {
        window.islandBridge.resizeWindow(targetWinWidth, targetWinHeight);
      }

      // Morph capsule width, height & border-radius seamlessly
      capsule.className = "island-capsule state-" + mode;
      capsule.style.width = targetDim.width + "px";
      capsule.style.height = targetDim.height + "px";

      Object.keys(views).forEach((key) => {
        if (views[key]) {
          views[key].classList.toggle("active", key === mode);
        }
      });
    }

    // Handle specific mode behaviors
    switch (mode) {
      case "idle":
        updateClock();
        break;

      case "welcome":
        renderWelcome(data);
        playAppleChime();
        dismissTimer = setTimeout(() => {
          if (currentState === "welcome") setMode("idle");
        }, 5500);
        break;

      case "notification":
        renderNotification(data);
        playAppleChime();
        dismissTimer = setTimeout(() => {
          if (currentState === "notification" && !isHovered) {
            setMode("idle");
          }
        }, 7000);
        break;

      case "reply":
        renderReply(data);
        setTimeout(() => {
          window.islandBridge?.focusWindow?.();
          replyInput?.focus();
        }, 120);
        break;

      case "chats":
        fetchAndRenderChats();
        break;

      case "chatview":
        renderChatView(data);
        setTimeout(() => {
          window.islandBridge?.focusWindow?.();
          chatviewInput?.focus();
        }, 120);
        break;

      case "audio":
        renderAudio(data);
        break;

      case "call":
        renderCall(data);
        playAppleChime();
        break;

      case "progress":
        renderProgress(data);
        break;

      case "settings":
        syncSettingsUI();
        break;
    }
  }

  // =========================================================================
  // View Renderers
  // =========================================================================
  function renderWelcome(data) {
    if (data.id || data._id || data.userId) currentUserId = String(data.id || data._id || data.userId);
    const name = data.userName || data.fullName || data.username || "مهندس يوسف";
    const hour = new Date().getHours();
    const greetingPrefix = hour < 12 ? "صباح الخير" : "مساء الخير";
    if (welcomeUserEl) welcomeUserEl.textContent = `${greetingPrefix}، ${name}`;
    setSafeAvatar(welcomeAvatarEl, welcomeAvatarFallback, data.avatarUrl, getInitial(name));
  }

  function renderNotification(data) {
    activeNotification = data;
    const privacy = currentSettings.privacyMode || "full";

    let sender = data.senderName || data.title || "رسالة جديدة";
    let body = data.body || data.content || "";

    if (privacy === "sender_only" || privacy === "hide_details") {
      body = "لديك رسالة جديدة";
    } else if (privacy === "hidden" || privacy === "sound_only") {
      sender = "iSmart Messenger";
      body = "رسالة خاصة جديدة";
    }

    if (notifSender) notifSender.textContent = sender;
    if (notifText) notifText.textContent = body;
    if (notifTime) notifTime.textContent = formatTime(new Date());

    const notifFallback = document.querySelector(".notif-fallback");
    if (privacy === "hidden") {
      setSafeAvatar(notifAvatar, notifFallback, null, "🔒");
    } else {
      setSafeAvatar(notifAvatar, notifFallback, data.avatarUrl, getInitial(sender));
    }
  }

  function renderReply(data) {
    const target = data || activeNotification || {};
    const sender = target.senderName || target.title || "المرسل";
    const privacy = currentSettings.privacyMode || "full";

    let body = target.body || target.content || "رسالة واردة";
    if (privacy === "sender_only" || privacy === "hide_details") {
      body = "رسالة خاصة";
    } else if (privacy === "hidden") {
      body = "محتوى محمي بالخصوصية";
    }

    if (replySender) replySender.textContent = `رد على: ${sender}`;
    if (replyQuoteSender) replyQuoteSender.textContent = sender;
    if (replyQuoteText) replyQuoteText.textContent = body;

    const replyFallback = replyAvatar?.nextElementSibling;
    setSafeAvatar(replyAvatar, replyFallback, target.avatarUrl, getInitial(sender));

    if (replyInput) {
      replyInput.value = "";
      replyInput.disabled = false;
    }
    if (replySubmitBtn) replySubmitBtn.disabled = false;
    if (replyStatus) replyStatus.textContent = "";
  }

  function renderAudio(data = {}) {
    activeAudioState = data;
    const audioPanel = views.audio;
    if (!audioPanel) return;

    const isPlaying = data.isPlaying !== false;
    audioPanel.classList.toggle("playing", isPlaying);

    if (audioPlayIcon) audioPlayIcon.style.display = isPlaying ? "none" : "block";
    if (audioPauseIcon) audioPauseIcon.style.display = isPlaying ? "block" : "none";

    const sender = data.senderName || "تسجيل صوتي";
    if (audioSender) audioSender.textContent = sender;

    const current = data.currentTime || "0:00";
    const total = data.totalTime || "0:00";
    if (audioTime) audioTime.textContent = `${current} / ${total}`;

    // Update progress bar
    const pct = data.percent !== undefined ? data.percent : (data.progress !== undefined ? data.progress * 100 : undefined);
    if (audioProgressBar && pct !== undefined) {
      audioProgressBar.style.width = `${Math.min(100, Math.max(0, pct))}%`;
    }

    // Sync speed display if passed
    if (data.speed !== undefined && audioSpeedBtn) {
      const num = Number(data.speed) || 1.0;
      const speedStr = `${num.toFixed(1)}x`;
      currentAudioSpeed = speedStr;
      audioSpeedBtn.textContent = speedStr;
    }

    setSafeAvatar(audioAvatar, audioAvatarFallback, data.avatarUrl, "🎙️");
  }

  function renderCall(data = {}) {
    activeCallState = data;
    const caller = data.callerName || data.name || "مكالمة واردة";
    if (callCallerName) callCallerName.textContent = caller;
    if (callStatusLabel) callStatusLabel.textContent = data.status || "جاري الاتصال...";

    setSafeAvatar(callAvatar, callAvatarFallback, data.avatarUrl, "📞");

    let seconds = 0;
    if (callTimerInterval) clearInterval(callTimerInterval);
    callTimerInterval = setInterval(() => {
      seconds += 1;
      const mins = String(Math.floor(seconds / 60)).padStart(2, "0");
      const secs = String(seconds % 60).padStart(2, "0");
      if (callStatusLabel && currentState === "call") {
        callStatusLabel.textContent = `${mins}:${secs}`;
      }
    }, 1000);
  }

  function renderProgress(data) {
    const label = data.label || "جاري نقل الملف...";
    const percent = Math.min(100, Math.max(0, Number(data.percent || 0)));

    if (progressLabel) progressLabel.textContent = label;
    if (progressPercent) progressPercent.textContent = `${Math.round(percent)}%`;
    if (progressBarFill) progressBarFill.style.width = `${percent}%`;

    if (percent >= 100) {
      if (progressLabel) progressLabel.textContent = "اكتمل بنجاح ✓";
      playSuccessChime();
      dismissTimer = setTimeout(() => {
        if (currentState === "progress") setMode("idle");
      }, 2500);
    }
  }

  async function fetchAndRenderChats() {
    if (!chatsContainer) return;
    chatsContainer.innerHTML = `
      <div style="text-align: center; color: var(--text-muted); font-size: 12px; padding: 25px;">
        جاري تحميل المحادثات...
      </div>
    `;

    try {
      const chats = await window.islandBridge?.getRecentChats();
      if (Array.isArray(chats) && chats.length > 0) {
        cachedChats = chats;
        filterAndRenderChatsList();
      } else {
        chatsContainer.innerHTML = `
          <div style="text-align: center; color: var(--text-muted); font-size: 12px; padding: 30px;">
            لا توجد محادثات حديثة
          </div>
        `;
      }
    } catch (_) {
      chatsContainer.innerHTML = `
        <div style="text-align: center; color: var(--text-muted); font-size: 12px; padding: 30px;">
          اضغط أدناه لفتح التطبيق
        </div>
      `;
    }
  }

  function filterAndRenderChatsList() {
    if (!chatsContainer) return;

    let filtered = [...cachedChats];

    // Filter by Tab
    if (currentChatFilterTab === "unread") {
      filtered = filtered.filter((c) => Number(c.unreadCount || 0) > 0);
    } else if (currentChatFilterTab === "groups") {
      filtered = filtered.filter((c) => c.isGroup || c.type === "group");
    }

    // Filter by Search Query
    if (chatSearchQuery.trim().length > 0) {
      const q = chatSearchQuery.toLowerCase();
      filtered = filtered.filter((c) => {
        const title = (c.name || c.title || "").toLowerCase();
        const snippet = (c.lastMessage?.content || c.snippet || "").toLowerCase();
        return title.includes(q) || snippet.includes(q);
      });
    }

    renderChatsList(filtered);
  }

  function renderChatsList(chats) {
    if (!chatsContainer) return;
    chatsContainer.innerHTML = "";

    if (!chats || chats.length === 0) {
      chatsContainer.innerHTML = `
        <div style="text-align: center; color: var(--text-muted); font-size: 12px; padding: 30px;">
          لا توجد نتائج مطابقة
        </div>
      `;
      return;
    }

    const privacy = currentSettings.privacyMode || "full";

    chats.slice(0, 15).forEach((chat) => {
      const item = document.createElement("div");
      item.className = "chat-item";

      const title = chat.name || chat.title || "محادثة";
      let preview = chat.lastMessage?.content || chat.snippet || "انقر للمراسلة";
      if (privacy === "hidden") {
        preview = "رسالة جديدة";
      }

      const time = chat.updatedAt ? formatTime(new Date(chat.updatedAt)) : "";
      const unread = Number(chat.unreadCount || 0);
      const initial = getInitial(title);

      item.innerHTML = `
        <div class="chat-avatar-wrap">
          <div class="avatar-holder" style="width:36px; height:36px;">
            <img class="chat-avatar" style="display:none;" alt="${escapeHtml(title)}">
            <div class="avatar-fallback" style="display:flex; font-size:14px;">${initial}</div>
          </div>
        </div>
        <div class="chat-info">
          <div class="chat-info-top">
            <span class="chat-name">${escapeHtml(title)}</span>
            <span class="chat-time">${time}</span>
          </div>
          <div class="chat-preview">${escapeHtml(preview)}</div>
        </div>
        ${unread > 0 ? `<span class="chat-unread-badge">${unread}</span>` : ""}
      `;

      const chatImgEl = item.querySelector(".chat-avatar");
      const chatFallbackEl = item.querySelector(".avatar-fallback");
      setSafeAvatar(chatImgEl, chatFallbackEl, chat.avatarUrl, initial);

      item.addEventListener("click", () => {
        setMode("chatview", chat);
      });

      chatsContainer.appendChild(item);
    });
  }

  // =========================================================================
  // Mini Chatview Controller (In-Island Chatting)
  // =========================================================================
  async function renderChatView(chat) {
    activeChat = chat;
    const title = chat.name || chat.title || "محادثة";
    if (chatviewTargetName) chatviewTargetName.textContent = title;
    setSafeAvatar(chatviewAvatar, chatviewAvatarFallback, chat.avatarUrl, getInitial(title));

    const conversationId = chat.id || chat._id;
    if (chatviewInput) {
      chatviewInput.value = "";
      chatviewInput.disabled = false;
      setTimeout(() => {
        window.islandBridge?.focusWindow?.();
        chatviewInput.focus();
      }, 100);
    }

    // 1. Instant Cache Display: Render cached or preview messages immediately (zero empty screen)
    let initialMessages = conversationMessagesCache.get(conversationId);
    if ((!initialMessages || initialMessages.length === 0) && (chat.snippet || chat.lastMessage)) {
      const lastMsgContent = typeof chat.lastMessage === "object" ? chat.lastMessage.content : (chat.snippet || "");
      if (lastMsgContent) {
        initialMessages = [{
          id: "preview_" + (chat.updatedAt || Date.now()),
          content: lastMsgContent,
          messageType: chat.lastMessage?.messageType || "text",
          fileName: chat.lastMessage?.fileName || null,
          fileUrl: chat.lastMessage?.fileUrl || null,
          createdAt: chat.updatedAt || new Date().toISOString(),
          isOutgoing: false,
          senderName: title,
        }];
        conversationMessagesCache.set(conversationId, initialMessages);
      }
    }

    if (Array.isArray(initialMessages) && initialMessages.length > 0) {
      renderMiniChatMessages(initialMessages);
    } else if (chatviewMessagesContainer) {
      chatviewMessagesContainer.innerHTML = `
        <div style="text-align: center; color: var(--text-muted); font-size: 12px; padding: 30px;">
          جاري تحميل الرسائل...
        </div>
      `;
    }

    // 2. Fetch fresh messages from API/bridge in the background
    try {
      const messages = await window.islandBridge?.getConversationMessages(conversationId);
      if (Array.isArray(messages) && messages.length > 0) {
        // Merge with locally sent messages from cache
        const existing = conversationMessagesCache.get(conversationId) || [];
        const localSent = existing.filter(m => String(m.id).startsWith("temp_") || String(m.id).startsWith("sent_"));
        const merged = [...messages];
        for (const local of localSent) {
          const exists = merged.some(m => m.content === local.content);
          if (!exists) merged.push(local);
        }
        merged.sort((a, b) => new Date(a.createdAt || 0) - new Date(b.createdAt || 0));
        conversationMessagesCache.set(conversationId, merged);
        if (activeChat?.id === conversationId || activeChat?._id === conversationId) {
          renderMiniChatMessages(merged);
        }
      } else {
        const existing = conversationMessagesCache.get(conversationId);
        if (!existing || existing.length === 0) {
          if (chatviewMessagesContainer) {
            chatviewMessagesContainer.innerHTML = `
              <div style="text-align: center; color: var(--text-muted); font-size: 12px; padding: 30px;">
                ابدأ المراسلة الآن...
              </div>
            `;
          }
        }
      }
    } catch (_) {
      const existing = conversationMessagesCache.get(conversationId);
      if (!existing || existing.length === 0) {
        if (chatviewMessagesContainer) {
          chatviewMessagesContainer.innerHTML = `
            <div style="text-align: center; color: var(--text-muted); font-size: 12px; padding: 30px;">
              اكتب رسالتك بالأسفل للإرسال
            </div>
          `;
        }
      }
    }
  }

  function formatBytes(bytes) {
    if (!bytes || isNaN(bytes)) return "";
    const b = Number(bytes);
    if (b < 1024) return b + " B";
    if (b < 1024 * 1024) return (b / 1024).toFixed(1) + " KB";
    return (b / (1024 * 1024)).toFixed(1) + " MB";
  }

  function isImageMedia(url, name, type) {
    if (type === "image") return true;
    const str = ((url || "") + " " + (name || "")).toLowerCase();
    return /\.(png|jpe?g|gif|webp|bmp|svg)(\?.*)?$/i.test(str);
  }

  function isAudioMedia(url, name, type) {
    if (type === "audio") return true;
    const str = ((url || "") + " " + (name || "")).toLowerCase();
    return /\.(mp3|wav|ogg|m4a|aac)(\?.*)?$/i.test(str);
  }

  function renderMiniChatMessages(messages) {
    if (!chatviewMessagesContainer) return;
    chatviewMessagesContainer.innerHTML = "";

    const myId = String(currentUserId || "");

    const pendingImagesToLoad = [];

    messages.slice(-25).forEach((msg) => {
      const bubble = document.createElement("div");
      const sId = String(msg.senderId || msg.sender?.id || msg.sender?._id || "");
      const isOutgoing = Boolean(
        msg.isOutgoing ||
        msg.isMine ||
        (myId && sId && sId === myId)
      );
      bubble.className = `mini-msg ${isOutgoing ? "outgoing" : "incoming"}${msg.sending ? " is-sending" : ""}`;

      const content = msg.content || msg.text || "";
      const time = msg.sending ? "جاري الإرسال..." : (msg.createdAt ? formatTime(new Date(msg.createdAt)) : "");
      const senderName = msg.senderName || msg.sender?.displayName || msg.sender?.fullName || "";
      const isGroup = Boolean(activeChat?.isGroup || activeChat?.type !== "direct");

      let html = "";

      // Group incoming messages: show sender name
      if (!isOutgoing && isGroup && senderName) {
        html += `<div class="mini-msg-sender">${escapeHtml(senderName)}</div>`;
      }

      // Check media attachments
      const fileUrl = msg.fileUrl;
      const fileName = msg.fileName;
      const msgType = msg.messageType;
      const mimeType = msg.mimeType;

      if (fileUrl && isImageMedia(fileUrl, fileName, msgType, mimeType)) {
        const uniqueImgId = "island_img_" + Math.random().toString(36).substring(2, 9);
        html += `
          <div class="mini-msg-media-wrap" data-url="${escapeHtml(fileUrl)}" data-name="${escapeHtml(fileName || 'image.png')}">
            <div class="mini-msg-img-placeholder" id="${uniqueImgId}_ph">
              <span class="mini-msg-spinner"></span>
              <span>جاري تحميل الصورة...</span>
            </div>
            <img id="${uniqueImgId}" alt="${escapeHtml(fileName || 'صورة')}" class="mini-msg-img" style="display:none;">
          </div>
        `;
        pendingImagesToLoad.push({ id: uniqueImgId, url: fileUrl });
      } else if (fileUrl && isAudioMedia(fileUrl, fileName, msgType, mimeType)) {
        html += `
          <div class="mini-msg-audio-pill" data-url="${escapeHtml(fileUrl)}" data-name="${escapeHtml(fileName || 'audio.mp3')}">
            <span>🎙️</span>
            <span>تسجيل صوتي</span>
          </div>
        `;
      } else if (fileName || fileUrl) {
        const displayName = fileName || "ملف مرفق";
        const sizeStr = formatBytes(msg.fileSize);
        html += `
          <div class="mini-msg-file-card" data-url="${escapeHtml(fileUrl || '')}" data-name="${escapeHtml(displayName)}">
            <span class="file-card-icon">📄</span>
            <div class="file-card-info">
              <span class="file-card-name" title="${escapeHtml(displayName)}">${escapeHtml(displayName)}</span>
              ${sizeStr ? `<span class="file-card-size">${sizeStr}</span>` : ""}
            </div>
          </div>
        `;
      }

      if (content && content.trim().length > 0 && content !== fileName) {
        html += `<span>${escapeHtml(content)}</span>`;
      }

      html += `<span class="mini-msg-time">${time} ${isOutgoing ? '✓✓' : ''}</span>`;

      bubble.innerHTML = html;

      // Add click handlers for attachments: Open the main iSmart Messenger app at this conversation
      bubble.querySelectorAll("img, a, [data-url], .mini-msg-media-wrap, .mini-msg-file-card, .mini-msg-audio-pill").forEach((el) => {
        el.style.cursor = "pointer";
        el.title = "فتح في تطبيق iSmart الرئيسي";
        el.addEventListener("click", (e) => {
          e.preventDefault();
          e.stopPropagation();
          const convId = activeChat?.id || activeChat?._id;
          if (convId && window.islandBridge?.openConversation) {
            window.islandBridge.openConversation(convId);
          } else if (window.islandBridge?.showMainWindow) {
            window.islandBridge.showMainWindow();
          }
          setMode("idle");
        });
      });

      chatviewMessagesContainer.appendChild(bubble);
    });

    pendingImagesToLoad.forEach(({ id, url }) => {
      const imgEl = document.getElementById(id);
      const phEl = document.getElementById(id + "_ph");
      if (imgEl) {
        loadAuthenticatedImage(imgEl, url, phEl);
      }
    });

    chatviewMessagesContainer.scrollTop = chatviewMessagesContainer.scrollHeight;
  }

  let chatViewErrorTimeout = null;
  function showChatViewError(message) {
    const errorPill = document.getElementById("chatview-error-pill");
    if (!errorPill) return;
    if (chatViewErrorTimeout) {
      clearTimeout(chatViewErrorTimeout);
      chatViewErrorTimeout = null;
    }
    errorPill.textContent = message || "فشل إرسال الرسالة.";
    errorPill.style.display = "block";
    if (chatviewStatusText) {
      chatviewStatusText.textContent = "فشل الإرسال";
      chatviewStatusText.style.color = "var(--danger-color)";
    }
    chatViewErrorTimeout = setTimeout(() => {
      errorPill.style.display = "none";
      if (chatviewStatusText && currentState === "chatview") {
        chatviewStatusText.textContent = "نشط الآن";
        chatviewStatusText.style.color = "";
      }
    }, 4000);
  }

  let isSendingMiniMsg = false;
  async function submitMiniChatMessage(customText = null) {
    if (isSendingMiniMsg) return;
    const text = (customText || chatviewInput?.value || "").trim();
    if (!text) return;

    if (!activeChat) {
      if (cachedChats && cachedChats.length > 0) {
        activeChat = cachedChats[0];
      }
    }

    if (!activeChat) {
      showChatViewError("يرجى اختيار محادثة أولاً من القائمة.");
      return;
    }

    const conversationId = activeChat.id || activeChat._id;
    if (!conversationId) {
      showChatViewError("معرف المحادثة غير صالح.");
      return;
    }

    isSendingMiniMsg = true;
    if (!customText && chatviewInput) {
      chatviewInput.value = "";
    }
    const sendBtn = document.getElementById("chatview-send-btn");
    if (sendBtn) sendBtn.disabled = true;
    if (chatviewStatusText) {
      chatviewStatusText.textContent = "جاري الإرسال...";
      chatviewStatusText.style.color = "var(--accent-blue)";
    }

    const tempId = "temp_" + Date.now();
    const tempMsg = {
      id: tempId,
      content: text,
      messageType: "text",
      createdAt: new Date().toISOString(),
      isOutgoing: true,
      isMine: true,
      senderName: currentUserName || "أنا",
      sending: false,
    };

    const existing = conversationMessagesCache.get(conversationId) || [];
    existing.push(tempMsg);
    renderMiniChatMessages(existing);

    const safetyTimer = setTimeout(() => {
      isSendingMiniMsg = false;
      if (sendBtn) sendBtn.disabled = false;
      if (chatviewStatusText && chatviewStatusText.textContent === "جاري الإرسال...") {
        chatviewStatusText.textContent = "نشط الآن";
        chatviewStatusText.style.color = "";
      }
    }, 4000);

    try {
      const res = await window.islandBridge?.sendReply({
        conversationId,
        content: text,
      });

      if (res && res.success !== false) {
        playSentPop();
        if (chatviewStatusText) {
          chatviewStatusText.textContent = "تم الإرسال ✓";
          chatviewStatusText.style.color = "var(--success-color)";
          setTimeout(() => {
            if (currentState === "chatview" && chatviewStatusText) {
              chatviewStatusText.textContent = "نشط الآن";
              chatviewStatusText.style.color = "";
            }
          }, 1500);
        }

        const confirmedMsg = res.message || {
          ...tempMsg,
          id: "srv_" + Date.now(),
          sending: false,
        };
        confirmedMsg.sending = false;
        const idx = existing.findIndex((m) => m.id === tempId);
        if (idx !== -1) {
          existing[idx] = confirmedMsg;
        }
        conversationMessagesCache.set(conversationId, existing);
        if (activeChat) {
          activeChat.snippet = text;
          activeChat.lastMessage = confirmedMsg;
        }
        renderMiniChatMessages(existing);
      } else {
        playErrorBuzz();
        if (!customText && chatviewInput) chatviewInput.value = text;
        const filtered = existing.filter((m) => m.id !== tempId);
        conversationMessagesCache.set(conversationId, filtered);
        renderMiniChatMessages(filtered);

        showChatViewError(res?.error || "فشل إرسال الرسالة، يرجى المحاولة ثانية.");
      }
    } catch (err) {
      playErrorBuzz();
      if (!customText && chatviewInput) chatviewInput.value = text;
      const filtered = existing.filter((m) => m.id !== tempId);
      conversationMessagesCache.set(conversationId, filtered);
      renderMiniChatMessages(filtered);
      showChatViewError("خطأ في الاتصال بالشبكة.");
    } finally {
      clearTimeout(safetyTimer);
      isSendingMiniMsg = false;
      if (sendBtn) sendBtn.disabled = false;
      if (chatviewInput) {
        chatviewInput.disabled = false;
        chatviewInput.focus();
      }
    }
  }

  // =========================================================================
  // Settings & Theme Engine
  // =========================================================================
  function applyTheme(theme) {
    document.body.className = "";
    if (theme && theme !== "obsidian") {
      document.body.classList.add(`theme-${theme}`);
    }
    themeDots.forEach((dot) => {
      dot.classList.toggle("active", dot.dataset.theme === theme);
    });
  }

  function syncSettingsUI() {
    if (toggleEnabled) toggleEnabled.checked = currentSettings.enabled !== false;
    if (toggleBootHidden) toggleBootHidden.checked = currentSettings.startMinimizedOnBoot !== false;
    if (selectPrivacy) selectPrivacy.value = currentSettings.privacyMode || "full";
    if (selectPosition) selectPosition.value = String(currentSettings.yOffset !== undefined ? currentSettings.yOffset : 0);
    if (toggleSound) toggleSound.checked = currentSettings.soundEnabled !== false;
    applyTheme(currentSettings.theme || "obsidian");
  }

  async function saveSettingsFromUI() {
    currentSettings.enabled = toggleEnabled ? toggleEnabled.checked : true;
    currentSettings.startMinimizedOnBoot = toggleBootHidden ? toggleBootHidden.checked : true;
    currentSettings.privacyMode = selectPrivacy ? selectPrivacy.value : "full";
    currentSettings.yOffset = selectPosition ? Number(selectPosition.value || 0) : 0;
    currentSettings.soundEnabled = toggleSound ? toggleSound.checked : true;

    applyTheme(currentSettings.theme);
    await window.islandBridge?.saveSettings(currentSettings);
  }

  // =========================================================================
  // Reply Actions
  // =========================================================================
  let isSendingQuickReply = false;
  async function submitQuickReply(customText = null) {
    if (isSendingQuickReply) return;
    const text = customText || replyInput?.value?.trim();
    if (!text) return;

    const conversationId = activeNotification?.conversationId || activeNotification?.id;
    if (!conversationId) {
      if (replyStatus) replyStatus.textContent = "لا يمكن العثور على المحادثة";
      return;
    }

    isSendingQuickReply = true;
    if (!customText && replyInput) {
      replyInput.value = "";
    }
    if (replySubmitBtn) replySubmitBtn.disabled = true;
    if (replyStatus) {
      replyStatus.textContent = "جاري الإرسال...";
      replyStatus.style.color = "var(--accent-color)";
    }

    const replySafetyTimer = setTimeout(() => {
      isSendingQuickReply = false;
      if (replyInput) replyInput.disabled = false;
      if (replySubmitBtn) replySubmitBtn.disabled = false;
    }, 4000);

    try {
      const res = await window.islandBridge?.sendReply({
        conversationId,
        content: text,
      });

      if (res?.success !== false) {
        playSentPop();
        if (replyStatus) {
          replyStatus.textContent = "تم الإرسال بنجاح ✓";
          replyStatus.style.color = "var(--success-color)";
        }
        dismissTimer = setTimeout(() => {
          if (currentState === "reply") setMode("idle");
        }, 1100);
      } else {
        playErrorBuzz();
        if (!customText && replyInput) replyInput.value = text;
        if (replyStatus) {
          replyStatus.textContent = res?.error || "فشل الإرسال";
          replyStatus.style.color = "var(--danger-color)";
        }
      }
    } catch (err) {
      playErrorBuzz();
      if (!customText && replyInput) replyInput.value = text;
      if (replyStatus) {
        replyStatus.textContent = "خطأ في الشبكة";
        replyStatus.style.color = "var(--danger-color)";
      }
    } finally {
      clearTimeout(replySafetyTimer);
      isSendingQuickReply = false;
      if (replyInput) {
        replyInput.disabled = false;
        replyInput.focus();
      }
      if (replySubmitBtn) replySubmitBtn.disabled = false;
    }
  }

  // =========================================================================
  // Helpers
  // =========================================================================
  function updateClock() {
    if (!clockEl) return;
    const now = new Date();
    const hours = String(now.getHours()).padStart(2, "0");
    const minutes = String(now.getMinutes()).padStart(2, "0");
    clockEl.textContent = `${hours}:${minutes}`;
  }

  function formatTime(d) {
    if (!d || isNaN(d)) return "";
    const hours = d.getHours();
    const mins = String(d.getMinutes()).padStart(2, "0");
    const ampm = hours >= 12 ? "م" : "ص";
    const formattedHours = hours % 12 || 12;
    return `${formattedHours}:${mins} ${ampm}`;
  }

  function escapeHtml(str) {
    if (!str) return "";
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  // =========================================================================
  // Event Listeners Binding
  // =========================================================================
  function setupEventListeners() {
    // =========================================================================
    // Auto-Dismiss when clicking outside anywhere on the computer screen
    // =========================================================================
    function handleOutsideDismiss(source = "outside") {
      // In interactive typing modes (chatview or reply), DO NOT auto-collapse on window blur or background signals!
      if ((currentState === "chatview" || currentState === "reply") && source === "blur") {
        return;
      }
      const dismissableModes = ["chats", "chatview", "reply", "settings", "welcome", "notification"];
      if (dismissableModes.includes(currentState)) {
        if (activeAudioState && activeAudioState.isPlaying) {
          setMode("audio", activeAudioState);
        } else if (activeCallState && activeCallState.status) {
          setMode("call", activeCallState);
        } else {
          setMode("idle");
        }
      }
    }

    window.addEventListener("blur", () => {
      setTimeout(() => {
        if (!document.hasFocus()) {
          handleOutsideDismiss("blur");
        }
      }, 300);
    });

    window.addEventListener("keydown", (e) => {
      if (e.key === "Escape") {
        handleOutsideDismiss("escape");
      }
    });

    window.islandBridge?.onCollapseRequested?.(() => {
      handleOutsideDismiss("blur");
    });
    // Hover interactivity on capsule
    capsule.addEventListener("mouseenter", () => {
      isHovered = true;
      if (dismissTimer && currentState === "notification") {
        clearTimeout(dismissTimer);
        dismissTimer = null;
      }
    });

    capsule.addEventListener("mouseleave", () => {
      isHovered = false;
      if (currentState === "notification") {
        dismissTimer = setTimeout(() => {
          if (currentState === "notification") setMode("idle");
        }, 3000);
      }
    });

    // Clicking idle capsule opens chats drawer with instant response (no mouse forwarding latency)
    capsule.addEventListener("click", (e) => {
      if (currentState === "idle") {
        e.stopPropagation();
        playAppleChime();
        setMode("chats");
      }
    });

    views.idle?.addEventListener("click", (e) => {
      if (currentState === "idle") {
        e.stopPropagation();
        playAppleChime();
        setMode("chats");
      }
    });

    // Dismiss when clicking on the transparent staging canvas outside the capsule
    document.body.addEventListener("click", (e) => {
      if (e.target === document.body || e.target === document.documentElement) {
        if (currentState !== "idle") {
          handleOutsideDismiss();
        }
      }
    });

    // Welcome dismiss
    document.getElementById("welcome-dismiss-btn")?.addEventListener("click", (e) => {
      e.stopPropagation();
      setMode("idle");
    });

    // Notification actions
    document.getElementById("notif-reply-btn")?.addEventListener("click", (e) => {
      e.stopPropagation();
      setMode("reply", activeNotification);
    });

    document.getElementById("notif-open-btn")?.addEventListener("click", (e) => {
      e.stopPropagation();
      if (activeNotification?.conversationId) {
        window.islandBridge?.openConversation(activeNotification.conversationId);
      } else {
        window.islandBridge?.showMainWindow();
      }
      setMode("idle");
    });

    document.getElementById("notif-dismiss-btn")?.addEventListener("click", (e) => {
      e.stopPropagation();
      setMode("idle");
    });

    document.getElementById("notif-body-click")?.addEventListener("click", () => {
      if (activeNotification?.conversationId) {
        setMode("chatview", {
          id: activeNotification.conversationId,
          name: activeNotification.senderName || activeNotification.title,
          avatarUrl: activeNotification.avatarUrl,
          snippet: activeNotification.body,
          lastMessage: {
            content: activeNotification.body,
            messageType: activeNotification.messageType || "text",
            fileName: activeNotification.fileName || null,
            fileUrl: activeNotification.fileUrl || null,
            createdAt: new Date().toISOString(),
          },
        });
      } else {
        setMode("reply", activeNotification);
      }
    });

    // Quick Reply actions
    document.getElementById("reply-cancel-btn")?.addEventListener("click", () => {
      setMode("idle");
    });

    replySubmitBtn?.addEventListener("click", () => submitQuickReply());

    // First replyInput keydown removed (consolidated below)

    // Quick Emojis
    document.querySelectorAll(".emoji-chip").forEach((btn) => {
      btn.addEventListener("click", () => {
        const emoji = btn.dataset.emoji;
        if (emoji) submitQuickReply(emoji);
      });
    });

    // Chats Search & Clear
    chatsSearchInput?.addEventListener("input", (e) => {
      chatSearchQuery = e.target.value || "";
      if (chatsSearchClear) {
        chatsSearchClear.style.display = chatSearchQuery.length > 0 ? "flex" : "none";
      }
      filterAndRenderChatsList();
    });

    chatsSearchClear?.addEventListener("click", () => {
      chatSearchQuery = "";
      if (chatsSearchInput) chatsSearchInput.value = "";
      chatsSearchClear.style.display = "none";
      filterAndRenderChatsList();
    });

    // Chats Category Tabs
    const tabs = [
      { el: tabFilterAll, tab: "all" },
      { el: tabFilterUnread, tab: "unread" },
      { el: tabFilterGroups, tab: "groups" },
    ];
    tabs.forEach(({ el, tab }) => {
      el?.addEventListener("click", () => {
        tabs.forEach((t) => t.el?.classList.toggle("active", t.tab === tab));
        currentChatFilterTab = tab;
        filterAndRenderChatsList();
      });
    });

    // Chats Drawer actions
    document.getElementById("chats-close-btn")?.addEventListener("click", () => {
      setMode("idle");
    });

    document.getElementById("chats-to-settings-btn")?.addEventListener("click", () => {
      setMode("settings");
    });

    document.getElementById("btn-open-full-app")?.addEventListener("click", () => {
      window.islandBridge?.showMainWindow();
      setMode("idle");
    });

    // Mini Chatview actions
    document.getElementById("chatview-back-btn")?.addEventListener("click", () => {
      setMode("chats");
    });

    document.getElementById("chatview-expand-btn")?.addEventListener("click", () => {
      if (activeChat?.id || activeChat?._id) {
        window.islandBridge?.openConversation(activeChat.id || activeChat._id);
      } else {
        window.islandBridge?.showMainWindow();
      }
      setMode("idle");
    });

    document.querySelector(".island-capsule")?.addEventListener("mousedown", () => {
      window.islandBridge?.focusWindow?.();
    });

    chatviewInput?.addEventListener("mousedown", (e) => {
      e.stopPropagation();
    });

    replyInput?.addEventListener("mousedown", (e) => {
      e.stopPropagation();
    });

    chatviewSendBtn?.addEventListener("click", (e) => {
      e.stopPropagation();
      submitMiniChatMessage();
    });

    chatviewInput?.addEventListener("keydown", (e) => {
      e.stopPropagation();
      if (e.key === "Enter") {
        e.preventDefault();
        submitMiniChatMessage();
      } else if (e.key === "Escape") {
        e.preventDefault();
        setMode("chats");
      }
    });

    replyInput?.addEventListener("keydown", (e) => {
      e.stopPropagation();
      if (e.key === "Enter") {
        e.preventDefault();
        submitQuickReply();
      } else if (e.key === "Escape") {
        e.preventDefault();
        setMode("idle");
      }
    });

    // Chatview Quick Canned Chips
    document.querySelectorAll(".chatview-chip").forEach((chip) => {
      chip.addEventListener("click", () => {
        const text = chip.dataset.text;
        if (text) submitMiniChatMessage(text);
      });
    });

    // Audio actions
    audioPlayPauseBtn?.addEventListener("click", (e) => {
      e.stopPropagation();
      window.islandBridge?.toggleAudio();
    });

    audioSpeedBtn?.addEventListener("click", (e) => {
      e.stopPropagation();
      const speeds = ["1.0x", "1.5x", "2.0x"];
      let idx = speeds.indexOf(currentAudioSpeed);
      if (idx === -1) {
        const num = parseFloat(currentAudioSpeed);
        if (num >= 1.9) idx = 2;
        else if (num >= 1.4) idx = 1;
        else idx = 0;
      }
      const nextIdx = (idx + 1) % speeds.length;
      currentAudioSpeed = speeds[nextIdx];
      if (audioSpeedBtn) audioSpeedBtn.textContent = currentAudioSpeed;
      const numSpeed = parseFloat(currentAudioSpeed);
      window.islandBridge?.setAudioSpeed?.(numSpeed);
    });

    audioProgressScrubber?.addEventListener("click", (e) => {
      e.stopPropagation();
      const rect = audioProgressScrubber.getBoundingClientRect();
      const clickX = e.clientX - rect.left;
      const pct = Math.max(0, Math.min(1, clickX / rect.width));
      if (audioProgressBar) audioProgressBar.style.width = `${pct * 100}%`;
      window.islandBridge?.seekAudio?.(pct);
    });

    document.getElementById("audio-close-btn")?.addEventListener("click", (e) => {
      e.stopPropagation();
      window.islandBridge?.stopAudio();
      setMode("idle");
    });

    // Call actions
    callAcceptBtn?.addEventListener("click", () => {
      if (callStatusLabel) callStatusLabel.textContent = "المكالمة جارية...";
      window.islandBridge?.acceptCall?.(activeCallState?.id || "active_call");
      playSentPop();
    });

    callDeclineBtn?.addEventListener("click", () => {
      if (callTimerInterval) clearInterval(callTimerInterval);
      window.islandBridge?.declineCall?.(activeCallState?.id || "active_call");
      setMode("idle");
    });

    // Progress dismiss
    document.getElementById("progress-dismiss-btn")?.addEventListener("click", () => {
      setMode("idle");
    });

    // Settings actions
    document.getElementById("settings-back-btn")?.addEventListener("click", () => {
      setMode("chats");
    });

    btnPreviewSound?.addEventListener("click", () => {
      playAppleChime();
    });

    btnTestNotif?.addEventListener("click", () => {
      setMode("notification", {
        senderName: "مهندس يوسف (تجربة)",
        body: "السلام عليكم! الجزيرة التفاعلية تعمل الآن بنجاح على الويندوز ✨",
        conversationId: "test_conv",
      });
    });

    btnTestAudio?.addEventListener("click", () => {
      setMode("audio", {
        senderName: "مهندس يوسف (فويس نوت)",
        currentTime: "0:12",
        totalTime: "1:45",
        isPlaying: true,
        percent: 25,
      });
    });

    btnTestCall?.addEventListener("click", () => {
      setMode("call", {
        callerName: "مهندس يوسف",
        status: "مكالمة واردة...",
      });
    });

    toggleEnabled?.addEventListener("change", saveSettingsFromUI);
    toggleBootHidden?.addEventListener("change", saveSettingsFromUI);
    selectPrivacy?.addEventListener("change", saveSettingsFromUI);
    selectPosition?.addEventListener("change", saveSettingsFromUI);
    toggleSound?.addEventListener("change", saveSettingsFromUI);

    themeDots.forEach((dot) => {
      dot.addEventListener("click", () => {
        currentSettings.theme = dot.dataset.theme;
        applyTheme(currentSettings.theme);
        saveSettingsFromUI();
      });
    });

    // Global Key shortcuts
    window.addEventListener("keydown", (e) => {
      if (e.key === "Escape" && currentState !== "idle") {
        setMode("idle");
      }
    });

    // Clock Interval
    setInterval(updateClock, 10000);
  }

  // =========================================================================
  // IPC Bridge Listeners from Main Process
  // =========================================================================
  async function initBridge() {
    if (!window.islandBridge) return;

    // Load initial settings and active user
    try {
      const loaded = await window.islandBridge.getSettings();
      if (loaded && typeof loaded === "object") {
        currentSettings = { ...currentSettings, ...loaded };
        applyTheme(currentSettings.theme || "obsidian");
        if (selectPosition) selectPosition.value = String(currentSettings.yOffset !== undefined ? currentSettings.yOffset : 0);
      }
    } catch (_) {}

    try {
      const user = await window.islandBridge.getActiveUser?.();
      if (user && typeof user === "object") {
        if (user.id || user._id || user.userId) {
          currentUserId = String(user.id || user._id || user.userId);
        }
        if (user.name || user.fullName || user.username || user.displayName) {
          currentUserName = user.name || user.fullName || user.username || user.displayName;
        }
      }
    } catch (_) {}

    // Notification listener
    window.islandBridge.onNotification((data) => {
      if (currentSettings.enabled === false) return;
      if (data && data.conversationId && data.body) {
        const convId = String(data.conversationId);
        const existing = conversationMessagesCache.get(convId) || [];
        const incomingMsg = {
          id: "notif_" + Date.now(),
          content: data.body,
          messageType: data.messageType || "text",
          fileName: data.fileName || null,
          fileUrl: data.fileUrl || null,
          createdAt: new Date().toISOString(),
          isOutgoing: false,
          isMine: false,
          senderName: data.senderName || data.title || "",
        };
        if (!existing.some((m) => m.content === incomingMsg.content && Math.abs(new Date(m.createdAt || 0) - new Date(incomingMsg.createdAt || 0)) < 30000)) {
          existing.push(incomingMsg);
          conversationMessagesCache.set(convId, existing);
        }
        if (currentState === "chatview" && activeChat && String(activeChat.id || activeChat._id) === convId) {
          renderMiniChatMessages(existing);
        }
      }
      setMode("notification", data);
    });

    // Welcome greeting listener
    window.islandBridge.onWelcome((data) => {
      if (currentSettings.enabled === false) return;
      setMode("welcome", data);
    });

    // Audio State listener (Voice Notes / Music)
    window.islandBridge.onAudioState((data) => {
      if (currentSettings.enabled === false) return;
      if (data && data.active) {
        setMode("audio", data);
      } else if (currentState === "audio") {
        setMode("idle");
      }
    });

    // Live Call listener
    window.islandBridge.onCallState?.((data) => {
      if (currentSettings.enabled === false) return;
      if (data && data.active) {
        setMode("call", data);
      } else if (currentState === "call") {
        setMode("idle");
      }
    });

    // Progress listener (uploads / transfers)
    window.islandBridge.onProgress((data) => {
      if (currentSettings.enabled === false) return;
      setMode("progress", data);
    });

    // Chats updated
    window.islandBridge.onChatsUpdated((chats) => {
      if (Array.isArray(chats)) {
        cachedChats = chats;
        chats.forEach((c) => {
          if (!c || !c.id) return;
          const convId = String(c.id);
          const lastMsg = c.lastMessage;
          const content = typeof lastMsg === "object" ? lastMsg.content : (c.snippet || "");
          if (content && !conversationMessagesCache.has(convId)) {
            conversationMessagesCache.set(convId, [{
              id: lastMsg?.id || ("seed_" + (c.updatedAt || Date.now())),
              content: content,
              messageType: lastMsg?.messageType || "text",
              fileName: lastMsg?.fileName || null,
              fileUrl: lastMsg?.fileUrl || null,
              createdAt: lastMsg?.createdAt || c.updatedAt || new Date().toISOString(),
              isOutgoing: false,
              senderName: c.name || c.title || "",
            }]);
          }
        });
        const totalUnread = chats.reduce(
          (acc, c) => acc + (Number(c.unreadCount) || 0),
          0,
        );
        if (unreadBadge) {
          if (totalUnread > 0) {
            unreadBadge.textContent = totalUnread > 99 ? "99+" : totalUnread;
            unreadBadge.classList.add("visible");
          } else {
            unreadBadge.classList.remove("visible");
          }
        }
        if (currentState === "chats") {
          filterAndRenderChatsList();
        }
      }
    });

    // Settings updated externally
    window.islandBridge.onSettingsUpdated((newSettings) => {
      currentSettings = { ...currentSettings, ...newSettings };
      syncSettingsUI();
    });

    // Active User updated
    window.islandBridge.onActiveUserUpdated?.((user) => {
      const prevId = currentUserId;
      if (user && typeof user === "object") {
        const newId = String(user.id || user._id || user.userId || "");
        if (newId && prevId && newId !== prevId) {
          // Account switch detected! Reset conversation messages cache and chats
          conversationMessagesCache.clear();
          cachedChats = [];
          if (currentState === "chatview") {
            setMode("chats");
          }
        }
        currentUserId = newId;
        if (user.name || user.fullName || user.username || user.displayName) {
          currentUserName = user.name || user.fullName || user.username || user.displayName;
        }
        if (welcomeUserEl) welcomeUserEl.textContent = `مرحباً بك، ${currentUserName || "مهندس يوسف"}`;
        setSafeAvatar(welcomeAvatarEl, welcomeAvatarFallback, user.avatarUrl, getInitial(currentUserName || "م"));
      } else {
        // User logged out
        currentUserId = "";
        currentUserName = "";
        conversationMessagesCache.clear();
        cachedChats = [];
        if (currentState !== "idle") {
          setMode("idle");
        }
      }
    });

    // Real-time message added from manager
    window.islandBridge.onMessageAdded?.(({ conversationId, message }) => {
      if (!conversationId || !message) return;
      const convId = String(conversationId);
      const existing = conversationMessagesCache.get(convId) || [];
      // Prevent duplicate if message with same ID already exists
      if (existing.some((m) => m.id === message.id)) return;
      // Prevent duplicate if message has same content from me sent very recently
      const dupIdx = existing.findIndex((m) =>
        (m.isOutgoing || m.isMine) &&
        m.content === message.content &&
        Math.abs(new Date(m.createdAt || 0) - new Date(message.createdAt || 0)) < 4000
      );
      if (dupIdx !== -1) {
        existing[dupIdx] = message;
        conversationMessagesCache.set(convId, existing);
        if (activeChat && (String(activeChat.id) === convId || String(activeChat._id) === convId)) {
          renderMiniChatMessages(existing);
        }
        return;
      }
      existing.push(message);
      existing.sort((a, b) => new Date(a.createdAt || 0) - new Date(b.createdAt || 0));
      conversationMessagesCache.set(convId, existing);
      if (activeChat && (String(activeChat.id) === convId || String(activeChat._id) === convId)) {
        renderMiniChatMessages(existing);
      }
    });
  }

  // Initialization
  document.addEventListener("DOMContentLoaded", () => {
    setupEventListeners();
    initBridge();
    setMode("idle");
  });
})();
