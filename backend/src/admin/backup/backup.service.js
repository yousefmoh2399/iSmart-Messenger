const fs = require("fs/promises");
const fsSync = require("fs");
const os = require("os");
const path = require("path");
const { execFile } = require("child_process");
const { Writable } = require("stream");
const { pipeline } = require("stream/promises");
const archiver = require("archiver");
const mongoose = require("mongoose");
const { EJSON } = require("bson");
const unzipper = require("unzipper");
const ApiError = require("../../utils/api-error");
const logger = require("../../utils/logger");
const { backupPreRestoreSnapshot, mongodbUri } = require("../../config/env");
const { logAuditEvent } = require("../../chat/services/audit.service");
const { getBackupsRoot, getUploadsRoot } = require("../../utils/storage-paths");

const ZIP_FILE_NAME_PATTERN = /^[a-zA-Z0-9._-]+\.zip$/;
const MAX_BACKUP_ENTRIES = Number(process.env.BACKUP_MAX_ENTRIES || 200000);
const MAX_BACKUP_UNCOMPRESSED_BYTES =
  Number(process.env.BACKUP_MAX_UNCOMPRESSED_GB || 10) * 1024 * 1024 * 1024;
const AUTO_RESTART_ON_RESTORE =
  String(process.env.BACKUP_RESTORE_AUTO_RESTART || "").toLowerCase() ===
  "true";

let activeOperation = null;



async function ensureDirectoryExists(directoryPath) {
  await fs.mkdir(directoryPath, { recursive: true });
}

async function fileExists(filePath) {
  try {
    await fs.access(filePath);
    return true;
  } catch (_) {
    return false;
  }
}

async function createBackupArchive({
  archivePath,
  dumpDirectory,
  uploadsPath,
  metadata = {},
}) {
  await ensureDirectoryExists(path.dirname(archivePath));

  return new Promise((resolve, reject) => {
    const output = fsSync.createWriteStream(archivePath);
    const archive = archiver("zip", { zlib: { level: 9 } });
    let hasError = false;

    const handleError = (error) => {
      if (!hasError) {
        hasError = true;
        logger.error("Backup archive: Creation error", {
          error: error.message,
          code: error.code,
        });
        reject(error);
      }
    };

    // Listen to output stream errors
    output.on("error", handleError);

    // Listen to archive errors
    archive.on("error", handleError);
    archive.on("warning", (warning) => {
      logger.warn("Backup archive: Warning", {
        message: warning.message,
        code: warning.code,
      });
    });

    // When the output file is fully closed and flushed
    output.on("close", () => {
      logger.info("Backup archive: Output file closed successfully");
      if (!hasError) {
        resolve();
      }
    });

    // Pipe archive to output file
    archive.pipe(output);

    logger.info("Backup archive: Adding mongo-dump directory", {
      dumpDirectory,
    });
    archive.directory(dumpDirectory, "mongo-dump");

    if (fsSync.existsSync(uploadsPath)) {
      logger.info("Backup archive: Adding uploads directory", {
        uploadsPath,
      });
      archive.directory(uploadsPath, "uploads");
    } else {
      logger.warn("Backup archive: Uploads directory not found", {
        uploadsPath,
      });
    }

    archive.append(
      JSON.stringify(
        {
          createdAt: new Date().toISOString(),
          source: "workplace-document-backend",
          version: 1,
          ...metadata,
        },
        null,
        2,
      ),
      { name: "backup-meta.json" },
    );

    logger.info("Backup archive: Finalizing archive");
    archive.finalize();
  });
}

async function extractBackupArchive({ archivePath, extractTo }) {
  await ensureDirectoryExists(extractTo);

  // Validate file exists and is not empty
  let fileStats;
  try {
    fileStats = await fs.stat(archivePath);
    if (fileStats.size === 0) {
      throw new ApiError(400, "Backup file is empty or incomplete.");
    }
    logger.info("Backup extraction: Starting", {
      archivePath,
      fileSize: fileStats.size,
      extractTo,
    });
  } catch (error) {
    if (error instanceof ApiError) throw error;
    throw new ApiError(400, "Backup file is missing or inaccessible.");
  }

  await verifyBackupArchiveIntegrity(archivePath);

  return new Promise((resolve, reject) => {
    const readStream = fsSync.createReadStream(archivePath);
    const extractStream = unzipper.Extract({ path: extractTo });
    let streamEnded = false;

    const cleanup = (error) => {
      if (streamEnded) return;
      streamEnded = true;
      readStream.destroy();
      extractStream.destroy();
      if (error) reject(error);
    };

    readStream.on("error", (error) => {
      logger.error("Backup extraction: Read stream error", {
        error: error.message,
        code: error.code,
      });
      cleanup(
        new ApiError(500, `Failed to read backup file: ${error.message}`),
      );
    });

    extractStream.on("error", (error) => {
      logger.error("Backup extraction: Unzip error", {
        error: error.message,
        code: error.code,
        errno: error.errno,
      });
      cleanup(
        new ApiError(
          400,
          `Backup file is corrupted or invalid: ${error.message}`,
        ),
      );
    });

    extractStream.on("finish", () => {
      logger.info("Backup extraction: Completed successfully");
      cleanup(null);
      resolve();
    });

    extractStream.on("close", () => {
      if (!streamEnded) {
        logger.info("Backup extraction: Stream closed (finish not called)");
        cleanup(null);
        resolve();
      }
    });

    readStream.pipe(extractStream);
  });
}

function getEntryUncompressedSize(entry) {
  return Number(
    entry.uncompressedSize ||
      entry.vars?.uncompressedSize ||
      entry.vars?.uncompressedSizeLow ||
      0,
  );
}

function assertSafeZipEntry(entry) {
  const entryPath = String(entry.path || "").replace(/\\/g, "/");
  if (!entryPath || entryPath.includes("\0")) {
    throw new ApiError(400, "Backup archive contains an invalid file path.");
  }
  if (
    path.posix.isAbsolute(entryPath) ||
    entryPath.startsWith("../") ||
    entryPath.includes("/../") ||
    entryPath === ".."
  ) {
    throw new ApiError(400, "Backup archive contains unsafe relative paths.");
  }
  if (!entryPath.startsWith("mongo-dump/") && !entryPath.startsWith("uploads/") && entryPath !== "backup-meta.json") {
    throw new ApiError(400, "Backup archive contains unsupported top-level content.");
  }
}

async function verifyBackupArchive(archivePath) {
  try {
    const directory = await unzipper.Open.file(archivePath);
    if (directory.files.length > MAX_BACKUP_ENTRIES) {
      throw new ApiError(400, "Backup archive contains too many files.");
    }
    let totalDeclaredBytes = 0;
    for (const entry of directory.files) {
      assertSafeZipEntry(entry);
      totalDeclaredBytes += getEntryUncompressedSize(entry);
      if (totalDeclaredBytes > MAX_BACKUP_UNCOMPRESSED_BYTES) {
        throw new ApiError(400, "Backup archive is too large after extraction.");
      }
    }
    const hasMongoDumpFolder = directory.files.some((entry) =>
      String(entry.path || "").startsWith("mongo-dump/")
    );
    if (!hasMongoDumpFolder) {
      throw new ApiError(400, "Backup archive is missing mongo-dump directory.");
    }
    return true;
  } catch (error) {
    if (error instanceof ApiError) {
      throw error;
    }
    throw new ApiError(
      400,
      `Backup file is corrupted or invalid: ${error.message || error}`
    );
  }
}

async function verifyBackupArchiveIntegrity(archivePath) {
  try {
    const directory = await unzipper.Open.file(archivePath);
    if (directory.files.length > MAX_BACKUP_ENTRIES) {
      throw new ApiError(400, "Backup archive contains too many files.");
    }
    const hasMongoDumpFolder = directory.files.some((entry) =>
      String(entry.path || "").startsWith("mongo-dump/")
    );
    if (!hasMongoDumpFolder) {
      throw new ApiError(400, "Backup archive is missing mongo-dump directory.");
    }

    let totalBytes = 0;
    for (const entry of directory.files) {
      assertSafeZipEntry(entry);
      const declaredBytes = getEntryUncompressedSize(entry);
      if (declaredBytes > 0) {
        totalBytes += declaredBytes;
        if (totalBytes > MAX_BACKUP_UNCOMPRESSED_BYTES) {
          throw new ApiError(400, "Backup archive is too large after extraction.");
        }
      }
      // Skip directories, only validate file entries
      if (entry.type !== "File") continue;
      const sink = new Writable({
        write(chunk, _encoding, callback) {
          if (!declaredBytes) {
            totalBytes += chunk.length;
            if (totalBytes > MAX_BACKUP_UNCOMPRESSED_BYTES) {
              callback(
                new ApiError(
                  400,
                  "Backup archive is too large after extraction.",
                ),
              );
              return;
            }
          }
          callback();
        },
      });
      await pipeline(entry.stream(), sink);
    }

    return true;
  } catch (error) {
    if (error instanceof ApiError) {
      throw error;
    }
    throw new ApiError(
      400,
      `Backup file is corrupted or invalid: ${error.message || error}`
    );
  }
}

function normalizeBackupFileName(fileName) {
  if (typeof fileName !== "string") {
    throw new ApiError(400, "backupFileName is required.");
  }
  const normalized = fileName.trim();
  if (!normalized) {
    throw new ApiError(400, "backupFileName is required.");
  }
  if (!ZIP_FILE_NAME_PATTERN.test(normalized)) {
    throw new ApiError(400, "Invalid backup file name.");
  }
  if (normalized !== path.basename(normalized)) {
    throw new ApiError(400, "Invalid backup file name.");
  }
  return normalized;
}

function resolveBackupPath(backupFileName) {
  const safeName = normalizeBackupFileName(backupFileName);
  const backupsRoot = getBackupsRoot();
  const absolutePath = path.join(backupsRoot, safeName);
  const resolvedBackupsRoot = path.resolve(backupsRoot);
  const resolvedTarget = path.resolve(absolutePath);
  if (!resolvedTarget.startsWith(`${resolvedBackupsRoot}${path.sep}`)) {
    throw new ApiError(400, "Invalid backup path.");
  }
  return { fileName: safeName, absolutePath: resolvedTarget };
}

async function copyDirectory(source, destination) {
  if (typeof fs.cp === "function") {
    await fs.cp(source, destination, { recursive: true, force: true });
    return;
  }

  await ensureDirectoryExists(destination);
  const entries = await fs.readdir(source, { withFileTypes: true });
  for (const entry of entries) {
    const sourcePath = path.join(source, entry.name);
    const destinationPath = path.join(destination, entry.name);
    if (entry.isDirectory()) {
      await copyDirectory(sourcePath, destinationPath);
      continue;
    }
    await fs.copyFile(sourcePath, destinationPath);
  }
}

async function replaceUploadsDirectory(source, destination) {
  if (!(await fileExists(source))) {
    return { restored: false, reason: "missing_source" };
  }

  await ensureDirectoryExists(path.dirname(destination));
  const rollbackPath = `${destination}.rollback-${Date.now()}-${Math.random()
    .toString(36)
    .slice(2, 8)}`;
  let hasRollback = false;

  try {
    if (await fileExists(destination)) {
      await fs.rename(destination, rollbackPath);
      hasRollback = true;
    }
    await copyDirectory(source, destination);
    if (hasRollback) {
      await fs.rm(rollbackPath, { recursive: true, force: true });
    }
    return { restored: true, rollbackUsed: hasRollback };
  } catch (error) {
    try {
      await fs.rm(destination, { recursive: true, force: true });
    } catch (_) {}
    if (hasRollback) {
      try {
        await fs.rename(rollbackPath, destination);
      } catch (rollbackError) {
        logger.error("Backup restore: Upload rollback failed", {
          destination,
          rollbackPath,
          error: rollbackError.message,
        });
      }
    }
    throw error;
  }
}

async function createSafetyBackupBeforeRestore(actor, sourceBackupFileName) {
  const timestampLabel = new Date()
    .toISOString()
    .replace(/[-:]/g, "")
    .replace(/\..+$/, "")
    .replace("T", "_");
  const backupFileName = `safety_before_restore_${timestampLabel}.zip`;
  const backupsRoot = getBackupsRoot();
  const backupPath = path.join(backupsRoot, backupFileName);
  const temporaryWorkspace = await fs.mkdtemp(
    path.join(os.tmpdir(), "workplace-backup-safety-"),
  );
  const dumpDirectory = path.join(temporaryWorkspace, "mongo-dump");

  try {
    await ensureDirectoryExists(backupsRoot);
    const databaseBackupMode = await runMongoDumpOrSnapshot(dumpDirectory);
    await createBackupArchive({
      archivePath: backupPath,
      dumpDirectory,
      uploadsPath: getUploadsRoot(),
      metadata: {
        type: "safety-before-restore",
        sourceBackupFileName,
        actorId: actor?.id || null,
      },
    });
    await verifyBackupArchiveIntegrity(backupPath);
    const stats = await fs.stat(backupPath);
    return {
      name: backupFileName,
      size: stats.size,
      createdAt: statsCreatedAt(stats),
      databaseBackupMode,
    };
  } catch (error) {
    try {
      await fs.rm(backupPath, { force: true });
    } catch (_) {}
    throw error;
  } finally {
    await fs.rm(temporaryWorkspace, { recursive: true, force: true });
  }
}

async function createInternalMongoSnapshot(dumpDirectory) {
  const db = mongoose.connection.db;
  if (!db) {
    throw new ApiError(500, "Database connection is not available.");
  }

  const collectionsDirectory = path.join(dumpDirectory, "collections");
  await ensureDirectoryExists(collectionsDirectory);

  logger.info("Backup archive: Creating internal snapshot", {
    dumpDirectory,
  });

  const collections = await db
    .listCollections({}, { nameOnly: true })
    .toArray();
  const collectionNames = collections
    .map((entry) => entry.name)
    .filter((name) => !name.startsWith("system."));

  logger.info("Backup archive: Found collections for backup", {
    count: collectionNames.length,
    collections: collectionNames,
  });

  const backedUpCollections = [];
  for (const collectionName of collectionNames) {
    try {
      const outputPath = path.join(collectionsDirectory, `${collectionName}.json`);
      const output = fsSync.createWriteStream(outputPath, { encoding: "utf8" });
      const cursor = db.collection(collectionName).find({});
      let documentCount = 0;

      logger.info("Backup archive: Backing up collection", {
        collection: collectionName,
        outputPath,
      });

      output.write("[\n");
      for await (const document of cursor) {
        if (documentCount > 0) {
          output.write(",\n");
        }
        output.write(EJSON.stringify(document, null, 2));
        documentCount += 1;
      }
      output.write("\n]");
      await new Promise((resolve, reject) => {
        output.on("error", reject);
        output.end(resolve);
      });

      backedUpCollections.push(collectionName);
      logger.info("Backup archive: Collection backed up", {
        collection: collectionName,
        documentCount,
      });
    } catch (error) {
      logger.error("Backup archive: Failed to backup collection", {
        collection: collectionName,
        error: error.message,
      });
      throw error;
    }
  }

  logger.info("Backup archive: Snapshot collections backed up", {
    backedUpCount: backedUpCollections.length,
    backedUpCollections,
  });

  await fs.writeFile(
    path.join(dumpDirectory, "collections-manifest.json"),
    JSON.stringify(
      {
        mode: "internal-json",
        collections: backedUpCollections,
        createdAt: new Date().toISOString(),
      },
      null,
      2,
    ),
    "utf8",
  );
}

async function restoreInternalMongoSnapshot(dumpDirectory) {
  const db = mongoose.connection.db;
  if (!db) {
    throw new ApiError(500, "Database connection is not available.");
  }

  const manifestPath = path.join(dumpDirectory, "collections-manifest.json");
  if (!(await fileExists(manifestPath))) {
    throw new ApiError(
      400,
      "Backup archive does not contain internal Mongo snapshot.",
    );
  }

  logger.info("Backup restore: Starting snapshot restoration", {
    manifestPath,
  });

  const manifest = JSON.parse(await fs.readFile(manifestPath, "utf8"));
  const snapshotCollections = (manifest.collections || [])
    .map(String)
    .filter((name) => name && !name.startsWith("system."));

  logger.info("Backup restore: Snapshot collections found", {
    count: snapshotCollections.length,
    collections: snapshotCollections,
  });

  const currentCollections = await db
    .listCollections({}, { nameOnly: true })
    .toArray();

  logger.info("Backup restore: Current database collections", {
    count: currentCollections.length,
    collections: currentCollections.map((c) => c.name),
  });

  for (const entry of currentCollections) {
    const collectionName = entry.name;
    if (collectionName.startsWith("system.")) {
      continue;
    }
    if (!snapshotCollections.includes(collectionName)) {
      logger.info("Backup restore: Dropping collection", {
        collection: collectionName,
      });
      try {
        await db.collection(collectionName).drop();
      } catch (_) {}
    }
  }

  for (const collectionName of snapshotCollections) {
    const collection = db.collection(collectionName);
    const sourcePath = path.join(
      dumpDirectory,
      "collections",
      `${collectionName}.json`,
    );

    let documents = [];
    if (await fileExists(sourcePath)) {
      logger.info("Backup restore: Loading collection data", {
        collection: collectionName,
        sourcePath,
      });

      const raw = await fs.readFile(sourcePath, "utf8");
      documents = EJSON.parse(raw);
      if (!Array.isArray(documents)) {
        documents = [];
      }
    }

    logger.info("Backup restore: Restoring collection", {
      collection: collectionName,
      documentCount: documents.length,
    });

    await collection.deleteMany({});
    if (documents.length) {
      await collection.insertMany(documents, { ordered: false });
    }
  }

  logger.info("Backup restore: Snapshot restoration completed successfully");
}

async function runMongoDumpOrSnapshot(dumpDirectory) {
  logger.info("Backup archive: Creating internal JSON snapshot");
  await createInternalMongoSnapshot(dumpDirectory);
  logger.info("Backup archive: Internal snapshot created successfully");
  return "internal-json";
}

async function runMongoRestoreOrSnapshot(dumpDirectory) {
  const manifestPath = path.join(dumpDirectory, "collections-manifest.json");

  logger.info("Backup restore: Checking dump directory", {
    dumpDirectory,
    hasManifest: await fileExists(manifestPath),
  });

  if (await fileExists(manifestPath)) {
    logger.info("Backup restore: Using internal JSON snapshot mode");
    await restoreInternalMongoSnapshot(dumpDirectory);
    return "internal-json";
  }

  throw new ApiError(
    400,
    "Invalid backup archive: missing collections-manifest.json",
  );
}

async function withOperationLock(operationName, operation) {
  if (activeOperation) {
    throw new ApiError(
      409,
      `Cannot start ${operationName} while "${activeOperation}" is running.`,
    );
  }

  activeOperation = operationName;
  try {
    return await operation();
  } finally {
    activeOperation = null;
  }
}

function formatBackupResult({ name, size, createdAt }) {
  return {
    name,
    size,
    createdAt,
  };
}

function statsCreatedAt(stats) {
  const createdMs = Math.max(
    Number(stats.birthtimeMs || 0),
    Number(stats.ctimeMs || 0),
    Number(stats.mtimeMs || 0),
  );
  return new Date(createdMs).toISOString();
}

async function createBackup(actor) {
  return withOperationLock("backup.create", async () => {
    const timestamp = new Date();
    const timestampLabel = timestamp
      .toISOString()
      .replace(/[-:]/g, "")
      .replace(/\..+$/, "")
      .replace("T", "_");
    const backupFileName = `backup_${timestampLabel}.zip`;
    const backupsRoot = getBackupsRoot();
    const backupPath = path.join(backupsRoot, backupFileName);
    const uploadsPath = getUploadsRoot();
    const temporaryWorkspace = await fs.mkdtemp(
      path.join(os.tmpdir(), "workplace-backup-create-"),
    );
    const dumpDirectory = path.join(temporaryWorkspace, "mongo-dump");

    try {
      await ensureDirectoryExists(backupsRoot);

      logger.info("Backup creation: Starting backup process", {
        actor: actor.id,
        backupFileName,
        temporaryWorkspace,
      });

      const databaseBackupMode = await runMongoDumpOrSnapshot(dumpDirectory);

      logger.info("Backup creation: Database backup mode selected", {
        databaseBackupMode,
      });

      await createBackupArchive({
        archivePath: backupPath,
        dumpDirectory,
        uploadsPath,
        metadata: {
          type: "manual",
          databaseBackupMode,
          actorId: actor.id,
        },
      });

      await verifyBackupArchiveIntegrity(backupPath);

      const stats = await fs.stat(backupPath);

      logger.info("Backup creation: Archive file created successfully", {
        backupFileName,
        fileSize: stats.size,
      });

      const created = formatBackupResult({
        name: backupFileName,
        size: stats.size,
        createdAt: statsCreatedAt(stats),
      });

      await logAuditEvent({
        actorId: actor.id,
        action: "admin.backup.create",
        entityType: "backup",
        entityId: backupFileName,
        payload: {
          size: stats.size,
          createdAt: created.createdAt,
          databaseBackupMode,
        },
      });

      logger.info("Backup creation: Completed successfully", {
        backupFileName,
        fileSize: stats.size,
        databaseBackupMode,
      });

      return {
        ...created,
        databaseBackupMode,
      };
    } catch (error) {
      logger.error("Backup creation: Failed", {
        actor: actor.id,
        backupFileName,
        error: error.message,
        stack: error.stack,
      });
      try {
        await fs.rm(backupPath, { force: true });
      } catch (_) {}
      throw error;
    } finally {
      logger.info("Backup creation: Cleaning up temporary workspace", {
        temporaryWorkspace,
      });
      try {
        await fs.rm(temporaryWorkspace, { recursive: true, force: true });
      } catch (cleanupError) {
        logger.warn("Backup creation: Failed to clean up temp workspace", {
          temporaryWorkspace,
          error: cleanupError.message,
        });
      }
    }
  });
}

async function listBackups() {
  const backupsRoot = getBackupsRoot();
  await ensureDirectoryExists(backupsRoot);
  const entries = await fs.readdir(backupsRoot, { withFileTypes: true });
  const backups = await Promise.all(
    entries
      .filter(
        (entry) => entry.isFile() && ZIP_FILE_NAME_PATTERN.test(entry.name),
      )
      .map(async (entry) => {
        const backupPath = path.join(backupsRoot, entry.name);
        const stats = await fs.stat(backupPath);
        return formatBackupResult({
          name: entry.name,
          size: stats.size,
          createdAt: statsCreatedAt(stats),
        });
      }),
  );

  backups.sort(
    (a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime(),
  );
  return backups;
}

async function inspectBackupArchive(backupFileName) {
  const { fileName, absolutePath } = resolveBackupPath(backupFileName);
  if (!(await fileExists(absolutePath))) {
    throw new ApiError(404, "Backup file not found.");
  }
  await verifyBackupArchive(absolutePath);
  const directory = await unzipper.Open.file(absolutePath);
  let metadata = null;
  let declaredBytes = 0;
  let fileCount = 0;
  let hasUploads = false;
  let hasInternalSnapshot = false;

  for (const entry of directory.files) {
    assertSafeZipEntry(entry);
    if (entry.type === "File") {
      fileCount += 1;
    }
    declaredBytes += getEntryUncompressedSize(entry);
    const entryPath = String(entry.path || "");
    if (entryPath.startsWith("uploads/")) {
      hasUploads = true;
    }
    if (entryPath === "mongo-dump/collections-manifest.json") {
      hasInternalSnapshot = true;
    }
    if (entryPath === "backup-meta.json" && entry.type === "File") {
      try {
        const chunks = [];
        await pipeline(
          entry.stream(),
          new Writable({
            write(chunk, _encoding, callback) {
              chunks.push(chunk);
              callback();
            },
          }),
        );
        metadata = JSON.parse(Buffer.concat(chunks).toString("utf8"));
      } catch (_) {
        metadata = null;
      }
    }
  }

  const stats = await fs.stat(absolutePath);
  return {
    name: fileName,
    size: stats.size,
    createdAt: statsCreatedAt(stats),
    fileCount,
    declaredUncompressedBytes: declaredBytes,
    hasInternalSnapshot,
    hasUploads,
    metadata,
  };
}

async function restoreBackup(
  actor,
  { backupFileName, confirmRestore, createSafetyBackup = true },
) {
  if (confirmRestore !== true) {
    throw new ApiError(
      400,
      "Restore requires explicit confirmation. Set confirmRestore=true.",
    );
  }

  return withOperationLock("backup.restore", async () => {
    const { fileName, absolutePath } = resolveBackupPath(backupFileName);
    if (!(await fileExists(absolutePath))) {
      throw new ApiError(404, "Backup file not found.");
    }

    logger.info("Backup restore: Starting", {
      backupFileName: fileName,
      actor: actor?.id || "emergency",
    });

    const temporaryWorkspace = await fs.mkdtemp(
      path.join(os.tmpdir(), "workplace-backup-restore-"),
    );
    const extractDirectory = path.join(temporaryWorkspace, "extracted");

    let safetyBackup = null;
    try {
      await extractBackupArchive({
        archivePath: absolutePath,
        extractTo: extractDirectory,
      });

      const dumpDirectory = path.join(extractDirectory, "mongo-dump");
      if (!(await fileExists(dumpDirectory))) {
        throw new ApiError(
          400,
          "Backup archive does not contain MongoDB dump.",
        );
      }

      if (backupPreRestoreSnapshot && createSafetyBackup) {
        logger.info("Backup restore: Creating safety backup before restore", {
          backupFileName: fileName,
        });
        safetyBackup = await createSafetyBackupBeforeRestore(actor, fileName);
        logger.info("Backup restore: Safety backup created", {
          safetyBackup,
        });
      }

      const restoreMode = await runMongoRestoreOrSnapshot(dumpDirectory);

      const extractedUploads = path.join(extractDirectory, "uploads");
      const targetUploads = getUploadsRoot();
      let uploadsRestore = { restored: false, reason: "missing_source" };
      if (await fileExists(extractedUploads)) {
        uploadsRestore = await replaceUploadsDirectory(extractedUploads, targetUploads);
      }

      if (actor?.id) {
        await logAuditEvent({
          actorId: actor.id,
          action: "admin.backup.restore",
          entityType: "backup",
          entityId: fileName,
          payload: {
            restoredAt: new Date().toISOString(),
            autoRestartScheduled: AUTO_RESTART_ON_RESTORE,
            restoreMode,
            uploadsRestore,
            safetyBackup,
          },
        }).catch((auditError) => {
          logger.warn("Backup restore: Audit log failed", {
            error: auditError.message,
          });
        });
      }

      logger.info("Backup restore: Completed successfully", {
        backupFileName: fileName,
        restoreMode,
        uploadsRestore,
        safetyBackup,
        autoRestartScheduled: AUTO_RESTART_ON_RESTORE,
      });

      if (AUTO_RESTART_ON_RESTORE) {
        setTimeout(() => {
          process.exit(0);
        }, 1500);
      }

      return {
        restored: true,
        backupFileName: fileName,
        autoRestartScheduled: AUTO_RESTART_ON_RESTORE,
        restoreMode,
        uploadsRestore,
        safetyBackup,
      };
    } catch (error) {
      logger.error("Backup restore: Failed", {
        backupFileName: fileName,
        actor: actor?.id || "emergency",
        error: error.message,
        code: error.code,
        status: error.status,
        safetyBackup,
      });
      throw error;
    } finally {
      await fs.rm(temporaryWorkspace, { recursive: true, force: true });
    }
  });
}

async function deleteBackup(actor, backupFileName) {
  return withOperationLock("backup.delete", async () => {
    const { fileName, absolutePath } = resolveBackupPath(backupFileName);
    if (!(await fileExists(absolutePath))) {
      throw new ApiError(404, "Backup file not found.");
    }

    await fs.rm(absolutePath, { force: true });

    await logAuditEvent({
      actorId: actor.id,
      action: "admin.backup.delete",
      entityType: "backup",
      entityId: fileName,
      payload: {
        deletedAt: new Date().toISOString(),
      },
    });

    return { deleted: true, backupFileName: fileName };
  });
}

async function getBackupForDownload(backupFileName) {
  const { fileName, absolutePath } = resolveBackupPath(backupFileName);
  if (!(await fileExists(absolutePath))) {
    throw new ApiError(404, "Backup file not found.");
  }
  return { fileName, absolutePath };
}

module.exports = {
  createBackup,
  listBackups,
  restoreBackup,
  deleteBackup,
  getBackupForDownload,
  inspectBackupArchive,
  verifyBackupArchive,
  verifyBackupArchiveIntegrity,
};
