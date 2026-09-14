const bidiFactory = require('bidi-js');
const bidi = bidiFactory();
const text = '??? ??????? (????)';
const embedding = bidi.getEmbeddingLevels(text, 'rtl');
console.log(bidi.getReorderedString(text, embedding));
