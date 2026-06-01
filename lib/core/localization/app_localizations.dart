import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    final localizations = Localizations.of<AppLocalizations>(context, AppLocalizations);
    assert(localizations != null, 'AppLocalizations not found in widget tree.');
    return localizations!;
  }

  late Map<String, dynamic> _localizedStrings;

  Future<void> load() async {
    final jsonString = await rootBundle.loadString('assets/translations/${locale.languageCode}.json');
    _localizedStrings = json.decode(jsonString) as Map<String, dynamic>;
  }

  String text(String key) {
    return _localizedStrings[key] as String? ?? key;
  }

  String format(String key, Map<String, Object?> values) {
    var template = text(key);
    values.forEach((name, value) {
      template = template.replaceAll('{$name}', value?.toString() ?? '');
    });
    return template;
  }

  bool get isArabic => locale.languageCode == 'ar';

  TextDirection get textDirection => isArabic ? TextDirection.rtl : TextDirection.ltr;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['en', 'ar'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    final appLocalizations = AppLocalizations(locale);
    await appLocalizations.load();
    return appLocalizations;
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) => false;
}
