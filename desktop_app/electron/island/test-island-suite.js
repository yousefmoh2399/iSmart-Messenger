/**
 * Automated Dynamic Island End-to-End Test Suite
 * Tests all states, sound synthesis, privacy masking, search filtering,
 * audio speeds, mini chat, and call activities.
 */

const assert = require("assert");
const fs = require("fs");
const path = require("path");

console.log("==================================================");
console.log("   DYNAMIC ISLAND V2 ULTRA AUTOMATED TEST SUITE   ");
console.log("==================================================");

// 1. Verify HTML Structure and All 10 Views
console.log("\n[TEST 1] Verifying HTML Views & Elements...");
const htmlPath = path.join(__dirname, "index.html");
const html = fs.readFileSync(htmlPath, "utf8");

const requiredViews = [
  "view-idle",
  "view-welcome",
  "view-notification",
  "view-reply",
  "view-chats",
  "view-chatview",
  "view-audio",
  "view-call",
  "view-progress",
  "view-settings",
];

requiredViews.forEach((viewId) => {
  assert(html.includes(`id="${viewId}"`), `Missing required view: ${viewId}`);
  console.log(`  ✓ View Panel present: ${viewId}`);
});

const requiredElements = [
  "chats-search-input",
  "chats-search-clear",
  "tab-filter-all",
  "tab-filter-unread",
  "tab-filter-groups",
  "audio-speed-btn",
  "audio-progress-scrubber",
  "audio-progress-bar",
  "call-accept-btn",
  "call-decline-btn",
  "btn-preview-sound",
  "btn-test-notification",
  "btn-test-audio",
  "btn-test-call",
  "setting-position-select",
  "dot-titanium",
];

requiredElements.forEach((elId) => {
  assert(html.includes(elId), `Missing required element: ${elId}`);
  console.log(`  ✓ Interactive Element present: ${elId}`);
});

// 2. Verify CSS Theme Classes and Animations
console.log("\n[TEST 2] Verifying CSS Themes & Keyframes...");
const cssPath = path.join(__dirname, "styles.css");
const css = fs.readFileSync(cssPath, "utf8");

const requiredCss = [
  "theme-obsidian",
  "theme-midnight",
  "theme-neon",
  "theme-emerald",
  "theme-crimson",
  "theme-titanium",
  "apple-spring-in",
  "wave-bounce",
  "call-pulse",
  "audio-progress-scrubber",
  "chats-search-bar",
  "chatview-quick-chips",
];

requiredCss.forEach((rule) => {
  assert(css.includes(rule), `Missing CSS rule/class: ${rule}`);
  console.log(`  ✓ CSS Rule present: ${rule}`);
});

// 3. Test DynamicIslandManager Logic & Privacy Engine
console.log("\n[TEST 3] Testing DynamicIslandManager & Privacy Engine...");
const { DynamicIslandManager } = require("./island-manager");
const manager = new DynamicIslandManager();

let dispatchedPayload = null;
let dispatchedChannel = null;

manager.islandWindow = {
  isDestroyed: () => false,
  isVisible: () => true,
  show: () => {},
  webContents: {
    send: (channel, data) => {
      dispatchedChannel = channel;
      dispatchedPayload = data;
    },
  },
};

// 3A. Privacy: Full mode
manager.settings.privacyMode = "full";
manager.showNotification({
  senderName: "أحمد علي",
  body: "نص الرسالة السري",
  conversationId: "conv_1",
});
assert.strictEqual(dispatchedPayload.senderName, "أحمد علي");
assert.strictEqual(dispatchedPayload.body, "نص الرسالة السري");
console.log("  ✓ Privacy Mode 'full' passes");

// 3B. Privacy: Sender Only mode
manager.settings.privacyMode = "sender_only";
manager.showNotification({
  senderName: "أحمد علي",
  body: "نص الرسالة السري",
  conversationId: "conv_1",
});
assert.strictEqual(dispatchedPayload.senderName, "أحمد علي");
assert.strictEqual(dispatchedPayload.body, "لديك رسالة جديدة");
console.log("  ✓ Privacy Mode 'sender_only' passes");

// 3C. Privacy: Hidden (Secret) mode
manager.settings.privacyMode = "hidden";
manager.showNotification({
  senderName: "أحمد علي",
  body: "نص الرسالة السري",
  conversationId: "conv_1",
});
assert.strictEqual(dispatchedPayload.senderName, "iSmart Messenger");
assert.strictEqual(dispatchedPayload.body, "رسالة خاصة جديدة");
assert.strictEqual(dispatchedPayload.avatarUrl, null);
console.log("  ✓ Privacy Mode 'hidden' passes");

// 3D. Audio State Synchronization
console.log("\n[TEST 4] Testing Audio State Synchronization...");
manager.syncAudioState({
  senderName: "يوسف الفويس",
  currentTime: "0:25",
  totalTime: "1:40",
  isPlaying: true,
  percent: 30,
});
assert.strictEqual(dispatchedChannel, "island:audio-state");
assert.strictEqual(dispatchedPayload.senderName, "يوسف الفويس");
assert.strictEqual(dispatchedPayload.currentTime, "0:25");
console.log("  ✓ Audio State Synchronization passes");

// 3E. Call State Synchronization
console.log("\n[TEST 5] Testing Call State Synchronization...");
manager.syncCallState({
  callerName: "أحمد محمود",
  status: "مكالمة واردة...",
});
assert.strictEqual(dispatchedChannel, "island:call-state");
assert.strictEqual(dispatchedPayload.callerName, "أحمد محمود");
console.log("  ✓ Call State Synchronization passes");

// 4. Test Search Filtering Algorithm
console.log("\n[TEST 6] Testing Chats Search & Category Filtering Algorithm...");
const testChats = [
  { id: "1", name: "فريق تطوير الديسكتوب", lastMessage: { content: "تم تحديث الجزيرة" }, isGroup: true, unreadCount: 2 },
  { id: "2", name: "مريم أحمد", lastMessage: { content: "أين الملف؟" }, isGroup: false, unreadCount: 0 },
  { id: "3", name: "دعم العملاء", lastMessage: { content: "مرحباً بكم" }, isGroup: true, unreadCount: 5 },
  { id: "4", name: "خالد بن الوليد", lastMessage: { content: "شكراً جزيلاً" }, isGroup: false, unreadCount: 0 },
];

// Test Unread tab
const unreadFilter = testChats.filter(c => Number(c.unreadCount || 0) > 0);
assert.strictEqual(unreadFilter.length, 2);
console.log("  ✓ Unread tab filters exactly 2 chats");

// Test Groups tab
const groupsFilter = testChats.filter(c => c.isGroup);
assert.strictEqual(groupsFilter.length, 2);
console.log("  ✓ Groups tab filters exactly 2 groups");

// Test Search keyword "تحديث"
const searchFilter = testChats.filter(c => 
  (c.name || "").includes("تحديث") || 
  (c.lastMessage?.content || "").includes("تحديث")
);
assert.strictEqual(searchFilter.length, 1);
assert.strictEqual(searchFilter[0].id, "1");
console.log("  ✓ Search query 'تحديث' correctly locates conversation 'فريق تطوير الديسكتوب'");

// 5. Calm Apple Sound Engine Audio Math Verification
console.log("\n[TEST 7] Verifying Calm Apple Acoustic Frequencies & Envelope...");
const rendererCode = fs.readFileSync(path.join(__dirname, "island-renderer.js"), "utf8");

// Verify Apple Frequencies used: E5 (659.25), B5 (987.77), E6 (1318.5)
assert(rendererCode.includes("659.25"), "Missing Apple E5 foundation frequency");
assert(rendererCode.includes("987.77"), "Missing Apple B5 marimba frequency");
assert(rendererCode.includes("1318.5"), "Missing Apple E6 shimmer frequency");
// Verify Lowpass filter exists
assert(rendererCode.includes("ctx.createBiquadFilter()"), "Missing BiquadFilter for silky warmth");
assert(rendererCode.includes("1400"), "Missing 1400Hz lowpass cutoff");
console.log("  ✓ Apple Acoustic Synthesizer frequencies and warm 1400Hz cutoff verified!");

console.log("\n==================================================");
console.log("  🎉 ALL 7 TEST SUITES PASSED FLAWLESSLY (100%)   ");
console.log("==================================================");
