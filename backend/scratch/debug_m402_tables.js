const mongoose = require("mongoose");
const path = require("path");
require("dotenv").config({ path: path.join(__dirname, "../.env") });

const PrinterSchema = new mongoose.Schema({}, { strict: false });
const Printer = mongoose.model("Printer", PrinterSchema);

async function run() {
  await mongoose.connect(process.env.MONGODB_URI || "mongodb://127.0.0.1:27017/workplace_documents");
  const pr = await Printer.findOne({ model: /M402/i }).lean();
  if (!pr) {
    console.log("No M402 printer found");
    return;
  }
  
  console.log("=== RAW KEY VALUES ===");
  pr.extendedDetails.rawKeyValues.forEach(kv => {
    if (kv.key.includes("%") || kv.value.includes("%") || kv.key.toLowerCase().includes("black") || kv.value.toLowerCase().includes("black") || kv.key.toLowerCase().includes("cartridge") || kv.value.toLowerCase().includes("cartridge") || kv.key.toLowerCase().includes("toner") || kv.value.toLowerCase().includes("toner")) {
      console.log(`${kv.key} => ${kv.value}`);
    }
  });

  console.log("\n=== SUPPLIES STRUCTURED ===");
  console.log(JSON.stringify(pr.extendedDetails.supplies, null, 2));

  await mongoose.disconnect();
}

run().catch(console.error);
