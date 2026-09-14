const fs = require('fs');
const buffer = fs.readFileSync('g:/iSmart-Messenger-Full/backend/src/assets/logo1.jpg');
// basic jpeg parsing to find width/height
let i = 2;
while (i < buffer.length) {
  if (buffer[i] === 0xFF && (buffer[i+1] === 0xC0 || buffer[i+1] === 0xC2)) {
    const height = buffer.readUInt16BE(i + 5);
    const width = buffer.readUInt16BE(i + 7);
    console.log('Logo1:', width, 'x', height);
    break;
  }
  i += buffer.readUInt16BE(i + 2) + 2;
}

const buffer2 = fs.readFileSync('g:/iSmart-Messenger-Full/backend/src/assets/logo2.jpg');
i = 2;
while (i < buffer2.length) {
  if (buffer2[i] === 0xFF && (buffer2[i+1] === 0xC0 || buffer2[i+1] === 0xC2)) {
    const height = buffer2.readUInt16BE(i + 5);
    const width = buffer2.readUInt16BE(i + 7);
    console.log('Logo2:', width, 'x', height);
    break;
  }
  i += buffer2.readUInt16BE(i + 2) + 2;
}
