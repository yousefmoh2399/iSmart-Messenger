# iSmart Backend — Disaster Recovery Runbook (`DISASTER_RECOVERY.md`)

> **Production High Availability & Fault-Tolerant Architecture**  
> Environment: On-Premise Corporate Infrastructure (VMware ESXi)  
> Target Endpoint: `https://ismart.company.local` (via Virtual IP `<VIP_IP>`)

---

## Overview

This runbook defines the exact operational procedures, automatic failover behavior, recovery steps, and expected end-user experience for **all 11 failure scenarios** in the iSmart High Availability architecture.

---

## Scenario 1 — Backend 1 Failure (`vm-app1` or `backend-01` down)

* **What fails?**  
  `Backend 1` (`<APP1_IP>:5000`) stops responding due to process hang, OS freeze, or network drop.
* **What continues?**  
  `HAProxy` active node, `Backend 2` (`<APP2_IP>:5000`), `MongoDB Replica Set`, `Redis`, and `Shared File Storage` continue operating normally.
* **How does failover happen?**  
  1. `HAProxy` executes `GET /health` every `2000ms` (`fall 3`).
  2. Within **4–6 seconds**, HAProxy marks `backend-01` as `DOWN` and removes it from rotation.
  3. All new HTTP requests and WebSocket handshakes are routed strictly to `backend-02`.
  4. Connected Socket.IO clients on `backend-01` detect connection loss and automatically reconnect through `VIP` → `HAProxy` → `backend-02`.
  5. Because `JWT_SECRET` is shared, `DeviceSession` is stored in MongoDB, and Socket.IO uses `@socket.io/redis-adapter`, users resume chat, presence, and file/print operations on `backend-02` without logging in again.
* **How do we recover?**  
  1. SSH to `vm-app1`: `sudo systemctl status ismart-backend` (or `pm2 status`).
  2. Inspect logs: `sudo journalctl -u ismart-backend -n 100 --no-pager`.
  3. Restart service if needed: `sudo systemctl restart ismart-backend`.
  4. Once `GET /health` returns HTTP `200` for `2` consecutive checks (`rise 2`), HAProxy automatically re-adds `backend-01` to the active pool.
* **What does the user experience?**  
  - Users already routed to `backend-02`: **Zero interruption.**
  - Users connected to `backend-01`: Brief **2–6 second** Socket.IO auto-reconnect; no session loss, no forced logout, no lost messages.

---

## Scenario 2 — Backend 2 Failure (`vm-app2` or `backend-02` down)

* **What fails?**  
  `Backend 2` (`<APP2_IP>:5000`) becomes unreachable.
* **What continues?**  
  `Backend 1` (`<APP1_IP>:5000`) serves 100% of API and Socket.IO traffic. Scheduled jobs (`scheduler.service.js`, `printer-scheduler.service.js`, `upload-retention.js`) continue executing on `Backend 1` because distributed locks in Redis automatically expire/transfer to `Backend 1`.
* **How does failover happen?**  
  1. HAProxy detects `/health` failure on `backend-02` within **4–6 seconds** and takes it out of rotation.
  2. Clients connected to `backend-02` transparently reconnect to `backend-01`.
  3. Instance-scoped presence reconciliation marks stale `backend-02` socket sessions offline after the grace window if clients do not reconnect, while immediately re-binding reconnected clients to `backend-01`.
* **How do we recover?**  
  1. Diagnose `vm-app2` (`journalctl -u ismart-backend` / `dmesg` / disk space check).
  2. Start/restart `ismart-backend.service`.
  3. Verify `curl -i http://<APP2_IP>:5000/ready` returns `200 OK`.
* **What does the user experience?**  
  - Users on `backend-01`: **Zero interruption.**
  - Users on `backend-02`: **2–6 second** automatic WebSocket reconnect.

---

## Scenario 3 — MongoDB Primary Failure (`vm-mongo1` down)

* **What fails?**  
  `mongo1` (`PRIMARY` member of `ismartRS`) crashes or loses network connectivity.
* **What continues?**  
  `mongo2` (data-bearing Secondary) and `mongo3` (data-bearing Secondary / Voter) remain online and maintain quorum (`2/3` members available).
* **How does failover happen?**  
  1. `mongo2` and `mongo3` detect missed heartbeats from `mongo1` (`electionTimeoutMillis: 5000`).
  2. `mongo2` (higher priority data-bearing node) initiates a Raft-based Replica Set election and becomes the new `PRIMARY` within **5–10 seconds**.
  3. Both `Backend 1` and `Backend 2` Mongoose drivers (`replicaSet=ismartRS`, `retryWrites=true`, `retryReads=true`) automatically discover the new topology and redirect writes to `mongo2`.
* **How do we recover?**  
  1. Bring `vm-mongo1` back online and start `mongod`: `sudo systemctl start mongod`.
  2. `mongo1` automatically rejoins `ismartRS` as a `SECONDARY`, catches up via the oplog, and either stays Secondary or steps back to Primary depending on priority settings.
  3. Check cluster state: `mongosh --eval "rs.status()"`.
* **What does the user experience?**  
  - **0–8 second** pause on write operations during election; retryable writes automatically complete once `mongo2` is elected Primary. No committed messages or documents are lost (`w: "majority"`, `j: true`).

---

## Scenario 4 — MongoDB Secondary Failure (`vm-mongo2` or `vm-mongo3` down)

* **What fails?**  
  One Secondary node (`mongo2` or `mongo3`) goes offline.
* **What continues?**  
  `mongo1` (`PRIMARY`) + the remaining healthy member (`2/3` quorum) continue accepting `w: "majority"` writes and serving reads without interruption.
* **How does failover happen?**  
  No primary election is required. The Replica Set continues operating normally with 2 active members.
* **How do we recover?**  
  1. Repair/restart `mongod` on the failed Secondary VM.
  2. Verify oplog catch-up via `rs.printSecondaryReplicationInfo()`.
  3. If the node was offline longer than the oplog window, resync by clearing `/var/lib/mongodb` on that Secondary only and restarting `mongod` for automatic initial sync.
* **What does the user experience?**  
  **Zero impact.** Users experience 0ms downtime.

---

## Scenario 5 — Redis Failure (`vm-redis` down)

* **What fails?**  
  The Redis service (`<REDIS_IP>:6379`) stops responding.
* **What continues?**  
  - **MongoDB** (all permanent data, messages, documents, tickets, users) remains 100% intact.
  - **HTTP API endpoints** continue working without interruption (`enableOfflineQueue: false`, `maxRetriesPerRequest: 0`).
  - **Rate limiting** automatically falls back to per-process `MemoryStore` (`src/config/rate-limit-store.js`).
  - **Distributed locks** (`src/utils/distributed-lock.js`) gracefully fall back to local process locks (`fallbackToLocal: true`).
  - **Scheduled messages** remain protected from duplication via atomic MongoDB `findOneAndUpdate({ _id, isScheduled: true })`.
* **How does failover happen?**  
  1. `ioredis` logs a single `redis.client_error` warning (no log flooding) and attempts background reconnection every `500ms–5000ms`.
  2. During Redis downtime, HAProxy `balance source` (IP affinity) keeps clients pinned to the same Backend node whenever possible.
* **How do we recover?**  
  1. Systemd automatically restarts `redis-server` (`Restart=always`).
  2. If VM is down, boot `vm-redis` or start standby Redis instance.
  3. Both Backends automatically reconnect (`redis.reconnected`) and resume cross-instance Pub/Sub.
* **What does the user experience?**  
  Logins, document uploads/downloads, tickets, and message persistence continue working. Cross-instance realtime Socket.IO events temporarily only reach clients on the same Backend node until Redis recovers (typically `< 5 seconds` on service restart).

---

## Scenario 6 — Storage Node Failure

* **What fails?**  
  Primary storage endpoint (`Storage 1` / NFS server) experiences failure.
* **What continues?**  
  In a replicated storage setup (DRBD Active/Passive NFS cluster, TrueNAS HA, or MinIO distributed cluster), the secondary storage node (`Storage 2`) takes over the Storage VIP and exports `/data/ismart`.
* **How does failover happen?**  
  1. Storage VIP transitions from `Storage 1` to `Storage 2` via Keepalived/Pacemaker.
  2. NFS v4 clients on `vm-app1` and `vm-app2` mounted with `hard,timeo=50,retrans=3` automatically resume I/O against `Storage 2`.
  3. If all storage is unreachable, `GET /health` and `GET /ready` report `storage: "unavailable"` (`HTTP 503`), alerting monitoring immediately.
* **How do we recover?**  
  1. Verify storage mount on both Backends: `df -h /data/ismart/uploads` and `curl http://localhost:5000/ready`.
  2. Resynchronize failed storage disk/node (`drbdadm status` or NAS replication check).
* **What does the user experience?**  
  Brief I/O pause (`3–10 seconds`) during storage VIP failover for file uploads/downloads; text chat and authentication remain unaffected.

---

## Scenario 7 — HAProxy Master Failure (`vm-hap1` down)

* **What fails?**  
  `HAProxy #1` (`MASTER`, `<HAP1_IP>`) crashes, or `haproxy` daemon stops on `vm-hap1`.
* **What continues?**  
  `HAProxy #2` (`BACKUP`, `<HAP2_IP>`) and both Backend nodes remain 100% healthy.
* **How does failover happen?**  
  1. `Keepalived` on `vm-hap1` runs `check_haproxy.sh` every `2 seconds`.
  2. If `haproxy` dies or `vm-hap1` goes down, `vm-hap2` stops receiving VRRP advertisements with higher priority within **3 seconds**.
  3. `vm-hap2` transitions to `MASTER`, binds the Virtual IP (`<VIP_IP>`), and broadcasts Gratuitous ARP (`GARP`) frames to the corporate switch.
  4. All traffic to `https://ismart.company.local` (`<VIP_IP>`) immediately flows through `HAProxy #2`.
* **How do we recover?**  
  1. Fix/restart `haproxy` and `keepalived` on `vm-hap1`: `sudo systemctl restart haproxy keepalived`.
  2. Once healthy, `vm-hap1` re-assumes `MASTER` (or stays `nopreempt` to avoid a second blip).
* **What does the user experience?**  
  - DNS URL `https://ismart.company.local` **never changes**.
  - **1–3 second** network blip while Virtual IP moves to `HAProxy #2`; active apps auto-reconnect seamlessly.

---

## Scenario 8 — Entire VM Failure (Any single VM crashes)

* **What fails?**  
  A single Guest OS / VM (e.g. `vm-app1`, `vm-mongo1`, or `vm-hap1`) suffers kernel panic or disk corruption.
* **What continues?**  
  Its redundant counterpart (`vm-app2`, `vm-mongo2`, or `vm-hap2`) continues serving production traffic.
* **How does failover happen?**  
  - If `vm-hap1` fails → Keepalived moves VIP to `vm-hap2` (`~3s`).
  - If `vm-app1` fails → HAProxy routes 100% traffic to `vm-app2` (`~5s`).
  - If `vm-mongo1` fails → Replica Set elects `vm-mongo2` as Primary (`~7s`).
* **How do we recover?**  
  1. Reboot the VM from vSphere/ESXi console or restore VM from latest ESXi snapshot / Ansible/setup playbook.
  2. Systemd automatically starts all services (`ismart-backend`, `mongod`, `haproxy`, `keepalived`) on boot (`systemctl enable`).
* **What does the user experience?**  
  Service remains online with `< 10 seconds` failover transition.

---

## Scenario 9 — Entire ESXi Physical Host Failure

* **What fails?**  
  An entire physical hypervisor server (`ESXi Host 1`) loses power, motherboard, or RAID controller.
* **What continues?**  
  - **Multi-Host ESXi Topology:** VMs placed on `ESXi Host 2` (`vm-hap2`, `vm-app2`, `vm-mongo2`, `Storage 2`) and `ESXi Host 3` (`vm-mongo3`) survive and maintain quorum (`2/3` MongoDB members + `1` HAProxy + `1` Backend).
  - **Single-Host Warning:** If all VMs reside on a single physical ESXi host, hardware failure of that host will take the entire system offline until the host is repaired or backups are restored to another machine.
* **How does failover happen?**  
  In the Multi-Host ESXi layout:
  1. `vm-hap2` (on Host 2) claims the Virtual IP via Keepalived.
  2. `vm-hap2` routes traffic to `vm-app2` (on Host 2).
  3. `vm-mongo2` (on Host 2) + `vm-mongo3` (on Host 3) form a `2/3` majority and elect `vm-mongo2` as Primary.
* **How do we recover?**  
  1. Repair `ESXi Host 1` or use VMware HA to restart affected VMs on surviving ESXi hosts.
  2. Verify MongoDB Replica Set (`rs.status()`) and HAProxy backend pool once Host 1 returns.
* **What does the user experience?**  
  In Multi-Host ESXi: **5–12 seconds** failover time, after which full service continues on Host 2.

---

## Scenario 10 — Data Corruption (Logical or Disk Corruption)

* **What fails?**  
  A MongoDB data file or collection becomes corrupted, or invalid data is written by a faulty operation.
* **What continues?**  
  - If **disk-level corruption** occurs on a single MongoDB node (`mongo1`), `mongo2` and `mongo3` have independent copies of the data.
  - If **logical corruption** replicates across the Replica Set, Point-in-Time / Daily Verified Backups on isolated Backup Storage remain untouched.
* **How does failover happen?**  
  - For single-node disk corruption: `mongod` on the affected node halts; Replica Set fails over to healthy Secondaries automatically.
  - For logical corruption across the cluster: Administrators trigger a controlled restore from the latest verified backup archive.
* **How do we recover?**  
  1. **Single-node disk corruption:** Stop `mongod` on corrupted node, wipe `/var/lib/mongodb`, restart `mongod` to perform clean initial sync from healthy Primary.
  2. **Logical corruption:**
     - Put HAProxy into maintenance mode or use Admin Backup Restore (`/api/admin/backup/restore` or CLI `--restore`).
     - `BACKUP_PRE_RESTORE_SNAPSHOT=true` automatically takes a safety snapshot before restoring.
     - Restore the latest verified backup from `/data/ismart/backups`.
* **What does the user experience?**  
  - Single-node disk corruption: Automatic failover (`< 10s`).
  - Logical restore: Planned maintenance window (`5–15 minutes` depending on dataset size).

---

## Scenario 11 — Accidental Deletion (User/Conversation/Document Deleted by Mistake)

* **What fails?**  
  An administrator or user accidentally deletes critical documents, tickets, or users (which replicates immediately across Replica Set members — **High Availability is NOT Backup**).
* **What continues?**  
  The system remains online and healthy, and daily immutable backup archives (`backup_YYYYMMDD_HHMMSS.zip`) in `/data/ismart/backups` (and off-box backup storage) retain the deleted records and files.
* **How does failover happen?**  
  Not a hardware failover event — handled via **Granular or Full Backup Recovery**.
* **How do we recover?**  
  **Option A — Granular Recovery (Zero Downtime for other users):**
  1. Extract the latest backup `.zip` into a temporary staging directory (`/tmp/restore-staging`).
  2. Inspect `mongo-dump/collections/<collection>.json` (EJSON format) and `uploads/` to locate the specific deleted document/user record and its physical file.
  3. Copy the missing file back to `/data/ismart/uploads/<relativePath>` and re-insert the specific EJSON document into MongoDB Primary.
  
  **Option B — Full System Rollback:**
  1. Trigger full restore via Admin Dashboard (`POST /api/admin/backup/restore`) or CLI.
* **What does the user experience?**  
  - Option A (Granular Recovery): **Zero downtime** for all users; deleted item reappears immediately.
  - Option B (Full Rollback): **2–5 minutes** maintenance window.
