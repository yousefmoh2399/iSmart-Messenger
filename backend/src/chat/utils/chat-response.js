function sendChatResponse(res, { status = 200, data = null, error = null, meta = null, legacy = {} }) {
  res.status(status).json({
    success: !error,
    data,
    error,
    meta,
    ...legacy,
  });
}

module.exports = {
  sendChatResponse,
};
