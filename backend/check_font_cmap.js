const fs = require("fs");
const path = require("path");

// Try to require fontkit
let fontkit;
try {
  fontkit = require("fontkit");
} catch (_) {
  try {
    fontkit = require("pdfkit/node_modules/fontkit");
  } catch (err) {
    console.error("Could not load fontkit:", err.message);
    process.exit(1);
  }
}

async function checkFont(fontName, relativePath) {
  const fontPath = path.join(__dirname, relativePath);
  console.log(`\nChecking font ${fontName} at: ${fontPath}`);
  if (!fs.existsSync(fontPath)) {
    console.log("File does not exist.");
    return;
  }
  try {
    const font = fontkit.openSync(fontPath);
    console.log("Font family name:", font.familyName);
    
    const testChars = [
      { code: 0x062a, name: "Teh (ت)" },
      { code: 0xfe97, name: "Teh shaped (ﺗ)" },
      { code: 0x0041, name: "A" },
      { code: 0x0054, name: "T" },
      { code: 0x0033, name: "3" },
      { code: 0x003a, name: ":" }
    ];
    
    for (const item of testChars) {
      const hex = "0x" + item.code.toString(16).padStart(4, '0');
      const hasGlyph = font.hasGlyphForCodePoint(item.code);
      console.log(`Character ${item.name} (${hex}): hasGlyph = ${hasGlyph}`);
    }
  } catch (err) {
    console.error("Error:", err.message);
  }
}

async function run() {
  await checkFont("NotoSansArabic", "src/assets/fonts/NotoSansArabic-Regular.ttf");
  await checkFont("Amiri", "src/assets/fonts/Amiri-Regular.ttf");
}

run();
