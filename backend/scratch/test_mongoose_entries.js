const mongoose = require("mongoose");
const path = require("path");
require("dotenv").config({ path: path.join(__dirname, "../.env") });

const Printer = require("../src/printers/models/printer.model");

async function run() {
  await mongoose.connect(process.env.MONGODB_URI || "mongodb://127.0.0.1:27017/workplace_documents");
  const pr = await Printer.findOne({ model: /M404/i });
  if (!pr) {
    console.log("No printer found");
    await mongoose.disconnect();
    return;
  }

  console.log("Type of tonerLevels:", typeof pr.tonerLevels, pr.tonerLevels.constructor.name);
  console.log("Object.entries(pr.tonerLevels):", Object.entries(pr.tonerLevels));
  console.log("Object.entries(pr.tonerLevels.toObject()):", Object.entries(pr.tonerLevels.toObject()));
  
  await mongoose.disconnect();
}

run().catch(console.error);
