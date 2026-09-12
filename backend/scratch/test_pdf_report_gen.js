const mongoose = require("mongoose");
const fs = require("fs");
const path = require("path");
const { buildPrinterPdfReport } = require("../src/printers/services/printer-report.service");
const PrinterBranch = require("../src/printers/models/printer-branch.model");
const Printer = require("../src/printers/models/printer.model");

async function run() {
  const uri = "mongodb://127.0.0.1:27017/workplace_documents";
  console.log("Connecting to MongoDB...");
  await mongoose.connect(uri);
  console.log("Connected.");

  const printer = await Printer.findOne({ deletedAt: null }).populate("branchId");
  if (!printer) {
    console.log("No printer found in the database!");
    await mongoose.disconnect();
    return;
  }

  console.log(`Generating report for printer: ${printer.printerName} (${printer.ipAddress})`);
  
  // We mock a list of snapshots
  const snapshots = [
    {
      snapshotAt: new Date(),
      counters: printer.counters,
      lifetimeCounters: printer.lifetimeCounters,
      tonerLevels: printer.tonerLevels,
      maintenance: printer.maintenance,
      status: printer.status
    }
  ];

  try {
    const report = await buildPrinterPdfReport({
      printer,
      snapshots,
      actor: { id: new mongoose.Types.ObjectId().toString() }
    });
    
    const outputPath = path.join(__dirname, "test_report_gen.pdf");
    fs.writeFileSync(outputPath, report.buffer);
    console.log(`Successfully generated PDF report at: ${outputPath}`);
  } catch (err) {
    console.error("PDF generation failed:", err);
  } finally {
    await mongoose.disconnect();
  }
}

run();
