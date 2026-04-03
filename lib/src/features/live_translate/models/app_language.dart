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

const englishLanguage = AppLanguage(
  code: 'en',
  label: 'English',
  localeTag: 'en-US',
);

const germanLanguage = AppLanguage(
  code: 'de',
  label: 'German',
  localeTag: 'de-DE',
);

const bosnianLanguage = AppLanguage(
  code: 'bs',
  label: 'Bosnian',
  localeTag: 'bs-BA',
);

const zipformerSourceLanguages = <AppLanguage>[englishLanguage];

const senseFlowSourceLanguages = <AppLanguage>[englishLanguage, germanLanguage];

const canarySourceLanguages = <AppLanguage>[englishLanguage, germanLanguage];

const whisperSourceLanguages = <AppLanguage>[
  englishLanguage,
  germanLanguage,
  bosnianLanguage,
];
