const ReportTemplate = require("../models/report-template.model");
const ApiError = require("../../utils/api-error");

const AVAILABLE_COLUMNS = {
  printer_consumption: [
    {
      key: "index",
      label: "الرقم",
      defaultEnabled: true,
      order: 1,
      width: 40,
      align: "center",
      description: "الرقم التسلسلي للسطر",
    },
    {
      key: "branchName",
      label: "الفرع",
      defaultEnabled: true,
      order: 2,
      width: 140,
      align: "center",
      description: "اسم الفرع",
    },
    {
      key: "printerName",
      label: "الطابعة",
      defaultEnabled: true,
      order: 3,
      width: 140,
      align: "center",
      description: "اسم الطابعة أو عنوانها",
    },
    {
      key: "monoPages",
      label: "عدد الصفحات (أسود)",
      defaultEnabled: true,
      order: 4,
      width: 85,
      align: "center",
      isNumeric: true,
      description: "استهلاك الطباعة بالأبيض والأسود",
    },
    {
      key: "colorPages",
      label: "عدد الصفحات (ملون)",
      defaultEnabled: true,
      order: 5,
      width: 85,
      align: "center",
      isNumeric: true,
      description: "استهلاك الطباعة الملونة",
    },
    {
      key: "wastePages",
      label: "الورق الهالك",
      defaultEnabled: true,
      order: 6,
      width: 70,
      align: "center",
      isNumeric: true,
      description: "عدد أوراق الطباعة التالفة أو الهالكة",
    },
    {
      key: "scanPages",
      label: "الاسكان",
      defaultEnabled: true,
      order: 7,
      width: 70,
      align: "center",
      isNumeric: true,
      description: "عدد صفحات المسح الضوئي",
    },
    {
      key: "totalPaper",
      label: "الإجمالي للورق",
      defaultEnabled: true,
      order: 8,
      width: 85,
      align: "center",
      isNumeric: true,
      description: "إجمالي استهلاك الورق الفعلي مع الهالك",
    },
    {
      key: "overallTotalReams",
      label: "إجمالي الرزم",
      defaultEnabled: true,
      order: 9,
      width: 85,
      align: "center",
      isNumeric: true,
      description: "عدد رزم الورق (500 ورقة/رزمة)",
    },
    {
      key: "branchCode",
      label: "كود الفرع",
      defaultEnabled: false,
      order: 10,
      width: 70,
      align: "center",
      description: "الرمز التعريفي للفرع",
    },
    {
      key: "ipAddress",
      label: "عنوان IP",
      defaultEnabled: false,
      order: 11,
      width: 90,
      align: "center",
      description: "عنوان IP للشبكة",
    },
    {
      key: "model",
      label: "الموديل",
      defaultEnabled: false,
      order: 12,
      width: 110,
      align: "center",
      description: "طراز وموديل الطابعة",
    },
    {
      key: "serialNumber",
      label: "الرقم التسلسلي",
      defaultEnabled: false,
      order: 13,
      width: 100,
      align: "center",
      description: "الرقم التسلسلي للجهاز",
    },
    {
      key: "vendor",
      label: "الشركة المصنعة",
      defaultEnabled: false,
      order: 14,
      width: 80,
      align: "center",
      description: "الشركة المصنعة (HP, Canon, Xerox...)",
    },
    {
      key: "status",
      label: "الحالة",
      defaultEnabled: false,
      order: 15,
      width: 70,
      align: "center",
      description: "حالة الطابعة (متصلة / غير متصلة)",
    },
    {
      key: "requiredReams",
      label: "الرزم المطلوبة محاسبياً",
      defaultEnabled: false,
      order: 16,
      width: 90,
      align: "center",
      isNumeric: true,
      description: "عدد الرزم المقربة للأعلى محاسبياً",
    },
    {
      key: "estimatedClients",
      label: "العملاء التقديريين",
      defaultEnabled: false,
      order: 17,
      width: 90,
      align: "center",
      isNumeric: true,
      description: "عدد العملاء التقديري بمعدل 16 ورقة/عميل",
    },
    {
      key: "currentTotal",
      label: "العداد الحالي",
      defaultEnabled: false,
      order: 18,
      width: 80,
      align: "center",
      isNumeric: true,
      description: "قراءة العداد الحالية",
    },
    {
      key: "lifetimeTotal",
      label: "عداد العمر الكلي",
      defaultEnabled: false,
      order: 19,
      width: 80,
      align: "center",
      isNumeric: true,
      description: "إجمالي الصفحات المطبوعة منذ تشغيل الطابعة",
    },
    {
      key: "dataQuality",
      label: "جودة القراءات",
      defaultEnabled: false,
      order: 20,
      width: 90,
      align: "center",
      description: "مؤشر دقة واكتمال بيانات الاستهلاك",
    },
  ],

  tickets: [
    {
      key: "ticketNumber",
      label: "رقم التذكرة",
      defaultEnabled: true,
      order: 1,
      width: 70,
      align: "center",
      description: "الرقم التسلسلي للطلب (#TKT-102)",
    },
    {
      key: "title",
      label: "العنوان",
      defaultEnabled: true,
      order: 2,
      width: 150,
      align: "center",
      description: "عنوان التذكرة أو المشكلة",
    },
    {
      key: "status",
      label: "الحالة",
      defaultEnabled: true,
      order: 3,
      width: 75,
      align: "center",
      description: "حالة التذكرة الحالية",
    },
    {
      key: "priority",
      label: "الأولوية",
      defaultEnabled: true,
      order: 4,
      width: 70,
      align: "center",
      description: "درجة الأولوية (حرجة، عالية، عادية، منخفضة)",
    },
    {
      key: "department",
      label: "القسم المعني",
      defaultEnabled: true,
      order: 5,
      width: 100,
      align: "center",
      description: "القسم الموجه إليه الطلب",
    },
    {
      key: "branch",
      label: "فرع مقدم الطلب",
      defaultEnabled: true,
      order: 6,
      width: 90,
      align: "center",
      description: "الفرع أو القسم التابع له المنشئ",
    },
    {
      key: "createdBy",
      label: "بواسطة",
      defaultEnabled: true,
      order: 7,
      width: 100,
      align: "center",
      description: "اسم الموظف أو المستخدم منشئ التذكرة",
    },
    {
      key: "assignedTo",
      label: "المسؤول",
      defaultEnabled: true,
      order: 8,
      width: 100,
      align: "center",
      description: "موظف الدعم أو المشرف المكلف",
    },
    {
      key: "createdAt",
      label: "تاريخ الإنشاء",
      defaultEnabled: true,
      order: 9,
      width: 80,
      align: "center",
      description: "تاريخ فتح التذكرة",
    },
    {
      key: "description",
      label: "الوصف والتفاصيل",
      defaultEnabled: false,
      order: 10,
      width: 180,
      align: "right",
      description: "الشرح التفصيلي للطلب أو الشكوى",
    },
    {
      key: "ticketType",
      label: "نوع الطلب",
      defaultEnabled: false,
      order: 11,
      width: 70,
      align: "center",
      description: "تذكرة دعم، شكوى، مقترح",
    },
    {
      key: "resolvedBy",
      label: "من قام بالحل",
      defaultEnabled: false,
      order: 12,
      width: 100,
      align: "center",
      description: "المستخدم الذي حوّل الحالة إلى تم الحل",
    },
    {
      key: "dueDate",
      label: "تاريخ الاستحقاق (SLA)",
      defaultEnabled: false,
      order: 13,
      width: 80,
      align: "center",
      description: "الموعد المستهدف لحل التذكرة",
    },
    {
      key: "lastUpdateAt",
      label: "آخر تحديث",
      defaultEnabled: false,
      order: 14,
      width: 80,
      align: "center",
      description: "تاريخ آخر رد أو تغيير حالة",
    },
    {
      key: "resolvedAt",
      label: "تاريخ الحل",
      defaultEnabled: false,
      order: 15,
      width: 80,
      align: "center",
      description: "تاريخ حل المشكلة",
    },
    {
      key: "closedAt",
      label: "تاريخ الإغلاق",
      defaultEnabled: false,
      order: 16,
      width: 80,
      align: "center",
      description: "تاريخ الإغلاق النهائي",
    },
    {
      key: "durationMinutes",
      label: "مدة الحل (بالدقائق)",
      defaultEnabled: false,
      order: 17,
      width: 80,
      align: "center",
      isNumeric: true,
      description: "الفارق الزمني بين الإنشاء والحل",
    },
    {
      key: "updatesCount",
      label: "عدد التحديثات",
      defaultEnabled: false,
      order: 18,
      width: 70,
      align: "center",
      isNumeric: true,
      description: "عدد الردود والأنشطة المسجلة",
    },
    {
      key: "rating",
      label: "التقييم",
      defaultEnabled: false,
      order: 19,
      width: 70,
      align: "center",
      description: "تقييم الخدمة بالنجوم",
    },
    {
      key: "lastMessage",
      label: "آخر رسالة/تعليق",
      defaultEnabled: false,
      order: 20,
      width: 150,
      align: "right",
      description: "نص آخر تعليق أو تحديث عام",
    },
  ],
};

function getAvailableColumns(reportType) {
  return AVAILABLE_COLUMNS[reportType] || [];
}

function getDefaultColumns(reportType) {
  const all = getAvailableColumns(reportType);
  return all.map((col) => ({
    key: col.key,
    label: col.label,
    enabled: col.defaultEnabled,
    order: col.order,
    width: col.width,
    align: col.align || "center",
  }));
}

async function ensureDefaultTemplate(reportType) {
  let template = await ReportTemplate.findOne({ reportType, isDefault: true });
  if (!template) {
    // If any template exists for this reportType, make the first one default
    template = await ReportTemplate.findOne({ reportType });
    if (template) {
      template.isDefault = true;
      await template.save();
      return template;
    }

    // Seed default template
    const isPrinters = reportType === "printer_consumption";
    template = await ReportTemplate.create({
      name: isPrinters ? "القالب المعتمد لاستهلاك الورق" : "القالب المعتمد لتذاكر الدعم والشكاوى",
      reportType,
      description: "القالب الأساسي المعتمد في المنظومة للطباعة والتصدير",
      isDefault: true,
      headerConfig: {
        line1: "جمعية رجال الأعمال والمستثمرين بالدقهلية",
        line2: "مشروع تنمية المنشآت الصغيرة والحرفية",
        line3: "رقم الإشهار: 777 لسنة 1995 - رقم الترخيص: 1031",
        titleFormat: isPrinters
          ? "استهلاك {entity} للورق عن شهر {month} {year}"
          : "تقرير {ticketType}",
        showLogo1: true,
        showLogo2: true,
        footerNote: "يعتمد، إدارة تكنولوجيا المعلومات",
        preparedByLabel: "إعداد: ",
      },
      columns: getDefaultColumns(reportType),
      options: {
        orientation: "landscape",
        includeSummaryRow: true,
        fontSize: 12,
        rowHeight: 50,
        exportFormatDefault: "xlsx",
      },
    });
  }
  return template;
}

async function listTemplates(reportType) {
  await ensureDefaultTemplate(reportType);
  return ReportTemplate.find({ reportType }).sort({ isDefault: -1, createdAt: -1 });
}

async function getTemplateById(id) {
  const template = await ReportTemplate.findById(id);
  if (!template) {
    throw new ApiError(404, "Report template not found.");
  }
  return template;
}

async function getActiveTemplate(reportType, templateId = null) {
  if (templateId) {
    const custom = await ReportTemplate.findById(templateId);
    if (custom) return custom;
  }
  return ensureDefaultTemplate(reportType);
}

async function createTemplate(user, data) {
  if (!data.name || !data.reportType) {
    throw new ApiError(400, "Template name and reportType are required.");
  }

  // If isDefault is true, un-default others of the same reportType
  if (data.isDefault) {
    await ReportTemplate.updateMany(
      { reportType: data.reportType },
      { $set: { isDefault: false } },
    );
  }

  const columns = Array.isArray(data.columns) && data.columns.length
    ? data.columns
    : getDefaultColumns(data.reportType);

  const template = await ReportTemplate.create({
    name: data.name,
    reportType: data.reportType,
    description: data.description || "",
    isDefault: data.isDefault === true,
    headerConfig: data.headerConfig || {},
    columns,
    options: data.options || {},
    createdBy: user?.id || null,
    updatedBy: user?.id || null,
  });

  return template;
}

async function updateTemplate(user, id, data) {
  const template = await ReportTemplate.findById(id);
  if (!template) {
    throw new ApiError(404, "Report template not found.");
  }

  if (data.isDefault && !template.isDefault) {
    await ReportTemplate.updateMany(
      { reportType: template.reportType },
      { $set: { isDefault: false } },
    );
  }

  if (data.name !== undefined) template.name = data.name;
  if (data.description !== undefined) template.description = data.description;
  if (data.isDefault !== undefined) template.isDefault = data.isDefault;
  if (data.headerConfig !== undefined) template.headerConfig = data.headerConfig;
  if (data.columns !== undefined) template.columns = data.columns;
  if (data.options !== undefined) template.options = data.options;
  template.updatedBy = user?.id || null;

  await template.save();
  return template;
}

async function deleteTemplate(user, id) {
  const template = await ReportTemplate.findById(id);
  if (!template) {
    throw new ApiError(404, "Report template not found.");
  }

  const count = await ReportTemplate.countDocuments({
    reportType: template.reportType,
  });
  if (count <= 1) {
    throw new ApiError(400, "Cannot delete the only template for this report type.");
  }

  const wasDefault = template.isDefault;
  await template.deleteOne();

  if (wasDefault) {
    // Pick another template to be default
    const replacement = await ReportTemplate.findOne({
      reportType: template.reportType,
    });
    if (replacement) {
      replacement.isDefault = true;
      await replacement.save();
    }
  }

  return { success: true };
}

async function setDefaultTemplate(user, id) {
  const template = await ReportTemplate.findById(id);
  if (!template) {
    throw new ApiError(404, "Report template not found.");
  }

  await ReportTemplate.updateMany(
    { reportType: template.reportType },
    { $set: { isDefault: false } },
  );

  template.isDefault = true;
  template.updatedBy = user?.id || null;
  await template.save();

  return template;
}

module.exports = {
  AVAILABLE_COLUMNS,
  getAvailableColumns,
  getDefaultColumns,
  ensureDefaultTemplate,
  listTemplates,
  getTemplateById,
  getActiveTemplate,
  createTemplate,
  updateTemplate,
  deleteTemplate,
  setDefaultTemplate,
};
