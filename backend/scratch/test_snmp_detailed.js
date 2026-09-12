const snmp = require("net-snmp");

const host = "192.168.10.11";
const community = "public";

const SCALAR_OIDS = {
  sysName: "1.3.6.1.2.1.1.5.0",
  sysDescr: "1.3.6.1.2.1.1.1.0",
  printerName: "1.3.6.1.2.1.43.5.1.1.16.1",
  serialNumber: "1.3.6.1.2.1.43.5.1.1.17.1",
  
  // Kyocera Proprietary OIDs
  kyoceraTotalPages: "1.3.6.1.4.1.1347.43.10.1.1.12.1.1",
  kyoceraPrintMono: "1.3.6.1.4.1.1347.42.3.1.2.1.1.1.1",
  kyoceraPrintColor: "1.3.6.1.4.1.1347.42.3.1.2.1.1.1.3",
  kyoceraCopyMono: "1.3.6.1.4.1.1347.42.3.1.2.1.1.2.1",
  kyoceraCopyColor: "1.3.6.1.4.1.1347.42.3.1.2.1.1.2.3",
  kyoceraScanPages: "1.3.6.1.4.1.1347.46.10.1.1.5.3",
  kyoceraDuplex: "1.3.6.1.4.1.1347.42.3.1.4.1.1.1",

  // HP Proprietary OIDs
  hpMonoPages: "1.3.6.1.4.1.11.2.3.9.4.2.1.4.1.2.6.0",
  hpColorPages: "1.3.6.1.4.1.11.2.3.9.4.2.1.4.1.2.7.0",
  hpDuplexPages: "1.3.6.1.4.1.11.2.3.9.4.2.1.4.1.2.22.0",
  hpAdfScan: "1.3.6.1.4.1.11.2.3.9.4.2.1.2.2.1.20.0",
  hpFlatbedScan: "1.3.6.1.4.1.11.2.3.9.4.2.1.2.2.1.21.0"
};

const session = snmp.createSession(host, community, {
  timeout: 3000,
  retries: 1,
  version: snmp.Version2c
});

console.log("Querying Detailed OIDs on", host);
session.get(Object.values(SCALAR_OIDS), (error, varbinds) => {
  if (error) {
    console.error("SNMP Get Error:", error.message || error);
  } else {
    for (const vb of varbinds) {
      if (snmp.isVarbindError(vb)) {
        console.log(`${vb.oid}: ERROR: ${snmp.varbindError(vb)}`);
      } else {
        const name = Object.keys(SCALAR_OIDS).find(k => SCALAR_OIDS[k] === vb.oid);
        console.log(`${name} (${vb.oid}): ${vb.value.toString()}`);
      }
    }
  }
  session.close();
});
