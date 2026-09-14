const fs = require('fs');
const buffer = fs.readFileSync('g:/iSmart-Messenger-Full/backend/src/assets/logo1.jpg');
// Find SOF0 marker to get channels
for(let i=0; i<buffer.length; i++) {
  if(buffer[i] === 0xFF && buffer[i+1] === 0xC0) {
    console.log('Channels:', buffer[i+9]);
    break;
  }
}
