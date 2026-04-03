class AppLanguage {
  const AppLanguage({
    required this.code,
    required this.label,
    required this.localeTag,
  });

  final String code;
  final String label;
  final String localeTag;
}

const supportedSourceLanguages = <AppLanguage>[
  AppLanguage(code: 'en', label: 'English', localeTag: 'en-US'),
];
