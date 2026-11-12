const assert = require("node:assert/strict");
const test = require("node:test");

const {
  sanitizeMessageContent,
  sanitizePinnedMessageContent,
} = require("../src/chat/services/chat.service");

test("sanitizeMessageContent preserves newlines from Shift+Enter", () => {
  const input = "السطر الأول\nالسطر الثاني\nالسطر الثالث";
  const result = sanitizeMessageContent(input);
  assert.equal(result, "السطر الأول\nالسطر الثاني\nالسطر الثالث");
});

test("sanitizeMessageContent normalizes Windows CRLF to LF", () => {
  const input = "First line\r\nSecond line";
  const result = sanitizeMessageContent(input);
  assert.equal(result, "First line\nSecond line");
});

test("sanitizeMessageContent collapses excessive horizontal spaces but preserves line breaks", () => {
  const input = "  Hello    World!   \n   Line 2   with   spaces  ";
  const result = sanitizeMessageContent(input);
  assert.equal(result, "Hello World!\n Line 2 with spaces");
});

test("sanitizeMessageContent caps consecutive empty lines to prevent flooding", () => {
  const input = "Line 1\n\n\n\n\n\nLine 2";
  const result = sanitizeMessageContent(input);
  assert.equal(result, "Line 1\n\n\nLine 2");
});

test("sanitizeMessageContent returns empty string if input contains only whitespace and newlines", () => {
  const input = "   \n  \r\n  \t  \n  ";
  const result = sanitizeMessageContent(input);
  assert.equal(result, "");
});

test("sanitizePinnedMessageContent preserves multi-line pinned notes", () => {
  const input = "📌 تنبيه هام للفرع:\n1. مراجعة الخزنة\n2. تسليم العهدة";
  const result = sanitizePinnedMessageContent(input);
  assert.equal(result, "📌 تنبيه هام للفرع:\n1. مراجعة الخزنة\n2. تسليم العهدة");
});
