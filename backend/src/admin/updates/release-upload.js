const path = require("path");
const { updateArtifactMaxBytes } = require("../../config/env");
const { getUpdateReleasesRoot } = require("../../utils/storage-paths");
const {
  randomToken,
  createAllowlistFilter,
  createDiskUpload,
} = require("../../utils/upload.util");

function sanitizeName(name) {
  return String(name || "")
    .replace(/[^\w.\-]+/g, "_")
    .slice(-180);
}

function buildReleaseFileName(originalName) {
  const timestamp = Date.now();
  const token = randomToken(7);
  const ext = path.extname(originalName || "").toLowerCase();
  const base = sanitizeName(path.basename(originalName || "artifact", ext));
  return `${timestamp}-${token}-${base || "artifact"}${ext || ".bin"}`;
}

const releaseUpload = createDiskUpload({
  resolveDestination: () => getUpdateReleasesRoot(),
  resolveFilename: (req, file) => buildReleaseFileName(file.originalname),
  fileFilter: createAllowlistFilter({
    allowedExtensions: [".exe", ".msi", ".apk", ".zip", ".bin"],
    message: "Artifact must be one of: .exe, .msi, .apk, .zip or .bin",
  }),
  limits: {
    fileSize: updateArtifactMaxBytes,
  },
});

module.exports = {
  releaseUpload,
  getUpdateReleasesRoot,
};
