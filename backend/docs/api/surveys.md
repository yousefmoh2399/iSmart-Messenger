# Poll (Survey) Creation API Documentation

## Creating a Poll Message

When creating a poll message, you must adhere to the following payload structure.

### Important Validation Note
If the `messageType` is **NOT** `poll`, then either `content` or `attachment` **MUST** be non-empty.
However, if `messageType` is `poll`, the backend allows empty `content` (since the poll details are stored in `metadata`).
**Developers must validate** that `metadata.options` is provided and valid before sending.

### Example JSON Payload
```json
{
  "conversationId": "60f7a9...",
  "messageType": "poll",
  "content": "",
  "metadata": {
    "question": "ما هو رأيك في التحديث الجديد؟",
    "options": [
      { "id": "1", "text": "ممتاز" },
      { "id": "2", "text": "جيد" },
      { "id": "3", "text": "ضعيف" }
    ],
    "isMultipleChoice": false,
    "isAnonymous": true,
    "isClosed": false,
    "votes": {}
  }
}
```
