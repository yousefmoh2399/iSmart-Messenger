# Redundant File Storage Architecture (`docs/file-storage.md`)

## 1. Shared Storage Design

```text
Backend #1 (vm-app1) ──┐
                       ├──► /data/ismart/uploads (NFSv4 / Replicated Storage)
Backend #2 (vm-app2) ──┘
```

Both Backend nodes mount the exact same shared storage directory at `/data/ismart/uploads`, `/data/ismart/backups`, and `/data/ismart/releases`.

## 2. Storage Abstraction & Consistency (`src/utils/storage-provider.js`)

Implemented in [`src/utils/storage-provider.js`](file:///g:/iSmart-Messenger-Full/backend/src/utils/storage-provider.js):
* `storage.save()` — Atomic temporary-file write + rename + post-write verification.
* `storage.verify()` — Confirms file exists on shared storage and size > 0 bytes.
* `storage.withUploadTransaction(filePath, dbWriteFn)` — Verifies physical file in storage before writing metadata to MongoDB; automatically deletes the orphan file if the MongoDB write fails.
* `storage.get()` / `storage.createReadStream()` / `storage.exists()` / `storage.delete()`.
* `storage.checkHealth()` — Verifies read/write access on `/data/ismart/uploads` for `/health` and `/ready` probes.
