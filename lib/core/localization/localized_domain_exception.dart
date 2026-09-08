import 'app_localizations.dart';

class LocalizedDomainException implements Exception {
  const LocalizedDomainException(
    this.key, {
    this.values = const <String, Object?>{},
    required this.fallback,
  });

  final String key;
  final Map<String, Object?> values;
  final String fallback;

  @override
  String toString() => fallback;
}

String localizedErrorText(AppLocalizations translations, Object error) {
  if (error is LocalizedDomainException) {
    final localized = translations.format(error.key, error.values);
    if (localized.trim().isEmpty || localized == error.key) {
      return error.fallback;
    }
    return localized;
  }
  return error.toString();
}
