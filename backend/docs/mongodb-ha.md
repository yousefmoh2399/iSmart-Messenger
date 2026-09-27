# MongoDB High Availability (`docs/mongodb-ha.md`)

## 1. Why 3 Data-Bearing Nodes Instead of an Arbiter?

| Criterion | 3 Data-Bearing Nodes (`Recommended`) | 2 Data Nodes + 1 Arbiter |
| :--- | :--- | :--- |
| **Election Quorum** | `2/3` votes (survives any 1 node failure) | `2/3` votes (survives any 1 node failure) |
| **`w: "majority"` Writes when 1 Data Node is Down** | **Continues working** (2 data-bearing nodes remain alive) | **BLOCKS / FAILS** (only 1 data node remains alive, cannot satisfy majority data write!) |
| **Data Redundancy** | **3 full copies** of corporate messages & metadata | Only 2 copies |

Therefore, `ismartRS` uses **3 data-bearing members** (`mongo1` priority `2`, `mongo2` priority `1`, `mongo3` priority `0.5`).

## 2. Node.js Connection & Durability Configuration

Configured in [`src/config/database.js`](file:///g:/iSmart-Messenger-Full/backend/src/config/database.js):
* **Connection String:**
  ```env
  MONGODB_URI=mongodb://mongo1:27017,mongo2:27017,mongo3:27017/workplace_documents?replicaSet=ismartRS
  ```
* **Write Concern:** `w: "majority"`, `journal: true` (never `w: 0`)
* **Retryable Operations:** `retryWrites: true`, `retryReads: true`
* **Read Preference:** `primaryPreferred`
* **Automatic Topology Discovery:** Mongoose monitors `connected`, `disconnected`, `reconnected`, and `fullsetup` events without hardcoding primary IPs.
