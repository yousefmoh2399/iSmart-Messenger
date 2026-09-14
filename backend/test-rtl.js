const PDFDocument = require('pdfkit');
const fs = require('fs');
const doc = new PDFDocument();
doc.pipe(fs.createWriteStream('test-rtl.pdf'));
doc.registerFont('Amiri', 'g:/iSmart-Messenger-Full/backend/src/assets/fonts/Amiri-Regular.ttf');
doc.font('Amiri').fontSize(16);
doc.text('????? ???? ???????', 100, 100, { features: ['rtla'] });
doc.text('????? ???? ???????', 100, 130);
doc.end();
