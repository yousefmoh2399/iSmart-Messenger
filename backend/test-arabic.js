const PDFDocument = require('pdfkit');
const fs = require('fs');

const doc = new PDFDocument();
doc.pipe(fs.createWriteStream('test-arabic.pdf'));
doc.registerFont('Arabic', 'g:/iSmart-Messenger-Full/backend/src/assets/fonts/NotoSansArabic-Regular.ttf');
doc.font('Arabic').fontSize(16);
doc.text('??????? ??????', 100, 100);
doc.text('??? ??????? (????)', 100, 130);
doc.end();
