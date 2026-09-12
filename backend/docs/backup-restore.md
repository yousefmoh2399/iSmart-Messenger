# Backup & Restore

## Normal restore

Use the authenticated admin backup APIs:

- `GET /api/admin/backup/list`
- `GET /api/admin/backup/:id/verify`
- `POST /api/admin/backup/restore`
- `POST /api/admin/backup/restore-upload`

By default, restore creates a safety backup before changing the database:

```json
{
  "backupFileName": "backup_20260623_120000.zip",
  "confirmRestore": true,
  "createSafetyBackup": true
}
```

## Emergency restore when the database is empty

If the users collection is empty and nobody can log in, restore a backup with:

```bash
curl -X POST "https://your-api-host/api/admin/backup/emergency/restore-upload" \
  -H "x-restore-token: YOUR_RESTORE_EMERGENCY_TOKEN" \
  -F "backup=@backup_20260623_120000.zip" \
  -F "createSafetyBackup=true"
```

Security rules:

- `RESTORE_EMERGENCY_TOKEN` must be set in `.env`.
- Emergency restore is allowed only when the users collection is empty by default.
- Keep `RESTORE_EMERGENCY_ALLOW_NON_EMPTY=false` unless you are doing a controlled disaster recovery.
- Rotate `RESTORE_EMERGENCY_TOKEN` after every emergency use.

After restore completes, sign in using an admin account from the restored backup.
