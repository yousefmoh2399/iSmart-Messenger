const Ticket = require("../models/ticket.model");
const TicketUpdate = require("../models/ticket-update.model");
const TicketSettings = require("../models/ticket-settings.model");
const TicketCounter = require("../models/ticket-counter.model");
const User = require("../../models/user.model");
const Department = require("../../chat/models/department.model");
const mongoose = require("mongoose");
const ApiError = require("../../utils/api-error");
const { escapeRegExp } = require("../../utils/regex.util");
const { logAuditEvent } = require("../../chat/services/audit.service");

const TICKET_STATUS = new Set([
  "open",
  "assigned",
  "in_progress",
  "waiting_branch",
  "resolved",
  "closed",
]);

const TICKET_PRIORITY = new Set(["low", "normal", "high", "critical"]);
const REPORT_TYPES = ["ticket", "complaint", "suggestion"];

function normalizeText(value, maxLength) {
  return String(value || "")
    .trim()
    .slice(0, maxLength);
}

function normalizeIdArray(value) {
  if (!Array.isArray(value)) {
    return [];
  }
  return Array.from(
    new Set(
      value
        .map((entry) => String(entry || "").trim())
        .filter((entry) => entry.length > 0),
    ),
  );
}

function toNullableString(value) {
  const normalized = String(value || "").trim();
  return normalized.length > 0 ? normalized : null;
}

async function getOrCreateSettings() {
  const existing = await TicketSettings.findOne({
    singletonKey: "default",
  }).lean();
  if (existing) {
    return existing;
  }
  const created = await TicketSettings.create({
    singletonKey: "default",
    supportAgentIds: [],
    reportExporters: [],
  });
  return created.toObject();
}

function normalizeTicketTypes(value) {
  if (!Array.isArray(value)) {
    return [];
  }
  return Array.from(
    new Set(
      value
        .map((entry) =>
          String(entry || "")
            .trim()
            .toLowerCase(),
        )
        .filter((entry) => REPORT_TYPES.includes(entry)),
    ),
  );
}

function toReportPermissionMap(settings) {
  const map = new Map();
  const exporters = Array.isArray(settings?.reportExporters)
    ? settings.reportExporters
    : [];
  for (const item of exporters) {
    const userId = item?.userId?.toString?.() || String(item?.userId || "");
    if (!userId) continue;
    map.set(userId, normalizeTicketTypes(item.ticketTypes));
  }
  return map;
}

function canExportType(currentUser, settings, ticketType) {
  if (currentUser.role === "admin") {
    return true;
  }
  const normalizedType = REPORT_TYPES.includes(ticketType)
    ? ticketType
    : "ticket";
  const map = toReportPermissionMap(settings);
  const allowed = map.get(String(currentUser.id)) || [];
  return allowed.includes(normalizedType);
}

async function getSupportAgentIdSet() {
  const settings = await getOrCreateSettings();
  return new Set(
    (settings.supportAgentIds || []).map(
      (entry) => entry?.toString?.() || String(entry),
    ),
  );
}

async function isSupportAgent(userId) {
  if (!userId) return false;
  const supportAgentIds = await getSupportAgentIdSet();
  return supportAgentIds.has(String(userId));
}

async function getItDepartmentIdSet() {
  const depts = await Department.find({
    deletedAt: null,
    $or: [
      { code: /^IT$/i },
      { code: /^IT[-_]/i },
      { name: /^IT$/i },
      { name: /IT SUPPORT/i },
      { name: /الدعم الفني/i },
    ],
  })
    .select("_id")
    .lean();
  return new Set(depts.map((entry) => entry._id.toString()));
}

async function isItTargetDepartment(departmentId) {
  const normalized = toNullableString(departmentId);
  if (!normalized) {
    return false;
  }
  const itDeptIds = await getItDepartmentIdSet();
  return itDeptIds.has(String(normalized));
}

const HANDLER_TYPE_FIELDS = {
  ticket: "ticketHandlers",
  complaint: "complaintHandlers",
  suggestion: "suggestionHandlers",
};

function normalizeHandlerType(value) {
  const normalized = String(value || "complaint")
    .trim()
    .toLowerCase();
  if (normalized === "ticket") {
    return "ticket";
  }
  if (normalized === "suggestion") {
    return "suggestion";
  }
  return "complaint";
}

function getHandlerFieldName(handlerType) {
  return HANDLER_TYPE_FIELDS[normalizeHandlerType(handlerType)];
}

async function getHandledDepartmentIds(userId, ticketType = null) {
  if (!userId) {
    return [];
  }

  const normalizedType = ticketType
    ? String(ticketType).trim().toLowerCase()
    : null;

  const userObjectId = toObjectIdIfValid(userId);
  const handlerMatch = userObjectId || userId;

  if (normalizedType === "ticket") {
    const departments = await Department.find({
      ticketHandlers: handlerMatch,
      deletedAt: null,
    })
      .select("_id")
      .lean();
    return departments.map((entry) => entry._id);
  }

  if (normalizedType === "complaint") {
    const departments = await Department.find({
      complaintHandlers: handlerMatch,
      deletedAt: null,
    })
      .select("_id")
      .lean();
    return departments.map((entry) => entry._id);
  }

  if (normalizedType === "suggestion") {
    const departments = await Department.find({
      suggestionHandlers: handlerMatch,
      deletedAt: null,
    })
      .select("_id")
      .lean();
    return departments.map((entry) => entry._id);
  }

  const departments = await Department.find({
    deletedAt: null,
    $or: [
      { ticketHandlers: handlerMatch },
      { complaintHandlers: handlerMatch },
      { suggestionHandlers: handlerMatch },
    ],
  })
    .select("_id")
    .lean();
  return departments.map((entry) => entry._id);
}

function resolveUserRefId(ref) {
  if (!ref) {
    return null;
  }
  return (
    ref._id?.toString?.() || ref.id?.toString?.() || ref.toString?.() || null
  );
}

function resolveDepartmentRefId(ref) {
  if (!ref) {
    return null;
  }
  return (
    ref._id?.toString?.() || ref.id?.toString?.() || ref.toString?.() || null
  );
}

function toObjectIdIfValid(value) {
  const normalized = toNullableString(value);
  if (!normalized || !mongoose.Types.ObjectId.isValid(normalized)) {
    return null;
  }
  return new mongoose.Types.ObjectId(normalized);
}

async function isUserHandlerForTicketTarget(userId, ticket) {
  const targetId = resolveDepartmentRefId(ticket.targetDepartmentId);
  if (!targetId || !userId) {
    return false;
  }
  const ticketType = ticket.ticketType || "ticket";
  const fieldName = getHandlerFieldName(ticketType);
  const userObjectId = toObjectIdIfValid(userId);
  const handlerMatch = userObjectId || userId;
  const count = await Department.countDocuments({
    _id: targetId,
    deletedAt: null,
    [fieldName]: handlerMatch,
  });
  return count > 0;
}

function buildRoutedTicketHandlerFilters(currentUser, handledDeptIds) {
  const accessFilters = [
    { createdBy: currentUser.id },
    { assignedTo: currentUser.id },
  ];
  if (handledDeptIds.length > 0) {
    accessFilters.push({ targetDepartmentId: { $in: handledDeptIds } });
  }
  return accessFilters;
}

function ticketMatchesHandledDepartments(ticket, handledDeptIds) {
  if (!handledDeptIds.length) {
    return false;
  }
  const targetId = resolveDepartmentRefId(ticket.targetDepartmentId);
  if (!targetId) {
    return false;
  }
  const handledIds = new Set(handledDeptIds.map((id) => id.toString()));
  return handledIds.has(targetId);
}

async function ticketTargetIsVisibleToSupportAgent(ticket) {
  const ticketType = ticket.ticketType || "ticket";
  if (ticketType !== "ticket") {
    return false;
  }
  const targetId = resolveDepartmentRefId(ticket.targetDepartmentId);
  if (!targetId) {
    return true; // Allow Support Agents to triage tickets without a department
  }
  return isItTargetDepartment(targetId);
}

async function isDepartmentTicketHandler(userId, ticketType = null) {
  const handledDeptIds = await getHandledDepartmentIds(userId, ticketType);
  return handledDeptIds.length > 0;
}

async function isGlobalTicketSupport(userId, role) {
  if (role === "admin") {
    return true;
  }
  return isSupportAgent(userId);
}

async function canManageTicket(currentUser, ticket) {
  if (currentUser.role === "admin") {
    return true;
  }
  const ticketType = ticket.ticketType || "ticket";

  if (ticketType === "ticket" && (await isSupportAgent(currentUser.id))) {
    const isVisible = await ticketTargetIsVisibleToSupportAgent(ticket);
    if (isVisible) {
      return true;
    }
  }

  const handledDeptIds = await getHandledDepartmentIds(
    currentUser.id,
    ticketType,
  );
  return ticketMatchesHandledDepartments(ticket, handledDeptIds);
}

async function ensureManageAccess(currentUser) {
  const support = await isSupportAgent(currentUser.id);
  if (currentUser.role === "admin" || support) {
    return { isSupport: support };
  }
  throw new ApiError(403, "Permission denied.");
}

function serializeUser(user) {
  if (!user) {
    return null;
  }
  return {
    id: user._id?.toString?.() || user.id?.toString?.() || null,
    username: user.username || "",
    fullName: user.fullName || "",
    role: user.role || "user",
    departmentId:
      user.departmentId?._id?.toString?.() ||
      user.departmentId?.toString?.() ||
      user.departmentId ||
      null,
    isOnline: user.isOnline === true,
    presenceStatus:
      user.presenceStatus || (user.isOnline ? "online" : "offline"),
    avatarUrl: user.avatarUrl || null,
    lastSeen: user.lastSeen || null,
    lastActiveAt: user.lastActiveAt || null,
  };
}

function serializeTicket(ticket) {
  return {
    id: ticket._id?.toString?.() || ticket.id?.toString?.() || "",
    ticketNumber: ticket.ticketNumber,
    title: ticket.title,
    ticketType: ticket.ticketType || "ticket",
    targetDepartmentId:
      ticket.targetDepartmentId?._id?.toString?.() ||
      ticket.targetDepartmentId?.toString?.() ||
      null,
    targetDepartmentName: ticket.targetDepartmentId?.name || null,
    description: ticket.description,
    status: ticket.status,
    priority: ticket.priority,
    createdBy: serializeUser(ticket.createdBy),
    assignedTo: serializeUser(ticket.assignedTo),
    branchDepartmentId:
      ticket.branchDepartmentId?._id?.toString?.() ||
      ticket.branchDepartmentId?.toString?.() ||
      null,
    branchDepartmentName: ticket.branchDepartmentId?.name || null,
    lastPublicMessage: ticket.lastPublicMessage || "",
    lastUpdateAt: ticket.lastUpdateAt || ticket.updatedAt || ticket.createdAt,
    resolvedAt: ticket.resolvedAt || null,
    closedAt: ticket.closedAt || null,
    dueDate: ticket.dueDate || null,
    isSlaBreached:
      ticket.dueDate && !ticket.resolvedAt && !ticket.closedAt
        ? new Date() > new Date(ticket.dueDate)
        : false,
    rating: ticket.rating || null,
    feedback: ticket.feedback || "",
    createdAt: ticket.createdAt,
    updatedAt: ticket.updatedAt,
  };
}

function serializeTicketUpdate(update) {
  return {
    id: update._id?.toString?.() || update.id?.toString?.() || "",
    ticketId: update.ticketId?.toString?.() || null,
    kind: update.kind,
    message: update.message || "",
    visibility: update.visibility || "public",
    createdBy: {
      id:
        update.createdBy?._id?.toString?.() ||
        update.createdBy?.toString?.() ||
        null,
      fullName: update.createdByName || "",
      role: update.createdByRole || "user",
    },
    fromStatus: toNullableString(update.fromStatus),
    toStatus: toNullableString(update.toStatus),
    fromAssigneeId: update.fromAssigneeId?.toString?.() || null,
    toAssigneeId: update.toAssigneeId?.toString?.() || null,
    toAssigneeName: toNullableString(update.toAssigneeName),
    metadata:
      update.metadata && typeof update.metadata === "object"
        ? update.metadata
        : null,
    createdAt: update.createdAt,
    updatedAt: update.updatedAt,
  };
}

async function generateTicketNumber(now = new Date()) {
  const yyyy = now.getUTCFullYear().toString();
  const mm = String(now.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(now.getUTCDate()).padStart(2, "0");
  const dateKey = `${yyyy}${mm}${dd}`;
  const counter = await TicketCounter.findOneAndUpdate(
    { dateKey },
    { $inc: { seq: 1 } },
    { upsert: true, new: true, setDefaultsOnInsert: true },
  );
  const seq = Number(counter?.seq || 1);
  const padded = String(seq).padStart(4, "0");
  return `TKT-${dateKey}-${padded}`;
}

async function loadTicketForAccess(ticketId) {
  const ticket = await Ticket.findOne({
    _id: ticketId,
    deletedAt: null,
  })
    .populate(
      "createdBy",
      "username fullName role departmentId isOnline presenceStatus avatarUrl lastSeen lastActiveAt",
    )
    .populate(
      "assignedTo",
      "username fullName role departmentId isOnline presenceStatus avatarUrl lastSeen lastActiveAt",
    )
    .populate("branchDepartmentId", "name code")
    .populate("targetDepartmentId", "name code")
    .exec();

  if (!ticket) {
    throw new ApiError(404, "Ticket not found.");
  }
  return ticket;
}

async function canAccessTicket(currentUser, ticket) {
  if (currentUser.role === "admin") {
    return true;
  }

  const userId = String(currentUser.id);
  if (resolveUserRefId(ticket.createdBy) === userId) {
    return true;
  }

  if (resolveUserRefId(ticket.assignedTo) === userId) {
    return true;
  }

  const ticketType = ticket.ticketType || "ticket";

  if (ticketType === "ticket" && (await isSupportAgent(userId))) {
    if (await ticketTargetIsVisibleToSupportAgent(ticket)) {
      return true;
    }
  }

  if (await isUserHandlerForTicketTarget(userId, ticket)) {
    return true;
  }

  const handledDeptIds = await getHandledDepartmentIds(userId, ticketType);
  return ticketMatchesHandledDepartments(ticket, handledDeptIds);
}

async function assertTicketAccess(currentUser, ticket) {
  const allowed = await canAccessTicket(currentUser, ticket);
  if (!allowed) {
    throw new ApiError(403, "Permission denied.");
  }
}

async function listSupportUsers() {
  const settings = await getOrCreateSettings();
  const selectedIds = new Set(
    (settings.supportAgentIds || []).map(
      (entry) => entry?.toString?.() || String(entry),
    ),
  );
  const reportPermissions = toReportPermissionMap(settings);

  // Fetch all active users to display in settings dialog
  const users = await User.find(
    { isActive: true },
    "_id username fullName role departmentId isOnline presenceStatus avatarUrl lastSeen lastActiveAt",
  )
    .sort({ fullName: 1, username: 1 })
    .lean();

  return {
    supportAgentIds: [...selectedIds],
    users: users.map((user) => {
      const userIdStr = user._id?.toString() || user.id?.toString() || "";
      return {
        ...serializeUser(user),
        isSupportAgent: selectedIds.has(userIdStr),
        exportTicketTypes: reportPermissions.get(userIdStr) || [],
      };
    }),
  };
}

async function buildNotifyUserIds(ticket, { includeCreator = true } = {}) {
  const ids = new Set([
    includeCreator
      ? ticket.createdBy?._id?.toString?.() ||
        ticket.createdBy?.toString?.() ||
        null
      : null,
    ticket.assignedTo?._id?.toString?.() ||
      ticket.assignedTo?.toString?.() ||
      null,
  ]);

  const ticketType = ticket.ticketType || "ticket";
  if (
    ticketType === "ticket" &&
    (await ticketTargetIsVisibleToSupportAgent(ticket))
  ) {
    const supportAgentIds = await getSupportAgentIdSet();
    for (const agentId of supportAgentIds) {
      ids.add(agentId);
    }
  }

  const targetDepartmentId =
    ticket.targetDepartmentId?._id?.toString?.() ||
    ticket.targetDepartmentId?.toString?.() ||
    null;
  if (targetDepartmentId) {
    const handlerField = getHandlerFieldName(ticketType);
    const targetDepartment = await Department.findById(targetDepartmentId)
      .select(handlerField)
      .lean();
    for (const handlerId of targetDepartment?.[handlerField] || []) {
      ids.add(handlerId.toString());
    }
  }

  ids.delete(null);
  return [...ids];
}

async function listTickets(currentUser, filters = {}) {
  const andClauses = [{ deletedAt: null }];
  const scope = String(filters.scope || "")
    .trim()
    .toLowerCase();
  const status = toNullableString(filters.status);
  const priority = toNullableString(filters.priority);
  const q = toNullableString(filters.q);
  const limit = Math.max(1, Math.min(Number(filters.limit || 80), 200));

  const ticketType = toNullableString(filters.ticketType);
  if (ticketType === "ticket") {
    andClauses.push({
      $or: [
        { ticketType: "ticket" },
        { ticketType: { $exists: false } },
        { ticketType: null },
      ],
    });
  } else if (ticketType === "complaint" || ticketType === "suggestion") {
    andClauses.push({ ticketType: ticketType });
  }

  const isAdmin = currentUser.role === "admin";
  const isSupport = await isSupportAgent(currentUser.id);
  const itDeptIds = isAdmin ? [] : [...(await getItDepartmentIdSet())];
  const itDeptObjectIds = itDeptIds.map(
    (id) => new mongoose.Types.ObjectId(id),
  );
  const ticketDeptIds = isAdmin
    ? []
    : await getHandledDepartmentIds(currentUser.id, "ticket");
  const complaintDeptIds = isAdmin
    ? []
    : await getHandledDepartmentIds(currentUser.id, "complaint");
  const suggestionDeptIds = isAdmin
    ? []
    : await getHandledDepartmentIds(currentUser.id, "suggestion");
  const isTicketHandler = ticketDeptIds.length > 0;
  const isComplaintHandler = complaintDeptIds.length > 0;
  const isSuggestionHandler = suggestionDeptIds.length > 0;
  const isDeptHandlerOnly =
    isTicketHandler || isComplaintHandler || isSuggestionHandler;
  const canManageTickets = isAdmin || isSupport || isDeptHandlerOnly;

  if (!isAdmin) {
    const personalAccess = [
      { createdBy: currentUser.id },
      { assignedTo: currentUser.id },
    ];

    if (ticketType === "complaint") {
      andClauses.push({
        $or: buildRoutedTicketHandlerFilters(currentUser, complaintDeptIds),
      });
    } else if (ticketType === "suggestion") {
      andClauses.push({
        $or: buildRoutedTicketHandlerFilters(currentUser, suggestionDeptIds),
      });
    } else if (ticketType === "ticket") {
      const visibility = [...personalAccess];
      if (isTicketHandler) {
        visibility.push({ targetDepartmentId: { $in: ticketDeptIds } });
      }
      if (isSupport && itDeptObjectIds.length > 0) {
        visibility.push({ targetDepartmentId: { $in: itDeptObjectIds } });
      }
      andClauses.push({ $or: visibility });
    } else {
      const mixedVisibility = [...personalAccess];

      if (isTicketHandler) {
        mixedVisibility.push({
          $and: [
            {
              $or: [
                { ticketType: "ticket" },
                { ticketType: { $exists: false } },
                { ticketType: null },
              ],
            },
            { targetDepartmentId: { $in: ticketDeptIds } },
          ],
        });
      }
      if (isComplaintHandler) {
        mixedVisibility.push({
          ticketType: "complaint",
          $or: buildRoutedTicketHandlerFilters(currentUser, complaintDeptIds),
        });
      }
      if (isSuggestionHandler) {
        mixedVisibility.push({
          ticketType: "suggestion",
          $or: buildRoutedTicketHandlerFilters(currentUser, suggestionDeptIds),
        });
      }
      if (isSupport && itDeptObjectIds.length > 0) {
        mixedVisibility.push({
          $and: [
            {
              $or: [
                { ticketType: "ticket" },
                { ticketType: { $exists: false } },
                { ticketType: null },
              ],
            },
            { targetDepartmentId: { $in: itDeptObjectIds } },
          ],
        });
      }

      andClauses.push({ $or: mixedVisibility });
    }
  } else if (ticketType === "ticket" && isSupport) {
    if (scope === "mine") {
      andClauses.push({ createdBy: currentUser.id });
    } else if (scope === "assigned") {
      andClauses.push({ assignedTo: currentUser.id });
    } else if (scope === "unassigned") {
      andClauses.push({ assignedTo: null });
    } else if (scope === "department") {
      if (!currentUser.departmentId) {
        andClauses.push({ _id: null });
      } else {
        andClauses.push({ branchDepartmentId: currentUser.departmentId });
      }
    }
  }

  if (status && TICKET_STATUS.has(status)) {
    andClauses.push({ status: status });
  }
  if (priority && TICKET_PRIORITY.has(priority)) {
    andClauses.push({ priority: priority });
  }
  if (q) {
    const qRegex = escapeRegExp(q);
    andClauses.push({
      $or: [
        { ticketNumber: { $regex: qRegex, $options: "i" } },
        { title: { $regex: qRegex, $options: "i" } },
        { description: { $regex: qRegex, $options: "i" } },
        { lastPublicMessage: { $regex: qRegex, $options: "i" } },
      ],
    });
  }

  const query = { $and: andClauses };

  const tickets = await Ticket.find(query)
    .populate(
      "createdBy",
      "username fullName role departmentId isOnline presenceStatus avatarUrl lastSeen lastActiveAt",
    )
    .populate(
      "assignedTo",
      "username fullName role departmentId isOnline presenceStatus avatarUrl lastSeen lastActiveAt",
    )
    .populate("branchDepartmentId", "name code")
    .populate("targetDepartmentId", "name code")
    .sort({ updatedAt: -1, createdAt: -1 })
    .limit(limit)
    .lean();

  return {
    tickets: tickets.map(serializeTicket),
    meta: {
      canManage: canManageTickets,
      isSupportAgent: isSupport,
      limit,
    },
  };
}

function csvCell(value) {
  const text = String(value ?? "")
    .replace(/\r?\n/g, " ")
    .trim();
  return `"${text.replace(/"/g, '""')}"`;
}

function minutesBetween(start, end) {
  if (!start || !end) return "";
  const diff = new Date(end).getTime() - new Date(start).getTime();
  if (!Number.isFinite(diff) || diff < 0) return "";
  return Math.round(diff / 60000);
}

const STATUS_AR = {
  open: "مفتوحة",
  assigned: "تم الإسناد",
  in_progress: "قيد المعالجة",
  waiting_branch: "في انتظار الفرع",
  resolved: "تم الحل",
  closed: "مغلقة",
};

const PRIORITY_AR = {
  low: "منخفضة",
  normal: "عادية",
  high: "عالية",
  critical: "حرجة",
};

async function exportTicketReport(currentUser, filters = {}, format = "csv") {
  const settings = await getOrCreateSettings();
  const ticketType = normalizeTicketTypes([filters.ticketType])[0] || "ticket";
  if (!canExportType(currentUser, settings, ticketType)) {
    throw new ApiError(403, "Permission denied.");
  }

  const andClauses = [{ deletedAt: null }];
  const status = toNullableString(filters.status);
  const priority = toNullableString(filters.priority);
  const q = toNullableString(filters.q);

  if (ticketType === "ticket") {
    andClauses.push({
      $or: [
        { ticketType: "ticket" },
        { ticketType: { $exists: false } },
        { ticketType: null },
      ],
    });
  } else {
    andClauses.push({ ticketType });
  }

  if (currentUser.role !== "admin") {
    const personalAccess = [
      { createdBy: currentUser.id },
      { assignedTo: currentUser.id },
    ];
    const isSupport = await isSupportAgent(currentUser.id);
    const itDeptIds = [...(await getItDepartmentIdSet())];
    const itDeptObjectIds = itDeptIds.map(
      (id) => new mongoose.Types.ObjectId(id),
    );
    const handledDeptIds = await getHandledDepartmentIds(
      currentUser.id,
      ticketType,
    );
    const visibility = buildRoutedTicketHandlerFilters(
      currentUser,
      handledDeptIds,
    );

    if (ticketType === "ticket") {
      if (isSupport && itDeptObjectIds.length > 0) {
        visibility.push({ targetDepartmentId: { $in: itDeptObjectIds } });
      }
    }

    andClauses.push({ $or: visibility.length ? visibility : personalAccess });
  }

  if (status && TICKET_STATUS.has(status)) {
    andClauses.push({ status: status });
  }
  if (priority && TICKET_PRIORITY.has(priority)) {
    andClauses.push({ priority: priority });
  }
  if (q) {
    const qRegex = escapeRegExp(q);
    andClauses.push({
      $or: [
        { ticketNumber: { $regex: qRegex, $options: "i" } },
        { title: { $regex: qRegex, $options: "i" } },
        { description: { $regex: qRegex, $options: "i" } },
      ],
    });
  }
  const query = { $and: andClauses };

  // Fetch ALL matching tickets for the export report
  const tickets = await Ticket.find(query)
    .populate("createdBy", "username fullName")
    .populate("assignedTo", "username fullName")
    .populate("branchDepartmentId", "name code")
    .populate("targetDepartmentId", "name code")
    .sort({ createdAt: -1 })
    .lean();

  const ids = tickets.map((ticket) => ticket._id);

  // Calculate updates count per ticket
  const updateCounts = ids.length
    ? await TicketUpdate.aggregate([
        { $match: { ticketId: { $in: ids } } },
        { $group: { _id: "$ticketId", count: { $sum: 1 } } },
      ])
    : [];
  const countsByTicket = new Map(
    updateCounts.map((entry) => [entry._id.toString(), entry.count]),
  );

  // Find who resolved the ticket
  const resolvedUpdates = ids.length
    ? await TicketUpdate.find({
        ticketId: { $in: ids },
        kind: "status",
        toStatus: "resolved",
      })
        .select("ticketId createdByName")
        .lean()
    : [];
  const resolvedByMap = new Map(
    resolvedUpdates.map((u) => [u.ticketId.toString(), u.createdByName]),
  );

  const rows = [
    [
      "رقم التذكرة",
      "العنوان",
      "الحالة",
      "الأولوية",
      "بواسطة",
      "المسؤول عنها",
      "من قام بالحل",
      "القسم",
      "تاريخ الإنشاء",
      "تاريخ الاستحقاق (SLA)",
      "آخر تحديث",
      "تاريخ الحل",
      "تاريخ الإغلاق",
      "مدة الحل بالدقائق",
      "عدد التحديثات",
      "التقييم",
      "آخر رسالة",
    ],
    ...tickets.map((ticket) => {
      const isResolved =
        ticket.status === "resolved" || ticket.status === "closed";
      const resolvedBy = isResolved
        ? resolvedByMap.get(ticket._id.toString()) ||
          ticket.assignedTo?.fullName ||
          ticket.assignedTo?.username ||
          ""
        : "";

      return [
        ticket.ticketNumber || "",
        ticket.title || "",
        STATUS_AR[ticket.status] || ticket.status,
        PRIORITY_AR[ticket.priority] || ticket.priority,
        ticket.createdBy?.fullName || ticket.createdBy?.username || "",
        ticket.assignedTo?.fullName ||
          ticket.assignedTo?.username ||
          "غير مسند",
        resolvedBy,
        ticket.branchDepartmentId?.name || "",
        ticket.createdAt ? new Date(ticket.createdAt).toISOString() : "",
        ticket.dueDate ? new Date(ticket.dueDate).toISOString() : "",
        ticket.lastUpdateAt ? new Date(ticket.lastUpdateAt).toISOString() : "",
        ticket.resolvedAt ? new Date(ticket.resolvedAt).toISOString() : "",
        ticket.closedAt ? new Date(ticket.closedAt).toISOString() : "",
        minutesBetween(ticket.createdAt, ticket.resolvedAt || ticket.closedAt),
        countsByTicket.get(ticket._id.toString()) || 0,
        ticket.rating ? `${ticket.rating} نجوم` : "لم يقيم",
        ticket.lastPublicMessage || "",
      ];
    }),
  ];

  if (format === "pdf" || format === "xlsx") {
    const {
      buildCustomPdfReport,
      buildCustomExcelReport,
      formatDate,
    } = require("./ticket-custom-reports.service");

    const reportData = tickets.map((ticket) => {
      const isResolved =
        ticket.status === "resolved" || ticket.status === "closed";
      const resolvedBy = isResolved
        ? resolvedByMap.get(ticket._id.toString()) ||
          ticket.assignedTo?.fullName ||
          ticket.assignedTo?.username ||
          ""
        : "";

      return {
        ticketNumber: ticket.ticketNumber || "",
        title: ticket.title || "",
        status: STATUS_AR[ticket.status] || ticket.status,
        priority: PRIORITY_AR[ticket.priority] || ticket.priority,
        department: ticket.branchDepartmentId?.name || "",
        createdBy:
          ticket.createdBy?.fullName || ticket.createdBy?.username || "",
        assignedTo:
          ticket.assignedTo?.fullName ||
          ticket.assignedTo?.username ||
          "غير مسند",
        resolvedBy: resolvedBy,
        createdAt: formatDate(ticket.createdAt),
        dueDate: formatDate(ticket.dueDate),
        lastUpdateAt: formatDate(ticket.lastUpdateAt),
        resolvedAt: formatDate(ticket.resolvedAt),
        closedAt: formatDate(ticket.closedAt),
        minutesBetween: minutesBetween(
          ticket.createdAt,
          ticket.resolvedAt || ticket.closedAt,
        ),
        updatesCount: countsByTicket.get(ticket._id.toString()) || 0,
        rating: ticket.rating ? `${ticket.rating} نجوم` : "لم يقيم",
        lastPublicMessage: ticket.lastPublicMessage || "",
      };
    });

    const reportTitle = `تقرير ${ticketType === "complaint" ? "الشكاوي" : ticketType === "suggestion" ? "المقترحات" : "التذاكر"}`;

    if (format === "pdf") {
      return await buildCustomPdfReport(
        reportData,
        "tickets-report",
        reportTitle,
      );
    } else {
      return await buildCustomExcelReport(
        reportData,
        "tickets-report",
        reportTitle,
      );
    }
  }

  return `\uFEFF${rows.map((row) => row.map(csvCell).join(",")).join("\r\n")}\r\n`;
}

function ticketTypeLabel(ticketType) {
  if (ticketType === "complaint") return "شكوى";
  if (ticketType === "suggestion") return "مقترح";
  return "تذكرة";
}

function statusLabel(status) {
  return (
    {
      open: "مفتوحة",
      assigned: "مسندة",
      in_progress: "قيد التنفيذ",
      waiting_branch: "بانتظار رد مقدم الطلب",
      resolved: "تم الحل",
      closed: "مغلقة",
    }[status] ||
    status ||
    ""
  );
}

function ticketNotificationTitle(action, ticket) {
  const typeLabel = ticketTypeLabel(ticket?.ticketType || "ticket");
  if (action === "created") return `${typeLabel} جديدة`;
  if (action === "comment_added") return `رد جديد على ${typeLabel}`;
  if (action === "status_updated") return `تغيير حالة ${typeLabel}`;
  if (action === "assignee_updated") return `تحديث إسناد ${typeLabel}`;
  return `تحديث ${typeLabel}`;
}

function ticketPushBody(action, ticket, update = null) {
  const number = ticket?.ticketNumber || "Ticket";
  if (action === "created")
    return `${number}: ${ticket?.title || "تذكرة جديدة"}`;
  if (action === "comment_added") {
    const author = update?.createdBy?.fullName || "عضو";
    return `${number}: ${author} أضاف رد جديد`;
  }
  if (action === "status_updated")
    return `${number}: تغيرت الحالة إلى ${statusLabel(ticket?.status)}`;
  if (action === "assignee_updated") {
    const assignee =
      ticket?.assignedTo?.fullName || ticket?.assignedTo?.username;
    return assignee
      ? `${number}: تم الإسناد إلى ${assignee}`
      : `${number}: تم إلغاء الإسناد`;
  }
  return `${number}: يوجد تحديث جديد`;
}

async function getTicketDetails(currentUser, ticketId) {
  const ticket = await loadTicketForAccess(ticketId);
  await assertTicketAccess(currentUser, ticket);

  const support = await isSupportAgent(currentUser.id);
  const canManage = await canManageTicket(currentUser, ticket);

  const updates = await TicketUpdate.find({ ticketId: ticket._id })
    .sort({ createdAt: 1 })
    .lean();

  const visibleUpdates = canManage
    ? updates
    : updates.filter((entry) => entry.visibility !== "internal");

  return {
    ticket: serializeTicket(ticket),
    updates: visibleUpdates.map(serializeTicketUpdate),
    meta: {
      canManage,
      isSupportAgent: support,
    },
  };
}

async function createTicket(currentUser, payload) {
  const title = normalizeText(payload.title, 220);
  const description = normalizeText(payload.description, 6000);
  const priority = toNullableString(payload.priority) || "normal";
  const ticketType = ["complaint", "suggestion"].includes(payload.ticketType)
    ? payload.ticketType
    : "ticket";
  const targetDepartmentId =
    toNullableString(payload.targetDepartmentId) || null;

  if (title.length < 4) {
    throw new ApiError(400, "Ticket title must be at least 4 characters.");
  }
  if (description.length < 4) {
    throw new ApiError(
      400,
      "Ticket description must be at least 4 characters.",
    );
  }
  if (!TICKET_PRIORITY.has(priority)) {
    throw new ApiError(400, "Invalid ticket priority.");
  }
  if (!targetDepartmentId) {
    throw new ApiError(400, "يجب اختيار القسم الموجه إليه الطلب.");
  }

  // Calculate SLA Due Date
  const now = new Date();
  const dueDate = new Date();
  if (priority === "critical") {
    dueDate.setHours(now.getHours() + 2);
  } else if (priority === "high") {
    dueDate.setHours(now.getHours() + 8);
  } else if (priority === "normal") {
    dueDate.setHours(now.getHours() + 24);
  } else {
    dueDate.setHours(now.getHours() + 48);
  }

  let autoAssigneeId = null;
  let status = "open";
  if (
    ticketType === "ticket" &&
    targetDepartmentId &&
    (await isItTargetDepartment(targetDepartmentId))
  ) {
    try {
      const supportAgentIds = await getSupportAgentIdSet();
      const eligibleSupportAgents = await User.find({
        _id: {
          $in: [...supportAgentIds]
            .filter((id) => id.length > 0)
            .map((id) => new mongoose.Types.ObjectId(id)),
        },
        isActive: true,
      })
        .select("_id")
        .lean();

      if (eligibleSupportAgents.length > 0) {
        const activeTicketCounts = await Ticket.aggregate([
          {
            $match: {
              ticketType: "ticket",
              status: {
                $in: ["open", "assigned", "in_progress", "waiting_branch"],
              },
              assignedTo: { $in: eligibleSupportAgents.map((a) => a._id) },
              deletedAt: null,
            },
          },
          {
            $group: {
              _id: "$assignedTo",
              count: { $sum: 1 },
            },
          },
        ]);

        const countsMap = new Map(
          activeTicketCounts.map((c) => [c._id.toString(), c.count]),
        );
        let bestAgent = eligibleSupportAgents[0];
        let minTickets = countsMap.get(bestAgent._id.toString()) || 0;

        for (const agent of eligibleSupportAgents) {
          const count = countsMap.get(agent._id.toString()) || 0;
          if (count < minTickets) {
            minTickets = count;
            bestAgent = agent;
          }
        }
        autoAssigneeId = bestAgent._id;
        status = "assigned";
      }
    } catch (err) {
      console.error("Failed IT support auto-assignment:", err);
    }
  }

  const ticketNumber = await generateTicketNumber();
  const ticket = await Ticket.create({
    ticketNumber,
    ticketType,
    targetDepartmentId,
    title,
    description,
    priority,
    status,
    createdBy: currentUser.id,
    branchDepartmentId: currentUser.departmentId || null,
    assignedTo: autoAssigneeId,
    dueDate,
    lastUpdateAt: new Date(),
    lastPublicMessage: description.slice(0, 600),
  });

  const createdUpdate = await TicketUpdate.create({
    ticketId: ticket._id,
    kind: "created",
    message: description,
    visibility: "public",
    createdBy: currentUser.id,
    createdByName: currentUser.fullName || currentUser.username,
    createdByRole: currentUser.role || "user",
    metadata: {
      ticketNumber,
      title,
    },
  });

  // If auto-assigned, create an assignment timeline event
  if (autoAssigneeId) {
    const assignedUser = await User.findById(autoAssigneeId).lean();
    if (assignedUser) {
      await TicketUpdate.create({
        ticketId: ticket._id,
        kind: "assignment",
        message: `تم إسناد التذكرة تلقائياً إلى ${assignedUser.fullName || assignedUser.username} (توزيع تلقائي ذكي لضغط العمل).`,
        visibility: "public",
        createdBy: currentUser.id,
        createdByName: "النظام الذكي",
        createdByRole: "admin",
        toAssigneeId: autoAssigneeId,
        toAssigneeName: assignedUser.fullName || assignedUser.username,
        toStatus: "assigned",
      });
    }
  }

  await logAuditEvent({
    actorId: currentUser.id,
    action: "ticket.created",
    entityType: "Ticket",
    entityId: ticket._id,
    payload: {
      ticketNumber,
      priority,
      branchDepartmentId: currentUser.departmentId || null,
      assignedTo: autoAssigneeId || null,
    },
  });

  const hydrated = await loadTicketForAccess(ticket._id);
  const notifyUserIds = await buildNotifyUserIds(hydrated);

  return {
    ticket: serializeTicket(hydrated),
    update: serializeTicketUpdate(createdUpdate.toObject()),
    notifyUserIds,
  };
}

async function addTicketComment(currentUser, ticketId, payload) {
  const ticket = await loadTicketForAccess(ticketId);
  await assertTicketAccess(currentUser, ticket);

  const support = await isSupportAgent(currentUser.id);
  const canManage = await canManageTicket(currentUser, ticket);
  const visibility = payload.visibility === "internal" ? "internal" : "public";
  const message = normalizeText(payload.message, 6000);

  if (message.length < 1) {
    throw new ApiError(400, "Comment message is required.");
  }
  if (visibility === "internal" && !canManage) {
    throw new ApiError(403, "Only IT/Admin can add internal notes.");
  }

  if (ticket.status === "closed" && !canManage) {
    throw new ApiError(
      400,
      "This ticket is closed and cannot receive new branch replies.",
    );
  }

  const previousStatus = ticket.status;
  if (canManage) {
    if (ticket.status === "open" || ticket.status === "assigned") {
      ticket.status = "in_progress";
    }
  } else if (
    ticket.status === "waiting_branch" ||
    ticket.status === "resolved"
  ) {
    ticket.status = "in_progress";
    ticket.resolvedAt = null;
  }

  ticket.lastUpdateAt = new Date();
  if (visibility === "public") {
    ticket.lastPublicMessage = message.slice(0, 600);
  }
  await ticket.save();

  const comment = await TicketUpdate.create({
    ticketId: ticket._id,
    kind: canManage && visibility === "internal" ? "note" : "comment",
    message,
    visibility,
    createdBy: currentUser.id,
    createdByName: currentUser.fullName || currentUser.username,
    createdByRole: currentUser.role || "user",
  });

  let statusUpdate = null;
  if (previousStatus !== ticket.status) {
    statusUpdate = await TicketUpdate.create({
      ticketId: ticket._id,
      kind: "status",
      message: "Ticket status updated automatically after new reply.",
      visibility: "internal",
      createdBy: currentUser.id,
      createdByName: currentUser.fullName || currentUser.username,
      createdByRole: currentUser.role || "user",
      fromStatus: previousStatus,
      toStatus: ticket.status,
    });
  }

  await logAuditEvent({
    actorId: currentUser.id,
    action: "ticket.comment.added",
    entityType: "Ticket",
    entityId: ticket._id,
    payload: {
      visibility,
      kind: canManage && visibility === "internal" ? "note" : "comment",
    },
  });

  const hydrated = await loadTicketForAccess(ticket._id);
  const notifyUserIds = await buildNotifyUserIds(hydrated, {
    includeCreator: visibility !== "internal",
  });
  return {
    ticket: serializeTicket(hydrated),
    update: serializeTicketUpdate(comment.toObject()),
    statusUpdate: statusUpdate
      ? serializeTicketUpdate(statusUpdate.toObject())
      : null,
    notifyUserIds,
  };
}

async function updateTicketStatus(currentUser, ticketId, statusValue) {
  const ticket = await loadTicketForAccess(ticketId);
  const allowed = await canManageTicket(currentUser, ticket);
  if (!allowed) {
    throw new ApiError(403, "Permission denied.");
  }
  const nextStatus = String(statusValue || "").trim();
  if (!TICKET_STATUS.has(nextStatus)) {
    throw new ApiError(400, "Invalid ticket status.");
  }

  const previousStatus = ticket.status;
  if (previousStatus === nextStatus) {
    return {
      ticket: serializeTicket(ticket),
      update: null,
      notifyUserIds: await buildNotifyUserIds(ticket),
    };
  }

  ticket.status = nextStatus;
  ticket.lastUpdateAt = new Date();

  if (nextStatus === "resolved") {
    ticket.resolvedAt = new Date();
    ticket.closedAt = null;
  } else if (nextStatus === "closed") {
    ticket.closedAt = new Date();
  } else {
    ticket.closedAt = null;
    if (nextStatus !== "resolved") {
      ticket.resolvedAt = null;
    }
  }
  await ticket.save();

  const update = await TicketUpdate.create({
    ticketId: ticket._id,
    kind: "status",
    message: `Status changed from ${previousStatus} to ${nextStatus}.`,
    visibility: "public",
    createdBy: currentUser.id,
    createdByName: currentUser.fullName || currentUser.username,
    createdByRole: currentUser.role || "user",
    fromStatus: previousStatus,
    toStatus: nextStatus,
  });

  await logAuditEvent({
    actorId: currentUser.id,
    action: "ticket.status.updated",
    entityType: "Ticket",
    entityId: ticket._id,
    payload: { fromStatus: previousStatus, toStatus: nextStatus },
  });

  const hydrated = await loadTicketForAccess(ticket._id);
  const notifyUserIds = await buildNotifyUserIds(hydrated);
  return {
    ticket: serializeTicket(hydrated),
    update: serializeTicketUpdate(update.toObject()),
    notifyUserIds,
  };
}

async function assignTicket(currentUser, ticketId, assignedToId) {
  const ticket = await loadTicketForAccess(ticketId);
  const allowed = await canManageTicket(currentUser, ticket);
  if (!allowed) {
    throw new ApiError(403, "Permission denied.");
  }
  const nextAssigneeId = toNullableString(assignedToId);

  const previousAssigneeId =
    ticket.assignedTo?._id?.toString?.() ||
    ticket.assignedTo?.toString?.() ||
    null;

  let nextAssigneeUser = null;
  if (nextAssigneeId) {
    nextAssigneeUser = await User.findOne(
      { _id: nextAssigneeId, isActive: true },
      "_id username fullName role departmentId isOnline presenceStatus avatarUrl lastSeen lastActiveAt",
    ).lean();
    if (!nextAssigneeUser) {
      throw new ApiError(404, "Assignee user not found.");
    }
    let isTargetAllowed = nextAssigneeUser.role === "admin";
    if (!isTargetAllowed && (await isSupportAgent(nextAssigneeId))) {
      if (await ticketTargetIsVisibleToSupportAgent(ticket)) {
        isTargetAllowed = true;
      }
    }
    if (!isTargetAllowed && ticket.targetDepartmentId) {
      const handlerField = getHandlerFieldName(ticket.ticketType || "ticket");
      const targetDepartmentId = resolveDepartmentRefId(
        ticket.targetDepartmentId,
      );
      const dept = targetDepartmentId
        ? await Department.findById(targetDepartmentId)
            .select(handlerField)
            .lean()
        : null;
      const handlers = dept?.[handlerField] || [];
      if (handlers.some((id) => id.toString() === nextAssigneeId)) {
        isTargetAllowed = true;
      }
    }
    if (!isTargetAllowed) {
      const type = ticket.ticketType || "ticket";
      const message =
        type === "suggestion"
          ? "الموظف المختار ليس من ضمن مسؤولي المقترحات لهذا القسم."
          : type === "complaint"
            ? "الموظف المختار ليس من ضمن مسؤولي الشكاوى لهذا القسم."
            : "الموظف المختار ليس من ضمن مسؤولي التذاكر أو فريق الدعم لهذا القسم.";
      throw new ApiError(400, message);
    }
  }

  const previousStatus = ticket.status;
  ticket.assignedTo = nextAssigneeUser?._id || null;
  ticket.lastUpdateAt = new Date();
  if (nextAssigneeUser && ticket.status === "open") {
    ticket.status = "assigned";
  }
  await ticket.save();

  const update = await TicketUpdate.create({
    ticketId: ticket._id,
    kind: "assignment",
    message: nextAssigneeUser
      ? `Assigned to ${nextAssigneeUser.fullName || nextAssigneeUser.username}.`
      : "Assignment removed.",
    visibility: "public",
    createdBy: currentUser.id,
    createdByName: currentUser.fullName || currentUser.username,
    createdByRole: currentUser.role || "user",
    fromAssigneeId: previousAssigneeId || null,
    toAssigneeId: nextAssigneeUser?._id || null,
    toAssigneeName: nextAssigneeUser
      ? nextAssigneeUser.fullName || nextAssigneeUser.username
      : "",
    fromStatus: previousStatus,
    toStatus: ticket.status,
  });

  await logAuditEvent({
    actorId: currentUser.id,
    action: "ticket.assignment.updated",
    entityType: "Ticket",
    entityId: ticket._id,
    payload: {
      fromAssigneeId: previousAssigneeId,
      toAssigneeId: nextAssigneeUser?._id?.toString?.() || null,
    },
  });

  const hydrated = await loadTicketForAccess(ticket._id);
  const notifyUserIds = await buildNotifyUserIds(hydrated);
  return {
    ticket: serializeTicket(hydrated),
    update: serializeTicketUpdate(update.toObject()),
    notifyUserIds,
  };
}

async function getTicketSettings(currentUser) {
  const settings = await getOrCreateSettings();
  const supportAgentIds = (settings.supportAgentIds || []).map(
    (entry) => entry?.toString?.() || String(entry),
  );
  const support = await isSupportAgent(currentUser.id);
  const ticketDeptIds = await getHandledDepartmentIds(currentUser.id, "ticket");
  const complaintDeptIds = await getHandledDepartmentIds(
    currentUser.id,
    "complaint",
  );
  const suggestionDeptIds = await getHandledDepartmentIds(
    currentUser.id,
    "suggestion",
  );
  const isDeptHandler =
    ticketDeptIds.length > 0 ||
    complaintDeptIds.length > 0 ||
    suggestionDeptIds.length > 0;
  const reportPermissions = toReportPermissionMap(settings);
  const exportTicketTypes = reportPermissions.get(String(currentUser.id)) || [];
  return {
    supportAgentIds,
    isSupportAgent: support,
    canManage: currentUser.role === "admin" || support || isDeptHandler,
    canExportTicketReport:
      currentUser.role === "admin" || exportTicketTypes.includes("ticket"),
    canExportComplaintReport:
      currentUser.role === "admin" || exportTicketTypes.includes("complaint"),
    canExportSuggestionReport:
      currentUser.role === "admin" || exportTicketTypes.includes("suggestion"),
  };
}

async function updateTicketSettings(currentUser, payload) {
  if (currentUser.role !== "admin") {
    throw new ApiError(403, "Admin access required.");
  }

  const supportIds = normalizeIdArray(payload.supportAgentIds);
  const reportExportersPayload = Array.isArray(payload.reportExporters)
    ? payload.reportExporters
    : [];
  const requestedExporterIds = normalizeIdArray(
    reportExportersPayload.map((item) => item?.userId),
  );
  const allRequestedUserIds = [
    ...new Set([...supportIds, ...requestedExporterIds]),
  ];
  const existingUsers = await User.find(
    { _id: { $in: allRequestedUserIds }, isActive: true },
    "_id",
  ).lean();
  const validUserIds = existingUsers.map((entry) => entry._id.toString());
  const validSupportIds = supportIds.filter((id) => validUserIds.includes(id));
  const reportExportersMap = new Map();
  for (const item of reportExportersPayload) {
    const userId = String(item?.userId || "").trim();
    if (!validUserIds.includes(userId)) {
      continue;
    }
    reportExportersMap.set(userId, normalizeTicketTypes(item?.ticketTypes));
  }
  const reportExporters = [...reportExportersMap.entries()].map(
    ([userId, ticketTypes]) => ({
      userId,
      ticketTypes,
    }),
  );

  const settings = await TicketSettings.findOneAndUpdate(
    { singletonKey: "default" },
    { $set: { supportAgentIds: validSupportIds, reportExporters } },
    { upsert: true, new: true, setDefaultsOnInsert: true },
  );

  await logAuditEvent({
    actorId: currentUser.id,
    action: "ticket.settings.updated",
    entityType: "TicketSettings",
    entityId: settings._id,
    payload: { supportAgentIds: validSupportIds, reportExporters },
  });

  return {
    supportAgentIds: validSupportIds,
    reportExporters,
  };
}

async function getDashboardStats(currentUser) {
  await ensureManageAccess(currentUser);

  const totalTickets = await Ticket.countDocuments({ deletedAt: null });

  // Status breakdown
  const statusAggregation = await Ticket.aggregate([
    { $match: { deletedAt: null } },
    { $group: { _id: "$status", count: { $sum: 1 } } },
  ]);
  const statuses = {
    open: 0,
    assigned: 0,
    in_progress: 0,
    waiting_branch: 0,
    resolved: 0,
    closed: 0,
  };
  statusAggregation.forEach((entry) => {
    if (entry._id in statuses) {
      statuses[entry._id] = entry.count;
    }
  });

  // Priority breakdown
  const priorityAggregation = await Ticket.aggregate([
    { $match: { deletedAt: null } },
    { $group: { _id: "$priority", count: { $sum: 1 } } },
  ]);
  const priorities = {
    low: 0,
    normal: 0,
    high: 0,
    critical: 0,
  };
  priorityAggregation.forEach((entry) => {
    if (entry._id in priorities) {
      priorities[entry._id] = entry.count;
    }
  });

  // Average resolution time in minutes (for resolved/closed tickets)
  const resolvedTickets = await Ticket.find({
    deletedAt: null,
    status: { $in: ["resolved", "closed"] },
    resolvedAt: { $ne: null },
  })
    .select("createdAt resolvedAt")
    .lean();

  let totalResolutionTime = 0;
  resolvedTickets.forEach((t) => {
    const diff =
      new Date(t.resolvedAt).getTime() - new Date(t.createdAt).getTime();
    if (diff > 0) {
      totalResolutionTime += diff / 60000;
    }
  });
  const avgResolutionTimeMinutes =
    resolvedTickets.length > 0
      ? Math.round(totalResolutionTime / resolvedTickets.length)
      : 0;

  // SLA Compliance (tickets resolved before or on dueDate)
  const slaCompliantTickets = await Ticket.countDocuments({
    deletedAt: null,
    status: { $in: ["resolved", "closed"] },
    resolvedAt: { $ne: null },
    dueDate: { $ne: null },
    $expr: { $lte: ["$resolvedAt", "$dueDate"] },
  });
  const totalSlaEvaluated = await Ticket.countDocuments({
    deletedAt: null,
    status: { $in: ["resolved", "closed"] },
    resolvedAt: { $ne: null },
    dueDate: { $ne: null },
  });
  const slaComplianceRate =
    totalSlaEvaluated > 0
      ? Math.round((slaCompliantTickets / totalSlaEvaluated) * 100)
      : 100;

  // Active SLA Breaches
  const activeSlaBreachesCount = await Ticket.countDocuments({
    deletedAt: null,
    status: { $nin: ["resolved", "closed"] },
    dueDate: { $ne: null, $lt: new Date() },
  });

  // CSAT (Customer Satisfaction Rating)
  const ratedTicketsAggregation = await Ticket.aggregate([
    { $match: { deletedAt: null, rating: { $ne: null } } },
    {
      $group: { _id: null, avgRating: { $avg: "$rating" }, count: { $sum: 1 } },
    },
  ]);
  const averageCsat =
    ratedTicketsAggregation.length > 0
      ? parseFloat(ratedTicketsAggregation[0].avgRating.toFixed(1))
      : 0;
  const ratedTicketsCount =
    ratedTicketsAggregation.length > 0 ? ratedTicketsAggregation[0].count : 0;

  // Workload Distribution
  const supportAgentIds = await getSupportAgentIdSet();
  const itDepts = await Department.find({
    $or: [
      { code: "IT" },
      { code: /IT/i },
      { name: "IT" },
      { name: /IT SUPPORT/i },
      { name: /الدعم الفني/i },
    ],
    deletedAt: null,
  })
    .select("_id")
    .lean();
  const itDeptIds = itDepts.map((d) => d._id);

  const eligibleAgents = await User.find({
    $or: [
      {
        _id: {
          $in: [...supportAgentIds]
            .filter((id) => id.length > 0)
            .map((id) => new mongoose.Types.ObjectId(id)),
        },
      },
      { departmentId: { $in: itDeptIds } },
    ],
    isActive: true,
  })
    .select("_id fullName username")
    .lean();

  const workloadCounts = await Ticket.aggregate([
    {
      $match: {
        status: { $in: ["open", "assigned", "in_progress", "waiting_branch"] },
        assignedTo: { $in: eligibleAgents.map((a) => a._id) },
        deletedAt: null,
      },
    },
    {
      $group: {
        _id: "$assignedTo",
        count: { $sum: 1 },
      },
    },
  ]);

  const workloadMap = new Map(
    workloadCounts.map((c) => [c._id.toString(), c.count]),
  );
  const workload = eligibleAgents
    .map((agent) => ({
      agentId: agent._id.toString(),
      fullName: agent.fullName || agent.username,
      activeTicketsCount: workloadMap.get(agent._id.toString()) || 0,
    }))
    .sort((a, b) => b.activeTicketsCount - a.activeTicketsCount);

  return {
    totalTickets,
    statuses,
    priorities,
    avgResolutionTimeMinutes,
    slaComplianceRate,
    activeSlaBreachesCount,
    averageCsat,
    ratedTicketsCount,
    workload,
  };
}

async function rateTicket(currentUser, ticketId, payload) {
  const ticket = await loadTicketForAccess(ticketId);

  if (ticket.createdBy.toString() !== currentUser.id) {
    throw new ApiError(
      403,
      "غير مصرح لك بتقييم هذه التذكرة. فقط منشئ التذكرة يمكنه التقييم.",
    );
  }

  if (ticket.status !== "resolved" && ticket.status !== "closed") {
    throw new ApiError(400, "لا يمكن تقييم التذكرة إلا بعد حلها أو إغلاقها.");
  }

  ticket.rating = payload.rating;
  ticket.feedback = payload.feedback || "";
  await ticket.save();

  await logAuditEvent({
    actorId: currentUser.id,
    action: "ticket.rated",
    entityType: "Ticket",
    entityId: ticket._id,
    payload: { rating: ticket.rating, feedback: ticket.feedback },
  });

  return serializeTicket(ticket);
}
async function getDepartmentHandlersByType(
  currentUser,
  departmentId,
  handlerType = "complaint",
) {
  if (currentUser.role !== "admin") {
    const handledDeptIds = await getHandledDepartmentIds(
      currentUser.id,
      handlerType,
    );
    const allowed = handledDeptIds.some(
      (entry) => entry.toString() === String(departmentId),
    );
    if (!allowed) {
      await ensureManageAccess(currentUser);
    }
  }
  const fieldName = getHandlerFieldName(handlerType);
  const dept = await Department.findById(departmentId)
    .populate(
      fieldName,
      "username fullName role departmentId isOnline presenceStatus avatarUrl lastSeen lastActiveAt",
    )
    .lean();
  if (!dept) throw new ApiError(404, "القسم غير موجود.");

  const handlers = Array.isArray(dept[fieldName]) ? dept[fieldName] : [];
  return handlers.map(serializeUser);
}

async function listDepartmentHandlerAssignments(
  currentUser,
  handlerType = "complaint",
) {
  if (currentUser.role !== "admin") {
    await ensureManageAccess(currentUser);
  }

  const fieldName = getHandlerFieldName(handlerType);
  const departments = await Department.find({ deletedAt: null })
    .select(`name ${fieldName}`)
    .lean();
  const assignments = {};

  for (const department of departments) {
    for (const handlerId of department[fieldName] || []) {
      const userId = handlerId.toString();
      if (!assignments[userId]) {
        assignments[userId] = [];
      }
      assignments[userId].push({
        departmentId: department._id.toString(),
        departmentName: department.name,
      });
    }
  }

  return assignments;
}

async function updateDepartmentHandlersByType(
  currentUser,
  departmentId,
  payload,
  handlerType = "complaint",
) {
  if (currentUser.role !== "admin") {
    throw new ApiError(403, "صلاحية محصورة لمدير النظام فقط.");
  }

  const fieldName = getHandlerFieldName(handlerType);
  const handlerIds = normalizeIdArray(payload.handlerIds);
  const dept = await Department.findById(departmentId);
  if (!dept) throw new ApiError(404, "القسم غير موجود.");

  const existingUsers = handlerIds.length
    ? await User.find(
        { _id: { $in: handlerIds }, isActive: true },
        "_id",
      ).lean()
    : [];
  const validHandlerIds = existingUsers.map((entry) => entry._id);

  dept[fieldName] = validHandlerIds;
  await dept.save();

  await logAuditEvent({
    actorId: currentUser.id,
    action: `department.${normalizeHandlerType(handlerType)}_handlers.updated`,
    entityType: "Department",
    entityId: dept._id,
    payload: { handlerIds: validHandlerIds.map((entry) => entry.toString()) },
  });

  return getDepartmentHandlersByType(currentUser, departmentId, handlerType);
}

// Backward-compatible aliases
async function getDepartmentComplaintHandlers(currentUser, departmentId) {
  return getDepartmentHandlersByType(currentUser, departmentId, "complaint");
}

async function updateDepartmentComplaintHandlers(
  currentUser,
  departmentId,
  payload,
) {
  return updateDepartmentHandlersByType(
    currentUser,
    departmentId,
    payload,
    "complaint",
  );
}

module.exports = {
  listTickets,
  getTicketDetails,
  createTicket,
  addTicketComment,
  updateTicketStatus,
  assignTicket,
  getTicketSettings,
  updateTicketSettings,
  listSupportUsers,
  exportTicketReport,
  ticketPushBody,
  ticketNotificationTitle,
  getDashboardStats,
  rateTicket,
  getDepartmentComplaintHandlers,
  updateDepartmentComplaintHandlers,
  getDepartmentHandlersByType,
  updateDepartmentHandlersByType,
  listDepartmentHandlerAssignments,
};
