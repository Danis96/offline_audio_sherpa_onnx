import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class ModelAssetBundle {
  ModelAssetBundle({
    required this.zipformerEncoderPath,
    required this.zipformerDecoderPath,
    required this.zipformerJoinerPath,
    required this.zipformerTokensPath,
    required this.senseVoiceModelPath,
    required this.senseVoiceTokensPath,
    required this.sileroVadModelPath,
    this.canaryEncoderPath,
    this.canaryDecoderPath,
    this.canaryTokensPath,
  });

  final String zipformerEncoderPath;
  final String zipformerDecoderPath;
  final String zipformerJoinerPath;
  final String zipformerTokensPath;
  final String senseVoiceModelPath;
  final String senseVoiceTokensPath;
  final String sileroVadModelPath;
  final String? canaryEncoderPath;
  final String? canaryDecoderPath;
  final String? canaryTokensPath;
}

class ModelAssetInstaller {
  static const List<String> _encoderCandidates = <String>[
    'assets/models/zipformer/encoder.int8.onnx',
    'assets/models/zipformer/encoder.onnx',
  ];
  static const List<String> _decoderCandidates = <String>[
    'assets/models/zipformer/decoder.int8.onnx',
    'assets/models/zipformer/decoder.onnx',
  ];
  static const List<String> _joinerCandidates = <String>[
    'assets/models/zipformer/joiner.int8.onnx',
    'assets/models/zipformer/joiner.onnx',
  ];
  static const List<String> _tokensCandidates = <String>[
    'assets/models/zipformer/tokens.txt',
  ];
  static const List<String> _senseVoiceModelCandidates = <String>[
    'assets/models/sensevoice/model.int8.onnx',
    'assets/models/sensevoice/model.onnx',
  ];
  static const List<String> _senseVoiceTokensCandidates = <String>[
    'assets/models/sensevoice/tokens.txt',
  ];
  static const List<String> _sileroVadCandidates = <String>[
    'assets/models/silero_vad.onnx',
  ];
  static const List<String> _canaryEncoderCandidates = <String>[
    'assets/models/canary/encoder.int8.onnx',
    'assets/models/canary/encoder.onnx',
  ];
  static const List<String> _canaryDecoderCandidates = <String>[
    'assets/models/canary/decoder.int8.onnx',
    'assets/models/canary/decoder.onnx',
  ];
  static const List<String> _canaryTokensCandidates = <String>[
    'assets/models/canary/tokens.txt',
  ];

  Future<ModelAssetBundle> installAssets() async {
    final supportDir = await getApplicationSupportDirectory();
    final zipformerDir = Directory('${supportDir.path}/models/zipformer');
    await zipformerDir.create(recursive: true);
    final senseVoiceDir = Directory('${supportDir.path}/models/sensevoice');
    await senseVoiceDir.create(recursive: true);

    final encoder = await _copyFirstAvailableAsset(
      candidates: _encoderCandidates,
      targetName: 'encoder.onnx',
      targetDir: zipformerDir,
    );
    final decoder = await _copyFirstAvailableAsset(
      candidates: _decoderCandidates,
      targetName: 'decoder.onnx',
      targetDir: zipformerDir,
    );
    final joiner = await _copyFirstAvailableAsset(
      candidates: _joinerCandidates,
      targetName: 'joiner.onnx',
      targetDir: zipformerDir,
    );
    final tokens = await _copyFirstAvailableAsset(
      candidates: _tokensCandidates,
      targetName: 'tokens.txt',
      targetDir: zipformerDir,
    );
    final senseVoiceModel = await _copyFirstAvailableAsset(
      candidates: _senseVoiceModelCandidates,
      targetName: 'model.onnx',
      targetDir: senseVoiceDir,
    );
    final senseVoiceTokens = await _copyFirstAvailableAsset(
      candidates: _senseVoiceTokensCandidates,
      targetName: 'tokens.txt',
      targetDir: senseVoiceDir,
    );
    final sileroVadModel = await _copyFirstAvailableAsset(
      candidates: _sileroVadCandidates,
      targetName: 'silero_vad.onnx',
      targetDir: senseVoiceDir,
    );

    debugPrint(
      '[ZIPFORMER_ASSETS] encoder=${encoder.path} bytes=${await encoder.length()}',
    );
    debugPrint(
      '[ZIPFORMER_ASSETS] decoder=${decoder.path} bytes=${await decoder.length()}',
    );
    debugPrint(
      '[ZIPFORMER_ASSETS] joiner=${joiner.path} bytes=${await joiner.length()}',
    );
    debugPrint(
      '[ZIPFORMER_ASSETS] tokens=${tokens.path} bytes=${await tokens.length()}',
    );
    debugPrint(
      '[SENSEFLOW_ASSETS] model=${senseVoiceModel.path} bytes=${await senseVoiceModel.length()}',
    );
    debugPrint(
      '[SENSEFLOW_ASSETS] tokens=${senseVoiceTokens.path} bytes=${await senseVoiceTokens.length()}',
    );
    debugPrint(
      '[SENSEFLOW_ASSETS] vad=${sileroVadModel.path} bytes=${await sileroVadModel.length()}',
    );

    return ModelAssetBundle(
      zipformerEncoderPath: encoder.path,
      zipformerDecoderPath: decoder.path,
      zipformerJoinerPath: joiner.path,
      zipformerTokensPath: tokens.path,
      senseVoiceModelPath: senseVoiceModel.path,
      senseVoiceTokensPath: senseVoiceTokens.path,
      sileroVadModelPath: sileroVadModel.path,
    );
  }

  Future<ModelAssetBundle> installCanaryAssets() async {
    final supportDir = await getApplicationSupportDirectory();
    final canaryDir = Directory('${supportDir.path}/models/canary');
    await canaryDir.create(recursive: true);

    final encoder = await _copyFirstAvailableAsset(
      candidates: _canaryEncoderCandidates,
      targetName: 'encoder.onnx',
      targetDir: canaryDir,
    );
    final decoder = await _copyFirstAvailableAsset(
      candidates: _canaryDecoderCandidates,
      targetName: 'decoder.onnx',
      targetDir: canaryDir,
    );
    final tokens = await _copyFirstAvailableAsset(
      candidates: _canaryTokensCandidates,
      targetName: 'tokens.txt',
      targetDir: canaryDir,
    );
    final sileroVadModel = await _copyFirstAvailableAsset(
      candidates: _sileroVadCandidates,
      targetName: 'silero_vad.onnx',
      targetDir: canaryDir,
    );

    debugPrint(
      '[CANARY_ASSETS] encoder=${encoder.path} bytes=${await encoder.length()}',
    );
    debugPrint(
      '[CANARY_ASSETS] decoder=${decoder.path} bytes=${await decoder.length()}',
    );
    debugPrint(
      '[CANARY_ASSETS] tokens=${tokens.path} bytes=${await tokens.length()}',
    );
    debugPrint(
      '[CANARY_ASSETS] vad=${sileroVadModel.path} bytes=${await sileroVadModel.length()}',
    );

    return ModelAssetBundle(
      zipformerEncoderPath: '',
      zipformerDecoderPath: '',
      zipformerJoinerPath: '',
      zipformerTokensPath: '',
      senseVoiceModelPath: '',
      senseVoiceTokensPath: '',
      sileroVadModelPath: sileroVadModel.path,
      canaryEncoderPath: encoder.path,
      canaryDecoderPath: decoder.path,
      canaryTokensPath: tokens.path,
    );
  }

  Future<File> _copyFirstAvailableAsset({
    required List<String> candidates,
    required String targetName,
    required Directory targetDir,
  }) async {
    final targetFile = File('${targetDir.path}/$targetName');

    for (final assetPath in candidates) {
      try {
        final assetData = await rootBundle.load(assetPath);
        final bytes = Uint8List.sublistView(assetData);
        await targetFile.writeAsBytes(bytes, flush: true);
        debugPrint(
          '[ZIPFORMER_ASSETS] copied $assetPath -> ${targetFile.path} bytes=${bytes.length}',
        );
        return targetFile;
      } catch (_) {
        continue;
      }
    }

    throw StateError(
      'Missing asset. Expected one of: ${candidates.join(', ')}',
    );
  }
}
