const mongoose = require("mongoose");
const path = require("path");
require("dotenv").config({ path: path.join(__dirname, "../.env") });

const PrinterSchema = new mongoose.Schema({}, { strict: false });
const Printer = mongoose.model("Printer", PrinterSchema);

async function run() {
  await mongoose.connect(process.env.MONGODB_URI || "mongodb://127.0.0.1:27017/workplace_documents");
  console.log("Connected to MongoDB");

  const pr = await Printer.findOne({ model: /M402/i }).lean();
  if (!pr) {
    console.log("No M402 printer found");
  } else {
    console.log(JSON.stringify(pr, null, 2));
  }

  await mongoose.disconnect();
}

run().catch(console.error);
