const mongoose = require("mongoose");

const itAuditLogSchema = new mongoose.Schema(
  {
    action: { type: String, required: true, trim: true, index: true },
    entityType: { type: String, required: true, trim: true, index: true },
    entityId: { type: mongoose.Schema.Types.ObjectId, required: true, index: true },
    documentNumber: { type: String, default: null, trim: true, index: true },
    summary: { type: String, required: true, trim: true },
    actorId: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true },
    actorName: { type: String, required: true, trim: true },
    metadata: { type: mongoose.Schema.Types.Mixed, default: {} },
    ipAddress: { type: String, default: "", trim: true },
    userAgent: { type: String, default: "", trim: true },
  },
  { timestamps: { createdAt: true, updatedAt: false } },
);

for (const hook of ["deleteOne", "deleteMany", "findOneAndDelete", "findOneAndRemove"]) {
  itAuditLogSchema.pre(hook, function preventAuditDeletion() {
    throw new Error("IT audit logs are immutable.");
  });
}

module.exports = mongoose.model("ItAuditLog", itAuditLogSchema);
