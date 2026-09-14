const path = require("path");
const PDFDocument = require("pdfkit");
const logo1 = path.join(__dirname, "../../assets/logo1.jpg");
const doc = new PDFDocument();
try { doc.image(logo1, 0, 0); console.log("Success"); } catch (e) { console.error("Error:", e.message); }
