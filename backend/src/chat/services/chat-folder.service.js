const ChatFolder = require("../models/chat-folder.model");
const ApiError = require("../../utils/ApiError");

async function getUserFolders(userId) {
  return await ChatFolder.find({ userId }).sort({ order: 1 }).lean();
}

async function createFolder(userId, payload) {
  const { name, icon, conversationIds } = payload;
  if (!name || !name.trim()) {
    throw new ApiError(400, "Folder name is required");
  }

  // Get current max order
  const lastFolder = await ChatFolder.findOne({ userId }).sort({ order: -1 }).lean();
  const nextOrder = lastFolder ? (lastFolder.order || 0) + 1 : 0;

  const folder = await ChatFolder.create({
    userId,
    name: name.trim(),
    icon: icon || null,
    conversationIds: conversationIds || [],
    order: nextOrder,
  });

  return folder;
}

async function updateFolder(userId, folderId, payload) {
  const { name, icon, conversationIds, order } = payload;
  const updateData = {};
  if (name !== undefined) updateData.name = name.trim();
  if (icon !== undefined) updateData.icon = icon;
  if (conversationIds !== undefined) updateData.conversationIds = conversationIds;
  if (order !== undefined) updateData.order = order;

  const folder = await ChatFolder.findOneAndUpdate(
    { _id: folderId, userId },
    { $set: updateData },
    { new: true }
  ).lean();

  if (!folder) {
    throw new ApiError(404, "Chat folder not found");
  }

  return folder;
}

async function deleteFolder(userId, folderId) {
  const folder = await ChatFolder.findOneAndDelete({ _id: folderId, userId }).lean();
  if (!folder) {
    throw new ApiError(404, "Chat folder not found");
  }
  return true;
}

async function reorderFolders(userId, folderIds) {
  const promises = folderIds.map((id, index) => 
    ChatFolder.updateOne({ _id: id, userId }, { $set: { order: index } })
  );
  await Promise.all(promises);
  return await getUserFolders(userId);
}

module.exports = {
  getUserFolders,
  createFolder,
  updateFolder,
  deleteFolder,
  reorderFolders,
};
