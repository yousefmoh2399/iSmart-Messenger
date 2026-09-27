# iSmart Backend — High Availability Architecture (`docs/architecture.md`)

## 1. Target Topology

```text
                         Clients (Flutter Mobile & Windows Desktop)
                                          |
                              https://ismart.company.local
                                          |
                                  Virtual IP (<VIP_IP>)
                                          |
                            +-------------+-------------+
                            |                           |
                            v                           v
                      HAProxy #1                  HAProxy #2
                       MASTER                      BACKUP
                     (Keepalived)                (Keepalived)
                            |                           |
                            +-------------+-------------+
                                          |
                               Load Balancing / Health
                                (GET /health & /ready)
                                          |
                            +-------------+-------------+
                            |                           |
                            v                           v
                     Backend Node #1             Backend Node #2
                     Node.js + Express           Node.js + Express
                     Socket.IO                   Socket.IO
                     (INSTANCE_ID=backend-01)    (INSTANCE_ID=backend-02)
                            |                           |
                            +-------------+-------------+
                                          |
                            +-------------+-------------+
                            |                           |
                            v                           v
                          Redis                     MongoDB
                     (Pub/Sub Adapter,            Replica Set (ismartRS)
                      Rate Limits,         +------------+------------+
                      Cron Locks)          |            |            |
                                           v            v            v
                                        Mongo1       Mongo2       Mongo3
                                       PRIMARY      SECONDARY   SECONDARY (Voter)
                                                        |
                                                        v
                                             Redundant File Storage
                                              (/data/ismart/uploads)
```

## 2. Infrastructure Inventory Table

| Component | VM | IP | Port | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **Virtual IP** | Floating VIP | `TBD` | `80 / 443` | Single client entry point (`ismart.company.local`) |
| **HAProxy 1** | `vm-hap1` | `TBD` | `80 / 443 / 8404` | Primary Load Balancer (`MASTER`) |
| **HAProxy 2** | `vm-hap2` | `TBD` | `80 / 443 / 8404` | Failover Load Balancer (`BACKUP`) |
| **Backend 1** | `vm-app1` | `TBD` | `5000` | Node.js API & Socket.IO (`backend-01`) |
| **Backend 2** | `vm-app2` | `TBD` | `5000` | Node.js API & Socket.IO (`backend-02`) |
| **Mongo 1** | `vm-mongo1` | `TBD` | `27017` | MongoDB Primary (`priority: 2`) |
| **Mongo 2** | `vm-mongo2` | `TBD` | `27017` | MongoDB Secondary (`priority: 1`) |
| **Mongo 3** | `vm-mongo3` | `TBD` | `27017` | MongoDB Data-Bearing Voting Member (`priority: 0.5`) |
| **Redis** | `vm-redis` | `TBD` | `6379` | Socket.IO Pub/Sub, Distributed Locks, Rate Limits |
| **Storage** | `vm-storage` / NAS | `TBD` | `2049` (NFSv4) | Redundant Shared File Storage |

## 3. VMware ESXi Physical Host Distribution

* **Multi-Host ESXi (Full Hardware Fault Tolerance):**
  - **ESXi Host 1:** `vm-hap1`, `vm-app1`, `vm-mongo1`, `vm-redis`
  - **ESXi Host 2:** `vm-hap2`, `vm-app2`, `vm-mongo2`, `vm-storage`
  - **ESXi Host 3:** `vm-mongo3`
* **Single-Host ESXi Warning:** If all VMs are deployed on a single physical ESXi host, the architecture protects against **VM, OS, process, and database service failures**, but **does NOT protect against physical ESXi host hardware failure**.
