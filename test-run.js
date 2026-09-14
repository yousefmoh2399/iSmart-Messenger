const { exportCustomReport } = require('./backend/src/printers/services/printer-custom-reports.service.js');
const fs = require('fs');

async function test() {
  const actor = { id: 'admin', role: 'admin' };
  const res = await exportCustomReport(actor, { type: 'global', format: 'pdf' });
  fs.writeFileSync('test-report.pdf', res.buffer);
  console.log('PDF saved to test-report.pdf');
}
test().catch(console.error);
