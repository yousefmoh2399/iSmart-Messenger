const bidiFactory = require('bidi-js');
const bidi = bidiFactory();
const { ArabicShaper } = require('arabic-persian-reshaper');

function processArabicText(text) {
  const input = text;
  const shaped = ArabicShaper.convertArabic(input);
  const embedding = bidi.getEmbeddingLevels(shaped, 'rtl');
  const reordered = bidi.getReorderedString(shaped, embedding);
  return reordered
    .replace(/\(/g, '\x01')
    .replace(/\)/g, '(')
    .replace(/\x01/g, ')');
}

console.log(processArabicText('????? ???? ??????? ??????????? ?????????'));
console.log(processArabicText('??? ??????? (????)'));
