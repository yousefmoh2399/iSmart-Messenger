const path = require('path');
const fs = require('fs');
const logo1Path = path.join('g:/iSmart-Messenger-Full/backend/src/printers/services', '../../assets/logo1.jpg');
console.log('Exists:', fs.existsSync(logo1Path), logo1Path);
