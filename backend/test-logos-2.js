const PDFDocument = require('pdfkit');
const fs = require('fs');

const doc = new PDFDocument();
doc.pipe(fs.createWriteStream('test-logos-2.pdf'));
const logo1Path = 'g:/iSmart-Messenger-Full/backend/src/assets/logo1.jpg';
const logo1 = fs.readFileSync(logo1Path);
try {
  doc.image(logo1, 30, 30, { width: 80 });
  console.log('Logo 1 added successfully');
} catch (e) {
  console.error('Error adding logo 1:', e);
}

const logo2Path = 'g:/iSmart-Messenger-Full/backend/src/assets/logo2.jpg';
const logo2 = fs.readFileSync(logo2Path);
try {
  doc.image(logo2, 700, 30, { width: 80 });
  console.log('Logo 2 added successfully');
} catch (e) {
  console.error('Error adding logo 2:', e);
}
doc.end();
