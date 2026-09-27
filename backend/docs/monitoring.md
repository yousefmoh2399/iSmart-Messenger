# Monitoring & Alerting (`docs/monitoring.md`)

## 1. Health & Readiness Probes

Implemented in [`src/app.js`](file:///g:/iSmart-Messenger-Full/backend/src/app.js):
* **`GET /health` (Liveness & Load Balancer Check):**
  Returns HTTP `200` when the Node.js process, MongoDB connection, and Shared Storage are healthy (`503` if degraded). Includes `X-Instance-Id` response header (`backend-01` / `backend-02`).
* **`GET /ready` (Readiness Probe):**
  Returns HTTP `200` only when MongoDB, Storage, and Redis (when configured) are ready to serve traffic.

## 2. Prometheus & Grafana Stack

Configuration files:
* **Prometheus Scrape Config:** [`deployment/ha/monitoring/prometheus.yml`](file:///g:/iSmart-Messenger-Full/backend/deployment/ha/monitoring/prometheus.yml)
* **Alert Rules:** [`deployment/ha/monitoring/alert-rules.yml`](file:///g:/iSmart-Messenger-Full/backend/deployment/ha/monitoring/alert-rules.yml)

### Monitored Metrics & Alerts
* `BackendInstanceDown` — HAProxy reports `backend-01` or `backend-02` down for `> 15s`
* `MongoDBMemberDown` & `MongoDBReplicaSetNoPrimary` — Replica Set health
* `MongoDBReplicationLagHigh` — Secondary oplog lag `> 10s`
* `RedisDown` — Redis instance unreachable
* `DiskSpaceAbove80Percent` (Warning) & `DiskSpaceAbove90Percent` (Critical)
* `HighMemoryUsage` (`> 85%`) & `HighCPUUsage` (`> 85%`)
* `HighAPIErrorRate` — `5xx` HTTP response rate spike
