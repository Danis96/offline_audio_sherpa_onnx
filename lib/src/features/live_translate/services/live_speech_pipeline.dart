import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../models/app_language.dart';
import '../models/live_result.dart';
import 'soniox_socket.dart';

abstract class LiveSpeechPipeline {
  bool get isReady;

  Future<void> warmUp({required AppLanguage sourceLanguage});

  Future<void> resetSession();

  Future<LiveResult?> ingestAudioFrame({
    required Uint8List pcmBytes,
    required List<double> samples,
  });

  Future<LiveResult?> finishSession();

  Future<void> dispose();
}

class SonioxRealtimePipeline implements LiveSpeechPipeline {
  SonioxRealtimePipeline({
    required String Function() apiKeyProvider,
    required bool Function() diarizationEnabledProvider,
    this.socketUrl = 'wss://stt-rt.soniox.com/transcribe-websocket',
  }) : _apiKeyProvider = apiKeyProvider,
       _diarizationEnabledProvider = diarizationEnabledProvider;

  final String Function() _apiKeyProvider;
  final bool Function() _diarizationEnabledProvider;
  final String socketUrl;

  SonioxSocket? _socket;
  StreamSubscription<Object>? _messageSub;
  Completer<void>? _sessionClosedCompleter;
  AppLanguage _sourceLanguage = englishLanguage;

  bool _isConfigured = false;
  String _finalTranscript = '';
  String _previewTranscript = '';
  String _lastDeliveredTranscript = '';
  String? _pendingError;
  final List<_SonioxToken> _finalTokens = <_SonioxToken>[];
  List<_SonioxToken> _previewTokens = <_SonioxToken>[];

  @override
  bool get isReady => _isConfigured;

  @override
  Future<void> warmUp({required AppLanguage sourceLanguage}) async {
    final apiKey = _apiKeyProvider().trim();
    if (apiKey.isEmpty) {
      throw StateError(
        'Enter a Soniox API key before starting the Soniox engine.',
      );
    }

    _sourceLanguage = sourceLanguage;
    _isConfigured = true;
    _pendingError = null;
  }

  @override
  Future<void> resetSession() async {
    if (!_isConfigured) {
      return;
    }

    await _closeSocket();
    _finalTranscript = '';
    _previewTranscript = '';
    _lastDeliveredTranscript = '';
    _pendingError = null;
    _finalTokens.clear();
    _previewTokens = <_SonioxToken>[];

    final socket = await connectSonioxSocket(socketUrl);
    final sessionClosedCompleter = Completer<void>();

    _socket = socket;
    _sessionClosedCompleter = sessionClosedCompleter;
    _messageSub = socket.messages.listen(
      _handleSocketMessage,
      onError: (Object error, StackTrace stackTrace) {
        _pendingError = 'Soniox connection error: $error';
        if (!sessionClosedCompleter.isCompleted) {
          sessionClosedCompleter.complete();
        }
      },
      onDone: () {
        if (!sessionClosedCompleter.isCompleted) {
          sessionClosedCompleter.complete();
        }
      },
    );

    await socket.sendText(
      jsonEncode(<String, Object>{
        'api_key': _apiKeyProvider().trim(),
        'model': 'stt-rt-v4',
        'audio_format': 'pcm_s16le',
        'sample_rate': 16000,
        'num_channels': 1,
        'language_hints': <String>[_sourceLanguage.code],
        'enable_speaker_diarization': _diarizationEnabledProvider(),
        'enable_endpoint_detection': true,
        'max_endpoint_delay_ms': 900,
      }),
    );
  }

  @override
  Future<LiveResult?> ingestAudioFrame({
    required Uint8List pcmBytes,
    required List<double> samples,
  }) async {
    _throwIfPendingError();

    final socket = _socket;
    if (socket == null) {
      return null;
    }

    await socket.sendBinary(pcmBytes);
    return _drainLatestTranscript();
  }

  @override
  Future<LiveResult?> finishSession() async {
    _throwIfPendingError();

    final socket = _socket;
    if (socket == null) {
      return _drainLatestTranscript();
    }

    await socket.sendBinary(Uint8List(0));
    await _sessionClosedCompleter?.future.timeout(
      const Duration(seconds: 4),
      onTimeout: () {},
    );
    _throwIfPendingError();
    return _drainLatestTranscript();
  }

  @override
  Future<void> dispose() async {
    _isConfigured = false;
    await _closeSocket();
  }

  Future<void> _closeSocket() async {
    await _messageSub?.cancel();
    _messageSub = null;
    await _socket?.close();
    _socket = null;
    _sessionClosedCompleter = null;
  }

  void _handleSocketMessage(Object message) {
    if (message is! String) {
      return;
    }

    final decoded = jsonDecode(message);
    if (decoded is! Map) {
      return;
    }
    final json = Map<String, dynamic>.from(decoded);

    final errorCode = json['error_code'];
    if (errorCode != null) {
      _pendingError = 'Soniox error $errorCode: ${json['error_message']}';
      if (_sessionClosedCompleter?.isCompleted == false) {
        _sessionClosedCompleter?.complete();
      }
      return;
    }

    final tokens = (json['tokens'] as List<dynamic>? ?? const <dynamic>[]);
    final nonFinalTokens = <_SonioxToken>[];
    final nonFinalBuffer = StringBuffer();

    for (final tokenEntry in tokens) {
      if (tokenEntry is! Map<String, dynamic>) {
        continue;
      }

      final text = tokenEntry['text'];
      if (text is! String || text.isEmpty) {
        continue;
      }

      final token = _SonioxToken(
        text: text,
        speaker: _normalizeSpeaker(tokenEntry['speaker']),
      );

      if (tokenEntry['is_final'] == true) {
        _finalTokens.add(token);
        _finalTranscript += text;
      } else {
        nonFinalTokens.add(token);
        nonFinalBuffer.write(text);
      }
    }

    _previewTokens = <_SonioxToken>[..._finalTokens, ...nonFinalTokens];
    _previewTranscript = _finalTranscript + nonFinalBuffer.toString();
    if (json['finished'] == true) {
      _previewTranscript = _finalTranscript;
      _previewTokens = List<_SonioxToken>.from(_finalTokens);
      if (_sessionClosedCompleter?.isCompleted == false) {
        _sessionClosedCompleter?.complete();
      }
    }
  }

  LiveResult? _drainLatestTranscript() {
    final transcript = _previewTranscript.trim();
    if (transcript.isEmpty || transcript == _lastDeliveredTranscript) {
      return null;
    }

    _lastDeliveredTranscript = transcript;
    return LiveResult(
      transcript: transcript,
      speakerTurns: _buildSpeakerTurns(_previewTokens),
    );
  }

  void _throwIfPendingError() {
    final error = _pendingError;
    if (error != null) {
      throw StateError(error);
    }
  }

  String? _normalizeSpeaker(Object? rawSpeaker) {
    if (rawSpeaker is String && rawSpeaker.trim().isNotEmpty) {
      return rawSpeaker.trim();
    }
    if (rawSpeaker is num) {
      return 'Speaker ${rawSpeaker.toInt()}';
    }
    return null;
  }

  List<SpeakerTurn> _buildSpeakerTurns(List<_SonioxToken> tokens) {
    if (!_diarizationEnabledProvider()) {
      return const <SpeakerTurn>[];
    }

    final turns = <SpeakerTurn>[];
    String? currentSpeaker;
    final currentText = StringBuffer();

    void commitTurn() {
      final text = currentText.toString().trim();
      final speakerLabel = currentSpeaker;
      if (text.isEmpty || speakerLabel == null) {
        currentText.clear();
        return;
      }
      turns.add(SpeakerTurn(speakerLabel: speakerLabel, text: text));
      currentText.clear();
    }

    for (final token in tokens) {
      final speaker = token.speaker ?? currentSpeaker;
      if (speaker == null) {
        currentText.write(token.text);
        continue;
      }
      if (currentSpeaker != null && speaker != currentSpeaker) {
        commitTurn();
      }
      currentSpeaker = speaker;
      currentText.write(token.text);
    }

    commitTurn();
    return turns;
  }
}

class _SonioxToken {
  const _SonioxToken({required this.text, this.speaker});

  final String text;
  final String? speaker;
}
