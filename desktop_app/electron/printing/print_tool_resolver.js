const fs = require("fs");
const path = require("path");
const { exec } = require("child_process");

function createPrintToolResolver({
  fsOverride,
  pathOverride,
  execOverride,
  appResourcesPath,
  envOverride
} = {}) {
  const _fs = fsOverride || fs;
  const _path = pathOverride || path;
  const _exec = execOverride || exec;
  const _env = envOverride || process.env;

  function findExecutableOnPath(executableName) {
    return new Promise((resolve) => {
      if (process.platform !== "win32") {
        resolve(null);
        return;
      }
      _exec(`where ${executableName}`, (err, stdout) => {
        if (err || !stdout) {
          resolve(null);
          return;
        }
        const lines = stdout.split("\r\n").map(l => l.trim()).filter(Boolean);
        for (const line of lines) {
          if (_fs.existsSync(line)) {
            resolve(line);
            return;
          }
        }
        resolve(null);
      });
    });
  }

  async function resolvePdfPrintTool(options = {}) {
    if (process.platform !== "win32") {
      return null;
    }

    // 1. SumatraPDF المرفق أولًا
    const resourcesPath = appResourcesPath || process.resourcesPath;
    if (resourcesPath) {
      const bundledPath = _path.join(resourcesPath, 'tools', 'sumatra', 'SumatraPDF.exe');
      if (_fs.existsSync(bundledPath)) {
        return { tool: "SumatraPDF", path: bundledPath };
      }
    }

    // 2. SumatraPDF المثبت في المسارات الشائعة
    const localAppData = _env.LOCALAPPDATA;
    const programFiles = _env.ProgramFiles;
    const programFilesX86 = _env["ProgramFiles(x86)"];

    const sumatraCandidates = [];
    if (programFiles) {
      sumatraCandidates.push(_path.join(programFiles, "SumatraPDF", "SumatraPDF.exe"));
    }
    if (programFilesX86) {
      sumatraCandidates.push(_path.join(programFilesX86, "SumatraPDF", "SumatraPDF.exe"));
    }
    if (localAppData) {
      sumatraCandidates.push(_path.join(localAppData, "SumatraPDF", "SumatraPDF.exe"));
    }

    for (const candidate of sumatraCandidates) {
      if (_fs.existsSync(candidate)) {
        return { tool: "SumatraPDF", path: candidate };
      }
    }

    // 3. SumatraPDF في الـ PATH
    const pathSumatra = await findExecutableOnPath("SumatraPDF.exe");
    if (pathSumatra) {
      return { tool: "SumatraPDF", path: pathSumatra };
    }

    // 4. Adobe Reader DC (إن لم يكن معطلاً)
    if (options.disableAdobeFallback !== true) {
      const acrobatCandidates = [];
      if (programFiles) {
        acrobatCandidates.push(_path.join(programFiles, "Adobe", "Acrobat Reader DC", "Reader", "AcroRd32.exe"));
      }
      if (programFilesX86) {
        acrobatCandidates.push(_path.join(programFilesX86, "Adobe", "Acrobat Reader DC", "Reader", "AcroRd32.exe"));
      }

      for (const candidate of acrobatCandidates) {
        if (_fs.existsSync(candidate)) {
          return { tool: "AdobeReader", path: candidate };
        }
      }

      const pathAcrobat = await findExecutableOnPath("AcroRd32.exe");
      if (pathAcrobat) {
        return { tool: "AdobeReader", path: pathAcrobat };
      }
    }

    return null;
  }

  return {
    resolvePdfPrintTool,
    findExecutableOnPath
  };
}

module.exports = {
  createPrintToolResolver
};
