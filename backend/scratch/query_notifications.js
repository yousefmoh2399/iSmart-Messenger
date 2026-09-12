const mongoose = require("mongoose");
const path = require("path");
require("dotenv").config({ path: path.join(__dirname, "../.env") });

const NotificationSchema = new mongoose.Schema({}, { strict: false });
const PrinterNotification = mongoose.model("PrinterNotification", NotificationSchema, "printernotifications");

async function run() {
  await mongoose.connect(process.env.MONGODB_URI || "mongodb://127.0.0.1:27017/workplace_documents");
  console.log("Connected to MongoDB");

  const notifs = await PrinterNotification.find({}).lean();
  console.log(`Total notifications in database: ${notifs.length}`);
  notifs.forEach(n => {
    console.log(`- [${n.createdAt}] Type: ${n.type}, Severity: ${n.severity}, Title: ${n.title}, Message: ${n.message}, readAt: ${n.readAt}`);
  });

  await mongoose.disconnect();
}

run().catch(console.error);
