import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class ModelAssetBundle {
  ModelAssetBundle({
    required this.zipformerEncoderPath,
    required this.zipformerDecoderPath,
    required this.zipformerJoinerPath,
    required this.zipformerTokensPath,
  });

  final String zipformerEncoderPath;
  final String zipformerDecoderPath;
  final String zipformerJoinerPath;
  final String zipformerTokensPath;
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

  Future<ModelAssetBundle> installZipformerAssets() async {
    final supportDir = await getApplicationSupportDirectory();
    final modelsDir = Directory('${supportDir.path}/models/zipformer');
    await modelsDir.create(recursive: true);

    final encoder = await _copyFirstAvailableAsset(
      candidates: _encoderCandidates,
      targetName: 'encoder.onnx',
      targetDir: modelsDir,
    );
    final decoder = await _copyFirstAvailableAsset(
      candidates: _decoderCandidates,
      targetName: 'decoder.onnx',
      targetDir: modelsDir,
    );
    final joiner = await _copyFirstAvailableAsset(
      candidates: _joinerCandidates,
      targetName: 'joiner.onnx',
      targetDir: modelsDir,
    );
    final tokens = await _copyFirstAvailableAsset(
      candidates: _tokensCandidates,
      targetName: 'tokens.txt',
      targetDir: modelsDir,
    );

    return ModelAssetBundle(
      zipformerEncoderPath: encoder.path,
      zipformerDecoderPath: decoder.path,
      zipformerJoinerPath: joiner.path,
      zipformerTokensPath: tokens.path,
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
        return targetFile;
      } catch (_) {
        continue;
      }
    }

    throw StateError(
      'Missing Zipformer asset. Expected one of: ${candidates.join(', ')}',
    );
  }
}
