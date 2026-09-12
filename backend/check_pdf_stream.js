const fs = require("fs");
const path = require("path");

function checkPdf() {
  const pdfPath = path.join(__dirname, "scratch/test_render.pdf");
  const data = fs.readFileSync(pdfPath, "utf8");
  
  // Find all TJ or Tj lines
  const regex = /\(([^)]+)\)\s*Tj|\[([^\]]+)\]\s*TJ/g;
  let match;
  console.log("Found text elements in PDF:");
  while ((match = regex.exec(data)) !== null) {
    if (match[1]) {
      console.log("Tj:", match[1]);
    } else if (match[2]) {
      console.log("TJ:", match[2]);
    }
  }
  
  // Also look for hex strings like <fe97...> Tj
  const hexRegex = /<([0-9a-fA-F]+)>\s*Tj/g;
  console.log("\nFound hex text elements in PDF:");
  let count = 0;
  while ((match = hexRegex.exec(data)) !== null && count < 20) {
    console.log("Hex Tj:", match[1]);
    count++;
  }
}

checkPdf();
