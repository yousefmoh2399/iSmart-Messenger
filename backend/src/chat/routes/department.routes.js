const express = require("express");
const { getDepartments } = require("../controllers/department.controller");
const { requireAuth } = require("../../middleware/auth.middleware");

const router = express.Router();

router.use(requireAuth);
router.get("/", getDepartments);

module.exports = router;
