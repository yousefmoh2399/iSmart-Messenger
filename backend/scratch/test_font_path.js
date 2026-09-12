const fs = require("fs");
const path = require("path");

const dir = "e:\\ismart messenger\\backend\\src\\printers\\services";

const regularPath = path.join(dir, "../../assets/fonts/Amiri-Regular.ttf");
const boldPath = path.join(dir, "../../assets/fonts/Amiri-Bold.ttf");

console.log("Amiri regular path:", regularPath);
console.log("Amiri regular exists:", fs.existsSync(regularPath));

const notoRegularPath = path.join(dir, "../../assets/fonts/NotoSansArabic-Regular.ttf");
console.log("Noto regular path:", notoRegularPath);
console.log("Noto regular exists:", fs.existsSync(notoRegularPath));
