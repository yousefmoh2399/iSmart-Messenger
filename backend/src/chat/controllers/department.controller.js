const asyncHandler = require("../../utils/async-handler");
const { sendChatResponse } = require("../utils/chat-response");
const {
  listDepartments,
  createDepartment,
  updateDepartment,
  deleteDepartment,
} = require("../services/department.service");

const getDepartments = asyncHandler(async (req, res) => {
  const departments = await listDepartments();
  sendChatResponse(res, {
    data: { departments },
    legacy: { departments },
  });
});

const createManagedDepartment = asyncHandler(async (req, res) => {
  const department = await createDepartment(req.user, req.body);
  const io = req.app.get("io");
  if (io) {
    io.emit("departments_updated", {});
  }
  sendChatResponse(res, {
    status: 201,
    data: { department },
    legacy: { department },
  });
});

const updateManagedDepartment = asyncHandler(async (req, res) => {
  const department = await updateDepartment(req.user, req.params.id, req.body);
  const io = req.app.get("io");
  if (io) {
    io.emit("departments_updated", {});
  }
  sendChatResponse(res, {
    data: { department },
    legacy: { department },
  });
});

const deleteManagedDepartment = asyncHandler(async (req, res) => {
  await deleteDepartment(req.user, req.params.id);
  const io = req.app.get("io");
  if (io) {
    io.emit("departments_updated", {});
  }
  sendChatResponse(res, {
    data: { deleted: true },
    legacy: { deleted: true },
  });
});

module.exports = {
  getDepartments,
  createManagedDepartment,
  updateManagedDepartment,
  deleteManagedDepartment,
};
