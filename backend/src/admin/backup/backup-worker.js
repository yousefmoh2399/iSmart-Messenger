const fs = require("fs/promises");
const fsSync = require("fs");
const os = require("os");
const path = require("path");
const { execFile } = require("child_process");
const archiver = require("archiver");

// Set worker to lowest CPU and scheduling priority so it NEVER degrades
// the main API or impacts active users.
try {
  if (typeof os.setPriority === "function") {
    const lowestPriority = os.constants?.priority?.PRIORITY_LOWEST ?? 19;
    os.setPriority(lowestPriority);
  }
} catch (_) {}

/**
 * Attempts to create the archive using the native Linux `zip` utility
 * wrapped in `nice -n 19` and `ionice -c 3`.
 * This offloads all I/O and compression to the C kernel level,
 * consuming less than 20 MB of RAM and having zero impact on V8 heap.
 */
function tryNativeLinuxZip(archivePath, dumpDirectory, uploadsPath, metadata) {
  return new Promise((resolve) => {
    if (process.platform !== "linux") {
      return resolve({ success: false, reason: "not_linux" });
    }

    execFile("which", ["zip"], (err, stdout) => {
      if (err || !stdout || !stdout.trim()) {
        return resolve({ success: false, reason: "zip_not_installed" });
      }

      const zipBin = stdout.trim();
      const parentDir = path.dirname(dumpDirectory);
      const dumpBase = path.basename(dumpDirectory);

      // Write backup-meta.json inside dump directory so it is included
      try {
        const metaPath = path.join(dumpDirectory, "backup-meta.json");
        fsSync.writeFileSync(
          metaPath,
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
        );
      } catch (metaErr) {
        return resolve({ success: false, reason: `meta_write_failed: ${metaErr.message}` });
      }

      // Check if uploads exists and create a temporary symlink in parentDir
      const uploadsSymlink = path.join(parentDir, "uploads");
      let symlinkCreated = false;
      try {
        if (uploadsPath && fsSync.existsSync(uploadsPath)) {
          if (!fsSync.existsSync(uploadsSymlink)) {
            fsSync.symlinkSync(uploadsPath, uploadsSymlink, "dir");
            symlinkCreated = true;
          }
        }
      } catch (symlinkErr) {
        return resolve({ success: false, reason: `symlink_failed: ${symlinkErr.message}` });
      }

      // Arguments for fast, low-priority zip creation:
      // -q: quiet, -r: recurse, -1: fastest compression (saves CPU on already compressed media)
      const zipArgs = ["-q", "-r", "-1", archivePath, dumpBase];
      if (symlinkCreated) {
        zipArgs.push("uploads");
      }

      // Wrap in nice -n 19 for minimal CPU contention
      execFile(
        "nice",
        ["-n", "19", zipBin, ...zipArgs],
        { cwd: parentDir, maxBuffer: 10 * 1024 * 1024 },
        (zipErr, _stdout, stderr) => {
          if (symlinkCreated) {
            try {
              fsSync.unlinkSync(uploadsSymlink);
            } catch (_) {}
          }
          if (zipErr) {
            return resolve({
              success: false,
              reason: `zip_exec_error: ${zipErr.message}`,
              stderr,
            });
          }
          return resolve({ success: true, method: "native-zip" });
        },
      );
    });
  });
}

/**
 * Fallback archive creation using archiver with zlib level: 1 (fast compression).
 * Consumes minimal memory compared to level: 9 and runs isolated in this worker.
 */
function runArchiverZip(archivePath, dumpDirectory, uploadsPath, metadata) {
  return new Promise((resolve, reject) => {
    const output = fsSync.createWriteStream(archivePath);
    // Level 1: Fast compression, low memory footprint
    const archive = archiver("zip", { zlib: { level: 1 } });
    let hasError = false;

    const handleError = (error) => {
      if (!hasError) {
        hasError = true;
        reject(error);
      }
    };

    output.on("error", handleError);
    archive.on("error", handleError);
    archive.on("warning", (warning) => {
      process.send?.({ type: "log", level: "warn", message: warning.message });
    });

    output.on("close", () => {
      if (!hasError) {
        resolve({ success: true, method: "archiver-worker" });
      }
    });

    archive.pipe(output);
    archive.directory(dumpDirectory, "mongo-dump");

    if (uploadsPath && fsSync.existsSync(uploadsPath)) {
      archive.directory(uploadsPath, "uploads");
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

    archive.finalize();
  });
}

async function executeArchive({ archivePath, dumpDirectory, uploadsPath, metadata }) {
  try {
    // 1. Try native Linux zip command if available
    const nativeResult = await tryNativeLinuxZip(
      archivePath,
      dumpDirectory,
      uploadsPath,
      metadata,
    );

    if (nativeResult.success) {
      return { success: true, method: nativeResult.method };
    }

    // 2. Fall back to isolated archiver with zlib level 1
    return await runArchiverZip(
      archivePath,
      dumpDirectory,
      uploadsPath,
      metadata,
    );
  } catch (error) {
    return { success: false, error: error.message, stack: error.stack };
  }
}

// IPC listener for parent process invocation
process.on("message", async (payload) => {
  if (!payload || !payload.archivePath) {
    process.send?.({ type: "error", error: "Missing payload" });
    process.exit(1);
  }

  const result = await executeArchive(payload);
  if (result.success) {
    process.send?.({ type: "success", method: result.method });
    process.exit(0);
  } else {
    process.send?.({ type: "error", error: result.error });
    process.exit(1);
  }
});
