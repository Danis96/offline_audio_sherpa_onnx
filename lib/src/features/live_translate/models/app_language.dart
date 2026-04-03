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

const supportedTargetLanguages = <AppLanguage>[
  AppLanguage(code: 'bs', label: 'Bosnian', localeTag: 'bs-BA'),
  AppLanguage(code: 'en', label: 'English', localeTag: 'en-US'),
  AppLanguage(code: 'de', label: 'German', localeTag: 'de-DE'),
  AppLanguage(code: 'hr', label: 'Croatian', localeTag: 'hr-HR'),
  AppLanguage(code: 'sr', label: 'Serbian', localeTag: 'sr-RS'),
  AppLanguage(code: 'zh', label: 'Chinese', localeTag: 'zh-CN'),
  AppLanguage(code: 'ja', label: 'Japanese', localeTag: 'ja-JP'),
  AppLanguage(code: 'ko', label: 'Korean', localeTag: 'ko-KR'),
  AppLanguage(code: 'yue', label: 'Cantonese', localeTag: 'zh-HK'),
];
