const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const { deleteFileIfExists } = require("../src/utils/file.util");

test("deleteFileIfExists removes an existing file", async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "file-util-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const filePath = path.join(directory, "document.txt");
  await fs.writeFile(filePath, "content");

  await deleteFileIfExists(filePath);

  await assert.rejects(fs.access(filePath), { code: "ENOENT" });
});

test("deleteFileIfExists ignores missing files", async () => {
  const missingPath = path.join(
    os.tmpdir(),
    `missing-file-${process.pid}-${Date.now()}`,
  );

  await assert.doesNotReject(deleteFileIfExists(missingPath));
});

test("deleteFileIfExists propagates non-ENOENT errors", async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "file-util-dir-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));

  await assert.rejects(
    deleteFileIfExists(directory),
    (error) => error.code !== "ENOENT",
  );
});
