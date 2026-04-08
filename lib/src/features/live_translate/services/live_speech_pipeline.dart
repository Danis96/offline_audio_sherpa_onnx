import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../models/app_language.dart';
import '../models/live_result.dart';
import 'model_asset_bundle.dart';
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

class SherpaStreamingZipformerPipeline implements LiveSpeechPipeline {
  SherpaStreamingZipformerPipeline({ModelAssetInstaller? assetInstaller})
    : _assetInstaller = assetInstaller ?? ModelAssetInstaller();

  static bool _bindingsInitialized = false;

  final ModelAssetInstaller _assetInstaller;

  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;
  ModelAssetBundle? _installedAssets;
  String _lastTranscript = '';

  @override
  bool get isReady => _recognizer != null && _stream != null;

  @override
  Future<void> warmUp({required AppLanguage sourceLanguage}) async {
    _ensureBindings();
    _installedAssets ??= await _assetInstaller.installAssets();
    debugPrint(
      '[ZIPFORMER_INIT] source=${sourceLanguage.code} encoder=${_installedAssets!.zipformerEncoderPath} decoder=${_installedAssets!.zipformerDecoderPath} joiner=${_installedAssets!.zipformerJoinerPath} tokens=${_installedAssets!.zipformerTokensPath}',
    );

    _stream?.free();
    _recognizer?.free();

    _recognizer = sherpa.OnlineRecognizer(
      sherpa.OnlineRecognizerConfig(
        model: sherpa.OnlineModelConfig(
          transducer: sherpa.OnlineTransducerModelConfig(
            encoder: _installedAssets!.zipformerEncoderPath,
            decoder: _installedAssets!.zipformerDecoderPath,
            joiner: _installedAssets!.zipformerJoinerPath,
          ),
          tokens: _installedAssets!.zipformerTokensPath,
          numThreads: 4,
          debug: false,
        ),
        decodingMethod: 'greedy_search',
        enableEndpoint: true,
        rule1MinTrailingSilence: 1.2,
        rule2MinTrailingSilence: 0.8,
        rule3MinUtteranceLength: 18.0,
      ),
    );

    /// decodingMethod:
    ///  {greedy_search}
    /// At every time step, the model produces a probability distribution over all possible tokens (characters, word-pieces, etc.).
    /// Greedy search simply picks the single highest-probability token at each step, without looking ahead or considering alternative paths.
    ///
    /// {beam_search}
    /// The other common option is beam_search, which keeps the top N candidate sequences alive at each step and picks the best complete sequence at the end.
    /// It's more accurate but significantly more expensive computationally.

    _stream = _recognizer!.createStream();
    _lastTranscript = '';
    debugPrint('[ZIPFORMER_INIT] online recognizer and stream created');
  }

  @override
  Future<void> resetSession() async {
    if (_recognizer == null) {
      return;
    }

    _stream?.free();
    _stream = _recognizer!.createStream();
    _lastTranscript = '';
  }

  @override
  Future<LiveResult?> ingestAudioFrame({
    required Uint8List pcmBytes,
    required List<double> samples,
  }) async {
    if (!isReady) {
      return null;
    }

    _stream!.acceptWaveform(
      samples: Float32List.fromList(samples),
      sampleRate: 16000,
    );

    var decodedAny = false;
    while (_recognizer!.isReady(_stream!)) {
      _recognizer!.decode(_stream!);
      decodedAny = true;
    }

    if (!decodedAny) {
      return null;
    }

    final result = _recognizer!.getResult(_stream!);
    final transcript = result.text.trim();
    debugPrint(
      '[ZIPFORMER_DECODE] decodedAny=$decodedAny transcript_length=${transcript.length} transcript="$transcript"',
    );
    if (transcript == _lastTranscript) {
      return null;
    }

    _lastTranscript = transcript;
    return LiveResult(transcript: transcript);
  }

  @override
  Future<LiveResult?> finishSession() async {
    if (!isReady) {
      return null;
    }

    _stream!.inputFinished();
    while (_recognizer!.isReady(_stream!)) {
      _recognizer!.decode(_stream!);
    }

    final result = _recognizer!.getResult(_stream!);
    final transcript = result.text.trim();
    debugPrint(
      '[ZIPFORMER_FINAL] transcript_length=${transcript.length} transcript="$transcript"',
    );
    final changed = transcript != _lastTranscript;
    _lastTranscript = transcript;

    if (_recognizer!.isEndpoint(_stream!)) {
      _recognizer!.reset(_stream!);
    }

    if (!changed) {
      return null;
    }

    return LiveResult(transcript: transcript);
  }

  void _ensureBindings() {
    if (_bindingsInitialized) {
      return;
    }

    sherpa.initBindings();
    _bindingsInitialized = true;
  }

  @override
  Future<void> dispose() async {
    _stream?.free();
    _stream = null;
    _recognizer?.free();
    _recognizer = null;
  }
}

enum ParakeetLatencyPreset { realtime, vad }

class SherpaSenseFlowPipeline implements LiveSpeechPipeline {
  SherpaSenseFlowPipeline({ModelAssetInstaller? assetInstaller})
    : _assetInstaller = assetInstaller ?? ModelAssetInstaller();

  static bool _bindingsInitialized = false;

  final ModelAssetInstaller _assetInstaller;

  sherpa.OfflineRecognizer? _recognizer;
  sherpa.VoiceActivityDetector? _vad;
  ModelAssetBundle? _installedAssets;
  String _fullTranscript = '';
  String _languageCode = 'en';

  @override
  bool get isReady => _recognizer != null && _vad != null;

  @override
  Future<void> warmUp({required AppLanguage sourceLanguage}) async {
    _ensureBindings();
    _installedAssets ??= await _assetInstaller.installAssets();
    _languageCode = sourceLanguage.code;

    debugPrint(
      '[SENSEFLOW_INIT] source=${sourceLanguage.code} model=${_installedAssets!.senseVoiceModelPath} tokens=${_installedAssets!.senseVoiceTokensPath} vad=${_installedAssets!.sileroVadModelPath}',
    );

    _recognizer?.free();
    _vad?.free();

    _recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          senseVoice: sherpa.OfflineSenseVoiceModelConfig(
            model: _installedAssets!.senseVoiceModelPath,
            language: _mapSenseFlowLanguage(sourceLanguage.code),
            useInverseTextNormalization: true,
          ),
          tokens: _installedAssets!.senseVoiceTokensPath,
          numThreads: 2,
          debug: false,
        ),
      ),
    );

    _vad = sherpa.VoiceActivityDetector(
      config: sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(
          model: _installedAssets!.sileroVadModelPath,
          threshold: 0.35,
          minSilenceDuration: 0.35,
          minSpeechDuration: 0.10,
          windowSize: 512,
        ),
        sampleRate: 16000,
        numThreads: 1,
        debug: false,
      ),
      bufferSizeInSeconds: 30,
    );

    _fullTranscript = '';
    debugPrint('[SENSEFLOW_INIT] offline recognizer and VAD created');
  }

  @override
  Future<void> resetSession() async {
    _vad?.clear();
    _vad?.reset();
    _fullTranscript = '';
  }

  @override
  Future<LiveResult?> ingestAudioFrame({
    required Uint8List pcmBytes,
    required List<double> samples,
  }) async {
    if (!isReady) {
      return null;
    }

    _vad!.acceptWaveform(Float32List.fromList(samples));
    if (_vad!.isEmpty()) {
      return null;
    }

    return _decodeQueuedSegment(isFinal: false);
  }

  @override
  Future<LiveResult?> finishSession() async {
    if (!isReady) {
      return null;
    }

    _vad!.flush();
    if (_vad!.isEmpty()) {
      debugPrint(
        '[SENSEFLOW_FINAL] transcript_length=${_fullTranscript.length} transcript="$_fullTranscript"',
      );
      return _fullTranscript.isEmpty
          ? null
          : LiveResult(transcript: _fullTranscript);
    }

    return _decodeQueuedSegment(isFinal: true);
  }

  LiveResult? _decodeQueuedSegment({required bool isFinal}) {
    final segment = _vad!.front();
    _vad!.pop();

    if (segment.samples.isEmpty) {
      return null;
    }

    final stream = _recognizer!.createStream();
    stream.acceptWaveform(sampleRate: 16000, samples: segment.samples);
    _recognizer!.decode(stream);
    final result = _recognizer!.getResult(stream);
    stream.free();

    final segmentText = result.text.trim();
    if (segmentText.isEmpty) {
      debugPrint(
        '[SENSEFLOW_${isFinal ? 'FINAL' : 'DECODE'}] empty segment lang=${result.lang} event=${result.event}',
      );
      return null;
    }

    _fullTranscript = _mergeText(_fullTranscript, segmentText);
    debugPrint(
      '[SENSEFLOW_${isFinal ? 'FINAL' : 'DECODE'}] lang=$_languageCode detected_lang=${result.lang} chars=${_fullTranscript.length} segment="$segmentText"',
    );
    return LiveResult(transcript: _fullTranscript);
  }

  String _mapSenseFlowLanguage(String code) {
    switch (code) {
      case 'de':
        return 'de';
      case 'en':
      default:
        return 'en';
    }
  }

  String _mergeText(String existingText, String newText) {
    if (existingText.isEmpty) {
      return newText;
    }
    if (newText.isEmpty) {
      return existingText;
    }

    final trimmedExisting = existingText.trimRight();
    final trimmedNew = newText.trimLeft();
    var maxOverlapLength = 20;
    if (trimmedNew.length < maxOverlapLength) {
      maxOverlapLength = trimmedNew.length;
    }
    if (trimmedExisting.length < maxOverlapLength) {
      maxOverlapLength = trimmedExisting.length;
    }

    for (var i = maxOverlapLength; i > 0; i--) {
      final suffix = trimmedExisting.substring(trimmedExisting.length - i);
      final prefix = trimmedNew.substring(0, i);
      if (suffix.toLowerCase() == prefix.toLowerCase()) {
        final mergedTail = trimmedNew.substring(i).trimLeft();
        return mergedTail.isEmpty
            ? trimmedExisting
            : '$trimmedExisting $mergedTail';
      }
    }

    return '$trimmedExisting $trimmedNew';
  }

  void _ensureBindings() {
    if (_bindingsInitialized) {
      return;
    }

    sherpa.initBindings();
    _bindingsInitialized = true;
  }

  @override
  Future<void> dispose() async {
    _vad?.free();
    _vad = null;
    _recognizer?.free();
    _recognizer = null;
  }
}

class SherpaCanaryPipeline implements LiveSpeechPipeline {
  SherpaCanaryPipeline({ModelAssetInstaller? assetInstaller})
    : _assetInstaller = assetInstaller ?? ModelAssetInstaller();

  static bool _bindingsInitialized = false;

  final ModelAssetInstaller _assetInstaller;

  sherpa.OfflineRecognizer? _recognizer;
  sherpa.VoiceActivityDetector? _vad;
  ModelAssetBundle? _installedAssets;
  String _fullTranscript = '';
  String _sourceLanguageCode = 'en';

  @override
  bool get isReady => _recognizer != null && _vad != null;

  @override
  Future<void> warmUp({required AppLanguage sourceLanguage}) async {
    _ensureBindings();
    _installedAssets ??= await _assetInstaller.installCanaryAssets();
    _sourceLanguageCode = sourceLanguage.code;

    debugPrint(
      '[CANARY_INIT] source=${sourceLanguage.code} encoder=${_installedAssets!.canaryEncoderPath} decoder=${_installedAssets!.canaryDecoderPath} tokens=${_installedAssets!.canaryTokensPath}',
    );

    _recognizer?.free();
    _vad?.free();

    _recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          canary: sherpa.OfflineCanaryModelConfig(
            encoder: _installedAssets!.canaryEncoderPath!,
            decoder: _installedAssets!.canaryDecoderPath!,
            srcLang: sourceLanguage.code,
            tgtLang: sourceLanguage.code,
            usePnc: true,
          ),
          tokens: _installedAssets!.canaryTokensPath!,
          numThreads: 2,
          debug: false,
        ),
      ),
    );

    _vad = sherpa.VoiceActivityDetector(
      config: sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(
          model: _installedAssets!.sileroVadModelPath,
          threshold: 0.35,
          minSilenceDuration: 0.35,
          minSpeechDuration: 0.10,
          windowSize: 512,
        ),
        sampleRate: 16000,
        numThreads: 1,
        debug: false,
      ),
      bufferSizeInSeconds: 3,
    );

    _fullTranscript = '';
    debugPrint('[CANARY_INIT] offline recognizer and VAD created');
  }

  @override
  Future<void> resetSession() async {
    _vad?.clear();
    _vad?.reset();
    _fullTranscript = '';
  }

  @override
  Future<LiveResult?> ingestAudioFrame({
    required Uint8List pcmBytes,
    required List<double> samples,
  }) async {
    if (!isReady) {
      return null;
    }

    _vad!.acceptWaveform(Float32List.fromList(samples));
    if (_vad!.isEmpty()) {
      return null;
    }

    return _decodeQueuedSegment(isFinal: false);
  }

  @override
  Future<LiveResult?> finishSession() async {
    if (!isReady) {
      return null;
    }

    _vad!.flush();
    if (_vad!.isEmpty()) {
      debugPrint(
        '[CANARY_FINAL] transcript_length=${_fullTranscript.length} transcript="$_fullTranscript"',
      );
      return _fullTranscript.isEmpty
          ? null
          : LiveResult(transcript: _fullTranscript);
    }

    return _decodeQueuedSegment(isFinal: true);
  }

  LiveResult? _decodeQueuedSegment({required bool isFinal}) {
    final segment = _vad!.front();
    _vad!.pop();

    if (segment.samples.isEmpty) {
      return null;
    }

    final stream = _recognizer!.createStream();
    stream.acceptWaveform(sampleRate: 16000, samples: segment.samples);
    _recognizer!.decode(stream);
    final result = _recognizer!.getResult(stream);
    stream.free();

    final segmentText = result.text.trim();
    if (segmentText.isEmpty) {
      debugPrint(
        '[CANARY_${isFinal ? 'FINAL' : 'DECODE'}] empty segment lang=${result.lang}',
      );
      return null;
    }

    _fullTranscript = _mergeText(_fullTranscript, segmentText);
    debugPrint(
      '[CANARY_${isFinal ? 'FINAL' : 'DECODE'}] src=$_sourceLanguageCode chars=${_fullTranscript.length} segment="$segmentText"',
    );
    return LiveResult(transcript: _fullTranscript);
  }

  String _mergeText(String existingText, String newText) {
    if (existingText.isEmpty) {
      return newText;
    }
    if (newText.isEmpty) {
      return existingText;
    }

    final trimmedExisting = existingText.trimRight();
    final trimmedNew = newText.trimLeft();
    var maxOverlapLength = 20;
    if (trimmedNew.length < maxOverlapLength) {
      maxOverlapLength = trimmedNew.length;
    }
    if (trimmedExisting.length < maxOverlapLength) {
      maxOverlapLength = trimmedExisting.length;
    }

    for (var i = maxOverlapLength; i > 0; i--) {
      final suffix = trimmedExisting.substring(trimmedExisting.length - i);
      final prefix = trimmedNew.substring(0, i);
      if (suffix.toLowerCase() == prefix.toLowerCase()) {
        final mergedTail = trimmedNew.substring(i).trimLeft();
        return mergedTail.isEmpty
            ? trimmedExisting
            : '$trimmedExisting $mergedTail';
      }
    }

    return '$trimmedExisting $trimmedNew';
  }

  void _ensureBindings() {
    if (_bindingsInitialized) {
      return;
    }

    sherpa.initBindings();
    _bindingsInitialized = true;
  }

  @override
  Future<void> dispose() async {
    _vad?.free();
    _vad = null;
    _recognizer?.free();
    _recognizer = null;
  }
}

class SherpaWhisperPipeline implements LiveSpeechPipeline {
  SherpaWhisperPipeline({ModelAssetInstaller? assetInstaller})
    : _assetInstaller = assetInstaller ?? ModelAssetInstaller();

  static bool _bindingsInitialized = false;
  static const int _sampleRate = 16000;
  static const int _forcedChunkSamples = 38400;

  final ModelAssetInstaller _assetInstaller;

  sherpa.OfflineRecognizer? _recognizer;
  sherpa.VoiceActivityDetector? _vad;
  ModelAssetBundle? _installedAssets;
  String _fullTranscript = '';
  String _sourceLanguageCode = 'en';
  int _samplesSinceLastCut = 0;

  @override
  bool get isReady => _recognizer != null && _vad != null;

  @override
  Future<void> warmUp({required AppLanguage sourceLanguage}) async {
    _ensureBindings();
    _installedAssets ??= await _assetInstaller.installWhisperAssets();
    _sourceLanguageCode = sourceLanguage.code;

    debugPrint(
      '[WHISPER_INIT] source=${sourceLanguage.code} encoder=${_installedAssets!.whisperEncoderPath} decoder=${_installedAssets!.whisperDecoderPath} tokens=${_installedAssets!.whisperTokensPath}',
    );

    _recognizer?.free();
    _vad?.free();

    _recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          whisper: sherpa.OfflineWhisperModelConfig(
            encoder: _installedAssets!.whisperEncoderPath!,
            decoder: _installedAssets!.whisperDecoderPath!,
            language: sourceLanguage.code,
            task: 'transcribe',
          ),
          tokens: _installedAssets!.whisperTokensPath!,
          numThreads: 2,
          debug: false,
        ),
      ),
    );

    _vad = sherpa.VoiceActivityDetector(
      config: sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(
          model: _installedAssets!.sileroVadModelPath,
          threshold: 0.35,
          minSilenceDuration: 0.22,
          minSpeechDuration: 0.08,
          windowSize: 512,
        ),
        sampleRate: 16000,
        numThreads: 1,
        debug: false,
      ),
      bufferSizeInSeconds: 2,
    );

    _fullTranscript = '';
    _samplesSinceLastCut = 0;
    debugPrint('[WHISPER_INIT] offline recognizer and VAD created');
  }

  @override
  Future<void> resetSession() async {
    _vad?.clear();
    _vad?.reset();
    _fullTranscript = '';
    _samplesSinceLastCut = 0;
  }

  @override
  Future<LiveResult?> ingestAudioFrame({
    required Uint8List pcmBytes,
    required List<double> samples,
  }) async {
    if (!isReady) {
      return null;
    }

    _vad!.acceptWaveform(Float32List.fromList(samples));
    _samplesSinceLastCut += samples.length;

    if (_vad!.isEmpty()) {
      if (_samplesSinceLastCut < _forcedChunkSamples) {
        return null;
      }

      debugPrint(
        '[WHISPER_FORCE_CUT] forcing flush after ${(_samplesSinceLastCut / _sampleRate).toStringAsFixed(2)}s without a completed chunk',
      );
      _vad!.flush();
      if (_vad!.isEmpty()) {
        _samplesSinceLastCut = 0;
        return null;
      }
    }

    return _decodeQueuedSegment(isFinal: false);
  }

  @override
  Future<LiveResult?> finishSession() async {
    if (!isReady) {
      return null;
    }

    _vad!.flush();
    _samplesSinceLastCut = 0;
    if (_vad!.isEmpty()) {
      debugPrint(
        '[WHISPER_FINAL] transcript_length=${_fullTranscript.length} transcript="$_fullTranscript"',
      );
      return _fullTranscript.isEmpty
          ? null
          : LiveResult(transcript: _fullTranscript);
    }

    return _decodeQueuedSegment(isFinal: true);
  }

  LiveResult? _decodeQueuedSegment({required bool isFinal}) {
    final segment = _vad!.front();
    _vad!.pop();

    if (segment.samples.isEmpty) {
      return null;
    }

    final stream = _recognizer!.createStream();
    stream.acceptWaveform(sampleRate: 16000, samples: segment.samples);
    _recognizer!.decode(stream);
    final result = _recognizer!.getResult(stream);
    stream.free();
    _samplesSinceLastCut = 0;

    final segmentText = result.text.trim();
    if (segmentText.isEmpty) {
      debugPrint(
        '[WHISPER_${isFinal ? 'FINAL' : 'DECODE'}] empty segment lang=${result.lang}',
      );
      return null;
    }

    _fullTranscript = _mergeText(_fullTranscript, segmentText);
    debugPrint(
      '[WHISPER_${isFinal ? 'FINAL' : 'DECODE'}] src=$_sourceLanguageCode detected_lang=${result.lang} chars=${_fullTranscript.length} segment="$segmentText"',
    );
    return LiveResult(transcript: _fullTranscript);
  }

  String _mergeText(String existingText, String newText) {
    if (existingText.isEmpty) {
      return newText;
    }
    if (newText.isEmpty) {
      return existingText;
    }

    final trimmedExisting = existingText.trimRight();
    final trimmedNew = newText.trimLeft();
    var maxOverlapLength = 20;
    if (trimmedNew.length < maxOverlapLength) {
      maxOverlapLength = trimmedNew.length;
    }
    if (trimmedExisting.length < maxOverlapLength) {
      maxOverlapLength = trimmedExisting.length;
    }

    for (var i = maxOverlapLength; i > 0; i--) {
      final suffix = trimmedExisting.substring(trimmedExisting.length - i);
      final prefix = trimmedNew.substring(0, i);
      if (suffix.toLowerCase() == prefix.toLowerCase()) {
        final mergedTail = trimmedNew.substring(i).trimLeft();
        return mergedTail.isEmpty
            ? trimmedExisting
            : '$trimmedExisting $mergedTail';
      }
    }

    return '$trimmedExisting $trimmedNew';
  }

  void _ensureBindings() {
    if (_bindingsInitialized) {
      return;
    }

    sherpa.initBindings();
    _bindingsInitialized = true;
  }

  @override
  Future<void> dispose() async {
    _vad?.free();
    _vad = null;
    _recognizer?.free();
    _recognizer = null;
  }
}

class SherpaOmnilingualPipeline implements LiveSpeechPipeline {
  SherpaOmnilingualPipeline({ModelAssetInstaller? assetInstaller})
    : _assetInstaller = assetInstaller ?? ModelAssetInstaller();

  static bool _bindingsInitialized = false;
  static const int _sampleRate = 16000;
  static const int _forcedChunkSamples = 38400;

  final ModelAssetInstaller _assetInstaller;

  sherpa.OfflineRecognizer? _recognizer;
  sherpa.VoiceActivityDetector? _vad;
  ModelAssetBundle? _installedAssets;
  String _fullTranscript = '';
  int _samplesSinceLastCut = 0;

  @override
  bool get isReady => _recognizer != null && _vad != null;

  @override
  Future<void> warmUp({required AppLanguage sourceLanguage}) async {
    _ensureBindings();
    _installedAssets ??= await _assetInstaller.installOmnilingualAssets();

    debugPrint(
      '[OMNILINGUAL_INIT] source=${sourceLanguage.code} model=${_installedAssets!.omnilingualModelPath} tokens=${_installedAssets!.omnilingualTokensPath}',
    );

    _recognizer?.free();
    _vad?.free();

    _recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          omnilingual: sherpa.OfflineOmnilingualAsrCtcModelConfig(
            model: _installedAssets!.omnilingualModelPath!,
          ),
          tokens: _installedAssets!.omnilingualTokensPath!,
          numThreads: 2,
          debug: false,
        ),
      ),
    );

    _vad = sherpa.VoiceActivityDetector(
      config: sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(
          model: _installedAssets!.sileroVadModelPath,
          threshold: 0.35,
          minSilenceDuration: 0.22,
          minSpeechDuration: 0.08,
          windowSize: 512,
        ),
        sampleRate: 16000,
        numThreads: 1,
        debug: false,
      ),
      bufferSizeInSeconds: 2,
    );

    _fullTranscript = '';
    _samplesSinceLastCut = 0;
    debugPrint('[OMNILINGUAL_INIT] offline recognizer and VAD created');
  }

  @override
  Future<void> resetSession() async {
    _vad?.clear();
    _vad?.reset();
    _fullTranscript = '';
    _samplesSinceLastCut = 0;
  }

  @override
  Future<LiveResult?> ingestAudioFrame({
    required Uint8List pcmBytes,
    required List<double> samples,
  }) async {
    if (!isReady) {
      return null;
    }

    _vad!.acceptWaveform(Float32List.fromList(samples));
    _samplesSinceLastCut += samples.length;

    if (_vad!.isEmpty()) {
      if (_samplesSinceLastCut < _forcedChunkSamples) {
        return null;
      }

      debugPrint(
        '[OMNILINGUAL_FORCE_CUT] forcing flush after ${(_samplesSinceLastCut / _sampleRate).toStringAsFixed(2)}s without a completed chunk',
      );
      _vad!.flush();
      if (_vad!.isEmpty()) {
        _samplesSinceLastCut = 0;
        return null;
      }
    }

    return _decodeQueuedSegment(isFinal: false);
  }

  @override
  Future<LiveResult?> finishSession() async {
    if (!isReady) {
      return null;
    }

    _vad!.flush();
    _samplesSinceLastCut = 0;
    if (_vad!.isEmpty()) {
      debugPrint(
        '[OMNILINGUAL_FINAL] transcript_length=${_fullTranscript.length} transcript="$_fullTranscript"',
      );
      return _fullTranscript.isEmpty
          ? null
          : LiveResult(transcript: _fullTranscript);
    }

    return _decodeQueuedSegment(isFinal: true);
  }

  LiveResult? _decodeQueuedSegment({required bool isFinal}) {
    final segment = _vad!.front();
    _vad!.pop();

    if (segment.samples.isEmpty) {
      return null;
    }

    final stream = _recognizer!.createStream();
    stream.acceptWaveform(sampleRate: 16000, samples: segment.samples);
    _recognizer!.decode(stream);
    final result = _recognizer!.getResult(stream);
    stream.free();
    _samplesSinceLastCut = 0;

    final segmentText = result.text.trim();
    if (segmentText.isEmpty) {
      debugPrint('[OMNILINGUAL_${isFinal ? 'FINAL' : 'DECODE'}] empty segment');
      return isFinal && _fullTranscript.isNotEmpty
          ? LiveResult(transcript: _fullTranscript)
          : null;
    }

    _fullTranscript = _fullTranscript.isEmpty
        ? segmentText
        : '$_fullTranscript $segmentText';

    debugPrint(
      '[OMNILINGUAL_${isFinal ? 'FINAL' : 'DECODE'}] chars=${_fullTranscript.length} segment="$segmentText"',
    );
    return LiveResult(transcript: _fullTranscript);
  }

  void _ensureBindings() {
    if (_bindingsInitialized) {
      return;
    }

    sherpa.initBindings();
    _bindingsInitialized = true;
  }

  @override
  Future<void> dispose() async {
    _vad?.free();
    _vad = null;
    _recognizer?.free();
    _recognizer = null;
  }
}

class SherpaParakeetPipeline implements LiveSpeechPipeline {
  SherpaParakeetPipeline({
    this.preset = ParakeetLatencyPreset.vad,
    ModelAssetInstaller? assetInstaller,
  }) : _assetInstaller = assetInstaller ?? ModelAssetInstaller();

  SherpaParakeetPipeline.realtime({ModelAssetInstaller? assetInstaller})
    : this(
        preset: ParakeetLatencyPreset.realtime,
        assetInstaller: assetInstaller,
      );

  SherpaParakeetPipeline.vad({ModelAssetInstaller? assetInstaller})
    : this(preset: ParakeetLatencyPreset.vad, assetInstaller: assetInstaller);

  static bool _bindingsInitialized = false;
  static const int _sampleRate = 16000;
  static const int _forcedChunkSamples = 38400;

  final ParakeetLatencyPreset preset;
  final ModelAssetInstaller _assetInstaller;

  sherpa.OfflineRecognizer? _recognizer;
  sherpa.VoiceActivityDetector? _vad;
  ModelAssetBundle? _installedAssets;
  String _fullTranscript = '';
  int _samplesSinceLastCut = 0;

  @override
  bool get isReady => _recognizer != null && _vad != null;

  @override
  Future<void> warmUp({required AppLanguage sourceLanguage}) async {
    _ensureBindings();
    _installedAssets ??= await _assetInstaller.installParakeetAssets();
    final logTag = switch (preset) {
      ParakeetLatencyPreset.realtime => 'PARAKEET_REALTIME',
      ParakeetLatencyPreset.vad => 'PARAKEET_VAD',
    };
    final minSilenceDuration = switch (preset) {
      ParakeetLatencyPreset.realtime => 0.12,
      ParakeetLatencyPreset.vad => 0.22,
    };
    final minSpeechDuration = switch (preset) {
      ParakeetLatencyPreset.realtime => 0.05,
      ParakeetLatencyPreset.vad => 0.08,
    };
    final bufferSizeInSeconds = switch (preset) {
      ParakeetLatencyPreset.realtime => 1.0,
      ParakeetLatencyPreset.vad => 2.0,
    };

    debugPrint(
      '[$logTag] source=${sourceLanguage.code} encoder=${_installedAssets!.parakeetEncoderPath} decoder=${_installedAssets!.parakeetDecoderPath} joiner=${_installedAssets!.parakeetJoinerPath} tokens=${_installedAssets!.parakeetTokensPath}',
    );

    _recognizer?.free();
    _vad?.free();

    _recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          transducer: sherpa.OfflineTransducerModelConfig(
            encoder: _installedAssets!.parakeetEncoderPath!,
            decoder: _installedAssets!.parakeetDecoderPath!,
            joiner: _installedAssets!.parakeetJoinerPath!,
          ),
          tokens: _installedAssets!.parakeetTokensPath!,
          modelType: 'nemo_transducer',
          numThreads: 2,
          debug: false,
        ),
      ),
    );

    _vad = sherpa.VoiceActivityDetector(
      config: sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(
          model: _installedAssets!.sileroVadModelPath,
          threshold: 0.35,
          minSilenceDuration: minSilenceDuration,
          minSpeechDuration: minSpeechDuration,
          windowSize: 512,
        ),
        sampleRate: 16000,
        numThreads: 1,
        debug: false,
      ),
      bufferSizeInSeconds: bufferSizeInSeconds,
    );

    _fullTranscript = '';
    _samplesSinceLastCut = 0;
    debugPrint(
      '[$logTag] offline recognizer and VAD created silence=${minSilenceDuration.toStringAsFixed(2)} speech=${minSpeechDuration.toStringAsFixed(2)} buffer=${bufferSizeInSeconds.toStringAsFixed(1)}',
    );
  }

  @override
  Future<void> resetSession() async {
    _vad?.clear();
    _vad?.reset();
    _fullTranscript = '';
    _samplesSinceLastCut = 0;
  }

  @override
  Future<LiveResult?> ingestAudioFrame({
    required Uint8List pcmBytes,
    required List<double> samples,
  }) async {
    if (!isReady) {
      return null;
    }

    _vad!.acceptWaveform(Float32List.fromList(samples));
    _samplesSinceLastCut += samples.length;

    if (_vad!.isEmpty()) {
      final forcedChunkSamples = switch (preset) {
        ParakeetLatencyPreset.realtime => 19200,
        ParakeetLatencyPreset.vad => _forcedChunkSamples,
      };

      if (_samplesSinceLastCut < forcedChunkSamples) {
        return null;
      }

      debugPrint(
        '[PARAKEET_FORCE_CUT] preset=$preset forcing flush after ${(_samplesSinceLastCut / _sampleRate).toStringAsFixed(2)}s without a completed chunk',
      );
      _vad!.flush();
      if (_vad!.isEmpty()) {
        _samplesSinceLastCut = 0;
        return null;
      }
    }

    return _decodeQueuedSegment(isFinal: false);
  }

  @override
  Future<LiveResult?> finishSession() async {
    if (!isReady) {
      return null;
    }

    _vad!.flush();
    _samplesSinceLastCut = 0;
    if (_vad!.isEmpty()) {
      debugPrint(
        '[PARAKEET_FINAL] transcript_length=${_fullTranscript.length} transcript="$_fullTranscript"',
      );
      return _fullTranscript.isEmpty
          ? null
          : LiveResult(transcript: _fullTranscript);
    }

    return _decodeQueuedSegment(isFinal: true);
  }

  LiveResult? _decodeQueuedSegment({required bool isFinal}) {
    final segment = _vad!.front();
    _vad!.pop();

    if (segment.samples.isEmpty) {
      return null;
    }

    final stream = _recognizer!.createStream();
    stream.acceptWaveform(sampleRate: 16000, samples: segment.samples);
    _recognizer!.decode(stream);
    final result = _recognizer!.getResult(stream);
    stream.free();
    _samplesSinceLastCut = 0;

    final segmentText = result.text.trim();
    if (segmentText.isEmpty) {
      debugPrint('[PARAKEET_${isFinal ? 'FINAL' : 'DECODE'}] empty segment');
      return isFinal && _fullTranscript.isNotEmpty
          ? LiveResult(transcript: _fullTranscript)
          : null;
    }

    _fullTranscript = _fullTranscript.isEmpty
        ? segmentText
        : '$_fullTranscript $segmentText';

    debugPrint(
      '[PARAKEET_${isFinal ? 'FINAL' : 'DECODE'}] chars=${_fullTranscript.length} segment="$segmentText"',
    );
    return LiveResult(transcript: _fullTranscript);
  }

  void _ensureBindings() {
    if (_bindingsInitialized) {
      return;
    }

    sherpa.initBindings();
    _bindingsInitialized = true;
  }

  @override
  Future<void> dispose() async {
    _vad?.free();
    _vad = null;
    _recognizer?.free();
    _recognizer = null;
  }
}

class SonioxRealtimePipeline implements LiveSpeechPipeline {
  SonioxRealtimePipeline({
    required String Function() apiKeyProvider,
    this.socketUrl = 'wss://stt-rt.soniox.com/transcribe-websocket',
  }) : _apiKeyProvider = apiKeyProvider;

  final String Function() _apiKeyProvider;
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

  @override
  bool get isReady => _isConfigured;

  @override
  Future<void> warmUp({required AppLanguage sourceLanguage}) async {
    final apiKey = _apiKeyProvider().trim();
    if (apiKey.isEmpty) {
      throw StateError(
        'Enter a Soniox API key before selecting the Soniox engine.',
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
    final nonFinalBuffer = StringBuffer();

    for (final tokenEntry in tokens) {
      if (tokenEntry is! Map<String, dynamic>) {
        continue;
      }

      final text = tokenEntry['text'];
      if (text is! String || text.isEmpty) {
        continue;
      }

      if (tokenEntry['is_final'] == true) {
        _finalTranscript += text;
      } else {
        nonFinalBuffer.write(text);
      }
    }

    _previewTranscript = _finalTranscript + nonFinalBuffer.toString();
    if (json['finished'] == true) {
      _previewTranscript = _finalTranscript;
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
    return LiveResult(transcript: transcript);
  }

  void _throwIfPendingError() {
    final error = _pendingError;
    if (error != null) {
      throw StateError(error);
    }
  }
}
