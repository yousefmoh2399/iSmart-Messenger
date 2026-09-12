const fs = require("fs");
const path = require("path");

/**
 * Returns the path to a bundled executable if it exists next to the binary,
 * otherwise returns the executable name to rely on the system PATH.
 */
function getBundledExecutable(name) {
  const executableName = process.platform === "win32" ? `${name}.exe` : name;
  
  // If we are running from a pkg binary, process.execPath is the path to the executable.
  // Otherwise, it's the node binary.
  // If we are bundled, we expect a "bin" folder next to the executable or in the project root.
  
  let searchPaths = [];
  
  if (process.pkg) {
    const execDir = path.dirname(process.execPath);
    searchPaths.push(path.join(execDir, "bin", executableName));
  } else {
    // Development mode
    searchPaths.push(path.join(__dirname, "../../bin", executableName));
  }

  // Also check DATA_DIR/bin as a fallback for user-provided binaries
  const envConfig = require("../config/env");
  if (envConfig.DATA_DIR) {
    searchPaths.push(path.join(envConfig.DATA_DIR, "bin", executableName));
  }

  for (const checkPath of searchPaths) {
    if (fs.existsSync(checkPath)) {
      console.log(`[EXECUTABLE_RESOLVER] Resolved bundled executable ${name} to: ${checkPath}`);
      return checkPath;
    }
  }

  console.log(`[EXECUTABLE_RESOLVER] Bundled executable ${name} not found in bin/ folders. Falling back to system PATH: ${executableName}`);
  return executableName;
}

module.exports = {
  getBundledExecutable,
};
