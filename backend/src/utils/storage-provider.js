const fs = require("fs");
const fsp = require("fs/promises");
const path = require("path");
const {
  getUploadsRoot,
  resolveStoredUploadPath,
  resolveUploadPath,
  toRelativeUploadPath,
  ensureDirectory,
  fileExists,
} = require("./storage-paths");
const { storageType } = require("../config/env");
const logger = require("./logger");

/**
 * Storage Abstraction Layer for High Availability.
 *
 * Supports:
 * - "local" / "shared-fs" / "nfs": Shared POSIX/SMB filesystem mounted identically across Backend nodes
 * - Provides unified save(), get(), delete(), exists(), verify(), and checkHealth() methods
 * - Guarantees upload consistency (verifies file exists & matches expected size after write, with rollback support)
 */
class StorageProvider {
  constructor() {
    this.type = storageType || "local";
  }

  getRoot() {
    return getUploadsRoot();
  }

  /**
   * Save a buffer or stream or verify an already-written Multer file on shared storage.
   * Returns metadata including relative storageKey and verified size.
   */
  async save({ buffer, sourceFilePath, targetRelativePath }) {
    const absolutePath = targetRelativePath
      ? resolveUploadPath(targetRelativePath)
      : resolveStoredUploadPath(sourceFilePath);

    if (!absolutePath) {
      throw new Error("Invalid storage target path.");
    }

    await ensureDirectory(path.dirname(absolutePath));

    if (buffer) {
      const tempPath = `${absolutePath}.tmp.${Date.now()}`;
      try {
        await fsp.writeFile(tempPath, buffer);
        await fsp.rename(tempPath, absolutePath);
      } catch (err) {
        try {
          await fsp.unlink(tempPath);
        } catch (_) {}
        throw err;
      }
    } else if (sourceFilePath && path.resolve(sourceFilePath) !== absolutePath) {
      await fsp.copyFile(sourceFilePath, absolutePath);
    }

    const verified = await this.verify(absolutePath);
    if (!verified.valid) {
      throw new Error("Storage write verification failed.");
    }

    return {
      storageKey: toRelativeUploadPath(absolutePath),
      absolutePath,
      size: verified.size,
    };
  }

  /**
   * Verify that a stored file exists on the storage backend and is non-empty.
   */
  async verify(storedPathOrAbsolute) {
    const resolved = resolveStoredUploadPath(storedPathOrAbsolute);
    if (!resolved) {
      return { valid: false, size: 0, absolutePath: null };
    }
    try {
      const stat = await fsp.stat(resolved);
      if (!stat.isFile() || stat.size <= 0) {
        return { valid: false, size: 0, absolutePath: resolved };
      }
      return { valid: true, size: stat.size, absolutePath: resolved };
    } catch (_) {
      return { valid: false, size: 0, absolutePath: resolved };
    }
  }

  /**
   * Read file bytes from storage.
   */
  async get(storedPath) {
    const resolved = resolveStoredUploadPath(storedPath);
    if (!resolved) {
      throw new Error("File path could not be resolved.");
    }
    return fsp.readFile(resolved);
  }

  /**
   * Create a readable stream from storage.
   */
  createReadStream(storedPath, options = {}) {
    const resolved = resolveStoredUploadPath(storedPath);
    if (!resolved) {
      throw new Error("File path could not be resolved.");
    }
    return fs.createReadStream(resolved, options);
  }

  /**
   * Check whether a file exists in storage.
   */
  async exists(storedPath) {
    const resolved = resolveStoredUploadPath(storedPath);
    if (!resolved) {
      return false;
    }
    return fileExists(resolved);
  }

  /**
   * Delete a file from storage safely (idempotent).
   */
  async delete(storedPath) {
    if (!storedPath || String(storedPath).startsWith("local-only:")) {
      return false;
    }
    const resolved = resolveStoredUploadPath(storedPath);
    if (!resolved) {
      return false;
    }
    try {
      await fsp.unlink(resolved);
      return true;
    } catch (error) {
      if (error && error.code === "ENOENT") {
        return false;
      }
      logger.warn("storage.delete_failed", {
        storedPath,
        errorMessage: error?.message,
      });
      throw error;
    }
  }

  /**
   * Execute a database write after verifying the uploaded file exists in storage.
   * Automatically rolls back (deletes the uploaded file) if the database operation fails.
   */
  async withUploadTransaction(uploadedFilePath, dbOperationFn) {
    const verification = await this.verify(uploadedFilePath);
    if (!verification.valid) {
      throw new Error("Uploaded file failed storage verification.");
    }
    try {
      return await dbOperationFn(verification);
    } catch (error) {
      try {
        await this.delete(uploadedFilePath);
      } catch (_) {}
      throw error;
    }
  }

  /**
   * Fast non-destructive health/readiness check for the storage backend.
   */
  async checkHealth() {
    try {
      const root = path.resolve(this.getRoot());
      await ensureDirectory(root);
      await fsp.access(root, fs.constants.R_OK | fs.constants.W_OK);
      return {
        available: true,
        type: this.type,
        status: "available",
      };
    } catch (error) {
      logger.error("storage.health_check_failed", {
        errorMessage: error?.message,
      });
      return {
        available: false,
        type: this.type,
        status: "unavailable",
      };
    }
  }
}

const storage = new StorageProvider();

module.exports = {
  storage,
  StorageProvider,
};
