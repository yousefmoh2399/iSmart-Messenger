const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const storagePaths = require("../src/utils/storage-paths");
const envConfig = require("../src/config/env");

const originalUploadDir = envConfig.uploadDir;
const originalBackupsDir = envConfig.backupsDir;
const originalUpdateReleasesDir = envConfig.updateReleasesDir;
const originalDataDir = envConfig.DATA_DIR;

test.afterEach(() => {
  envConfig.uploadDir = originalUploadDir;
  envConfig.backupsDir = originalBackupsDir;
  envConfig.updateReleasesDir = originalUpdateReleasesDir;
  envConfig.DATA_DIR = originalDataDir;
});

test("getUploadsRoot supports defaults, relative paths, and absolute paths", () => {
  envConfig.uploadDir = path.join(storagePaths.getBackendRoot(), "uploads");
  assert.equal(
    storagePaths.getUploadsRoot(),
    path.join(storagePaths.getBackendRoot(), "uploads"),
  );

  envConfig.uploadDir = path.join(storagePaths.getBackendRoot(), "runtime/files");
  assert.equal(
    storagePaths.getUploadsRoot(),
    path.join(storagePaths.getBackendRoot(), "runtime/files"),
  );

  envConfig.uploadDir = path.join(os.tmpdir(), "configured-uploads");
  assert.equal(
    storagePaths.getUploadsRoot(),
    path.normalize(envConfig.uploadDir),
  );
});

test("configured backup and update release roots support env paths", () => {
  envConfig.backupsDir = path.join(storagePaths.getBackendRoot(), "backups");
  envConfig.updateReleasesDir = path.join(storagePaths.getBackendRoot(), "releases");

  assert.equal(
    storagePaths.getBackupsRoot(),
    path.join(storagePaths.getBackendRoot(), "backups"),
  );
  assert.equal(
    storagePaths.getUpdateReleasesRoot(),
    path.join(storagePaths.getBackendRoot(), "releases"),
  );

  envConfig.backupsDir = path.resolve(storagePaths.getBackendRoot(), "../server-storage/backups");
  envConfig.updateReleasesDir = path.resolve(storagePaths.getBackendRoot(), "../server-storage/releases");

  assert.equal(
    storagePaths.getBackupsRoot(),
    path.resolve(storagePaths.getBackendRoot(), "../server-storage/backups"),
  );
  assert.equal(
    storagePaths.getUpdateReleasesRoot(),
    path.resolve(storagePaths.getBackendRoot(), "../server-storage/releases"),
  );
});

test("sanitizePathSegment removes traversal and unsafe characters", () => {
  assert.equal(storagePaths.sanitizePathSegment(null, "fallback"), "fallback");
  assert.equal(
    storagePaths.sanitizePathSegment(" ../ reports / <daily>:2026?.pdf "),
    path.join("reports", "_daily__2026_.pdf"),
  );
  assert.equal(
    storagePaths.sanitizePathSegment("folder\\nested\\file.txt"),
    path.join("folder", "nested", "file.txt"),
  );
});

test("isPathInsideRoot rejects sibling and parent paths", () => {
  const root = path.join(os.tmpdir(), "uploads-root");

  assert.equal(storagePaths.isPathInsideRoot(root, root), true);
  assert.equal(
    storagePaths.isPathInsideRoot(root, path.join(root, "chat", "file.pdf")),
    true,
  );
  assert.equal(
    storagePaths.isPathInsideRoot(root, `${root}-other/file.pdf`),
    false,
  );
  assert.equal(
    storagePaths.isPathInsideRoot(root, path.dirname(root)),
    false,
  );
});

test("upload directory helpers stay inside the configured root", () => {
  envConfig.uploadDir = path.join(os.tmpdir(), "uploads-root");

  assert.equal(
    storagePaths.resolveUploadPath("..", "chat", "../room", "file.pdf"),
    path.join(envConfig.uploadDir, "chat", "room", "file.pdf"),
  );
  assert.equal(
    storagePaths.getChatUploadsDir("room-1"),
    path.join(envConfig.uploadDir, "chat", "room-1"),
  );
  assert.equal(
    storagePaths.getChatTransferUploadsDir("user-1"),
    path.join(envConfig.uploadDir, "chat_transfers", "user-1"),
  );
  assert.equal(
    storagePaths.getAvatarUploadsDir("user-1"),
    path.join(envConfig.uploadDir, "avatars", "user-1"),
  );
  assert.equal(
    storagePaths.getDocumentsUploadsDir("user-1"),
    path.join(envConfig.uploadDir, "user-1"),
  );
});

test("ensureDirectory and fileExists reflect filesystem state", async (t) => {
  const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), "storage-paths-"));
  t.after(() => fs.rm(tempRoot, { recursive: true, force: true }));
  const directory = path.join(tempRoot, "nested");
  const filePath = path.join(directory, "file.txt");

  assert.equal(await storagePaths.fileExists(null), false);
  assert.equal(await storagePaths.fileExists(filePath), false);
  assert.equal(await storagePaths.ensureDirectory(directory), directory);
  await fs.writeFile(filePath, "content");
  assert.equal(await storagePaths.fileExists(filePath), true);
});

test("relative and stored upload paths are normalized safely", () => {
  envConfig.uploadDir = path.join(os.tmpdir(), "uploads-root");
  const filePath = path.join(envConfig.uploadDir, "chat", "file.pdf");

  assert.equal(
    storagePaths.toRelativeUploadPath(filePath),
    path.join("chat", "file.pdf"),
  );
  assert.equal(storagePaths.toRelativeUploadPath(null), null);
  assert.throws(
    () => storagePaths.toRelativeUploadPath(path.join(os.tmpdir(), "elsewhere")),
    /outside uploads root/,
  );

  assert.equal(storagePaths.resolveStoredUploadPath(null), null);
  assert.equal(
    storagePaths.resolveStoredUploadPath("chat/file.pdf"),
    filePath,
  );
  assert.equal(
    storagePaths.resolveStoredUploadPath("uploads-root/chat/file.pdf"),
    filePath,
  );
  assert.equal(storagePaths.resolveStoredUploadPath(filePath), filePath);
  assert.equal(
    storagePaths.resolveStoredUploadPath(
      path.join(os.tmpdir(), "legacy", "uploads-root", "chat", "file.pdf"),
    ),
    filePath,
  );
  assert.equal(
    storagePaths.resolveStoredUploadPath(
      path.join(os.tmpdir(), "legacy", "unknown", "file.pdf"),
    ),
    null,
  );
});

test("stored update release paths can move from legacy releases root", () => {
  envConfig.updateReleasesDir = path.join(os.tmpdir(), "new-releases");

  assert.equal(storagePaths.resolveStoredUpdateReleasePath(null), null);
  assert.equal(
    storagePaths.resolveStoredUpdateReleasePath("installer.zip"),
    path.join(envConfig.updateReleasesDir, "installer.zip"),
  );
  assert.equal(
    storagePaths.resolveStoredUpdateReleasePath(
      path.join(os.tmpdir(), "legacy", "releases", "installer.zip"),
    ),
    path.join(envConfig.updateReleasesDir, "installer.zip"),
  );
});

