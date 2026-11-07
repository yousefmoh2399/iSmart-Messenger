const mongoose = require("mongoose");

const ReportColumnSchema = new mongoose.Schema(
  {
    key: { type: String, required: true },
    label: { type: String, required: true },
    enabled: { type: Boolean, default: true },
    order: { type: Number, default: 0 },
    width: { type: Number, default: 100 },
    align: {
      type: String,
      enum: ["center", "right", "left"],
      default: "center",
    },
    calculationType: {
      type: String,
      enum: ["none", "sum", "avg", "count", "diff", "min", "max"],
      default: "none",
    },
  },
  { _id: false },
);

const ReportHeaderConfigSchema = new mongoose.Schema(
  {
    line1: {
      type: String,
      default: "جمعية رجال الأعمال والمستثمرين بالدقهلية",
    },
    line2: {
      type: String,
      default: "مشروع تنمية المنشآت الصغيرة والحرفية",
    },
    line3: {
      type: String,
      default: "رقم الإشهار: 777 لسنة 1995 - رقم الترخيص: 1031",
    },
    titleFormat: { type: String, default: "" },
    showLogo1: { type: Boolean, default: true },
    showLogo2: { type: Boolean, default: true },
    customLogo1: { type: String, default: "" },
    customLogo2: { type: String, default: "" },
    secondaryNote: { type: String, default: "" },
    footerNote: {
      type: String,
      default: "يعتمد، إدارة تكنولوجيا المعلومات",
    },
    preparedByLabel: { type: String, default: "إعداد: " },
    approvedByLabel: { type: String, default: "اعتماد: " },
  },
  { _id: false },
);

const ReportOptionsSchema = new mongoose.Schema(
  {
    orientation: {
      type: String,
      enum: ["landscape", "portrait"],
      default: "landscape",
    },
    includeSummaryRow: { type: Boolean, default: true },
    fontSize: { type: Number, default: 12 },
    rowHeight: { type: Number, default: 50 },
    exportFormatDefault: {
      type: String,
      enum: ["xlsx", "pdf"],
      default: "xlsx",
    },
  },
  { _id: false },
);

const ReportTemplateSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true },
    reportType: {
      type: String,
      required: true,
      enum: ["printer_consumption", "tickets"],
    },
    description: { type: String, default: "" },
    isDefault: { type: Boolean, default: false },
    headerConfig: { type: ReportHeaderConfigSchema, default: () => ({}) },
    columns: { type: [ReportColumnSchema], default: [] },
    options: { type: ReportOptionsSchema, default: () => ({}) },
    createdBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      default: null,
    },
    updatedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      default: null,
    },
  },
  { timestamps: true },
);

ReportTemplateSchema.index({ reportType: 1, isDefault: 1 });

module.exports = mongoose.model("ReportTemplate", ReportTemplateSchema);
