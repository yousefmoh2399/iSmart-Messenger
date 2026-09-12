const mongoose = require("mongoose");
const { mongodbUri } = require("./env");

mongoose.set("bufferCommands", false);

async function connectDatabase() {
  await mongoose.connect(mongodbUri, {
    serverSelectionTimeoutMS: 5000,
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
