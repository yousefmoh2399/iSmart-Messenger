const fs = require("fs");
const logger = require("../utils/logger");
const ConversationMemberState = require("../chat/models/conversation-member-state.model");

let firebaseAdmin = null;
try {
  firebaseAdmin = require("firebase-admin");
} catch (_) {
  firebaseAdmin = null;
}

const PushDevice = require("../models/push-device.model");

let cachedMessaging = null;
let loggedMessagingInitError = false;

function normalizePlatform(value) {
  const normalized = String(value || "")
    .trim()
    .toLowerCase();
  if (normalized === "android" || normalized === "ios") {
    return normalized;
  }
  return "unknown";
}

function loadServiceAccountFromEnv() {
  const rawJson = String(process.env.FIREBASE_SERVICE_ACCOUNT_JSON || "").trim();
  if (rawJson) {
    return JSON.parse(rawJson);
  }

  const rawBase64 = String(
    process.env.FIREBASE_SERVICE_ACCOUNT_BASE64 || ""
  ).trim();
  if (rawBase64) {
    return JSON.parse(Buffer.from(rawBase64, "base64").toString("utf8"));
  }

  const rawPath = String(process.env.FIREBASE_SERVICE_ACCOUNT_PATH || "").trim();
  if (rawPath && fs.existsSync(rawPath)) {
    return JSON.parse(fs.readFileSync(rawPath, "utf8"));
  }

  return null;
}

function getMessaging() {
  if (cachedMessaging) {
    return cachedMessaging;
  }
  if (!firebaseAdmin) {
    return null;
  }

  try {
    const app =
      firebaseAdmin.apps.length > 0
        ? firebaseAdmin.app()
        : firebaseAdmin.initializeApp({
            credential: (() => {
              const serviceAccount = loadServiceAccountFromEnv();
              if (serviceAccount) {
                return firebaseAdmin.credential.cert(serviceAccount);
              }
              return firebaseAdmin.credential.applicationDefault();
            })(),
          });
    cachedMessaging = app.messaging();
    return cachedMessaging;
  } catch (error) {
    // Push is optional; surface the misconfiguration once so it does not fail
    // silently forever, but keep the app running without push delivery.
    if (!loggedMessagingInitError) {
      loggedMessagingInitError = true;
      logger.warn("push.messaging_init_failed", {
        errorName: error?.name,
        errorMessage: error?.message,
      });
    }
    return null;
  }
}

function buildChatBody(message) {
  const content = String(message?.content || "").trim();
  if (content) {
    return content.slice(0, 160);
  }

  const fileName = String(message?.fileName || "").trim();
  if (fileName) {
    return `Attachment: ${fileName}`.slice(0, 160);
  }

  return "You have received a new chat message.";
}

function normalizeNotificationToneId(value) {
  const normalized = String(value || "").trim().toLowerCase();
  if (
    normalized === "default" ||
    normalized === "chime" ||
    normalized === "alert" ||
    normalized === "silent"
  ) {
    return normalized;
  }
  return "default";
}

function androidChannelIdForToneId(toneId) {
  switch (normalizeNotificationToneId(toneId)) {
    case "chime":
      return "chat_messages_chime_v1";
    case "alert":
      return "chat_messages_alert_v1";
    case "silent":
      return "chat_messages_silent_v1";
    default:
      return "chat_messages_default_v1";
  }
}

function groupPushDevicesByAndroidChannel(devices = []) {
  const grouped = new Map();
  for (const entry of devices) {
    const token = String(entry?.token || "").trim();
    if (!token) {
      continue;
    }
    const platform = normalizePlatform(entry?.platform);
    const bucketKey =
      platform === "android"
        ? `android:${androidChannelIdForToneId(entry?.notificationToneId)}`
        : `other:${platform}`;
    const bucket = grouped.get(bucketKey) || [];
    bucket.push(entry);
    grouped.set(bucketKey, bucket);
  }
  return [...grouped.values()];
}

function normalizeUserId(value) {
  if (!value) {
    return "";
  }
  if (typeof value === "object") {
    return String(value._id || value.id || value.userId || "").trim();
  }
  const text = String(value).trim();
  return /^[a-f0-9]{24}$/i.test(text) ? text : "";
}

function normalizeUserIds(values = []) {
  return [
    ...new Set(
      (values || [])
        .map(normalizeUserId)
        .filter(Boolean),
    ),
  ];
}

async function disableInvalidTokens(tokens) {
  if (!tokens.length) {
    return;
  }
  await PushDevice.updateMany(
    { token: { $in: tokens } },
    {
      $set: {
        isActive: false,
      },
    }
  );
}

async function sendChatPushNotifications({
  recipientUserIds = [],
  conversation = null,
  message = null,
  senderName = "New message",
  shouldNotifyUser = null,
} = {}) {
  const messaging = getMessaging();
  if (!messaging) {
    return { enabled: false, sentCount: 0, skippedCount: recipientUserIds.length };
  }

  if (message?.metadata?.silent === true) {
    return { enabled: true, sentCount: 0, skippedCount: recipientUserIds.length };
  }

  const userIds = normalizeUserIds(recipientUserIds);
  if (userIds.length === 0) {
    return { enabled: true, sentCount: 0, skippedCount: 0 };
  }

  let allowedUserIds =
    typeof shouldNotifyUser === "function"
      ? userIds.filter((userId) => shouldNotifyUser(userId) === true)
      : userIds;

  if (allowedUserIds.length > 0 && conversation && message) {
    const mentions = message.metadata?.mentions || [];
    const memberStates = await ConversationMemberState.find(
      {
        conversationId: conversation._id || conversation.id,
        userId: { $in: allowedUserIds },
        isMuted: true,
      },
      "userId"
    ).lean();

    const mutedUserIds = new Set(
      memberStates.map((doc) => doc.userId.toString())
    );

    allowedUserIds = allowedUserIds.filter((userId) => {
      if (!mutedUserIds.has(userId)) {
        return true;
      }
      if (mentions.includes(userId)) {
        return true;
      }
      return false;
    });
  }

  if (allowedUserIds.length === 0) {
    return { enabled: true, sentCount: 0, skippedCount: userIds.length };
  }

  const devices = await PushDevice.find(
    {
      userId: { $in: allowedUserIds },
      isActive: true,
      token: { $ne: null },
    },
    "userId token platform notificationToneId isLoggedOut unreadSinceLogout"
  ).lean();

  const loggedInDevices = [];
  
  for (const device of devices) {
    if (device.isLoggedOut) {
      const newUnreadCount = (device.unreadSinceLogout || 0) + 1;
      if (newUnreadCount >= 5) {
        try {
          await messaging.send({
            token: device.token,
            notification: {
              title: "لديك رسائل غير مقروءة",
              body: "سجل الدخول لمشاهدة الرسائل الجديدة والمهمة.",
            },
            data: { type: "logged_out_alert" }
          });
        } catch (e) {
          // ignore
        }
        await PushDevice.updateOne({ _id: device._id }, { $set: { unreadSinceLogout: 0 } });
      } else {
        await PushDevice.updateOne({ _id: device._id }, { $inc: { unreadSinceLogout: 1 } });
      }
    } else {
      loggedInDevices.push(device);
    }
  }

  const deviceGroups = groupPushDevicesByAndroidChannel(loggedInDevices);
  const uniqueTokens = [
    ...new Set(loggedInDevices.map((entry) => String(entry.token || "").trim()).filter(Boolean)),
  ];
  if (uniqueTokens.length === 0) {
    return {
      enabled: true,
      sentCount: 0,
      skippedCount: userIds.length,
    };
  }

  const invalidTokens = [];
  let successCount = 0;
  let failureCount = 0;

  for (const deviceGroup of deviceGroups) {
    const groupTokens = [
      ...new Set(deviceGroup.map((entry) => String(entry.token || "").trim()).filter(Boolean)),
    ];
    const firstDevice = deviceGroup[0] || {};
    const androidChannelId =
      normalizePlatform(firstDevice.platform) === "android"
        ? androidChannelIdForToneId(firstDevice.notificationToneId)
        : null;

    for (let index = 0; index < groupTokens.length; index += 500) {
      const batch = groupTokens.slice(index, index + 500);
      const response = await messaging.sendEachForMulticast({
        tokens: batch,
        notification: {
          title: String(senderName || "New message").slice(0, 120),
          body: buildChatBody(message),
        },
        data: {
          type: "chat",
          conversationId:
            String(message?.conversationId || conversation?.id || "").trim(),
          messageId: String(message?.id || "").trim(),
          senderId: String(message?.senderId || "").trim(),
        },
        android: {
          priority: "high",
          notification: {
            channelId: androidChannelId || "chat_messages_default_v1",
            priority: "high",
          },
        },
        apns: {
          headers: {
            "apns-priority": "10",
          },
          payload: {
            aps: {
              sound: "default",
              contentAvailable: true,
            },
          },
        },
      });

      successCount += response.successCount || 0;
      failureCount += response.failureCount || 0;
      response.responses.forEach((entry, responseIndex) => {
        if (entry.success) {
          return;
        }
        const code = String(entry.error?.code || "");
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token"
        ) {
          invalidTokens.push(batch[responseIndex]);
        }
      });
    }
  }

  await disableInvalidTokens(invalidTokens);

  return {
    enabled: true,
    sentCount: successCount,
    skippedCount: Math.max(0, userIds.length - allowedUserIds.length),
    failureCount,
  };
}

async function sendChatReactionPushNotifications({
  recipientUserIds = [],
  conversationId = "",
  messageId = "",
  emoji = "",
  reactorName = "",
  shouldNotifyUser = null,
} = {}) {
  const messaging = getMessaging();
  if (!messaging) {
    return { enabled: false, sentCount: 0, skippedCount: recipientUserIds.length };
  }

  const userIds = normalizeUserIds(recipientUserIds);
  if (userIds.length === 0) {
    return { enabled: true, sentCount: 0, skippedCount: 0 };
  }

  const allowedUserIds =
    typeof shouldNotifyUser === "function"
      ? userIds.filter((userId) => shouldNotifyUser(userId) === true)
      : userIds;
  if (allowedUserIds.length === 0) {
    return { enabled: true, sentCount: 0, skippedCount: userIds.length };
  }

  const devices = await PushDevice.find(
    {
      userId: { $in: allowedUserIds },
      isActive: true,
      isLoggedOut: { $ne: true },
      token: { $ne: null },
    },
    "userId token platform notificationToneId"
  ).lean();

  const deviceGroups = groupPushDevicesByAndroidChannel(devices);
  const uniqueTokens = [
    ...new Set(devices.map((entry) => String(entry.token || "").trim()).filter(Boolean)),
  ];
  if (uniqueTokens.length === 0) {
    return {
      enabled: true,
      sentCount: 0,
      skippedCount: userIds.length,
    };
  }

  const title = String(reactorName || "تفاعل جديد").slice(0, 120);
  const body = `تفاعل على رسالتك: ${String(emoji || "❤️").slice(0, 16)}`.slice(0, 160);
  const invalidTokens = [];
  let successCount = 0;
  let failureCount = 0;

  for (const deviceGroup of deviceGroups) {
    const groupTokens = [
      ...new Set(deviceGroup.map((entry) => String(entry.token || "").trim()).filter(Boolean)),
    ];
    const firstDevice = deviceGroup[0] || {};
    const androidChannelId =
      normalizePlatform(firstDevice.platform) === "android"
        ? androidChannelIdForToneId(firstDevice.notificationToneId)
        : null;

    for (let index = 0; index < groupTokens.length; index += 500) {
      const batch = groupTokens.slice(index, index + 500);
      const response = await messaging.sendEachForMulticast({
        tokens: batch,
        notification: {
          title,
          body,
        },
        data: {
          type: "chat_reaction",
          conversationId: String(conversationId || "").trim(),
          messageId: String(messageId || "").trim(),
          emoji: String(emoji || "").trim().slice(0, 16),
        },
        android: {
          priority: "high",
          notification: {
            channelId: androidChannelId || "chat_messages_default_v1",
            priority: "high",
          },
        },
        apns: {
          headers: {
            "apns-priority": "10",
          },
          payload: {
            aps: {
              sound: "default",
              contentAvailable: true,
            },
          },
        },
      });

      successCount += response.successCount || 0;
      failureCount += response.failureCount || 0;
      response.responses.forEach((entry, responseIndex) => {
        if (entry.success) {
          return;
        }
        const code = String(entry.error?.code || "");
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token"
        ) {
          invalidTokens.push(batch[responseIndex]);
        }
      });
    }
  }

  await disableInvalidTokens(invalidTokens);

  return {
    enabled: true,
    sentCount: successCount,
    skippedCount: Math.max(0, userIds.length - allowedUserIds.length),
    failureCount,
  };
}

async function sendTicketPushNotifications({
  recipientUserIds = [],
  ticket = null,
  action = "",
  title = "تحديث تذكرة",
  body = "",
} = {}) {
  const messaging = getMessaging();
  if (!messaging) {
    return { enabled: false, sentCount: 0, skippedCount: recipientUserIds.length };
  }

  const userIds = normalizeUserIds(recipientUserIds);
  if (userIds.length === 0) {
    return { enabled: true, sentCount: 0, skippedCount: 0 };
  }

  const devices = await PushDevice.find(
    {
      userId: { $in: userIds },
      isActive: true,
      isLoggedOut: { $ne: true },
      token: { $ne: null },
    },
    "userId token platform notificationToneId"
  ).lean();

  const deviceGroups = groupPushDevicesByAndroidChannel(devices);
  const uniqueTokens = [
    ...new Set(devices.map((entry) => String(entry.token || "").trim()).filter(Boolean)),
  ];
  if (uniqueTokens.length === 0) {
    return { enabled: true, sentCount: 0, skippedCount: userIds.length };
  }

  const invalidTokens = [];
  let successCount = 0;
  let failureCount = 0;
  const ticketId = String(ticket?.id || ticket?._id || "").trim();
  const ticketNumber = String(ticket?.ticketNumber || "").trim();

  for (const deviceGroup of deviceGroups) {
    const groupTokens = [
      ...new Set(deviceGroup.map((entry) => String(entry.token || "").trim()).filter(Boolean)),
    ];
    const firstDevice = deviceGroup[0] || {};
    const androidChannelId =
      normalizePlatform(firstDevice.platform) === "android"
        ? androidChannelIdForToneId(firstDevice.notificationToneId)
        : null;

    for (let index = 0; index < groupTokens.length; index += 500) {
      const batch = groupTokens.slice(index, index + 500);
      const response = await messaging.sendEachForMulticast({
        tokens: batch,
        notification: {
          title: String(title || "تحديث تذكرة").slice(0, 120),
          body: String(body || ticket?.title || "يوجد تحديث على التذاكر").slice(0, 160),
        },
        data: {
          type: "ticket",
          ticketId,
          ticketNumber,
          action: String(action || "").trim(),
          title: String(title || "").slice(0, 120),
          body: String(body || ticket?.title || "").slice(0, 160),
        },
        android: {
          priority: "high",
          notification: {
            channelId: androidChannelId || "chat_messages_default_v1",
            priority: "high",
          },
        },
        apns: {
          headers: { "apns-priority": "10" },
          payload: { aps: { sound: "default", contentAvailable: true } },
        },
      });

      successCount += response.successCount || 0;
      failureCount += response.failureCount || 0;
      response.responses.forEach((entry, responseIndex) => {
        if (entry.success) return;
        const code = String(entry.error?.code || "");
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token"
        ) {
          invalidTokens.push(batch[responseIndex]);
        }
      });
    }
  }

  await disableInvalidTokens(invalidTokens);
  return { enabled: true, sentCount: successCount, skippedCount: 0, failureCount };
}

async function registerPushDevice(actor, payload = {}) {
  const token = String(payload.token || "").trim();
  if (!token) {
    return null;
  }

  const deviceId = String(payload.deviceId || "").trim() || null;
  if (deviceId) {
    await PushDevice.updateMany(
      {
        userId: actor.id,
        deviceId,
        token: { $ne: token },
      },
      {
        $set: {
          isActive: false,
        },
      }
    );
  }

  return PushDevice.findOneAndUpdate(
    { token },
    {
      $set: {
        userId: actor.id,
        token,
        platform: normalizePlatform(payload.platform),
        deviceId,
        deviceName: String(payload.deviceName || "").trim() || null,
        appVersion: String(payload.appVersion || "").trim() || null,
        notificationToneId: normalizeNotificationToneId(
          payload.notificationToneId
        ),
        isActive: true,
        isLoggedOut: false,
        unreadSinceLogout: 0,
        lastSeenAt: new Date(),
      },
    },
    {
      upsert: true,
      new: true,
      setDefaultsOnInsert: true,
    }
  ).lean();
}

async function unregisterPushDevice(actor, payload = {}) {
  const token = String(payload.token || "").trim();
  if (!token) {
    return false;
  }

  await PushDevice.updateMany(
    {
      userId: actor.id,
      token,
    },
    {
      $set: {
        isLoggedOut: true,
        unreadSinceLogout: 0,
      },
    }
  );
  return true;
}

module.exports = {
  registerPushDevice,
  unregisterPushDevice,
  sendChatPushNotifications,
  sendChatReactionPushNotifications,
  sendTicketPushNotifications,
};
