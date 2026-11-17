const UserStickers = require("../models/user-stickers.model");

async function getUserStickers(userId) {
  let doc = await UserStickers.findOne({ userId }).lean();
  if (!doc) {
    return { stickers: [], packs: [] };
  }
  return {
    stickers: doc.stickers || [],
    packs: doc.packs || [],
  };
}

async function syncUserStickers(userId, { stickers = [], packs = [] }) {
  const sanitizedStickers = (Array.isArray(stickers) ? stickers : [])
    .filter((s) => s && s.id && s.name && s.bytes)
    .slice(0, 500); // cap to 500 stickers per user

  const sanitizedPacks = (Array.isArray(packs) ? packs : [])
    .filter((p) => p && p.id && p.name)
    .slice(0, 50);

  const updated = await UserStickers.findOneAndUpdate(
    { userId },
    {
      $set: {
        stickers: sanitizedStickers,
        packs: sanitizedPacks,
      },
    },
    { upsert: true, new: true, setDefaultsOnInsert: true }
  ).lean();

  return {
    stickers: updated.stickers || [],
    packs: updated.packs || [],
  };
}

async function addOrUpdateUserSticker(userId, stickerData) {
  if (!stickerData || !stickerData.name || !stickerData.bytes) {
    throw new Error("Invalid sticker data");
  }

  const id = stickerData.id || `${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  const sticker = {
    id,
    name: String(stickerData.name).slice(0, 255),
    bytes: String(stickerData.bytes),
    category: stickerData.category || "عام",
    favorite: Boolean(stickerData.favorite),
    lastUsedAt: Number(stickerData.lastUsedAt) || Date.now(),
  };

  let doc = await UserStickers.findOne({ userId });
  if (!doc) {
    doc = new UserStickers({ userId, stickers: [sticker], packs: [] });
  } else {
    const existingIndex = doc.stickers.findIndex(
      (s) => s.id === sticker.id || (s.name === sticker.name && s.bytes === sticker.bytes)
    );
    if (existingIndex >= 0) {
      doc.stickers[existingIndex] = { ...doc.stickers[existingIndex].toObject(), ...sticker };
    } else {
      doc.stickers.unshift(sticker);
      if (doc.stickers.length > 500) {
        doc.stickers = doc.stickers.slice(0, 500);
      }
    }
  }

  await doc.save();
  return {
    sticker,
    stickers: doc.stickers,
    packs: doc.packs,
  };
}

async function deleteUserSticker(userId, stickerId) {
  const doc = await UserStickers.findOne({ userId });
  if (!doc) return { stickers: [], packs: [] };

  doc.stickers = doc.stickers.filter((s) => s.id !== stickerId);
  doc.packs = doc.packs.map((pack) => {
    pack.stickerIds = pack.stickerIds.filter((id) => id !== stickerId);
    if (pack.coverStickerId === stickerId) {
      pack.coverStickerId = pack.stickerIds[0] || null;
    }
    return pack;
  });

  await doc.save();
  return {
    stickers: doc.stickers,
    packs: doc.packs,
  };
}

module.exports = {
  getUserStickers,
  syncUserStickers,
  addOrUpdateUserSticker,
  deleteUserSticker,
};
