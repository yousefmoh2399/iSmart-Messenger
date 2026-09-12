const snmp = require("net-snmp");

const host = "192.168.10.11";
const community = "public";

const oids = [
  "1.3.6.1.2.1.1.1.0", // sysDescr
  "1.3.6.1.2.1.43.10.2.1.4.1.1", // Standard Life Count
  "1.3.6.1.4.1.1347.43.10.1.1.12.1.1", // Kyocera Total Pages
  "1.3.6.1.4.1.1347.43.10.1.1.12.1.2", // Kyocera Copy Pages
  "1.3.6.1.4.1.1347.42.3.1.1.1.1.2",   // Kyocera Copy Pages (Alt)
  "1.3.6.1.4.1.1347.43.10.1.1.12.1.3", // Kyocera Print Pages
  "1.3.6.1.4.1.1347.46.10.1.1.5.3",    // Kyocera Scan Pages
  "1.3.6.1.4.1.1347.42.3.1.1.1.1.3",   // Kyocera Scan Pages (Alt)
  "1.3.6.1.4.1.1347.43.10.1.1.12.1.4"  // Kyocera Scan Pages (Alt 2)
];

const session = snmp.createSession(host, community, {
  timeout: 3000,
  retries: 1,
  version: snmp.Version2c
});

console.log("Querying SNMP OIDs on", host);
session.get(oids, (error, varbinds) => {
  if (error) {
    console.error("SNMP Get Error:", error.message || error);
  } else {
    for (const vb of varbinds) {
      if (snmp.isVarbindError(vb)) {
        console.log(`${vb.oid}: ERROR: ${snmp.varbindError(vb)}`);
      } else {
        console.log(`${vb.oid}: ${vb.value.toString()}`);
      }
    }
  }
  session.close();
});
