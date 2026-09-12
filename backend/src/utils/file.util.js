const fs = require("fs/promises");
const { resolveStoredUploadPath } = require("./storage-paths");

async function deleteFileIfExists(filePath) {
  const resolvedPath = resolveStoredUploadPath(filePath) || filePath;
  try {
    await fs.unlink(resolvedPath);
  } catch (error) {
    if (error.code !== "ENOENT") {
      throw error;
    }
  }
}

module.exports = {
  deleteFileIfExists,
};
