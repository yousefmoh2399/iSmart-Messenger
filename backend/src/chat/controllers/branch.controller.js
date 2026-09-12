const asyncHandler = require("../../utils/async-handler");
const { sendChatResponse } = require("../utils/chat-response");
const {
  listBranches,
  createBranch,
  updateBranch,
  deleteBranch,
} = require("../services/branch.service");

const getBranches = asyncHandler(async (req, res) => {
  const branches = await listBranches();
  sendChatResponse(res, {
    data: { branches },
    legacy: { branches },
  });
});

const createManagedBranch = asyncHandler(async (req, res) => {
  const branch = await createBranch(req.user, req.body);
  const io = req.app.get("io");
  if (io) {
    io.emit("branches_updated", {});
  }
  sendChatResponse(res, {
    status: 201,
    data: { branch },
    legacy: { branch },
  });
});

const updateManagedBranch = asyncHandler(async (req, res) => {
  const branch = await updateBranch(req.user, req.params.id, req.body);
  const io = req.app.get("io");
  if (io) {
    io.emit("branches_updated", {});
  }
  sendChatResponse(res, {
    data: { branch },
    legacy: { branch },
  });
});

const deleteManagedBranch = asyncHandler(async (req, res) => {
  await deleteBranch(req.user, req.params.id);
  const io = req.app.get("io");
  if (io) {
    io.emit("branches_updated", {});
  }
  sendChatResponse(res, {
    data: { deleted: true },
    legacy: { deleted: true },
  });
});

module.exports = {
  getBranches,
  createManagedBranch,
  updateManagedBranch,
  deleteManagedBranch,
};
