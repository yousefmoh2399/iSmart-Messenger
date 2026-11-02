/**
 * iSmart Dynamic Island - Client Renderer & State Controller
 * Fully compatible with Windows 7 (32-bit), 10, and 11
 */

(function () {
  // State definitions and exact window dimensions
  const STATE_DIMENSIONS = {
    idle: { width: 260, height: 42 },
    welcome: { width: 380, height: 106 },
    notification: { width: 400, height: 88 },
    reply: { width: 400, height: 140 },
    chats: { width: 420, height: 380 },
    progress: { width: 380, height: 80 },
    settings: { width: 420, height: 420 },
  };

  let currentState = "idle";
  let activeNotification = null;
  let dismissTimer = null;
  let isHovered = false;
  let cachedChats = [];
  let currentSettings = {
    enabled: true,
    privacyMode: "full",
    theme: "obsidian",
    soundEnabled: true,
    startMinimizedOnBoot: true,
  };

  // DOM Elements
  const capsule = document.getElementById("island-capsule");
  const views = {
    idle: document.getElementById("view-idle"),
    welcome: document.getElementById("view-welcome"),
    notification: document.getElementById("view-notification"),
    reply: document.getElementById("view-reply"),
    chats: document.getElementById("view-chats"),
    progress: document.getElementById("view-progress"),
    settings: document.getElementById("view-settings"),
  };

  // Clock & Badge
  const clockEl = document.getElementById("idle-clock");
  const unreadBadge = document.getElementById("idle-unread-badge");

  // Welcome elements
  const welcomeUserEl = document.getElementById("welcome-user-name");
  const welcomeAvatarEl = document.getElementById("welcome-avatar");

  // Notification elements
  const notifAvatar = document.getElementById("notif-avatar");
  const notifSender = document.getElementById("notif-sender");
  const notifTime = document.getElementById("notif-time");
  const notifText = document.getElementById("notif-text");

  // Reply elements
  const replyAvatar = document.getElementById("reply-avatar");
  const replySender = document.getElementById("reply-sender-name");
  const replyInput = document.getElementById("reply-text-input");
  const replySubmitBtn = document.getElementById("reply-submit-btn");
  const replyStatus = document.getElementById("reply-status-text");

  // Chats list
  const chatsContainer = document.getElementById("chats-items-container");

  // Progress elements
  const progressLabel = document.getElementById("progress-label");
  const progressPercent = document.getElementById("progress-percent");
  const progressBarFill = document.getElementById("progress-bar-fill");

  // Settings elements
  const toggleEnabled = document.getElementById("setting-toggle-enabled");
  const toggleBootHidden = document.getElementById("setting-toggle-boot-hidden");
  const selectPrivacy = document.getElementById("setting-privacy-select");
  const toggleSound = document.getElementById("setting-toggle-sound");
  const themeDots = document.querySelectorAll(".theme-dot");
  const btnTestNotif = document.getElementById("btn-test-notification");

  // =========================================================================
  // Web Audio Synthesizer (Zero External Dependencies, Pure iOS-Grade Chimes)
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

  function playNotificationChime() {
    if (!currentSettings.soundEnabled) return;
    try {
      const ctx = getAudioContext();
      if (!ctx) return;
      const now = ctx.currentTime;

      // Soft harmonic chime (Two gentle bells)
      const osc1 = ctx.createOscillator();
      const osc2 = ctx.createOscillator();
      const gainNode = ctx.createGain();

      osc1.type = "sine";
      osc1.frequency.setValueAtTime(880, now); // A5
      osc1.frequency.exponentialRampToValueAtTime(1318.51, now + 0.12); // E6

      osc2.type = "triangle";
      osc2.frequency.setValueAtTime(1760, now); // A6
      osc2.frequency.exponentialRampToValueAtTime(2093, now + 0.15); // C7

      gainNode.gain.setValueAtTime(0.001, now);
      gainNode.gain.linearRampToValueAtTime(0.18, now + 0.04);
      gainNode.gain.exponentialRampToValueAtTime(0.001, now + 0.45);

      osc1.connect(gainNode);
      osc2.connect(gainNode);
      gainNode.connect(ctx.destination);

      osc1.start(now);
      osc2.start(now);
      osc1.stop(now + 0.46);
      osc2.stop(now + 0.46);
    } catch (_) {}
  }

  function playSuccessPop() {
    try {
      const ctx = getAudioContext();
      if (!ctx) return;
      const now = ctx.currentTime;
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();

      osc.type = "sine";
      osc.frequency.setValueAtTime(523.25, now); // C5
      osc.frequency.exponentialRampToValueAtTime(1046.5, now + 0.09); // C6

      gain.gain.setValueAtTime(0.12, now);
      gain.gain.exponentialRampToValueAtTime(0.001, now + 0.2);

      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(now);
      osc.stop(now + 0.21);
    } catch (_) {}
  }

  // =========================================================================
  // State Transition Machine
  // =========================================================================
  function setMode(mode, data = {}) {
    if (!STATE_DIMENSIONS[mode]) mode = "idle";
    currentState = mode;

    if (dismissTimer) {
      clearTimeout(dismissTimer);
      dismissTimer = null;
    }

    // Hide all view panels, activate targeted panel
    Object.keys(views).forEach((key) => {
      if (views[key]) {
        views[key].classList.toggle("active", key === mode);
      }
    });

    // Update capsule CSS class for morphing
    capsule.className = `island-capsule state-${mode}`;

    // Resize window bounds to fit capsule exactly
    const dim = STATE_DIMENSIONS[mode];
    if (window.islandBridge?.resizeWindow) {
      window.islandBridge.resizeWindow(dim.width, dim.height);
    }

    // Handle specific mode behaviors
    switch (mode) {
      case "idle":
        updateClock();
        break;

      case "welcome":
        renderWelcome(data);
        playNotificationChime();
        dismissTimer = setTimeout(() => {
          if (currentState === "welcome") setMode("idle");
        }, 5000);
        break;

      case "notification":
        renderNotification(data);
        playNotificationChime();
        dismissTimer = setTimeout(() => {
          if (currentState === "notification" && !isHovered) {
            setMode("idle");
          }
        }, 6500);
        break;

      case "reply":
        renderReply(data);
        setTimeout(() => replyInput?.focus(), 150);
        break;

      case "chats":
        fetchAndRenderChats();
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
    const name = data.userName || data.fullName || "مرحباً بك في iSmart";
    if (welcomeUserEl) welcomeUserEl.textContent = name;
    if (data.avatarUrl && welcomeAvatarEl) {
      welcomeAvatarEl.src = data.avatarUrl;
    }
  }

  function renderNotification(data) {
    activeNotification = data;
    const privacy = currentSettings.privacyMode || "full";

    let sender = data.senderName || data.title || "رسالة جديدة";
    let body = data.body || data.content || "";

    if (privacy === "sender_only") {
      body = "لديك رسالة جديدة";
    } else if (privacy === "hidden") {
      sender = "iSmart Messenger";
      body = "رسالة خاصة جديدة";
    }

    if (notifSender) notifSender.textContent = sender;
    if (notifText) notifText.textContent = body;
    if (notifTime) notifTime.textContent = formatTime(new Date());

    if (data.avatarUrl && notifAvatar) {
      notifAvatar.src = data.avatarUrl;
    } else {
      notifAvatar.src = "../build/icon.ico";
    }
  }

  function renderReply(data) {
    const target = data || activeNotification || {};
    if (replySender) {
      replySender.textContent = `رد على: ${target.senderName || target.title || "المرسل"}`;
    }
    if (replyAvatar) {
      replyAvatar.src = target.avatarUrl || "../build/icon.ico";
    }
    if (replyInput) {
      replyInput.value = "";
      replyInput.disabled = false;
    }
    if (replySubmitBtn) {
      replySubmitBtn.disabled = false;
    }
    if (replyStatus) {
      replyStatus.textContent = "";
    }
  }

  function renderProgress(data) {
    const label = data.label || "جاري نقل الملف...";
    const percent = Math.min(100, Math.max(0, Number(data.percent || 0)));

    if (progressLabel) progressLabel.textContent = label;
    if (progressPercent) progressPercent.textContent = `${Math.round(percent)}%`;
    if (progressBarFill) progressBarFill.style.width = `${percent}%`;

    if (percent >= 100) {
      if (progressLabel) progressLabel.textContent = "اكتمل بنجاح ✓";
      playSuccessPop();
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
        renderChatsList(chats);
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

  function renderChatsList(chats) {
    if (!chatsContainer) return;
    chatsContainer.innerHTML = "";

    chats.slice(0, 10).forEach((chat) => {
      const item = document.createElement("div");
      item.className = "chat-item";

      const title = chat.name || chat.title || "محادثة";
      const preview = chat.lastMessage?.content || chat.snippet || "انقر للمراسلة";
      const time = chat.updatedAt ? formatTime(new Date(chat.updatedAt)) : "";
      const unread = Number(chat.unreadCount || 0);
      const avatarSrc = chat.avatarUrl || "../build/icon.ico";

      item.innerHTML = `
        <div class="chat-avatar-wrap">
          <img src="${avatarSrc}" alt="${escapeHtml(title)}" class="chat-avatar" onerror="this.src='../build/icon.ico'">
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

      item.addEventListener("click", () => {
        window.islandBridge?.openConversation(chat.id || chat._id);
        setMode("idle");
      });

      chatsContainer.appendChild(item);
    });
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
    if (toggleSound) toggleSound.checked = currentSettings.soundEnabled !== false;
    applyTheme(currentSettings.theme || "obsidian");
  }

  async function saveSettingsFromUI() {
    currentSettings.enabled = toggleEnabled ? toggleEnabled.checked : true;
    currentSettings.startMinimizedOnBoot = toggleBootHidden ? toggleBootHidden.checked : true;
    currentSettings.privacyMode = selectPrivacy ? selectPrivacy.value : "full";
    currentSettings.soundEnabled = toggleSound ? toggleSound.checked : true;

    applyTheme(currentSettings.theme);
    await window.islandBridge?.saveSettings(currentSettings);
  }

  // =========================================================================
  // Reply Actions
  // =========================================================================
  async function submitQuickReply() {
    const text = replyInput?.value?.trim();
    if (!text) return;

    const conversationId = activeNotification?.conversationId || activeNotification?.id;
    if (!conversationId) {
      if (replyStatus) replyStatus.textContent = "لا يمكن العثور على المحادثة";
      return;
    }

    if (replyInput) replyInput.disabled = true;
    if (replySubmitBtn) replySubmitBtn.disabled = true;
    if (replyStatus) {
      replyStatus.textContent = "جاري الإرسال...";
      replyStatus.style.color = "var(--accent-color)";
    }

    try {
      const res = await window.islandBridge?.sendReply({
        conversationId,
        content: text,
      });

      if (res?.success !== false) {
        playSuccessPop();
        if (replyStatus) {
          replyStatus.textContent = "تم الإرسال بنجاح ✓";
          replyStatus.style.color = "var(--success-color)";
        }
        dismissTimer = setTimeout(() => {
          if (currentState === "reply") setMode("idle");
        }, 1200);
      } else {
        if (replyStatus) {
          replyStatus.textContent = res?.error || "فشل الإرسال";
          replyStatus.style.color = "var(--danger-color)";
        }
        if (replyInput) replyInput.disabled = false;
        if (replySubmitBtn) replySubmitBtn.disabled = false;
      }
    } catch (err) {
      if (replyStatus) {
        replyStatus.textContent = "خطأ في الشبكة";
        replyStatus.style.color = "var(--danger-color)";
      }
      if (replyInput) replyInput.disabled = false;
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

    // Clicking idle capsule opens chats drawer
    views.idle?.addEventListener("click", () => {
      setMode("chats");
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
        window.islandBridge?.openConversation(activeNotification.conversationId);
      } else {
        window.islandBridge?.showMainWindow();
      }
      setMode("idle");
    });

    // Reply actions
    document.getElementById("reply-cancel-btn")?.addEventListener("click", () => {
      setMode("idle");
    });

    replySubmitBtn?.addEventListener("click", submitQuickReply);

    replyInput?.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault();
        submitQuickReply();
      } else if (e.key === "Escape") {
        e.preventDefault();
        setMode("idle");
      }
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

    // Progress dismiss
    document.getElementById("progress-dismiss-btn")?.addEventListener("click", () => {
      setMode("idle");
    });

    // Settings actions
    document.getElementById("settings-back-btn")?.addEventListener("click", () => {
      setMode("chats");
    });

    btnTestNotif?.addEventListener("click", () => {
      setMode("notification", {
        senderName: "مهندس يوسف (تجربة)",
        body: "السلام عليكم! الجزيرة التفاعلية تعمل الآن بنجاح على الويندوز ✨",
        conversationId: "test_conv",
      });
    });

    toggleEnabled?.addEventListener("change", saveSettingsFromUI);
    toggleBootHidden?.addEventListener("change", saveSettingsFromUI);
    selectPrivacy?.addEventListener("change", saveSettingsFromUI);
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

    // Load initial settings
    try {
      const loaded = await window.islandBridge.getSettings();
      if (loaded && typeof loaded === "object") {
        currentSettings = { ...currentSettings, ...loaded };
        applyTheme(currentSettings.theme || "obsidian");
      }
    } catch (_) {}

    // Notification listener
    window.islandBridge.onNotification((data) => {
      if (currentSettings.enabled === false) return;
      setMode("notification", data);
    });

    // Welcome greeting listener
    window.islandBridge.onWelcome((data) => {
      if (currentSettings.enabled === false) return;
      setMode("welcome", data);
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
          renderChatsList(chats);
        }
      }
    });

    // Settings updated externally
    window.islandBridge.onSettingsUpdated((newSettings) => {
      currentSettings = { ...currentSettings, ...newSettings };
      syncSettingsUI();
    });

    // Active User updated
    window.islandBridge.onActiveUserUpdated((user) => {
      if (user) {
        if (welcomeUserEl) welcomeUserEl.textContent = user.fullName || user.username || "مرحباً بك";
        if (user.avatarUrl && welcomeAvatarEl) {
          welcomeAvatarEl.src = user.avatarUrl;
        }
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
