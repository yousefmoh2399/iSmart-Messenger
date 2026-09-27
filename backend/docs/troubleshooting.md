# Troubleshooting Guide (`docs/troubleshooting.md`)

## 1. Identifying Which Backend Served a Request

Every HTTP response includes the `X-Instance-Id` header (`backend-01` or `backend-02`), and every structured JSON log line emitted by [`src/utils/logger.js`](file:///g:/iSmart-Messenger-Full/backend/src/utils/logger.js) includes `"instanceId": "backend-01"`.

```bash
curl -I https://ismart.company.local/health
# Look for: X-Instance-Id: backend-01
```

## 2. Common Issues & Fixes

### Issue A: `GET /health` returns HTTP `503` (`"status": "degraded"`)
* **Check payload:** `curl -s http://localhost:5000/health | jq`
* If `"database": "disconnected"`:
  - Verify MongoDB Replica Set status: `mongosh --eval "rs.status()"`.
  - Check firewall TCP `27017` between `vm-app*` and `vm-mongo*`.
* If `"storage": "unavailable"`:
  - Verify NFS mount on Backend VM: `mount | grep /data/ismart` and `ls -la /data/ismart/uploads`.
  - Remount if necessary: `sudo mount -a`.

### Issue B: Socket.IO messages not crossing between Backend 1 and Backend 2
* Check `/ready` endpoint: `curl -s http://localhost:5000/ready | jq`.
* Verify `"redis": "connected"`.
* Check Backend startup logs for `"message": "socketio.redis_adapter.attached"`.
* Ensure both Backend nodes point to the **same** `REDIS_URL`.

### Issue C: `401 Unauthorized` when user switches from Backend 1 to Backend 2
* Cause: `JWT_SECRET` differs between `vm-app1` and `vm-app2`.
* Fix: Copy the exact same `JWT_SECRET` into `/etc/ismart/backend.env` on both nodes and restart `ismart-backend`.
