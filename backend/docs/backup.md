# Backup & Restore Verification Strategy (`docs/backup.md`)

## 1. Why High Availability Is Not Backup

MongoDB Replica Sets immediately replicate writes—including accidental deletions (`DELETE /api/documents/:id`) or logical bugs—to all Secondaries. Therefore, **independent daily verified backups** are mandatory.

## 2. Automated Backup Pipeline

* **Backup Script:** [`deployment/ha/backup/backup-cron.sh`](file:///g:/iSmart-Messenger-Full/backend/deployment/ha/backup/backup-cron.sh)
  - Runs daily at `02:00 AM` via cron.
  - Uses `readPreference=secondaryPreferred` to avoid impacting the MongoDB Primary.
  - Bundles MongoDB BSON collections + `/data/ismart/uploads` + `backup-manifest.json`.
  - Generates and verifies `.sha256` checksums and tar integrity (`tar -tzf`).
  - Enforces a configurable retention policy (default `14 days`).
* **Cluster-Safe Admin Backup Mutex:**  
  [`src/admin/backup/backup.service.js`](file:///g:/iSmart-Messenger-Full/backend/src/admin/backup/backup.service.js) uses `withDistributedLock("admin:backup_operation")` so two admins on different Backend nodes cannot trigger conflicting backups simultaneously.

## 3. Restore Testing (`verify-restore.sh`)

Never trust a backup solely because `mongodump` exited with code `0`.  
Run [`deployment/ha/backup/verify-restore.sh`](file:///g:/iSmart-Messenger-Full/backend/deployment/ha/backup/verify-restore.sh) weekly (via cron) to restore the latest archive into an isolated temporary database (`ismart_restore_verification_*`), count restored documents, and drop the temporary database.
