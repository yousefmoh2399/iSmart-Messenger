import 'package:flutter/material.dart';
import '../models/workspace_doc.dart';

class WorkspaceTemplate {
  const WorkspaceTemplate({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.category,
    required this.coverColor,
    required this.accentColor,
    required this.blocksBuilder,
  });

  final String id;
  final String title;
  final String description;
  final String icon;
  final String category;
  final String coverColor;
  final Color accentColor;
  final List<WorkspaceBlock> Function() blocksBuilder;
}

class WorkspaceTemplates {
  static final List<WorkspaceTemplate> all = [
    WorkspaceTemplate(
      id: 'daily_plan',
      title: 'خطة عمل اليوم',
      description: 'تنظيم مهام الفرع، الأولويات، ومتابعة الإنجاز اليومي',
      icon: '📋',
      category: 'مهام الفرع',
      coverColor: '0xFFE0F2FE',
      accentColor: const Color(0xFF007AFF),
      blocksBuilder: () => [
        WorkspaceBlock(
          type: WorkspaceBlockType.callout,
          content: 'الهدف الرئيسي لليوم: إنجاز معاملات العملاء بأعلى سرعة وجودة',
          calloutIcon: '🎯',
          colorHex: 'blue',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.heading2,
          content: '☀️ مهام الصباح وتجهيز الفرع',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.todo,
          content: 'فتح الصالة والتأكد من جاهزية المكاتب والمظهر العام',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.todo,
          content: 'فحص اتصال الطابعات الحرارية وتوافر رولات الورق',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.todo,
          content: 'مراجعة رصيد الخزينة والعهدة النقدية الصباحية',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.divider,
          content: '',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.heading2,
          content: '📊 جدول متابعة المعاملات الهامة',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.table,
          content: 'جدول المعاملات',
          tableData: [
            ['رقم الطلب / العميل', 'الخدمة المطلوبة', 'الحالة'],
            ['#1042 - شركة النور', 'تجديد عقود وطباعة', 'قيد التنفيذ'],
            ['#1045 - عميل فرع', 'مراجعة مستندات', 'مكتمل ✅'],
          ],
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.toggle,
          content: 'ملاحظات إضافية لنهاية الدوام',
          subContent: 'التأكد من إغلاق كافة الأجهزة ورفع التقرير اليومي للإدارة قبل المغادرة.',
          isExpanded: true,
        ),
      ],
    ),
    WorkspaceTemplate(
      id: 'shift_handover',
      title: 'استلام وتسليم الشفت',
      description: 'توثيق العهدة، الطابعات، والملاحظات للزميل المستلم',
      icon: '🤝',
      category: 'استلام وتسليم',
      coverColor: '0xFFDCFCE7',
      accentColor: const Color(0xFF10B981),
      blocksBuilder: () => [
        WorkspaceBlock(
          type: WorkspaceBlockType.callout,
          content: 'سجل رسمي لتسليم وتسلم الوردية والعهدة والأجهزة بدقة',
          calloutIcon: '🧾',
          colorHex: 'green',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.table,
          content: 'بيانات التسليم',
          tableData: [
            ['البيان', 'التفاصيل / القيمة', 'التأكيد'],
            ['الموظف المسلّم', 'اكتب الاسم هنا', 'تم التوقيع'],
            ['الموظف المستلم', 'اكتب الاسم هنا', 'تم الاستلام'],
            ['حالة الطابعات والورق', 'ممتازة - 4 رولات احتياطي', 'جاهز ✅'],
          ],
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.heading2,
          content: '☑️ قائمة التحقق قبل المغادرة',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.todo,
          content: 'جرد الدرج النقدي ومطابقته مع تقارير النظام',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.todo,
          content: 'تسليم المفاتيح وبطاقات الدخول للزميل المستلم',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.heading2,
          content: '📌 طلبات معلقة للمتابعة في الشفت القادم',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.quote,
          content: 'العميل صاحب المعاملة رقم #208 سيحضر الساعة 5 مساءً لاستلام الأصل.',
        ),
      ],
    ),
    WorkspaceTemplate(
      id: 'meeting_notes',
      title: 'محضر اجتماع الفرع',
      description: 'تدوين النقاط الرئيسية، القرارات، وتوزيع المهام',
      icon: '👥',
      category: 'اجتماعات',
      coverColor: '0xFFF3E8FF',
      accentColor: const Color(0xFF8B5CF6),
      blocksBuilder: () => [
        WorkspaceBlock(
          type: WorkspaceBlockType.callout,
          content: 'اجتماع فريق العمل الدوري لمناقشة تحسين الأداء وخدمة العملاء',
          calloutIcon: '👥',
          colorHex: 'purple',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.heading2,
          content: 'محاور الاجتماع',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.numbered,
          content: 'مراجعة سرعة الإنجاز وتقليل وقت انتظار العملاء',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.numbered,
          content: 'تنظيم أرشيف الملفات والمستندات الممسوحة ضوئياً',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.heading2,
          content: 'القرارات والمهام المتفق عليها',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.todo,
          content: 'تحديث قوالب الطباعة السريعة على جميع الأجهزة',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.todo,
          content: 'مراجعة مخزون الأحبار والورق الأسبوعي',
        ),
      ],
    ),
    WorkspaceTemplate(
      id: 'ideas_proposals',
      title: 'أفكار ومقترحات تطويرية',
      description: 'مساحة لتدوين الأفكار الإبداعية وحلول المشكلات بالفرع',
      icon: '💡',
      category: 'أفكار ومشاريع',
      coverColor: '0xFFFEF3C7',
      accentColor: const Color(0xFFF59E0B),
      blocksBuilder: () => [
        WorkspaceBlock(
          type: WorkspaceBlockType.callout,
          content: 'فكرة جديدة لتسريع العمل وتحسين تجربة الموظف والعميل',
          calloutIcon: '💡',
          colorHex: 'amber',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.heading2,
          content: 'وصف الفكرة والهدف منها',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.text,
          content: 'اكتب هنا تفاصيل المقترح وكيف سيساعد في توفير الوقت أو الجهد...',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.heading2,
          content: 'خطوات التنفيذ المقترحة',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.bullet,
          content: 'الخطوة الأولى: تجربة الفكرة لمدة أسبوع في الفرع',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.bullet,
          content: 'الخطوة الثانية: قياس النتيجة ومشاركتها مع الإدارة',
        ),
      ],
    ),
    WorkspaceTemplate(
      id: 'tech_reference',
      title: 'دليل الأرقام والأكواد السريعة',
      description: 'حفظ أرقام الطابعات، عناوين IP، والتحويلات الهامة',
      icon: '⚡',
      category: 'شخصي',
      coverColor: '0xFFFCE7F3',
      accentColor: const Color(0xFFEC4899),
      blocksBuilder: () => [
        WorkspaceBlock(
          type: WorkspaceBlockType.callout,
          content: 'مرجع سريع للبيانات التقنية والتحويلات الداخلية للفرع',
          calloutIcon: '⚡',
          colorHex: 'rose',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.table,
          content: 'أرقام وتحويلات هامة',
          tableData: [
            ['الجهة / القسم', 'رقم التحويلة / التواصل', 'ملاحظات'],
            ['الدعم الفني IT', '101', 'متاح طوال اليوم'],
            ['إدارة المشتريات', '105', 'لطلب الورق والأحبار'],
          ],
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.heading2,
          content: 'إعدادات الطابعة والشبكة',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.code,
          content: 'Printer IP: 192.168.1.200\nPort: 9100 (Thermal RAW)',
        ),
      ],
    ),
  ];
}
