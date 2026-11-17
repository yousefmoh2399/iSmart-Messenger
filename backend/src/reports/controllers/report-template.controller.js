const asyncHandler = require("../../utils/async-handler");
const { sendChatResponse } = require("../../chat/utils/chat-response");
const {
  getAvailableColumns,
  listTemplates,
  getTemplateById,
  createTemplate,
  updateTemplate,
  deleteTemplate,
  setDefaultTemplate,
} = require("../services/report-template.service");

const listTemplatesHandler = asyncHandler(async (req, res) => {
  const reportType = req.query.reportType || "printer_consumption";
  const templates = await listTemplates(reportType);
  sendChatResponse(res, {
    data: { templates },
    legacy: { templates },
  });
});

const getAvailableColumnsHandler = asyncHandler(async (req, res) => {
  const reportType = req.query.reportType || "printer_consumption";
  const columns = getAvailableColumns(reportType);
  sendChatResponse(res, {
    data: { columns, reportType },
    legacy: { columns, reportType },
  });
});

const getTemplateByIdHandler = asyncHandler(async (req, res) => {
  const template = await getTemplateById(req.params.id);
  sendChatResponse(res, {
    data: { template },
    legacy: { template },
  });
});

const createTemplateHandler = asyncHandler(async (req, res) => {
  const template = await createTemplate(req.user, req.body);
  sendChatResponse(res, {
    data: { template },
    legacy: { template },
  });
});

const updateTemplateHandler = asyncHandler(async (req, res) => {
  const template = await updateTemplate(req.user, req.params.id, req.body);
  sendChatResponse(res, {
    data: { template },
    legacy: { template },
  });
});

const deleteTemplateHandler = asyncHandler(async (req, res) => {
  const result = await deleteTemplate(req.user, req.params.id);
  sendChatResponse(res, {
    data: result,
    legacy: result,
  });
});

const setDefaultTemplateHandler = asyncHandler(async (req, res) => {
  const template = await setDefaultTemplate(req.user, req.params.id);
  sendChatResponse(res, {
    data: { template },
    legacy: { template },
  });
});

module.exports = {
  listTemplatesHandler,
  getAvailableColumnsHandler,
  getTemplateByIdHandler,
  createTemplateHandler,
  updateTemplateHandler,
  deleteTemplateHandler,
  setDefaultTemplateHandler,
};
