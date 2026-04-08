class LiveResult {
  const LiveResult({
    required this.transcript,
    this.speakerTurns = const <SpeakerTurn>[],
  });

  final String transcript;
  final List<SpeakerTurn> speakerTurns;

  bool get hasSpeakerTurns => speakerTurns.isNotEmpty;
}

class SpeakerTurn {
  const SpeakerTurn({required this.speakerLabel, required this.text});

  final String speakerLabel;
  final String text;
}
