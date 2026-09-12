const fs = require("fs");
const path = require("path");
const PDFDocument = require("pdfkit");
const bidiFactory = require("bidi-js");
const { ArabicShaper } = require("arabic-persian-reshaper");

const bidi = bidiFactory();

function shapeArabicLine(text) {
  const input = String(text || "");
  if (!/[\u0600-\u06FF]/.test(input)) return input;
  const shaped = ArabicShaper.convertArabic(input);
  const embedding = bidi.getEmbeddingLevels(shaped, "rtl");
  return bidi.getReorderedString(shaped, embedding);
}

function drawTextStandard(doc, text, options = {}) {
  const processed = shapeArabicLine(text);
  doc.text(processed, options);
}

function drawTextSegmented(doc, text, options = {}) {
  const processed = shapeArabicLine(text);
  
  // Split the text into segments of ASCII and non-ASCII characters
  // We match printable ASCII: letters, numbers, punctuation, spaces
  const segments = processed.split(/([\x20-\x7E]+)/g);
  
  const originalFont = doc._font.name;
  
  for (let i = 0; i < segments.length; i++) {
    const segment = segments[i];
    if (!segment) continue;
    
    const isAscii = /^[\x20-\x7E]+$/.test(segment);
    const isLast = i === segments.length - 1 || segments.slice(i + 1).every(s => !s);
    
    if (isAscii) {
      const isBold = originalFont.includes("Bold");
      doc.font(isBold ? "Helvetica-Bold" : "Helvetica");
    } else {
      const isBold = originalFont.includes("Bold");
      if (isBold && doc._registeredFonts?.ArabicBold) {
        doc.font("ArabicBold");
      } else if (doc._registeredFonts?.Arabic) {
        doc.font("Arabic");
      } else {
        doc.font(isBold ? "Helvetica-Bold" : "Helvetica");
      }
    }
    
    doc.text(segment, {
      ...options,
      continued: !isLast
    });
  }
  
  doc.font(originalFont);
}

function run() {
  const doc = new PDFDocument({ size: "A4" });
  doc.pipe(fs.createWriteStream(path.join(__dirname, "test_render.pdf")));
  
  // Register fonts
  const fontsDir = path.join(__dirname, "../src/assets/fonts");
  doc.registerFont("Arabic", path.join(fontsDir, "NotoSansArabic-Regular.ttf"));
  doc.registerFont("ArabicBold", path.join(fontsDir, "NotoSansArabic-Bold.ttf"));
  
  doc.font("Arabic").fontSize(12);
  
  doc.text("1. Testing NotoSansArabic directly (should draw boxes for English):", { align: "right" });
  drawTextStandard(doc, "اسم المنتج: TASKalfa 3051ci", { align: "right" });
  doc.moveDown(1);
  
  doc.text("2. Testing Segmented drawing (should fallback to Helvetica for English, preventing boxes):", { align: "right" });
  drawTextSegmented(doc, "اسم المنتج: TASKalfa 3051ci", { align: "right" });
  doc.moveDown(1);
  
  doc.end();
  console.log("Generated test_render.pdf successfully!");
}

run();
