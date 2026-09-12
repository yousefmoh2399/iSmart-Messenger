const Branch = require("../models/branch.model");
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

function serializeBranch(branch, membersCount = branch.membersCount || 0) {
  return {
    id: branch._id.toString(),
    name: branch.name,
    code: branch.code,
    description: branch.description,
    createdBy: branch.createdBy?.toString?.() || branch.createdBy || null,
    membersCount,
    createdAt: branch.createdAt,
    updatedAt: branch.updatedAt,
    deletedAt: branch.deletedAt || null,
  };
}

async function listBranches() {
  const branches = await Branch.find({ deletedAt: null })
    .sort({ name: 1 })
    .lean();
  const counts = await Promise.all(
    branches.map((branch) => User.countDocuments({ branchId: branch._id })),
  );
  return branches.map((branch, index) => serializeBranch(branch, counts[index]));
}

async function createBranch(actor, payload) {
  const allowed = await userHasPermission(actor, "canCreateDepartments");
  if (!allowed) {
    throw new ApiError(403, "Permission denied.");
  }

  const code = String(payload.code || "")
    .trim()
    .toUpperCase();
  const name = String(payload.name || "").trim();

  if (!name || !code) {
    throw new ApiError(400, "Branch name and code are required.");
  }

  const existing = await Branch.findOne({ code, deletedAt: null }).lean();
  if (existing) {
    throw new ApiError(409, "Branch code already exists.");
  }

  let branch;
  try {
    branch = await Branch.create({
      name,
      code,
      description: String(payload.description || "").trim(),
      createdBy: actor.id,
      membersCount: 0,
    });
  } catch (error) {
    if (isDuplicateCodeError(error)) {
      throw new ApiError(409, "Branch code already exists.");
    }
    throw error;
  }

  return serializeBranch(branch);
}

async function updateBranch(actor, branchId, payload) {
  const allowed = await userHasPermission(actor, "canCreateDepartments");
  if (!allowed) {
    throw new ApiError(403, "Permission denied.");
  }

  const branch = await Branch.findOne({ _id: branchId, deletedAt: null });
  if (!branch) {
    throw new ApiError(404, "Branch not found.");
  }

  if (payload.name != null) {
    branch.name = String(payload.name).trim();
  }
  if (payload.code != null) {
    const nextCode = String(payload.code).trim().toUpperCase();
    if (nextCode !== branch.code) {
      const exists = await Branch.findOne({
        _id: { $ne: branch._id },
        code: nextCode,
        deletedAt: null,
      }).lean();
      if (exists) {
        throw new ApiError(409, "Branch code already exists.");
      }
      branch.code = nextCode;
    }
  }
  if (payload.description != null) {
    branch.description = String(payload.description).trim();
  }

  try {
    await branch.save();
  } catch (error) {
    if (isDuplicateCodeError(error)) {
      throw new ApiError(409, "Branch code already exists.");
    }
    throw error;
  }
  return serializeBranch(branch);
}

async function deleteBranch(actor, branchId) {
  const allowed = await userHasPermission(actor, "canCreateDepartments");
  if (!allowed) {
    throw new ApiError(403, "Permission denied.");
  }

  const branch = await Branch.findOne({ _id: branchId, deletedAt: null });
  if (!branch) {
    throw new ApiError(404, "Branch not found.");
  }

  // Cascade cleanup: nullify branchId for all users assigned to this branch
  await User.updateMany({ branchId: branch._id }, { $set: { branchId: null } });

  await Branch.deleteOne({ _id: branchId });
}

module.exports = {
  listBranches,
  createBranch,
  updateBranch,
  deleteBranch,
  serializeBranch,
};
