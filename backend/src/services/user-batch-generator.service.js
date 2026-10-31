const bcrypt = require("bcryptjs");
const User = require("../models/user.model");
const Branch = require("../chat/models/branch.model");
const Department = require("../chat/models/department.model");
const ApiError = require("../utils/api-error");
const { logAuditEvent } = require("../chat/services/audit.service");

const DEFAULT_JOB_TEMPLATES = [
  {
    key: "man",
    title: "مدير فرع",
    prefix: "man",
    defaultCount: 1,
    allowUnnumberedFirst: true,
    departmentKeywords: [
      "branch managers",
      "branch manager",
      "managers",
      "man branches",
      "مدير فرع",
      "إدارة الفروع",
      "إدارة",
      "ادارة",
      "management",
      "mgmt",
    ],
  },
  {
    key: "vman",
    title: "نائب مدير فرع",
    prefix: "vman",
    defaultCount: 1,
    allowUnnumberedFirst: true,
    departmentKeywords: [
      "branch managers",
      "branch manager",
      "vman",
      "نائب مدير",
      "إدارة الفروع",
      "managers",
      "إدارة",
    ],
  },
  {
    key: "acc",
    title: "محاسب",
    prefix: "acc",
    defaultCount: 2,
    allowUnnumberedFirst: false,
    departmentKeywords: [
      "acc branches",
      "acc",
      "accounting",
      "accounts",
      "حسابات",
      "مالية",
      "finance",
    ],
  },
  {
    key: "cashier",
    title: "أمين خزنة",
    prefix: "cash",
    defaultCount: 0,
    allowUnnumberedFirst: false,
    departmentKeywords: [
      "cashier branches",
      "cashier",
      "cash",
      "خزينة",
      "خزنة",
      "صراف",
      "أمين خزنة",
      "امين خزنة",
    ],
  },
  {
    key: "acash",
    title: "مساعد أمين خزنة",
    prefix: "acash",
    defaultCount: 0,
    allowUnnumberedFirst: false,
    departmentKeywords: [
      "cashier branches",
      "cashier",
      "cash",
      "خزينة",
      "خزنة",
      "صراف",
      "مساعد أمين خزنة",
      "مساعد امين خزنة",
    ],
  },
  {
    key: "ghead",
    title: "رئيس مجموعة",
    prefix: "ghead",
    defaultCount: 4,
    allowUnnumberedFirst: false,
    departmentKeywords: [
      "ghead branches",
      "ghead",
      "group head",
      "مجموعات",
      "رئيس مجموعة",
      "رئيسة مجموعة",
      "تمويل",
      "ائتمان",
      "credit",
    ],
  },
  {
    key: "csup",
    title: "مشرف / مشرفة منسقات",
    prefix: "csup",
    defaultCount: 4,
    allowUnnumberedFirst: false,
    departmentKeywords: [
      "csup branches",
      "csup",
      "مشرف منسقات",
      "مشرفة منسقات",
      "coord sup",
      "منسق",
      "منسقات",
      "coord",
    ],
  },
  {
    key: "spec",
    title: "أخصائي",
    prefix: "spec",
    defaultCount: 7,
    allowUnnumberedFirst: false,
    departmentKeywords: [
      "spec branches",
      "spec",
      "specialist",
      "أخصائي",
      "اخصائي",
      "تمويل",
      "ائتمان",
      "credit",
    ],
  },
  {
    key: "coord",
    title: "منسقة",
    prefix: "coord",
    defaultCount: 8,
    allowUnnumberedFirst: false,
    departmentKeywords: [
      "coord branches",
      "coord",
      "coordinator",
      "منسقة",
      "منسق",
      "منسقات",
    ],
  },
  {
    key: "collect",
    title: "محصل",
    prefix: "collect",
    defaultCount: 1,
    allowUnnumberedFirst: false,
    departmentKeywords: [
      "collect branches",
      "collect",
      "collector",
      "تحصيل",
      "محصل",
      "collections",
    ],
  },
];

function getNextAvailableIndex(existingUsernames, prefix, branchCode) {
  const normalizedBranch = String(branchCode).trim().toLowerCase();
  const normalizedPrefix = String(prefix).trim().toLowerCase();

  const numberedRegex = new RegExp(`^${normalizedPrefix}(\\d+)-${normalizedBranch}$`, "i");
  const unnumberedRegex = new RegExp(`^${normalizedPrefix}-${normalizedBranch}$`, "i");

  let maxIndex = 0;
  for (const u of existingUsernames) {
    const un = String(u).trim().toLowerCase();
    const match = un.match(numberedRegex);
    if (match) {
      const idx = parseInt(match[1], 10);
      if (!isNaN(idx) && idx > maxIndex) {
        maxIndex = idx;
      }
    } else if (unnumberedRegex.test(un)) {
      if (maxIndex < 1) {
        maxIndex = 1;
      }
    }
  }

  return maxIndex + 1;
}

function generateUsernames(existingUsernames, prefix, branchCode, count, allowUnnumberedFirst = false) {
  const normalizedBranch = String(branchCode).trim().toLowerCase();
  const normalizedPrefix = String(prefix).trim().toLowerCase();
  const results = [];

  const existingSet = new Set(existingUsernames.map((u) => String(u).trim().toLowerCase()));
  const nextIdx = getNextAvailableIndex(existingUsernames, prefix, branchCode);

  // If allowUnnumberedFirst is true (e.g. for man, vman), count == 1, and prefix-branch does not exist yet:
  if (allowUnnumberedFirst && count === 1 && !existingSet.has(`${normalizedPrefix}-${normalizedBranch}`)) {
    results.push({
      username: `${normalizedPrefix}-${normalizedBranch}`,
      index: 1,
      isNumbered: false,
    });
    return results;
  }

  for (let i = 0; i < count; i++) {
    const currentIdx = nextIdx + i;
    results.push({
      username: `${normalizedPrefix}${currentIdx}-${normalizedBranch}`,
      index: currentIdx,
      isNumbered: true,
    });
  }

  return results;
}

function resolveDepartmentForTitle(allDepartments, titleConfig = {}) {
  if (titleConfig.departmentId) {
    const found = allDepartments.find((d) => d._id.toString() === String(titleConfig.departmentId));
    if (found) return found._id;
  }

  const branchDepts = allDepartments.filter((d) => {
    const n = (d.name || "").toLowerCase();
    const c = (d.code || "").toLowerCase();
    return n.includes("branch") || n.includes("فرع") || c.includes("branch");
  });

  const keywords = titleConfig.departmentKeywords || [];
  for (const kw of keywords) {
    const normalizedKw = String(kw).trim().toLowerCase();
    if (!normalizedKw) continue;

    // Check branch departments first
    const matchedBranch = branchDepts.find(
      (d) =>
        (d.name && d.name.toLowerCase().includes(normalizedKw)) ||
        (d.code && d.code.toLowerCase().includes(normalizedKw))
    );
    if (matchedBranch) return matchedBranch._id;

    // Check all departments
    const matched = allDepartments.find(
      (d) =>
        (d.name && d.name.toLowerCase().includes(normalizedKw)) ||
        (d.code && d.code.toLowerCase().includes(normalizedKw))
    );
    if (matched) {
      return matched._id;
    }
  }

  return null;
}

async function batchGenerateBranchUsers(actor, {
  branchId,
  defaultPassword = "123456",
  items = [],
} = {}) {
  if (!branchId) {
    throw new ApiError(400, "معرّف الفرع مطلوب.");
  }

  const branch = await Branch.findById(branchId);
  if (!branch) {
    throw new ApiError(404, "الفرع المحدد غير موجود.");
  }

  const branchCode = String(branch.code || "").trim();
  if (!branchCode) {
    throw new ApiError(400, "الفرع المحدد لا يحتوي على كود فرع صالح (كود الفرع مطلوب للتسمية).");
  }

  const passwordStr = String(defaultPassword || "123456").trim();
  if (passwordStr.length < 6) {
    throw new ApiError(400, "كلمة المرور الافتراضية يجب ألا تقل عن 6 أحرف.");
  }

  // Hash password once for all accounts in the batch
  const passwordHash = await bcrypt.hash(passwordStr, 10);

  // Fetch all active departments to resolve mappings
  const allDepartments = await Department.find({ deletedAt: null }).lean();

  // Fetch all existing usernames in the database to prevent duplicate keys across entire system
  const allExistingUsers = await User.find({}).select("username").lean();
  const existingUsernames = allExistingUsers.map((u) => u.username);

  // Normalize requested items
  const configsToProcess = [];
  for (const item of items) {
    const count = parseInt(item.count, 10);
    if (isNaN(count) || count <= 0) {
      continue;
    }

    const template = DEFAULT_JOB_TEMPLATES.find((t) => t.key === item.key);
    const title = String(item.title || template?.title || item.key).trim();
    const prefix = String(item.prefix || template?.prefix || item.key).trim().toLowerCase();
    const allowUnnumberedFirst =
      item.allowUnnumberedFirst != null
        ? Boolean(item.allowUnnumberedFirst)
        : template?.allowUnnumberedFirst ?? false;

    const departmentKeywords = item.departmentKeywords || template?.departmentKeywords || [prefix, title];

    let departmentId = null;
    if (item.departmentId !== undefined) {
      if (item.departmentId) {
        const found = allDepartments.find((d) => d._id.toString() === String(item.departmentId));
        departmentId = found ? found._id : null;
      } else {
        departmentId = null;
      }
    } else {
      departmentId = resolveDepartmentForTitle(allDepartments, {
        departmentKeywords,
      });
    }

    configsToProcess.push({
      key: item.key,
      title,
      prefix,
      count,
      allowUnnumberedFirst,
      departmentId,
    });
  }

  if (configsToProcess.length === 0) {
    throw new ApiError(400, "لم يتم تحديد أي مسمى وظيفي بعدد أكبر من صفر.");
  }

  const docsToInsert = [];
  const deptCountIncrements = {};

  for (const config of configsToProcess) {
    const generated = generateUsernames(
      existingUsernames,
      config.prefix,
      branchCode,
      config.count,
      config.allowUnnumberedFirst
    );

    for (const g of generated) {
      const username = g.username.toLowerCase();
      existingUsernames.push(username); // Keep tracking locally for this batch

      const fullName = g.isNumbered ? `${config.title} ${g.index}` : config.title;

      docsToInsert.push({
        username,
        passwordHash,
        fullName,
        jobTitle: config.title,
        role: "user", // Normal user permissions as requested
        permissionOverrides: {},
        branchId: branch._id,
        branchCode: branchCode.toUpperCase(),
        departmentId: config.departmentId || null,
        departmentIds: config.departmentId ? [config.departmentId] : [],
        isActive: true,
      });

      if (config.departmentId) {
        const deptKey = config.departmentId.toString();
        deptCountIncrements[deptKey] = (deptCountIncrements[deptKey] || 0) + 1;
      }
    }
  }

  // Insert generated users in MongoDB
  const createdUsers = await User.insertMany(docsToInsert);

  // Increment branch membersCount
  await Branch.findByIdAndUpdate(branch._id, {
    $inc: { membersCount: createdUsers.length },
  });

  // Increment department membersCount for each affected department
  const deptUpdatePromises = Object.entries(deptCountIncrements).map(([deptId, incCount]) =>
    Department.findByIdAndUpdate(deptId, {
      $inc: { membersCount: incCount },
    })
  );
  await Promise.all(deptUpdatePromises);

  // Audit log
  await logAuditEvent(
    actor,
    "user_batch_generated",
    "Branch",
    branch._id,
    {
      branchName: branch.name,
      branchCode,
      totalUsersCreated: createdUsers.length,
      rolesSummary: configsToProcess.map((c) => `${c.title}: ${c.count}`).join(", "),
    }
  );

  return {
    success: true,
    totalCreated: createdUsers.length,
    branch: {
      id: branch._id,
      name: branch.name,
      code: branchCode,
    },
    users: createdUsers.map((u) => ({
      id: u._id.toString(),
      username: u.username,
      fullName: u.fullName,
      jobTitle: u.jobTitle,
      role: u.role,
      branchId: u.branchId ? u.branchId.toString() : null,
      branchCode: u.branchCode,
      departmentId: u.departmentId ? u.departmentId.toString() : null,
      departmentIds: (u.departmentIds || []).map((d) => d.toString()),
      isActive: u.isActive,
      avatar: u.avatar || null,
      permissions: {},
      maxAttachmentSizeMB: 20,
      createdAt: u.createdAt ? u.createdAt.toISOString() : new Date().toISOString(),
      lastSeen: null,
    })),
  };
}

module.exports = {
  DEFAULT_JOB_TEMPLATES,
  getNextAvailableIndex,
  generateUsernames,
  resolveDepartmentForTitle,
  batchGenerateBranchUsers,
};
