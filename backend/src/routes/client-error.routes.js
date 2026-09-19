const express = require("express");
const { reportError } = require("../controllers/client-error.controller");
const { requireAuth } = require("../middleware/auth.middleware");

const router = express.Router();

// We can allow authenticated users to post errors.
router.post("/", requireAuth, reportError);

module.exports = router;
