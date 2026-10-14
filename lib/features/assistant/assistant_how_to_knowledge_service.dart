/// Small, curated Ventio workflow guides used to answer app-usage questions.
///
/// Keep these steps aligned with the corresponding screens and validation
/// rules when those workflows change. Only the best matching guide is sent
/// with a question, keeping provider prompts bounded.
class AssistantHowToKnowledgeService {
  AssistantHowToKnowledgeService._();

  static const int _maxContextCharacters = 4200;
  static const List<String> _howToIntentKeywords = <String>[
    'كيف',
    'طريقه',
    'خطوات',
    'انشاء',
    'انشئ',
    'اعمل',
    'ادخل',
    'ادخال',
    'اضيف',
    'اضافه',
    'اصدر',
    'سجل',
    'اسجل',
    'تسجيل',
    'استخراج',
    'استخرج',
    'استخرجلي',
    'اطبع',
    'اطلع',
    'طلعلي',
    'طباعه',
    'how',
    'create',
    'make',
    'enter',
    'add',
    'generate',
    'print',
  ];

  static const List<_Guide> _guides = <_Guide>[
    _Guide(
      title: 'Create a sales invoice',
      keywords: <String>[
        'فاتورة مبيع',
        'فاتورة مبيعات',
        'انشاء فاتورة',
        'عمل فاتورة',
        'اعمل فاتورة',
        'انشئ فاتورة',
        'اضيف فاتورة',
        'create invoice',
        'make invoice',
        'add invoice',
      ],
      content: '''المسار: المبيعات.
1. ابحث عن المنتج بالاسم أو الرمز، أو امسح الباركود، ثم أضفه إلى السلة. راجع الأصناف والكميات والأسعار والإجمالي.
2. اضغط «متابعة الدفع». اختر العميل؛ ويمكن استخدام العميل النقدي للفاتورة الفورية. اختر طريقة الدفع والعملة، وأدخل المقبوض إذا ظهر حقل المبلغ المقبوض.
3. راجع الخصم والإجمالي والمبلغ المدفوع أو المتبقي، ثم اضغط «تأكيد الدفع» لحفظ الفاتورة.
تنبيهات: استخدم العميل النقدي للمبيعات الفورية المدفوعة؛ خيار الائتمان غير متاح له. لا تخمّن السعر أو المخزون؛ اعتمد القيم الظاهرة في شاشة Ventio. يختلف ظهور الشاشة بحسب صلاحيات المستخدم.''',
    ),
    _Guide(
      title: 'Create a purchase document',
      keywords: <String>[
        'فاتورة شراء',
        'انشاء فاتورة شراء',
        'انشئ فاتورة شراء',
        'مشتريات',
        'شراء بضاعة',
        'purchase invoice',
        'create purchase',
        'new purchase',
      ],
      content: '''المسار: المشتريات ← «شراء جديد».
1. اختر المورد والمستودع؛ كلاهما مطلوب. اختر عملة التكلفة قبل إضافة الأصناف، لأن تغييرها يتوقف بعد إضافة أول صنف.
2. اختر المنتج ووحدة الشراء، وأدخل الكمية وتكلفة الوحدة. راجع تحويل الوحدة إلى وحدات المخزون. أدخل تاريخ الصلاحية إذا كان المنتج يتتبع الصلاحية، ثم أضف السطر وكرر ذلك لباقي الأصناف.
3. حدّد «استلام الآن» إذا كانت البضاعة وصلت. عند الاستلام قد يطلب التطبيق توزيع الكمية على الدفعات وتواريخ الصلاحية. إذا لم تصل بعد، اترك الاستلام مغلقًا ليُحفظ المستند كمسودة، ثم استخدم إجراء الاستلام لاحقًا.
4. اختر حالة الدفع: مدفوع، آجل، أو جزئي. عند الدفع الجزئي أدخل مبلغًا أكبر من صفر ولا يتجاوز الإجمالي، واختر طريقة الدفع. راجع الإجمالي ثم احفظ.
تنبيه: الحفظ كمسودة لا يعني إدخال الكمية إلى المخزون؛ يجب استلام المستند لإثبات وصول البضاعة.''',
    ),
    _Guide(
      title: 'Create a manual journal entry',
      keywords: <String>[
        'قيد',
        'قيد يومية',
        'قيد محاسبي',
        'قيد يدوي',
        'انشاء قيد',
        'انشئ قيد',
        'عمل قيد',
        'اعمل قيد',
        'journal entry',
        'manual journal',
      ],
      content: '''المسار: المحاسبة ← الإدارة ← «قيد يدوي» (Manual journal).
1. اكتب وصف القيد، وحدد الفرع إذا لزم.
2. اختر حسابًا مدينًا وأدخل مبلغه، ثم اختر حسابًا دائنًا وأدخل مبلغه. يمكن اختيار مركز تكلفة لكل طرف.
3. أدخل المبلغ نفسه في طرفي المدين والدائن. راجع الحسابات والمبلغ والوصف قبل الضغط على «ترحيل»؛ فهذا ينشئ القيد مباشرة. تاريخ القيد في هذه النافذة هو تاريخ اليوم تلقائيًا.
تنبيهات: يلزم امتلاك صلاحية إدارة المحاسبة. اختر الحسابات وفق مستند العملية وسياسة المحاسبة في المنشأة؛ لا تختَر حسابًا بالتخمين. الفواتير والقبض والصرف تنشئ قيودها المرتبطة تلقائيًا في الحالات المدعومة، لذلك لا تنشئ قيدًا يدويًا مكررًا لها.''',
    ),
    _Guide(
      title: 'Open or print a report',
      keywords: <String>[
        'تقرير',
        'تقارير',
        'كشف مبيعات',
        'استخراج تقرير',
        'طباعة تقرير',
        'قائمة الدخل',
        'ميزانية',
        'ميزان مراجعة',
        'دفتر الأستاذ',
        'report',
        'reports',
        'sales report',
        'expense report',
        'inventory report',
        'trial balance',
        'income statement',
        'balance sheet',
      ],
      content:
          '''لملخصات المبيعات والمشتريات والمصروفات والمخزون: افتح «التقارير»، راجع البطاقات والبيانات المعروضة، ثم استخدم زر «طباعة» أعلى الصفحة.
للتقارير المحاسبية التفصيلية: افتح «المحاسبة» ← «التقارير المالية»، اختر التقرير (ميزان المراجعة، قائمة الدخل، الميزانية، التدفق النقدي، الضرائب أو المخزون)، ثم حدد الفترة أو الفترة المحاسبية من شريط الفترة. في الميزانية تكون النتيجة كما في التاريخ المحدد. استخدم زر الطباعة داخل التقرير عند الحاجة.
إذا لم تحدد نوع التقرير أو الفترة، اسأل المستخدم عنهما قبل إعطاء خطوات تفصيلية أو تفسير أرقام.''',
    ),
  ];

  /// Returns one relevant, bounded guide; unrelated questions receive no extra
  /// context so business-analysis prompts stay compact.
  static String contextFor(String question) {
    final normalizedQuestion = _normalize(question);
    if (normalizedQuestion.isEmpty) return '';
    if (!_howToIntentKeywords
        .any((keyword) => normalizedQuestion.contains(_normalize(keyword)))) {
      return '';
    }

    _Guide? best;
    var bestScore = 0;
    for (final guide in _guides) {
      var score = 0;
      for (final keyword in guide.keywords) {
        final normalizedKeyword = _normalize(keyword);
        if (normalizedKeyword.isNotEmpty &&
            normalizedQuestion.contains(normalizedKeyword)) {
          // Longer, more specific phrases count more than generic words.
          score += normalizedKeyword.length;
        }
      }
      if (score > bestScore) {
        best = guide;
        bestScore = score;
      }
    }

    if (best == null) return '';
    final context = 'Ventio workflow guide — ${best.title}\n${best.content}';
    return context.length <= _maxContextCharacters
        ? context
        : context.substring(0, _maxContextCharacters);
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff]+'), ' ')
      .trim();
}

class _Guide {
  const _Guide({
    required this.title,
    required this.keywords,
    required this.content,
  });

  final String title;
  final List<String> keywords;
  final String content;
}
