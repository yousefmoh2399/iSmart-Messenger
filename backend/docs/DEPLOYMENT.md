# Deployment & Migration Guide (`docs/deployment.md`)

## 1. Resource Sizing Plan (Corporate Internal Scale)

| VM Name | vCPU | RAM | Disk | OS |
| :--- | :--- | :--- | :--- | :--- |
| `vm-hap1` / `vm-hap2` | 2 vCPU | 2 GB | 20 GB | Ubuntu 22.04 LTS |
| `vm-app1` / `vm-app2` | 4 vCPU | 4 GB | 40 GB | Ubuntu 22.04 LTS |
| `vm-mongo1` / `vm-mongo2` | 4 vCPU | 8 GB | 100 GB SSD | Ubuntu 22.04 LTS |
| `vm-mongo3` | 2 vCPU | 4 GB | 80 GB SSD | Ubuntu 22.04 LTS |
| `vm-redis` | 2 vCPU | 4 GB | 20 GB | Ubuntu 22.04 LTS |
| `vm-storage` | 2–4 vCPU | 4–8 GB | 500 GB+ | Ubuntu 22.04 LTS / TrueNAS |

## 2. Step-by-Step Staging-First Migration Strategy (`iSmart HA Test`)

Never migrate production in-place without validating in `iSmart HA Test`:

1. **Clone Backend** repository onto `vm-app1` and `vm-app2` under `/opt/ismart/backend`.
2. **Setup Shared Storage** (`vm-storage`) and mount `/data/ismart` on both `vm-app1` and `vm-app2`.
3. **Setup MongoDB Replica Set** (`ismartRS`) across `vm-mongo1`, `vm-mongo2`, `vm-mongo3` using [`mongod-rs.conf`](file:///g:/iSmart-Messenger-Full/backend/deployment/ha/mongodb/mongod-rs.conf) and [`init-replica-set.js`](file:///g:/iSmart-Messenger-Full/backend/deployment/ha/mongodb/init-replica-set.js).
4. **Setup Redis** on `vm-redis` using [`redis-ha.conf`](file:///g:/iSmart-Messenger-Full/backend/deployment/ha/redis/redis-ha.conf).
5. **Deploy Backend 1 & Backend 2:**
   - Set `INSTANCE_ID=backend-01` on `vm-app1` and `INSTANCE_ID=backend-02` on `vm-app2`.
   - Ensure both share the exact same `JWT_SECRET`, `MONGODB_URI`, and `REDIS_URL`.
   - Enable systemd unit [`ismart-backend.service`](file:///g:/iSmart-Messenger-Full/backend/deployment/ha/systemd/ismart-backend.service).
6. **Setup HAProxy & Keepalived** on `vm-hap1` and `vm-hap2` with Virtual IP `<VIP_IP>`.
7. **Execute Failover Tests** ([`run-failover-tests.sh`](file:///g:/iSmart-Messenger-Full/backend/deployment/ha/tests/run-failover-tests.sh)) and verify backup/restore ([`verify-restore.sh`](file:///g:/iSmart-Messenger-Full/backend/deployment/ha/backup/verify-restore.sh)).
8. **Cutover Production DNS:** Point `ismart.company.local` to `<VIP_IP>`.
