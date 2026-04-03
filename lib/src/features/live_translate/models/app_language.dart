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

const spanishLanguage = AppLanguage(
  code: 'es',
  label: 'Spanish',
  localeTag: 'es-ES',
);

const croatianLanguage = AppLanguage(
  code: 'hr',
  label: 'Croatian',
  localeTag: 'hr-HR',
);

const serbianLanguage = AppLanguage(
  code: 'sr',
  label: 'Serbian',
  localeTag: 'sr-RS',
);

const slovenianLanguage = AppLanguage(
  code: 'sl',
  label: 'Slovenian',
  localeTag: 'sl-SI',
);

const macedonianLanguage = AppLanguage(
  code: 'mk',
  label: 'Macedonian',
  localeTag: 'mk-MK',
);

const albanianLanguage = AppLanguage(
  code: 'sq',
  label: 'Albanian',
  localeTag: 'sq-AL',
);

const montenegrinLanguage = AppLanguage(
  code: 'cnr',
  label: 'Montenegrin',
  localeTag: 'sr-ME',
);

const zipformerSourceLanguages = <AppLanguage>[englishLanguage];

const senseFlowSourceLanguages = <AppLanguage>[englishLanguage, germanLanguage];

const canarySourceLanguages = <AppLanguage>[englishLanguage, germanLanguage];

const whisperSourceLanguages = <AppLanguage>[
  englishLanguage,
  germanLanguage,
  bosnianLanguage,
];

const omnilingualSourceLanguages = <AppLanguage>[
  englishLanguage,
  germanLanguage,
  spanishLanguage,
  bosnianLanguage,
  croatianLanguage,
  serbianLanguage,
  slovenianLanguage,
  macedonianLanguage,
  albanianLanguage,
  montenegrinLanguage,
];

const parakeetSourceLanguages = <AppLanguage>[
  englishLanguage,
  germanLanguage,
  spanishLanguage,
  croatianLanguage,
  slovenianLanguage,
];
