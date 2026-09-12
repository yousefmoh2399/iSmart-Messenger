const { probePrinter } = require("../src/printers/services/snmp-printer.service");

async function run() {
  console.log("Probing printer 192.168.10.11...");
  try {
    const printer = await probePrinter("192.168.10.11", { skipWebDetails: true });
    console.log("Success! Returned printer payload:");
    console.log(JSON.stringify(printer, null, 2));
  } catch (err) {
    console.error("Probe failed:", err);
  }
}

run();
