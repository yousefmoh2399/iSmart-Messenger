const Department = require("../models/department.model");
const Conversation = require("../models/conversation.model");
const User = require("../../models/user.model");
const ApiError = require("../../utils/api-error");
const { userHasPermission } = require("./role.service");

function isDuplicateCodeError(error) {
  return (
    error &&
    error.code === 11000 &&
    (error.keyPattern?.code === 1 ||
      Object.prototype.hasOwnProperty.call(error.keyValue || {}, "code"))
  );
}

function serializeDepartment(department, membersCount = department.membersCount || 0) {
  return {
    id: department._id.toString(),
    name: department.name,
    code: department.code,
    description: department.description,
    createdBy:
      department.createdBy?.toString?.() || department.createdBy || null,
    managers: (department.managers || []).map((entry) => entry.toString()),
    membersCount,
    defaultConversationId: department.defaultConversationId
      ? department.defaultConversationId.toString()
      : null,
    createdAt: department.createdAt,
    updatedAt: department.updatedAt,
    deletedAt: department.deletedAt || null,
  };
}

async function listDepartments() {
  const departments = await Department.find({ deletedAt: null })
    .sort({ name: 1 })
    .lean();
  const counts = await Promise.all(
    departments.map((department) =>
      User.countDocuments({
        $or: [
          { departmentId: department._id },
          { departmentIds: department._id },
        ],
      }),
    ),
  );
  return departments.map((department, index) =>
    serializeDepartment(department, counts[index]),
  );
}

async function createDepartment(actor, payload) {
  const allowed = await userHasPermission(actor, "canCreateDepartments");
  if (!allowed) {
    throw new ApiError(403, "Permission denied.");
  }

  const code = String(payload.code || "")
    .trim()
    .toUpperCase();
  const name = String(payload.name || "").trim();

  if (!name || !code) {
    throw new ApiError(400, "Department name and code are required.");
  }

  const existing = await Department.findOne({ code, deletedAt: null }).lean();
  if (existing) {
    throw new ApiError(409, "Department code already exists.");
  }

  let department;
  try {
    department = await Department.create({
      name,
      code,
      description: String(payload.description || "").trim(),
      createdBy: actor.id,
      managers: payload.managers || [],
      membersCount: 0,
    });
  } catch (error) {
    if (isDuplicateCodeError(error)) {
      throw new ApiError(409, "Department code already exists.");
    }
    throw error;
  }

  return serializeDepartment(department);
}

async function updateDepartment(actor, departmentId, payload) {
  const allowed = await userHasPermission(actor, "canCreateDepartments");
  if (!allowed) {
    throw new ApiError(403, "Permission denied.");
  }

  const department = await Department.findOne({
    _id: departmentId,
    deletedAt: null,
  });
  if (!department) {
    throw new ApiError(404, "Department not found.");
  }

  if (payload.name != null) {
    department.name = String(payload.name).trim();
  }
  if (payload.code != null) {
    const nextCode = String(payload.code).trim().toUpperCase();
    if (nextCode !== department.code) {
      const exists = await Department.findOne({
        _id: { $ne: department._id },
        code: nextCode,
        deletedAt: null,
      }).lean();
      if (exists) {
        throw new ApiError(409, "Department code already exists.");
      }
      department.code = nextCode;
    }
  }
  if (payload.description != null) {
    department.description = String(payload.description).trim();
  }
  if (payload.managers != null) {
    department.managers = payload.managers;
  }

  try {
    await department.save();
  } catch (error) {
    if (isDuplicateCodeError(error)) {
      throw new ApiError(409, "Department code already exists.");
    }
    throw error;
  }

  return serializeDepartment(department);
}

async function deleteDepartment(actor, departmentId) {
  const allowed = await userHasPermission(actor, "canCreateDepartments");
  if (!allowed) {
    throw new ApiError(403, "Permission denied.");
  }

  const department = await Department.findOne({
    _id: departmentId,
    deletedAt: null,
  });
  if (!department) {
    throw new ApiError(404, "Department not found.");
  }

  // Cascade cleanup: nullify departmentId and pull from departmentIds for all assigned users
  await User.updateMany(
    { departmentId: department._id },
    { $set: { departmentId: null } },
  );
  await User.updateMany(
    { departmentIds: department._id },
    { $pull: { departmentIds: department._id } },
  );

  // Cascade delete support tickets and ticket updates associated with this department
  const Ticket = require("../../tickets/models/ticket.model");
  const TicketUpdate = require("../../tickets/models/ticket-update.model");
  const tickets = await Ticket.find({
    $or: [
      { targetDepartmentId: department._id },
      { branchDepartmentId: department._id },
    ],
  }).select("_id").lean();
  const ticketIds = tickets.map((t) => t._id);
  if (ticketIds.length > 0) {
    await TicketUpdate.deleteMany({ ticketId: { $in: ticketIds } });
    await Ticket.deleteMany({ _id: { $in: ticketIds } });
  }

  await Conversation.deleteMany({ departmentId: department._id });
  await Department.deleteOne({ _id: departmentId });
}

module.exports = {
  listDepartments,
  createDepartment,
  updateDepartment,
  deleteDepartment,
  serializeDepartment,
};
