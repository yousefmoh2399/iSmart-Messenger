const asyncHandler = require("../utils/async-handler");
const { sendChatResponse } = require("../chat/utils/chat-response");
const { sendUploadFile } = require("../utils/send-upload-file");
const {
  createUser,
  listUsers,
  updateUser,
  patchUserStatus,
  resetUserPassword,
  logoutUserAll,
  deleteUser,
  getProfile,
  updateProfile,
  updateUserAvatar,
  getAvatarFilePath,
  registerCurrentPushDevice,
  unregisterCurrentPushDevice,
} = require("../services/user.service");

const getUsers = asyncHandler(async (req, res) => {
  const { users, pagination } = await listUsers(req.user, req.query);
  sendChatResponse(res, {
    data: { users, pagination },
    legacy: { users, pagination },
  });
});

const createManagedUser = asyncHandler(async (req, res) => {
  const user = await createUser(req.body, req.user);
  const io = req.app.get("io");
  if (io) {
    io.emit("users_updated", {});
    if (user.isActive === false) {
      io.to(`user:${user.id}`).emit("force_logout", {
        reason: "account_disabled",
      });
    }
  }
  sendChatResponse(res, { status: 201, data: { user }, legacy: { user } });
});

const updateManagedUser = asyncHandler(async (req, res) => {
  const user = await updateUser(req.user, req.params.id, req.body);
  const io = req.app.get("io");
  if (io) {
    io.emit("users_updated", {});
    io.emit("user_profile_updated", { user });
    if (req.body?.password) {
      io.to(`user:${req.params.id}`).emit("force_logout", {
        reason: "password_changed",
      });
    }
  }
  sendChatResponse(res, { data: { user }, legacy: { user } });
});

const updateManagedUserStatus = asyncHandler(async (req, res) => {
  const user = await patchUserStatus(
    req.user,
    req.params.id,
    req.body.isActive,
  );
  const io = req.app.get("io");
  if (io) {
    io.emit("users_updated", {});
    io.emit("user_profile_updated", { user });
    if (user.isActive === false) {
      io.to(`user:${req.params.id}`).emit("force_logout", {
        reason: "account_disabled",
      });
    }
  }
  sendChatResponse(res, { data: { user }, legacy: { user } });
});

const resetManagedUserPassword = asyncHandler(async (req, res) => {
  const user = await resetUserPassword(
    req.user,
    req.params.id,
    req.body.password,
  );
  const io = req.app.get("io");
  if (io) {
    io.emit("users_updated", {});
    io.emit("user_profile_updated", { user });
    io.to(`user:${req.params.id}`).emit("force_logout", {
      reason: "password_reset",
    });
  }
  sendChatResponse(res, { data: { user }, legacy: { user } });
});

const getMyProfile = asyncHandler(async (req, res) => {
  const user = await getProfile(req.user);
  sendChatResponse(res, { data: { user }, legacy: { user } });
});

const updateMyProfile = asyncHandler(async (req, res) => {
  const user = await updateProfile(req.user, req.body);
  const io = req.app.get("io");
  if (io) {
    io.emit("user_profile_updated", { user });
    if (req.body?.password) {
      io.to(`user:${req.user.id}`).emit("force_logout", {
        reason: "password_changed",
      });
    }
  }
  sendChatResponse(res, { data: { user }, legacy: { user } });
});

const uploadMyAvatar = asyncHandler(async (req, res) => {
  const user = await updateUserAvatar(req.user, req.file);
  const io = req.app.get("io");
  if (io) {
    io.emit("user_profile_updated", { user });
  }
  sendChatResponse(res, { data: { user }, legacy: { user } });
});

const registerMyPushDevice = asyncHandler(async (req, res) => {
  const device = await registerCurrentPushDevice(req.user, req.body);
  sendChatResponse(res, {
    data: { registered: Boolean(device), device },
    legacy: { registered: Boolean(device), device },
  });
});

const unregisterMyPushDevice = asyncHandler(async (req, res) => {
  const removed = await unregisterCurrentPushDevice(req.user, req.body);
  sendChatResponse(res, {
    data: { removed },
    legacy: { removed },
  });
});

const downloadAvatar = asyncHandler(async (req, res) => {
  const filePath = await getAvatarFilePath(req.params.id);
  await sendUploadFile(res, filePath, {
    cacheControl: "private, max-age=300",
    disposition: "inline",
    notFoundMessage: "Avatar not found.",
    logLabel: "avatar-download",
  });
});

const logoutUserAllHandler = asyncHandler(async (req, res) => {
  const result = await logoutUserAll(
    req.user,
    req.params.id,
    req.app.get("io"),
  );
  sendChatResponse(res, { data: result });
});

const deleteUserHandler = asyncHandler(async (req, res) => {
  const result = await deleteUser(req.user, req.params.id);
  const io = req.app.get("io");
  if (io) {
    io.emit("users_updated", {});
    io.to(`user:${req.params.id}`).emit("force_logout", {
      reason: "account_deleted",
    });
  }
  sendChatResponse(res, { status: 200, data: result });
});

module.exports = {
  getUsers,
  createManagedUser,
  updateManagedUser,
  updateManagedUserStatus,
  resetManagedUserPassword,
  logoutUserAllHandler,
  deleteUserHandler,
  getMyProfile,
  updateMyProfile,
  uploadMyAvatar,
  registerMyPushDevice,
  unregisterMyPushDevice,
  downloadAvatar,
};
