# Keepalived & Virtual IP Failover (`docs/keepalived.md`)

## 1. Configuration Files

* **MASTER (`vm-hap1`):** [`deployment/ha/keepalived/keepalived-master.conf`](file:///g:/iSmart-Messenger-Full/backend/deployment/ha/keepalived/keepalived-master.conf)
* **BACKUP (`vm-hap2`):** [`deployment/ha/keepalived/keepalived-backup.conf`](file:///g:/iSmart-Messenger-Full/backend/deployment/ha/keepalived/keepalived-backup.conf)
* **Health Script:** [`deployment/ha/keepalived/check_haproxy.sh`](file:///g:/iSmart-Messenger-Full/backend/deployment/ha/keepalived/check_haproxy.sh)

## 2. How Virtual IP Failover Works

1. `vm-hap1` (`MASTER`, priority `101` + `20` script weight = `121`) holds `<VIP_IP>`.
2. Every `2 seconds`, `check_haproxy.sh` verifies that `haproxy` is alive.
3. If `haproxy` stops on `vm-hap1` or `vm-hap1` powers off, its effective priority drops below `vm-hap2` (`120`) or VRRP advertisements cease.
4. Within **2–3 seconds**, `vm-hap2` claims `<VIP_IP>` and broadcasts Gratuitous ARP (`GARP`).
5. Clients continue communicating with `https://ismart.company.local` (`<VIP_IP>`) with zero configuration changes.
