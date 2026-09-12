const snmp = require("net-snmp");

const host = "192.168.10.11";
const community = "public";

const TABLE_OIDS = {
  suppliesDescription: "1.3.6.1.2.1.43.11.1.1.6",
  suppliesMaxCapacity: "1.3.6.1.2.1.43.11.1.1.8",
  suppliesLevel: "1.3.6.1.2.1.43.11.1.1.9",
};

const session = snmp.createSession(host, community, {
  timeout: 3000,
  retries: 1,
  version: snmp.Version2c
});

console.log("Querying supplies tables on", host);

async function getSubtree(oid) {
  return new Promise((resolve) => {
    const result = {};
    session.subtree(oid, 20, (varbinds) => {
      for (const vb of varbinds) {
        if (!vb || snmp.isVarbindError(vb)) continue;
        result[vb.oid] = vb.value.toString();
      }
    }, () => resolve(result));
  });
}

async function run() {
  const descriptions = await getSubtree(TABLE_OIDS.suppliesDescription);
  const maxCapacities = await getSubtree(TABLE_OIDS.suppliesMaxCapacity);
  const levels = await getSubtree(TABLE_OIDS.suppliesLevel);

  console.log("\nDescriptions:");
  for (const [oid, val] of Object.entries(descriptions)) {
    console.log(`${oid} = ${val}`);
  }

  console.log("\nMax Capacities:");
  for (const [oid, val] of Object.entries(maxCapacities)) {
    console.log(`${oid} = ${val}`);
  }

  console.log("\nLevels:");
  for (const [oid, val] of Object.entries(levels)) {
    console.log(`${oid} = ${val}`);
  }

  session.close();
}

run();
