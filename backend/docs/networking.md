# Network & DNS Design (`docs/networking.md`)

## 1. Internal DNS & Single Client Endpoint

* **Single Endpoint Rule:** Flutter Mobile and Windows Desktop clients **never** connect to individual server IPs (`<APP1_IP>`, `<APP2_IP>`, `<MONGO1_IP>`).
* **Internal DNS Record:**
  ```text
  ismart.company.local  --->  A Record  --->  <VIP_IP>
  ```
* All infrastructure topology changes remain 100% transparent behind `<VIP_IP>`.

## 2. Logical Network Segmentation & Firewall Rules

```text
Clients Network / VLAN
   │
   │  TCP 80 / 443 ONLY
   ▼
Load Balancer Tier (HAProxy #1 & #2 — VIP <VIP_IP>)
   │  VRRP Protocol (IP Proto 112) between HAP1 <-> HAP2
   │  TCP 5000 to Backend Nodes
   ▼
Application Tier (Backend #1 & Backend #2)
   ├──► TCP 6379  to Redis (vm-redis)
   ├──► TCP 27017 to MongoDB Replica Set (mongo1, mongo2, mongo3)
   └──► TCP 2049  to Shared NFSv4 Storage (vm-storage)
```

| Source | Destination | Port / Protocol | Purpose |
| :--- | :--- | :--- | :--- |
| Clients | `<VIP_IP>` | `TCP 80, 443` | HTTPS API & WSS Socket.IO |
| `vm-hap1` ↔ `vm-hap2` | Peer IP | `VRRP (Proto 112)` | Keepalived Virtual IP heartbeat |
| `vm-hap1`, `vm-hap2` | `vm-app1`, `vm-app2` | `TCP 5000` | Reverse proxy + `/health` checks |
| `vm-app1`, `vm-app2` | `vm-redis` | `TCP 6379` | Socket.IO Pub/Sub & locks |
| `vm-app1`, `vm-app2` | `mongo1..3` | `TCP 27017` | Replica Set read/write |
| `mongo1` ↔ `mongo2` ↔ `mongo3` | `mongo1..3` | `TCP 27017` | Replica Set election & oplog replication |
| `vm-app1`, `vm-app2` | `vm-storage` | `TCP 2049` | Shared `/data/ismart` storage |
