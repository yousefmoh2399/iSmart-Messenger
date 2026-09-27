# HAProxy Load Balancing (`docs/haproxy.md`)

## 1. Configuration File

Production configuration is located at [`deployment/ha/haproxy/haproxy.cfg`](file:///g:/iSmart-Messenger-Full/backend/deployment/ha/haproxy/haproxy.cfg).

## 2. Key Features

* **Active HTTP Health Check:**
  Polls `GET /health` every `2000ms` (`fall 3`, `rise 2`). If a Backend node returns `503` (e.g. MongoDB or Storage disconnected) or times out, HAProxy removes it from rotation within `6 seconds` and re-inserts it automatically once healthy.
* **WebSocket & Sticky Routing:**
  Uses `balance source` (`hash-type consistent`) so Socket.IO HTTP long-polling handshakes and WebSocket upgrades always land on the same Backend instance, while `timeout tunnel 3600s` maintains long-lived WebSocket connections.
* **Large Upload/Download Timeouts:**
  `timeout server 900s` matches the 15-minute timeout configured in `src/app.js` for OTA releases, chat file transfers, and backups.
* **Zero-Downtime Reload:**
  ```bash
  sudo haproxy -c -f /etc/haproxy/haproxy.cfg && sudo systemctl reload haproxy
  ```
