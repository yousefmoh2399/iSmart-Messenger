const fs = require("fs");
const path = require("path");

exports.default = async function (context) {
  const localeDir = path.join(context.appOutDir, "locales");
  const localesToKeep = ["en-US.pak", "en-GB.pak", "ar.pak"];

  if (fs.existsSync(localeDir)) {
    const files = fs.readdirSync(localeDir);
    for (const file of files) {
      if (!localesToKeep.includes(file)) {
        try {
          fs.unlinkSync(path.join(localeDir, file));
        } catch (_) {}
      }
    }
  }
};
