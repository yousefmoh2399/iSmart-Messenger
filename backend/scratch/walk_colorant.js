const snmp = require("net-snmp");

const host = "192.168.10.11";
const community = "public";

const session = snmp.createSession(host, community, {
  timeout: 3000,
  retries: 1,
  version: snmp.Version2c
});

console.log("Walking colorant MIB (1.3.6.1.2.1.43.12) on", host);

session.subtree("1.3.6.1.2.1.43.12", 20, (varbinds) => {
  for (const vb of varbinds) {
    if (!vb || snmp.isVarbindError(vb)) continue;
    console.log(`${vb.oid} = ${vb.value.toString()} (type: ${vb.type})`);
  }
}, (err) => {
  if (err) console.error("Walk error:", err);
  session.close();
});
