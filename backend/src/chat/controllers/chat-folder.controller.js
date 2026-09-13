const asyncHandler = require("../../middleware/async-handler");
const {
  getUserFolders,
  createFolder,
  updateFolder,
  deleteFolder,
  reorderFolders,
} = require("../services/chat-folder.service");

const getFolders = asyncHandler(async (req, res) => {
  const folders = await getUserFolders(req.user.id);
  res.status(200).json({ status: 200, data: folders });
});

const postFolder = asyncHandler(async (req, res) => {
  const folder = await createFolder(req.user.id, req.body);
  res.status(201).json({ status: 201, data: folder });
});

const putFolder = asyncHandler(async (req, res) => {
  const folder = await updateFolder(req.user.id, req.params.folderId, req.body);
  res.status(200).json({ status: 200, data: folder });
});

const removeFolder = asyncHandler(async (req, res) => {
  await deleteFolder(req.user.id, req.params.folderId);
  res.status(200).json({ status: 200, data: null });
});

const putFoldersReorder = asyncHandler(async (req, res) => {
  const { folderIds } = req.body;
  const folders = await reorderFolders(req.user.id, folderIds);
  res.status(200).json({ status: 200, data: folders });
});

module.exports = {
  getFolders,
  postFolder,
  putFolder,
  removeFolder,
  putFoldersReorder,
};
