const asyncHandler = require("../../utils/async-handler");
const { sendChatResponse } = require("../../chat/utils/chat-response");
const {
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
  getDepartmentHandlersByType,
  updateDepartmentHandlersByType,
  listDepartmentHandlerAssignments,
} = require("../services/ticket.service");
const { sendTicketPushNotifications } = require("../../services/push-notification.service");

function emitTicketUpdate(req, { action, ticket, update = null, notifyUserIds = [] }) {
  const io = req.app.get("io");
  if (!io || !ticket) {
    return;
  }

  const actorId = req.user?.id?.toString?.() || req.user?._id?.toString?.() || "";
  const title = ticketNotificationTitle(action, ticket);
  const body = ticketPushBody(action, ticket, update);
  const payload = {
    action,
    ticketId: ticket.id,
    ticket,
    update,
    notification: {
      title,
      body,
    },
    at: new Date().toISOString(),
  };

  const userIds = new Set((notifyUserIds || []).map((entry) => String(entry)));
  if (actorId) {
    userIds.delete(actorId);
  }
  for (const userId of userIds) {
    io.to(`user:${userId}`).emit("ticket_updated", payload);
    io.to(`user:${userId}`).emit("tickets_updated", {
      action,
      ticketId: ticket.id,
      at: payload.at,
    });
  }

  sendTicketPushNotifications({
    recipientUserIds: [...userIds],
    ticket,
    action,
    title,
    body,
  }).catch((error) => {
    console.error("Failed to send ticket push notification:", error);
  });
}

const getTickets = asyncHandler(async (req, res) => {
  const result = await listTickets(req.user, {
    scope: req.query.scope,
    status: req.query.status,
    priority: req.query.priority,
    ticketType: req.query.ticketType,
    q: req.query.q,
    limit: req.query.limit,
  });
  sendChatResponse(res, {
    data: { tickets: result.tickets },
    meta: result.meta,
    legacy: { tickets: result.tickets, meta: result.meta },
  });
});

const getTicketById = asyncHandler(async (req, res) => {
  const result = await getTicketDetails(req.user, req.params.id);
  sendChatResponse(res, {
    data: {
      ticket: result.ticket,
      updates: result.updates,
    },
    meta: result.meta,
    legacy: {
      ticket: result.ticket,
      updates: result.updates,
      meta: result.meta,
    },
  });
});

const createNewTicket = asyncHandler(async (req, res) => {
  const result = await createTicket(req.user, req.body);
  emitTicketUpdate(req, {
    action: "created",
    ticket: result.ticket,
    update: result.update,
    notifyUserIds: result.notifyUserIds,
  });
  sendChatResponse(res, {
    status: 201,
    data: { ticket: result.ticket, update: result.update },
    legacy: { ticket: result.ticket, update: result.update },
  });
});

const addCommentToTicket = asyncHandler(async (req, res) => {
  const result = await addTicketComment(req.user, req.params.id, req.body);
  emitTicketUpdate(req, {
    action: "comment_added",
    ticket: result.ticket,
    update: result.update,
    notifyUserIds: result.notifyUserIds,
  });
  sendChatResponse(res, {
    data: {
      ticket: result.ticket,
      update: result.update,
      statusUpdate: result.statusUpdate,
    },
    legacy: {
      ticket: result.ticket,
      update: result.update,
      statusUpdate: result.statusUpdate,
    },
  });
});

const setTicketStatus = asyncHandler(async (req, res) => {
  const result = await updateTicketStatus(req.user, req.params.id, req.body.status);
  emitTicketUpdate(req, {
    action: "status_updated",
    ticket: result.ticket,
    update: result.update,
    notifyUserIds: result.notifyUserIds,
  });
  sendChatResponse(res, {
    data: { ticket: result.ticket, update: result.update },
    legacy: { ticket: result.ticket, update: result.update },
  });
});

const setTicketAssignee = asyncHandler(async (req, res) => {
  const result = await assignTicket(req.user, req.params.id, req.body.assignedToId);
  emitTicketUpdate(req, {
    action: "assignee_updated",
    ticket: result.ticket,
    update: result.update,
    notifyUserIds: result.notifyUserIds,
  });
  sendChatResponse(res, {
    data: { ticket: result.ticket, update: result.update },
    legacy: { ticket: result.ticket, update: result.update },
  });
});

const getMyTicketSettings = asyncHandler(async (req, res) => {
  const settings = await getTicketSettings(req.user);
  sendChatResponse(res, {
    data: { settings },
    legacy: { settings },
  });
});

const saveTicketSettings = asyncHandler(async (req, res) => {
  const settings = await updateTicketSettings(req.user, req.body);
  const io = req.app.get("io");
  if (io) {
    io.emit("ticket_settings_updated", {
      supportAgentIds: settings.supportAgentIds,
      at: new Date().toISOString(),
    });
  }
  sendChatResponse(res, {
    data: { settings },
    legacy: { settings },
  });
});

const getSupportUsers = asyncHandler(async (req, res) => {
  const result = await listSupportUsers();
  sendChatResponse(res, {
    data: {
      users: result.users,
      supportAgentIds: result.supportAgentIds,
    },
    legacy: {
      users: result.users,
      supportAgentIds: result.supportAgentIds,
    },
  });
});

const exportTicketsReport = asyncHandler(async (req, res) => {
  const csv = await exportTicketReport(req.user, {
    status: req.query.status,
    priority: req.query.priority,
    ticketType: req.query.ticketType,
    q: req.query.q,
  });
  const rawType = String(req.query.ticketType || "ticket").trim().toLowerCase();
  const reportType = ["ticket", "complaint", "suggestion"].includes(rawType)
    ? rawType
    : "ticket";
  const prefix = reportType === "ticket" ? "tickets" : reportType === "complaint" ? "complaints" : "suggestions";
  const fileName = `${prefix}-report-${new Date().toISOString().slice(0, 10)}.csv`;
  res.setHeader("Content-Type", "text/csv; charset=utf-8");
  res.setHeader(
    "Content-Disposition",
    `attachment; filename="${fileName}"`,
  );
  res.status(200).send(csv);
});

const getTicketDashboardStats = asyncHandler(async (req, res) => {
  const stats = await getDashboardStats(req.user);
  sendChatResponse(res, {
    data: stats,
    legacy: stats,
  });
});

const submitTicketRating = asyncHandler(async (req, res) => {
  const result = await rateTicket(req.user, req.params.id, req.body);
  sendChatResponse(res, {
    data: { ticket: result },
    legacy: { ticket: result },
  });
});

const getDepartmentHandlers = asyncHandler(async (req, res) => {
  const handlerType = req.query.handlerType || "complaint";
  const users = await getDepartmentHandlersByType(
    req.user,
    req.params.departmentId,
    handlerType,
  );
  sendChatResponse(res, {
    data: { users, handlerType },
    legacy: { users, handlerType },
  });
});

const updateDepartmentHandlers = asyncHandler(async (req, res) => {
  const handlerType = req.body.handlerType || req.query.handlerType || "complaint";
  const users = await updateDepartmentHandlersByType(
    req.user,
    req.params.departmentId,
    req.body,
    handlerType,
  );
  sendChatResponse(res, {
    data: { users, handlerType },
    legacy: { users, handlerType },
  });
});

const getDepartmentHandlerAssignments = asyncHandler(async (req, res) => {
  const handlerType = req.query.handlerType || "complaint";
  const assignments = await listDepartmentHandlerAssignments(
    req.user,
    handlerType,
  );
  sendChatResponse(res, {
    data: { assignments, handlerType },
    legacy: { assignments, handlerType },
  });
});

module.exports = {
  getTickets,
  getTicketById,
  createNewTicket,
  addCommentToTicket,
  setTicketStatus,
  setTicketAssignee,
  getMyTicketSettings,
  saveTicketSettings,
  getSupportUsers,
  exportTicketsReport,
  getTicketDashboardStats,
  submitTicketRating,
  getDepartmentHandlers,
  updateDepartmentHandlers,
  getDepartmentHandlerAssignments,
};
