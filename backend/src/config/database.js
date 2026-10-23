const mongoose = require("mongoose");
const { mongodbUri } = require("./env");

mongoose.set("bufferCommands", true);

async function connectDatabase() {
  await mongoose.connect(mongodbUri, {
    serverSelectionTimeoutMS: 8000,
    maxPoolSize: 100,
    minPoolSize: 10,
    socketTimeoutMS: 45000,
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
