const { ArabicShaper } = require("arabic-persian-reshaper");
const bidiFactory = require("bidi-js");
const bidi = bidiFactory();

const input = "اسم المنتج: TASKalfa 3051ci";
const shaped = ArabicShaper.convertArabic(input);
const embedding = bidi.getEmbeddingLevels(shaped, "rtl");
const reordered = bidi.getReorderedString(shaped, embedding);

console.log("Input:", input);
console.log("Shaped:", shaped);
console.log("Reordered:", reordered);

// Log word by word or check characters
for (let i = 0; i < reordered.length; i++) {
  const char = reordered[i];
  const code = char.charCodeAt(0);
  if (code >= 32 && code <= 126) {
    // ASCII printable
    process.stdout.write(char);
  } else {
    process.stdout.write(`\\u${code.toString(16).padStart(4, '0')}`);
  }
}
console.log();
