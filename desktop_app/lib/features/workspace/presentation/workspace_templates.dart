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
      description: 'تنظيم مهام الفرع، الأولويات، ومتابعة العمل اليومي',
      icon: '📋',
      category: 'مهام الفرع',
      coverColor: '0xFFE0F2FE',
      accentColor: const Color(0xFF0284C7),
      blocksBuilder: () => [
        WorkspaceBlock(
          type: WorkspaceBlockType.callout,
          content: '🎯 الهدف الرئيسي لليوم: إنجاز معاملات العملاء والالتزام بجودة الخدمة',
          calloutIcon: '🎯',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.heading1,
          content: 'مهام الصباح وتجهيز الفرع',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.todo,
          content: 'فتح الصالة والتأكد من النظافة والمظهر العام',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.todo,
          content: 'تشغيل أجهزة الكمبيوتر والتأكد من اتصال الطابعات الحرارية',
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
          type: WorkspaceBlockType.heading1,
          content: 'المعاملات والمتابعات الهامة',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.todo,
          content: 'متابعة الطلبات المعلقة من الشفت السابق',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.todo,
          content: 'التواصل مع العملاء للرد على الاستفسارات',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.callout,
          content: '💡 ملاحظة: رفع تقرير المعاملات المنجزة قبل انتهاء الدوام',
          calloutIcon: '💡',
        ),
      ],
    ),
    WorkspaceTemplate(
      id: 'shift_handover',
      title: 'استلام وتسليم الشفت',
      description: 'توثيق العهدة، الخزينة، والملاحظات للزميل القادم',
      icon: '🤝',
      category: 'استلام وتسليم',
      coverColor: '0xFFDCFCE7',
      accentColor: const Color(0xFF059669),
      blocksBuilder: () => [
        WorkspaceBlock(
          type: WorkspaceBlockType.callout,
          content: 'سجل رسمي لتوثيق تسليم وتسلم الشفت والعهدة بدقة',
          calloutIcon: '🧾',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.heading1,
          content: 'الرصيد النقدي والعهدة',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.todo,
          content: 'جرد رصيد الدرج النقدي ومطابقته مع مبيعات اليوم',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.todo,
          content: 'تسليم بطاقات النظام والمفاتيح للزميل المستلم',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.divider,
          content: '',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.heading1,
          content: 'حالة الطابعات والمستهلكات',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.bullet,
          content: 'رولات الورق الحراري: كافية للشفت القادم',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.bullet,
          content: 'مستوى الحبر والأجهزة: تعمل بكفاءة وبدون أعطال',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.divider,
          content: '',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.heading2,
          content: 'ملاحظات وتنبيهات معلقة',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.quote,
          content: 'يرجى متابعة العميل الخاص بالطلب رقم #1042 عند حضوره لاستلام المستندات.',
        ),
      ],
    ),
    WorkspaceTemplate(
      id: 'ideas_proposals',
      title: 'فكرة أو مقترح جديد',
      description: 'توثيق أفكار مبتكرة لتطوير أداء الفرع وزيادة الإنتاجية',
      icon: '💡',
      category: 'أفكار ومشاريع',
      coverColor: '0xFFFEF3C7',
      accentColor: const Color(0xFFD97706),
      blocksBuilder: () => [
        WorkspaceBlock(
          type: WorkspaceBlockType.callout,
          content: 'الأفكار الصغيرة المستمرة تصنع التميز الكبير للفرع!',
          calloutIcon: '✨',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.heading1,
          content: 'ملخص الفكرة أو الفرصة',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.text,
          content: 'شرح موجز للفكرة وما هي المشكلة التي تعالجها في الفرع...',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.heading1,
          content: 'خطوات التنفيذ المقترحة',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.todo,
          content: 'الخطوة 1: دراسة الاحتياج والتكلفة',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.todo,
          content: 'الخطوة 2: مناقشة الفكرة مع مدير الفرع',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.todo,
          content: 'الخطوة 3: تجربة الفكرة وقياس الأثر',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.divider,
          content: '',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.heading2,
          content: 'الفوائد والنتائج المتوقعة',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.bullet,
          content: 'تسريع وقت خدمة العميل وتقليل الانتظار',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.bullet,
          content: 'تسهيل عمل الموظفين والحد من الأخطاء',
        ),
      ],
    ),
    WorkspaceTemplate(
      id: 'meeting_notes',
      title: 'محضر اجتماع ومتابعة',
      description: 'تسجيل وقائع الاجتماعات والقرارات والمسؤوليات',
      icon: '👥',
      category: 'اجتماعات',
      coverColor: '0xFFF3E8FF',
      accentColor: const Color(0xFF7C3AED),
      blocksBuilder: () => [
        WorkspaceBlock(
          type: WorkspaceBlockType.callout,
          content: 'محضر توثيقي للقرارات والتكليفات المعتمدة في الاجتماع',
          calloutIcon: '📌',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.heading1,
          content: 'أبرز النقاط التي نوقشت',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.bullet,
          content: 'مراجعة أداء الفرع ومؤشرات الجودة خلال الأسبوع الماضي',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.bullet,
          content: 'مناقشة خطط التطوير وتلبية طلبات الإدارة',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.divider,
          content: '',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.heading1,
          content: 'القرارات والتكليفات المتفق عليها',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.todo,
          content: 'تحديث بيانات المخزون والأجهزة',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.todo,
          content: 'إرسال التقرير المالي الأسبوعي للإدارة',
        ),
      ],
    ),
    WorkspaceTemplate(
      id: 'quick_checklist',
      title: 'قائمة مهام تفاعلية',
      description: 'قائمة مهام سريعة ومرتبة للمتابعة الفورية',
      icon: '🎯',
      category: 'مهام الفرع',
      coverColor: '0xFFFCE7F3',
      accentColor: const Color(0xFFDB2777),
      blocksBuilder: () => [
        WorkspaceBlock(
          type: WorkspaceBlockType.heading1,
          content: 'قائمة الأولويات والمهام',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.todo,
          content: 'المهمة الأولى ذات الأولوية القصوى',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.todo,
          content: 'المهمة الثانية ومتابعة المستندات',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.todo,
          content: 'المهمة الثالثة وأرشفة الإيصالات',
        ),
        WorkspaceBlock(
          type: WorkspaceBlockType.todo,
          content: 'المهمة الرابعة والتأكد من إغلاق الصندوق',
        ),
      ],
    ),
  ];
}
