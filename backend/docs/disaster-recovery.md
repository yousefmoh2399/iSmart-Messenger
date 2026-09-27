# Disaster Recovery Reference (`docs/disaster-recovery.md`)

See the full root runbook at [`DISASTER_RECOVERY.md`](file:///g:/iSmart-Messenger-Full/backend/DISASTER_RECOVERY.md) for detailed procedures covering all 11 failure scenarios:

1. **Scenario 1:** Backend 1 failure (`vm-app1`)
2. **Scenario 2:** Backend 2 failure (`vm-app2`)
3. **Scenario 3:** MongoDB Primary failure (`vm-mongo1`)
4. **Scenario 4:** MongoDB Secondary failure (`vm-mongo2` / `vm-mongo3`)
5. **Scenario 5:** Redis failure (`vm-redis`)
6. **Scenario 6:** Storage node failure (`vm-storage`)
7. **Scenario 7:** HAProxy Master failure (`vm-hap1`)
8. **Scenario 8:** Entire VM failure
9. **Scenario 9:** Entire ESXi physical host failure
10. **Scenario 10:** Data corruption
11. **Scenario 11:** Accidental deletion
