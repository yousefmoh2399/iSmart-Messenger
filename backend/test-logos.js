const PDFDocument = require('pdfkit');
const fs = require('fs');
const doc = new PDFDocument();
doc.pipe(fs.createWriteStream('test-logos.pdf'));
doc.image('g:/iSmart-Messenger-Full/backend/src/assets/logo1.jpg', 0, 0, {width: 100});
doc.image('g:/iSmart-Messenger-Full/backend/src/assets/logo2.jpg', 150, 0, {width: 100});
doc.end();
