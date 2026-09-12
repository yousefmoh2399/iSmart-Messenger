const Branch = require("../models/branch.model");
const Department = require("../models/department.model");
const logger = require("../../utils/logger");

async function dropIndexIfExists(collection, indexName) {
  try {
    const indexes = await collection.indexes();
    if (!indexes.some((entry) => entry?.name === indexName)) {
      return false;
    }
    await collection.dropIndex(indexName);
    return true;
  } catch (_) {
    return false;
  }
}

async function syncModelIndexes(model, label) {
  try {
    await model.syncIndexes();
    logger.info("directory.indexes.synced", { model: label });
  } catch (error) {
    logger.warn("directory.indexes.sync_failed", {
      model: label,
      message: error?.message || String(error),
    });
  }
}

async function ensureDirectoryIndexes() {
  await dropIndexIfExists(Branch.collection, "code_1");
  await dropIndexIfExists(Department.collection, "code_1");

  await syncModelIndexes(Branch, "Branch");
  await syncModelIndexes(Department, "Department");
}

module.exports = {
  ensureDirectoryIndexes,
};
