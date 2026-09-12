const {
  getAppSettings,
  updateAppSettings,
} = require("./app-settings.service");

async function getAppSettingsHandler(req, res) {
  const settings = await getAppSettings();
  res.status(200).json({ settings });
}

async function updateAppSettingsHandler(req, res) {
  const settings = await updateAppSettings(req.user, req.body || {});
  const io = req.app.get("io");
  if (io) {
    io.emit("app_settings_updated", {
      at: new Date().toISOString(),
      settings,
      updatedBy: req.user?.id || null,
    });
  }
  res.status(200).json({ settings });
}

module.exports = {
  getAppSettingsHandler,
  updateAppSettingsHandler,
};
