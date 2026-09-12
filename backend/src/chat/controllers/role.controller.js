const asyncHandler = require("../../utils/async-handler");
const {
  listRoles,
  createRole,
  updateRolePermissions,
} = require("../services/role.service");
const { sendChatResponse } = require("../utils/chat-response");

const getAdminRoles = asyncHandler(async (req, res) => {
  const roles = await listRoles();
  sendChatResponse(res, {
    data: { roles },
    legacy: { roles },
  });
});

const createAdminRole = asyncHandler(async (req, res) => {
  const role = await createRole(req.user, req.body);
  sendChatResponse(res, {
    status: 201,
    data: { role },
    legacy: { role },
  });
});

const updateAdminRole = asyncHandler(async (req, res) => {
  const role = await updateRolePermissions(req.user, req.params.id, req.body.permissions);
  const io = req.app.get("io");
  if (io) {
    io.emit("users_updated", { reason: "permissions_updated" });
  }
  sendChatResponse(res, {
    data: { role },
    legacy: { role },
  });
});

module.exports = {
  getAdminRoles,
  createAdminRole,
  updateAdminRole,
};
