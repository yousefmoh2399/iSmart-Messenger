const bidiFactory = require('bidi-js');
const bidi = bidiFactory();
const { ArabicShaper } = require('arabic-persian-reshaper');
const text = "??? ??????? (????)";
const shaped = ArabicShaper.convertArabic(text);
const embedding = bidi.getEmbeddingLevels(shaped, 'rtl');
console.log('bidi.getReorderedString:', bidi.getReorderedString(shaped, embedding));
console.log('Old split-reverse:', shaped.split(" ").reverse().join(" "));
