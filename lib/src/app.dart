import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:record/record.dart';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:sherpa_onnx/sherpa_onnx.dart';

class LiveTranslationScreen extends StatefulWidget {
  final String modelPath;
  final String tokensPath;
  final String vadModelPath;

  const LiveTranslationScreen({
    Key? key,
    required this.modelPath,
    required this.tokensPath,
    required this.vadModelPath,
  }) : super(key: key);

  @override
  _LiveTranslationScreenState createState() => _LiveTranslationScreenState();
}

class _LiveTranslationScreenState extends State<LiveTranslationScreen> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioStreamSub;
  final ScrollController _scrollController = ScrollController();

  OfflineRecognizer? _recognizer;
  VoiceActivityDetector? _vad;

  String _finalText = "";
  final int _sampleRate = 16000;

  final Queue<Float32List> _processingQueue = Queue<Float32List>();
  bool _isEngineBusy = false;
  bool _isSherpaInitialized = false;
  int _frameCount = 0; // Dodano za praćenje protoka audia

  @override
  void initState() {
    super.initState();
    print("🚀 INIT: Pokrećem LiveTranslationScreen...");
    _initSherpa();
  }

  Future<void> _initSherpa() async {
    print("⚙️ SHERPA: Započinjem inicijalizaciju...");
    if (!_isSherpaInitialized) {
      sherpa_onnx.initBindings();
      _isSherpaInitialized = true;
      print("⚙️ SHERPA: Native bindings inicijalizovani.");
    }

    // 1. ASR Model (SenseVoice)
    final config = sherpa_onnx.OfflineRecognizerConfig(
      model: sherpa_onnx.OfflineModelConfig(
        tokens: widget.tokensPath,
        senseVoice: sherpa_onnx.OfflineSenseVoiceModelConfig(
          model: widget.modelPath,
          language: "en",
        ),
        numThreads: 1,
        debug: true,
        modelType: 'sense_voice',
      ),
      feat: sherpa_onnx.FeatureConfig(
        sampleRate: 16000,
        featureDim: 80,
      ),
    );

    try {
      _recognizer = sherpa_onnx.OfflineRecognizer(config);
      print("✅ SHERPA: ASR Recognizer USPJEŠNO kreiran!");
    } catch (e) {
      print("❌ SHERPA GREŠKA: Recognizer nije kreiran. Razlog: $e");
    }

    // 2. VAD Model (Silero)
    try {
      _vad = VoiceActivityDetector(
        config: VadModelConfig(
          sileroVad: SileroVadModelConfig(
            model: widget.vadModelPath,
            threshold: 0.2, // OVO SMANJI SA 0.5 NA 0.2 (veća osjetljivost)
            minSpeechDuration: 0.1,
            minSilenceDuration: 0.5,
            windowSize: 512,
          ),
          sampleRate: _sampleRate,
          numThreads: 1,
          debug: false,
        ),
        bufferSizeInSeconds: 60.0,
      );
      print("✅ SHERPA: VAD Model USPJEŠNO kreiran!");
    } catch (e) {
      print("❌ SHERPA GREŠKA: VAD nije kreiran. Razlog: $e");
    }
    setState(() {});
  }

  Future<void> _startListening() async {
    print("🎙️ MIC: Pokušavam pokrenuti snimanje...");

    if (!await _audioRecorder.hasPermission()) {
      print("❌ MIC GREŠKA: Nemam dozvolu za mikrofon!");
      return;
    }
    print("✅ MIC: Dozvola odobrena.");

    try {
      final stream = await _audioRecorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
        ),
      );
      print("✅ MIC: Stream uspješno pokrenut. Slušam...");

      _audioStreamSub = stream.listen((data) {
        _frameCount++;
        if (_frameCount % 20 == 0) {
          // Printamo svake ~2 sekunde da potvrdimo da podaci zaista stižu
          print("🌊 AUDIO TOK: Primam podatke... (Frame: $_frameCount, Veličina: ${data.length} bytes)");
        }
        _processAudioFrame(_convertBytesToFloat32(data));
      });

      setState(() {});
    } catch (e) {
      print("❌ MIC GREŠKA: Pucanje pri pokretanju streama: $e");
    }
  }

  String _mergeText(String existingText, String newText) {
    // 1. Očistimo SenseVoice tagove (npr. <|zh|>, <|NEUTRAL|>, <|Speech|>)
    String cleanNewText = newText.replaceAll(RegExp(r'<\|.*?\|>'), '').trim();

    if (existingText.isEmpty) return cleanNewText;
    if (cleanNewText.isEmpty) return existingText;

    existingText = existingText.trimRight();

    // 2. Sigurnije spajanje bez RangeError-a
    int maxOverlapLength = 20;
    if (cleanNewText.length < maxOverlapLength) maxOverlapLength = cleanNewText.length;
    if (existingText.length < maxOverlapLength) maxOverlapLength = existingText.length;

    for (int i = maxOverlapLength; i > 0; i--) {
      // Dodali smo try-catch da nikad ne pukne ako se desi neki čudan index
      try {
        String suffix = existingText.substring(existingText.length - i);
        String prefix = cleanNewText.substring(0, i);

        if (suffix.toLowerCase() == prefix.toLowerCase()) {
          return existingText + " " + cleanNewText.substring(i).trimLeft();
        }
      } catch (e) {
        continue;
      }
    }

    return existingText + " " + cleanNewText;
  }

  void _processAudioFrame(Float32List frame) {
    if (_vad == null || _recognizer == null) return;

    _vad!.acceptWaveform(frame);

    while (!_vad!.isEmpty()) {
      print("🎯 VAD DETEKTOVAO GOVOR: Cijela rečenica je uhvaćena i spremna za dekodiranje!");

      final segment = _vad!.front();
      _vad!.pop();

      _processingQueue.add(Float32List.fromList(segment.samples));
      print("📦 RED ČEKANJA: Novi audio segment dodan u red (Dužina reda: ${_processingQueue.length})");

      if (!_isEngineBusy) {
        _processNextInQueue();
      } else {
        print("⏳ RED ČEKANJA: Engine je zauzet, segment će sačekati.");
      }
    }
  }

  Future<void> _processNextInQueue() async {
    if (_processingQueue.isEmpty || _recognizer == null) {
      _isEngineBusy = false;
      return;
    }

    _isEngineBusy = true;
    print("⚙️ ASR ENGINE: Preuzimam segment iz reda i krećem u prepoznavanje...");
    final chunk = _processingQueue.removeFirst();

    try {
      final offlineStream = _recognizer!.createStream();
      offlineStream.acceptWaveform(sampleRate: _sampleRate, samples: chunk);

      print("🧠 ASR ENGINE: Dekodiram...");
      _recognizer!.decode(offlineStream);

      final result = _recognizer!.getResult(offlineStream);
      offlineStream.free();

      print("📝 ASR REZULTAT (RAW): '${result.text}'");

      if (result.text.isNotEmpty) {
        setState(() {
          _finalText = _mergeText(_finalText, result.text);
        });
        _scrollToBottom();
      } else {
        print("⚠️ ASR ENGINE: Model je vratio prazan string.");
      }
    } catch (e) {
      print("❌ ASR GREŠKA: Pucanje prilikom prepoznavanja: $e");
    }

    _processNextInQueue();
  }

  Float32List _convertBytesToFloat32(Uint8List data) {
    // Koristimo ByteData za sigurnu manipulaciju bajtovima
    final byteData = ByteData.sublistView(data);

    // Svaki sample ima 2 bajta (16 bita), pa je dužina niza duplo manja
    final float32List = Float32List(data.length ~/ 2);

    double maxAmplitude = 0.0;

    for (int i = 0; i < float32List.length; i++) {
      // Eksplicitno čitamo 16-bitni integer kao Little Endian (iOS/Android standard)
      int sample = byteData.getInt16(i * 2, Endian.little);

      // Normalizacija u raspon -1.0 do 1.0
      float32List[i] = sample / 32768.0;

      if (float32List[i].abs() > maxAmplitude) {
        maxAmplitude = float32List[i].abs();
      }
    }

    if (_frameCount % 20 == 0) {
      print("🔊 JAČINA ZVUKA (Max Amplituda): ${maxAmplitude.toStringAsFixed(4)}");
    }

    return float32List;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _stopListening() async {
    print("🛑 MIC: Zaustavljam mikrofon...");
    await _audioStreamSub?.cancel();
    _audioStreamSub = null;
    await _audioRecorder.stop();
    setState(() {});
    print("🛑 MIC: Uspješno zaustavljen.");
  }

  @override
  void dispose() {
    print("🗑️ DISPOSE: Gasim aplikaciju i oslobađam memoriju...");
    _stopListening();
    _audioRecorder.dispose();
    _recognizer?.free();
    _vad?.free();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Live ASR Engine", style: TextStyle(color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Text(
                    _finalText.isEmpty ? "Pritisni mikrofon i reci nešto..." : _finalText,
                    style: const TextStyle(
                      fontSize: 24,
                      height: 1.4,
                      color: Colors.black87,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(32.0),
              child: FloatingActionButton.large(
                onPressed: _audioStreamSub == null ? _startListening : _stopListening,
                backgroundColor: _audioStreamSub == null ? Colors.blueAccent : Colors.redAccent,
                elevation: 4,
                child: Icon(
                  _audioStreamSub == null ? Icons.mic : Icons.stop,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}