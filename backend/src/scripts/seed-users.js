const bcrypt = require("bcryptjs");
const { connectDatabase } = require("../config/database");
const User = require("../models/user.model");
const Department = require("../chat/models/department.model");
const { ensureDefaultRoles } = require("../chat/services/role.service");
const { createDepartment } = require("../chat/services/department.service");

const demoUsers = [
  {
    username: "admin@dbacd.com",
    password: "Admin@123456",
    fullName: "System Administrator",
    role: "admin",
    departmentCode: "OPS",
  },
  {
    username: "manager1",
    password: "123456",
    fullName: "Operations Manager",
    role: "manager",
    departmentCode: "OPS",
  },
  {
    username: "user1",
    password: "123456",
    fullName: "Demo User One",
    role: "user",
    departmentCode: "OPS",
  },
  {
    username: "user2",
    password: "123456",
    fullName: "Demo User Two",
    role: "user",
    departmentCode: "HR",
  },
];

async function seedUsers() {
  await connectDatabase();
  await ensureDefaultRoles();

  for (const user of demoUsers) {
    const passwordHash = await bcrypt.hash(user.password, 10);
    await User.updateOne(
      { username: user.username },
      {
        $set: {
          fullName: user.fullName,
          role: user.role,
          passwordHash,
        },
      },
      { upsert: true }
    );
  }

  const admin = await User.findOne({ username: "admin@dbacd.com" });
  const manager = await User.findOne({ username: "manager1" });
  if (!admin) {
    throw new Error("Admin user was not created.");
  }

  const departmentsSeed = [
    {
      name: "Operations",
      code: "OPS",
      description: "Operations and workflow department",
      managers: manager ? [manager._id] : [],
    },
    {
      name: "Human Resources",
      code: "HR",
      description: "People operations and HR documents",
      managers: [],
    },
  ];

  for (const departmentPayload of departmentsSeed) {
    const existing = await Department.findOne({ code: departmentPayload.code }).lean();
    if (!existing) {
      await createDepartment(
        {
          id: admin._id.toString(),
          role: "admin",
        },
        departmentPayload
      );
    }
  }

  const departments = await Department.find({
    code: { $in: departmentsSeed.map((entry) => entry.code) },
  }).lean();
  const departmentsByCode = Object.fromEntries(
    departments.map((department) => [department.code, department])
  );

  for (const user of demoUsers) {
    const department = departmentsByCode[user.departmentCode];
    await User.updateOne(
      { username: user.username },
      {
        $set: {
          departmentId: department?._id || null,
          isActive: true,
        },
      }
    );
  }

  console.log("Seeded demo users successfully.");
  process.exit(0);
}

if (process.env.NODE_ENV === "production" || process.pkg) {
  console.error("Seeding users is disabled in production.");
  process.exit(1);
}

seedUsers().catch((error) => {
  console.error("Failed to seed users", error);
  process.exit(1);
});

