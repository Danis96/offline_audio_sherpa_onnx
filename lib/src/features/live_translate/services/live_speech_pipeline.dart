import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../models/app_language.dart';
import '../models/live_result.dart';
import 'model_asset_bundle.dart';

abstract class LiveSpeechPipeline {
  bool get isReady;

  Future<void> warmUp({required AppLanguage sourceLanguage});

  void resetSession();

  LiveResult? ingestAudioFrame({required List<double> samples});

  LiveResult? finishSession();

  void dispose();
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
  void resetSession() {
    if (_recognizer == null) {
      return;
    }

    _stream?.free();
    _stream = _recognizer!.createStream();
    _lastTranscript = '';
  }

  @override
  LiveResult? ingestAudioFrame({required List<double> samples}) {
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
  LiveResult? finishSession() {
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
  void dispose() {
    _stream?.free();
    _stream = null;
    _recognizer?.free();
    _recognizer = null;
  }
}

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
  void resetSession() {
    _vad?.clear();
    _vad?.reset();
    _fullTranscript = '';
  }

  @override
  LiveResult? ingestAudioFrame({required List<double> samples}) {
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
  LiveResult? finishSession() {
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
  void dispose() {
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
      bufferSizeInSeconds: 30,
    );

    _fullTranscript = '';
    debugPrint('[CANARY_INIT] offline recognizer and VAD created');
  }

  @override
  void resetSession() {
    _vad?.clear();
    _vad?.reset();
    _fullTranscript = '';
  }

  @override
  LiveResult? ingestAudioFrame({required List<double> samples}) {
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
  LiveResult? finishSession() {
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
  void dispose() {
    _vad?.free();
    _vad = null;
    _recognizer?.free();
    _recognizer = null;
  }
}
