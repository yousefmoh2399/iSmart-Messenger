const mongoose = require("mongoose");
const { mongodbUri, env } = require("./env");
const logger = require("../utils/logger");

mongoose.set("bufferCommands", false);

let listenersAttached = false;

function attachConnectionListeners() {
  if (listenersAttached) return;
  listenersAttached = true;

  const conn = mongoose.connection;
  conn.on("connected", () => {
    logger.info("mongodb.connected", {
      host: conn.host,
      port: conn.port,
      name: conn.name,
    });
  });
  conn.on("reconnected", () => {
    logger.info("mongodb.reconnected", {
      host: conn.host,
      port: conn.port,
    });
  });
  conn.on("disconnected", () => {
    logger.warn("mongodb.disconnected");
  });
  conn.on("error", (err) => {
    logger.error("mongodb.error", {
      errorName: err?.name,
      errorMessage: err?.message,
    });
  });
  conn.on("fullsetup", () => {
    logger.info("mongodb.replica_set.fullsetup");
  });
}

async function connectDatabase() {
  attachConnectionListeners();

  const isReplicaSetUri =
    /replicaSet=/i.test(mongodbUri) || mongodbUri.includes(",");
  const writeConcernW =
    process.env.MONGO_WRITE_CONCERN ||
    (isReplicaSetUri || env === "production" ? "majority" : 1);

  await mongoose.connect(mongodbUri, {
    serverSelectionTimeoutMS: Number(
      process.env.MONGO_SERVER_SELECTION_TIMEOUT_MS || 5000
    ),
    socketTimeoutMS: Number(process.env.MONGO_SOCKET_TIMEOUT_MS || 45000),
    heartbeatFrequencyMS: Number(
      process.env.MONGO_HEARTBEAT_FREQUENCY_MS || 5000
    ),
    maxPoolSize: Number(process.env.MONGO_MAX_POOL_SIZE || 25),
    minPoolSize: Number(process.env.MONGO_MIN_POOL_SIZE || 2),
    retryWrites: true,
    retryReads: true,
    w: writeConcernW,
    journal: true,
    readPreference: process.env.MONGO_READ_PREFERENCE || "primaryPreferred",
  });
}

function getDatabaseStatus() {
  switch (mongoose.connection.readyState) {
    case 0:
      return "disconnected";
    case 1:
      return "connected";
    case 2:
      return "connecting";
    case 3:
      return "disconnecting";
    default:
      return "unknown";
  }
}

module.exports = {
  connectDatabase,
  getDatabaseStatus,
};
