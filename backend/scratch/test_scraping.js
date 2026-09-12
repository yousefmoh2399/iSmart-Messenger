const { collectPrinterWebDetails } = require("../src/printers/services/printer-web-detail.service");

async function run() {
  console.log("Starting scraping for 192.168.10.11...");
  const details = await collectPrinterWebDetails("192.168.10.11");
  console.log("Scraped details:");
  console.log(JSON.stringify(details, null, 2));
}

run();
