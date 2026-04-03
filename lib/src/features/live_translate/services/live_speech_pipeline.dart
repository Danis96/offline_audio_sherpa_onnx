import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../models/app_language.dart';
import '../models/live_result.dart';
import 'model_asset_bundle.dart';

abstract class LiveSpeechPipeline {
  bool get isReady;

  Future<void> warmUp({
    required AppLanguage sourceLanguage,
    required AppLanguage targetLanguage,
  });

  void resetSession();

  LiveResult? ingestAudioFrame({
    required List<double> samples,
    required AppLanguage sourceLanguage,
    required AppLanguage targetLanguage,
  });

  LiveResult? finishSession({
    required AppLanguage sourceLanguage,
    required AppLanguage targetLanguage,
  });

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
  Future<void> warmUp({
    required AppLanguage sourceLanguage,
    required AppLanguage targetLanguage,
  }) async {
    _ensureBindings();
    _installedAssets ??= await _assetInstaller.installZipformerAssets();

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

    _stream = _recognizer!.createStream();
    _lastTranscript = '';
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
  LiveResult? ingestAudioFrame({
    required List<double> samples,
    required AppLanguage sourceLanguage,
    required AppLanguage targetLanguage,
  }) {
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
    if (transcript == _lastTranscript) {
      return null;
    }

    _lastTranscript = transcript;
    return LiveResult(
      transcript: transcript,
      translation: _buildTranslation(
        transcript: transcript,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      ),
    );
  }

  @override
  LiveResult? finishSession({
    required AppLanguage sourceLanguage,
    required AppLanguage targetLanguage,
  }) {
    if (!isReady) {
      return null;
    }

    _stream!.inputFinished();
    while (_recognizer!.isReady(_stream!)) {
      _recognizer!.decode(_stream!);
    }

    final result = _recognizer!.getResult(_stream!);
    final transcript = result.text.trim();
    final changed = transcript != _lastTranscript;
    _lastTranscript = transcript;

    if (_recognizer!.isEndpoint(_stream!)) {
      _recognizer!.reset(_stream!);
    }

    if (!changed) {
      return null;
    }

    return LiveResult(
      transcript: transcript,
      translation: _buildTranslation(
        transcript: transcript,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      ),
    );
  }

  String _buildTranslation({
    required String transcript,
    required AppLanguage sourceLanguage,
    required AppLanguage targetLanguage,
  }) {
    if (sourceLanguage.code == targetLanguage.code) {
      return transcript;
    }

    return '[Offline translation model not connected yet] $transcript';
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
