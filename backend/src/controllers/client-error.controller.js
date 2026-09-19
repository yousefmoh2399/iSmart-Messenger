const asyncHandler = require("../utils/async-handler");
const ClientError = require("../models/client-error.model");

const reportError = asyncHandler(async (req, res) => {
  const { source, errorMessage, errorContext, stackTrace, clientType, sessionId } = req.body;

  if (!errorMessage) {
    return res.status(400).json({ success: false, message: "errorMessage is required." });
  }

  const clientError = new ClientError({
    userId: req.user?.id || null, // from requireAuth (if authenticated)
    sessionId: sessionId || null,
    clientType: clientType || req.user?.clientType || "unknown",
    source: source || "app",
    errorMessage,
    errorContext: errorContext || {},
    stackTrace: stackTrace || null,
  });

  await clientError.save();

  res.status(201).json({
    success: true,
    message: "Error logged successfully",
  });
});

module.exports = {
  reportError,
};
