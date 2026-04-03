import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

// Ovdje importuj svoj LiveTranslationScreen
import 'src/app.dart';

void main() {
  // Obavezno kada radimo sa native pluginima prije runApp-a
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const TranslationApp());
}

class TranslationApp extends StatelessWidget {
  const TranslationApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Live Translation',
      theme: ThemeData(primarySwatch: Colors.blue),
      // Aplikacija se otvara na Loading ekranu
      home: const InitialLoadingScreen(),
    );
  }
}

// --- LOADING EKRAN I LOGIKA ZA KOPIRANJE ---

class InitialLoadingScreen extends StatefulWidget {
  const InitialLoadingScreen({Key? key}) : super(key: key);

  @override
  _InitialLoadingScreenState createState() => _InitialLoadingScreenState();
}

class _InitialLoadingScreenState extends State<InitialLoadingScreen> {
  String _statusMessage = "Inicijalizacija...";

  @override
  void initState() {
    super.initState();
    _prepareAssetsAndStart();
  }

  Future<void> _prepareAssetsAndStart() async {
    try {
      setState(() => _statusMessage = "Priprema VAD modela...");
      File vadFile = await _copyAssetToPhysicalStorage('assets/models/silero_vad.onnx');

      setState(() => _statusMessage = "Priprema AI rječnika...");
      File tokensFile = await _copyAssetToPhysicalStorage('assets/models/whisper/small-tokens.txt');

      setState(() => _statusMessage = "Priprema glavnog ASR modela (ovo može potrajati)...");
      File modelFile = await _copyAssetToPhysicalStorage('assets/models/whisper/small-encoder.int8.onnx');

      setState(() => _statusMessage = "Priprema glavnog ASR modela (ovo može potrajati)...");
      File modelDecoderFile = await _copyAssetToPhysicalStorage('assets/models/whisper/small-decoder.int8.onnx');

      // Kada je sve gotovo, prebacujemo korisnika na glavni ekran
      // Koristimo pushReplacement da korisnik ne može uraditi "Back" na loading ekran
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => LiveTranslationScreen(
              modelPath: modelFile.path,      // Uzimamo .path iz File objekta
              tokensPath: tokensFile.path,
              vadModelPath: vadFile.path,
              model2Path: modelDecoderFile.path,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _statusMessage = "Greška pri učitavanju: $e");
    }
  }

  // --- HELPER FUNKCIJA (Privatna za ovu klasu) ---
  Future<File> _copyAssetToPhysicalStorage(String assetPath) async {
    final supportDir = await getApplicationSupportDirectory();

    // Zadržavamo strukturu foldera (sklanjamo 'assets/' sa početka)
    // Npr. 'assets/models/sensevoice/tokens.txt' postaje 'models/sensevoice/tokens.txt'
    final relativePath = assetPath.replaceFirst('assets/', '');
    final targetFile = File('${supportDir.path}/$relativePath');

    // NOVA LINIJA: Ako fajl već postoji, preskoči kopiranje i samo ga vrati
    if (await targetFile.exists()) {
      return targetFile;
    }

    // Kreiraj folder ako ne postoji
    await targetFile.parent.create(recursive: true);

    // Učitaj i prekopiraj fajl
    final assetData = await rootBundle.load(assetPath);
    final bytes = Uint8List.sublistView(assetData);
    await targetFile.writeAsBytes(bytes, flush: true);

    return targetFile;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}