const { ArabicShaper } = require("arabic-persian-reshaper");
const bidiFactory = require("bidi-js");
const bidi = bidiFactory();

const input = "تقرير مراقبة الطابعات";
const shaped = ArabicShaper.convertArabic(input);
const embedding = bidi.getEmbeddingLevels(shaped, "rtl");
const reordered = bidi.getReorderedString(shaped, embedding);

console.log("Input:", input);
console.log("Shaped:", shaped);
console.log("Reordered:", reordered);

// Log char codes of reordered
for (let i = 0; i < reordered.length; i++) {
  const char = reordered[i];
  console.log(`${char}: \\u${char.charCodeAt(0).toString(16).padStart(4, '0')}`);
}
