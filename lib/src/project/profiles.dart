enum Recipe { clean, counter }

enum StateStyle { cubit, bloc, riverpod, provider }

extension StateStyleBackend on StateStyle {
  bool get usesBloc => this == StateStyle.cubit || this == StateStyle.bloc;

  String get controllerSuffix => switch (this) {
    StateStyle.cubit => 'Cubit',
    StateStyle.bloc => 'Bloc',
    StateStyle.riverpod => 'Notifier',
    StateStyle.provider => 'Notifier',
  };
}

enum LintProfile { flutter, veryGood }

extension LintProfileName on LintProfile {
  String get configName =>
      this == LintProfile.veryGood ? 'very_good' : 'flutter';
}

LintProfile parseLintProfile(String value) => switch (value) {
  'flutter' => LintProfile.flutter,
  'very_good' => LintProfile.veryGood,
  _ => throw FormatException('Unsupported lint profile: $value'),
};
