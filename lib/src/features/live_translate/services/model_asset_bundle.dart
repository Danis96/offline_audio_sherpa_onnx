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
    this.omnilingualModelPath,
    this.omnilingualTokensPath,
    this.parakeetEncoderPath,
    this.parakeetDecoderPath,
    this.parakeetJoinerPath,
    this.parakeetTokensPath,
    this.whisperEncoderPath,
    this.whisperDecoderPath,
    this.whisperTokensPath,
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
  final String? omnilingualModelPath;
  final String? omnilingualTokensPath;
  final String? parakeetEncoderPath;
  final String? parakeetDecoderPath;
  final String? parakeetJoinerPath;
  final String? parakeetTokensPath;
  final String? whisperEncoderPath;
  final String? whisperDecoderPath;
  final String? whisperTokensPath;
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
  static const List<String> _omnilingualModelCandidates = <String>[
    'assets/models/omnilingual_ctc/model.int8.onnx',
    'assets/models/omnilingual_ctc/model.onnx',
  ];
  static const List<String> _omnilingualTokensCandidates = <String>[
    'assets/models/omnilingual_ctc/tokens.txt',
  ];
  static const List<String> _parakeetEncoderCandidates = <String>[
    'assets/models/parakeet_v3/encoder.int8.onnx',
    'assets/models/parakeet_v3/encoder.onnx',
  ];
  static const List<String> _parakeetDecoderCandidates = <String>[
    'assets/models/parakeet_v3/decoder.int8.onnx',
    'assets/models/parakeet_v3/decoder.onnx',
  ];
  static const List<String> _parakeetJoinerCandidates = <String>[
    'assets/models/parakeet_v3/joiner.int8.onnx',
    'assets/models/parakeet_v3/joiner.onnx',
  ];
  static const List<String> _parakeetTokensCandidates = <String>[
    'assets/models/parakeet_v3/tokens.txt',
  ];
  static const List<String> _whisperEncoderCandidates = <String>[
    'assets/models/whisper_small/encoder.int8.onnx',
    'assets/models/whisper_small/encoder.onnx',
  ];
  static const List<String> _whisperDecoderCandidates = <String>[
    'assets/models/whisper_small/decoder.int8.onnx',
    'assets/models/whisper_small/decoder.onnx',
  ];
  static const List<String> _whisperTokensCandidates = <String>[
    'assets/models/whisper_small/tokens.txt',
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

  Future<ModelAssetBundle> installOmnilingualAssets() async {
    final supportDir = await getApplicationSupportDirectory();
    final omnilingualDir = Directory(
      '${supportDir.path}/models/omnilingual_ctc',
    );
    await omnilingualDir.create(recursive: true);

    final model = await _copyFirstAvailableAsset(
      candidates: _omnilingualModelCandidates,
      targetName: 'model.onnx',
      targetDir: omnilingualDir,
    );
    final tokens = await _copyFirstAvailableAsset(
      candidates: _omnilingualTokensCandidates,
      targetName: 'tokens.txt',
      targetDir: omnilingualDir,
    );
    final sileroVadModel = await _copyFirstAvailableAsset(
      candidates: _sileroVadCandidates,
      targetName: 'silero_vad.onnx',
      targetDir: omnilingualDir,
    );

    debugPrint(
      '[OMNILINGUAL_ASSETS] model=${model.path} bytes=${await model.length()}',
    );
    debugPrint(
      '[OMNILINGUAL_ASSETS] tokens=${tokens.path} bytes=${await tokens.length()}',
    );
    debugPrint(
      '[OMNILINGUAL_ASSETS] vad=${sileroVadModel.path} bytes=${await sileroVadModel.length()}',
    );

    return ModelAssetBundle(
      zipformerEncoderPath: '',
      zipformerDecoderPath: '',
      zipformerJoinerPath: '',
      zipformerTokensPath: '',
      senseVoiceModelPath: '',
      senseVoiceTokensPath: '',
      sileroVadModelPath: sileroVadModel.path,
      omnilingualModelPath: model.path,
      omnilingualTokensPath: tokens.path,
    );
  }

  Future<ModelAssetBundle> installParakeetAssets() async {
    final supportDir = await getApplicationSupportDirectory();
    final parakeetDir = Directory('${supportDir.path}/models/parakeet_v3');
    await parakeetDir.create(recursive: true);

    final encoder = await _copyFirstAvailableAsset(
      candidates: _parakeetEncoderCandidates,
      targetName: 'encoder.onnx',
      targetDir: parakeetDir,
    );
    final decoder = await _copyFirstAvailableAsset(
      candidates: _parakeetDecoderCandidates,
      targetName: 'decoder.onnx',
      targetDir: parakeetDir,
    );
    final joiner = await _copyFirstAvailableAsset(
      candidates: _parakeetJoinerCandidates,
      targetName: 'joiner.onnx',
      targetDir: parakeetDir,
    );
    final tokens = await _copyFirstAvailableAsset(
      candidates: _parakeetTokensCandidates,
      targetName: 'tokens.txt',
      targetDir: parakeetDir,
    );
    final sileroVadModel = await _copyFirstAvailableAsset(
      candidates: _sileroVadCandidates,
      targetName: 'silero_vad.onnx',
      targetDir: parakeetDir,
    );

    debugPrint(
      '[PARAKEET_ASSETS] encoder=${encoder.path} bytes=${await encoder.length()}',
    );
    debugPrint(
      '[PARAKEET_ASSETS] decoder=${decoder.path} bytes=${await decoder.length()}',
    );
    debugPrint(
      '[PARAKEET_ASSETS] joiner=${joiner.path} bytes=${await joiner.length()}',
    );
    debugPrint(
      '[PARAKEET_ASSETS] tokens=${tokens.path} bytes=${await tokens.length()}',
    );
    debugPrint(
      '[PARAKEET_ASSETS] vad=${sileroVadModel.path} bytes=${await sileroVadModel.length()}',
    );

    return ModelAssetBundle(
      zipformerEncoderPath: '',
      zipformerDecoderPath: '',
      zipformerJoinerPath: '',
      zipformerTokensPath: '',
      senseVoiceModelPath: '',
      senseVoiceTokensPath: '',
      sileroVadModelPath: sileroVadModel.path,
      parakeetEncoderPath: encoder.path,
      parakeetDecoderPath: decoder.path,
      parakeetJoinerPath: joiner.path,
      parakeetTokensPath: tokens.path,
    );
  }

  Future<ModelAssetBundle> installWhisperAssets() async {
    final supportDir = await getApplicationSupportDirectory();
    final whisperDir = Directory('${supportDir.path}/models/whisper_small');
    await whisperDir.create(recursive: true);

    final encoder = await _copyFirstAvailableAsset(
      candidates: _whisperEncoderCandidates,
      targetName: 'encoder.onnx',
      targetDir: whisperDir,
    );
    final decoder = await _copyFirstAvailableAsset(
      candidates: _whisperDecoderCandidates,
      targetName: 'decoder.onnx',
      targetDir: whisperDir,
    );
    final tokens = await _copyFirstAvailableAsset(
      candidates: _whisperTokensCandidates,
      targetName: 'tokens.txt',
      targetDir: whisperDir,
    );
    final sileroVadModel = await _copyFirstAvailableAsset(
      candidates: _sileroVadCandidates,
      targetName: 'silero_vad.onnx',
      targetDir: whisperDir,
    );

    debugPrint(
      '[WHISPER_ASSETS] encoder=${encoder.path} bytes=${await encoder.length()}',
    );
    debugPrint(
      '[WHISPER_ASSETS] decoder=${decoder.path} bytes=${await decoder.length()}',
    );
    debugPrint(
      '[WHISPER_ASSETS] tokens=${tokens.path} bytes=${await tokens.length()}',
    );
    debugPrint(
      '[WHISPER_ASSETS] vad=${sileroVadModel.path} bytes=${await sileroVadModel.length()}',
    );

    return ModelAssetBundle(
      zipformerEncoderPath: '',
      zipformerDecoderPath: '',
      zipformerJoinerPath: '',
      zipformerTokensPath: '',
      senseVoiceModelPath: '',
      senseVoiceTokensPath: '',
      sileroVadModelPath: sileroVadModel.path,
      whisperEncoderPath: encoder.path,
      whisperDecoderPath: decoder.path,
      whisperTokensPath: tokens.path,
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
