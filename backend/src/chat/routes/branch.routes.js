const express = require("express");
const { getBranches } = require("../controllers/branch.controller");
const { requireAuth } = require("../../middleware/auth.middleware");

const router = express.Router();

router.use(requireAuth);
router.get("/", getBranches);

module.exports = router;
