import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';

import 'models/app_language.dart';
import 'models/live_result.dart';
import 'services/live_speech_pipeline.dart';
import 'widgets/waveform_bar.dart';

class LiveTranslateScreen extends StatefulWidget {
  const LiveTranslateScreen({super.key});

  @override
  State<LiveTranslateScreen> createState() => _LiveTranslateScreenState();
}

class _LiveTranslateScreenState extends State<LiveTranslateScreen> {
  static const int _sampleRate = 16000;
  static const int _waveformBars = 24;
  static const int _maxLogEntries = 80;

  final AudioRecorder _audioRecorder = AudioRecorder();
  final ScrollController _resultsScrollController = ScrollController();
  final ScrollController _logScrollController = ScrollController();
  final TextEditingController _sonioxApiKeyController = TextEditingController();

  StreamSubscription<Uint8List>? _audioStreamSub;

  List<double> _waveformLevels = List<double>.filled(_waveformBars, 0.04);
  final List<_LogEntry> _logs = <_LogEntry>[];

  late LiveSpeechPipeline _pipeline;
  AppLanguage _sourceLanguage = sonioxSourceLanguages.first;
  String _sonioxApiKey = '';
  bool _sonioxSpeakerDiarizationEnabled = true;

  String _transcript = '';
  List<SpeakerTurn> _speakerTurns = const <SpeakerTurn>[];
  String? _statusMessage = 'Preparing Soniox real-time transcription...';
  int _frameCount = 0;
  int _emptyDecodeWindows = 0;

  bool _isRecording = false;
  bool _isWarmingUp = false;

  @override
  void initState() {
    super.initState();
    _pipeline = _createPipeline();
    _appendLog(
      category: _LogCategory.system,
      message: 'Boot sequence started. Validating Soniox session settings.',
    );
    _sonioxApiKeyController.addListener(() {
      _sonioxApiKey = _sonioxApiKeyController.text;
    });
    unawaited(_warmUpPipeline());
  }

  Future<void> _warmUpPipeline() async {
    _setStatus(
      'Preparing Soniox session...',
      category: _LogCategory.system,
      logMessage:
          'Warmup requested for ${_sourceLanguage.label} on Soniox Real-Time API.',
    );

    setState(() {
      _isWarmingUp = true;
    });

    try {
      await _pipeline.warmUp(sourceLanguage: _sourceLanguage);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isWarmingUp = false;
      });
      _setStatus(
        'Pipeline init failed: ${error.toString()}',
        category: _LogCategory.error,
        logMessage: 'Warmup failed: $error',
      );
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isWarmingUp = false;
    });
    _setStatus(
      'Ready. Soniox will open a real-time cloud session for ${_sourceLanguage.label} when recording starts.',
      category: _LogCategory.success,
      logMessage:
          'Warmup finished. Soniox pipeline is online for ${_sourceLanguage.label}.',
    );
  }

  List<AppLanguage> get _currentSourceLanguages => sonioxSourceLanguages;

  LiveSpeechPipeline _createPipeline() => SonioxRealtimePipeline(
    apiKeyProvider: () => _sonioxApiKey,
    diarizationEnabledProvider: () => _sonioxSpeakerDiarizationEnabled,
  );

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopListening(flushPendingAudio: true);
      return;
    }

    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      _setStatus(
        'Microphone permission is required before recording.',
        category: _LogCategory.error,
        logMessage:
            'Recorder start blocked because microphone permission is missing.',
      );
      return;
    }

    if (!_pipeline.isReady) {
      _appendLog(
        category: _LogCategory.system,
        message: 'Pipeline was cold. Re-running warmup before capture.',
      );
      await _warmUpPipeline();
      if (!_pipeline.isReady) {
        return;
      }
    }

    await _startListening();
  }

  Future<void> _startListening() async {
    try {
      await _pipeline.resetSession();
    } catch (error) {
      _setStatus(
        'Unable to start Soniox: ${error.toString()}',
        category: _LogCategory.error,
        logMessage:
            'Capture start blocked because pipeline session setup failed: $error',
      );
      return;
    }

    final stream = await _audioRecorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
      ),
    );

    _frameCount = 0;
    _emptyDecodeWindows = 0;
    _appendLog(
      category: _LogCategory.capture,
      message: 'Microphone stream opened at 16 kHz mono PCM.',
    );
    setState(() {
      _transcript = '';
      _speakerTurns = const <SpeakerTurn>[];
    });

    _audioStreamSub = stream.listen(
      (data) => unawaited(_processAudioFrame(data)),
      onError: (Object error) {
        if (!mounted) {
          return;
        }

        setState(() {
          _isRecording = false;
        });
        _setStatus(
          'Recording error: $error',
          category: _LogCategory.error,
          logMessage: 'Recorder stream emitted an error: $error',
        );
      },
    );

    setState(() {
      _isRecording = true;
    });
    _setStatus(
      'Listening in ${_sourceLanguage.label}. Soniox will stream provisional and final transcript tokens over the network.',
      category: _LogCategory.capture,
      logMessage:
          'Capture armed for ${_sourceLanguage.label} on Soniox Real-Time API.',
    );
  }

  Future<void> _processAudioFrame(Uint8List pcmBytes) async {
    final frame = _convertBytesToDouble(pcmBytes);
    _updateWaveform(frame);
    _frameCount += 1;
    LiveResult? result;

    try {
      result = await _pipeline.ingestAudioFrame(
        pcmBytes: pcmBytes,
        samples: frame,
      );
    } catch (error) {
      if (_isRecording) {
        await _stopListening(flushPendingAudio: false);
      }
      _setStatus(
        'Streaming failed: ${error.toString()}',
        category: _LogCategory.error,
        logMessage: 'Pipeline ingest failed: $error',
      );
      return;
    }

    if (result != null) {
      _emptyDecodeWindows = 0;
      _applyStreamingResult(result);
      return;
    }

    if (_frameCount % 25 == 0) {
      _appendLog(
        category: _LogCategory.capture,
        message:
            'Audio checkpoint. engine=Soniox Real-Time API, frames=$_frameCount, rms=${_calculateRms(frame).toStringAsFixed(3)}.',
      );
    }

    if (_frameCount % 60 == 0) {
      _emptyDecodeWindows += 1;
      _appendLog(
        category: _LogCategory.decode,
        message:
            'No transcript update yet. engine=Soniox Real-Time API, frames=$_frameCount, empty_windows=$_emptyDecodeWindows.',
      );
    }
  }

  Future<void> _stopListening({required bool flushPendingAudio}) async {
    await _audioStreamSub?.cancel();
    _audioStreamSub = null;
    await _audioRecorder.stop();
    _appendLog(
      category: _LogCategory.capture,
      message: 'Microphone stream closed.',
    );

    if (flushPendingAudio) {
      LiveResult? finalResult;
      try {
        finalResult = await _pipeline.finishSession();
      } catch (error) {
        _setStatus(
          'Finalization failed: ${error.toString()}',
          category: _LogCategory.error,
          logMessage: 'Pipeline finalization failed: $error',
        );
      }
      if (finalResult != null) {
        _applyStreamingResult(finalResult, isFinal: true);
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isRecording = false;
      _waveformLevels = List<double>.filled(_waveformBars, 0.04);
    });
    _setStatus(
      'Recording stopped.',
      category: _LogCategory.system,
      logMessage: 'Capture stopped by user.',
    );
  }

  void _updateWaveform(List<double> frame) {
    final nextLevel = (_calculateRms(frame) * 6).clamp(0.04, 1.0);
    final updated = List<double>.from(_waveformLevels)
      ..removeAt(0)
      ..add(nextLevel);

    if (!mounted) {
      _waveformLevels = updated;
      return;
    }

    setState(() {
      _waveformLevels = updated;
    });
  }

  double _calculateRms(List<double> frame) {
    if (frame.isEmpty) {
      return 0;
    }

    var sum = 0.0;
    for (final sample in frame) {
      sum += sample * sample;
    }

    return math.sqrt(sum / frame.length);
  }

  List<double> _convertBytesToDouble(Uint8List data) {
    final byteData = ByteData.sublistView(data);
    final sampleCount = data.lengthInBytes ~/ 2;
    final samples = List<double>.filled(sampleCount, 0);

    for (var i = 0; i < sampleCount; i++) {
      final sample = byteData.getInt16(i * 2, Endian.little);
      samples[i] = sample / 32768.0;
    }

    return samples;
  }

  void _applyStreamingResult(LiveResult result, {bool isFinal = false}) {
    if (!mounted) {
      return;
    }

    setState(() {
      _transcript = result.transcript;
      _speakerTurns = result.speakerTurns;
    });

    final preview = result.transcript.isEmpty
        ? '(empty transcript)'
        : result.transcript.length > 72
        ? '${result.transcript.substring(0, 72)}...'
        : result.transcript;

    _appendLog(
      category: isFinal ? _LogCategory.success : _LogCategory.decode,
      message:
          '${isFinal ? 'Final' : 'Partial'} transcript update. chars=${result.transcript.length}, text="$preview"',
    );
    _scrollResultsToBottom();
  }

  void _setStatus(
    String message, {
    required _LogCategory category,
    String? logMessage,
  }) {
    if (mounted) {
      setState(() {
        _statusMessage = message;
      });
    } else {
      _statusMessage = message;
    }

    if (logMessage != null) {
      _appendLog(category: category, message: logMessage);
    }
  }

  void _appendLog({required _LogCategory category, required String message}) {
    final entry = _LogEntry(
      timestamp: DateTime.now(),
      category: category,
      message: message,
    );
    debugPrint('[APP_LOG][${category.label}] $message');

    if (mounted) {
      setState(() {
        _logs.insert(0, entry);
        if (_logs.length > _maxLogEntries) {
          _logs.removeLast();
        }
      });
    } else {
      _logs.insert(0, entry);
      if (_logs.length > _maxLogEntries) {
        _logs.removeLast();
      }
    }

    _scrollLogsToTop();
  }

  void _scrollResultsToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_resultsScrollController.hasClients) {
        return;
      }

      _resultsScrollController.animateTo(
        _resultsScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _scrollLogsToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logScrollController.hasClients) {
        return;
      }

      _logScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    unawaited(_audioStreamSub?.cancel());
    unawaited(_audioRecorder.stop());
    _audioRecorder.dispose();
    _sonioxApiKeyController.dispose();
    unawaited(_pipeline.dispose());
    _resultsScrollController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color(0xFF08121B),
              Color(0xFF071C1C),
              Color(0xFF0B1020),
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final isWide = constraints.maxWidth >= 1100;
              final topSection = _buildCommandDeck(theme, isWide: isWide);

              final outputSection = isWide
                  ? _TextPanel(
                      title: 'Transcript',
                      subtitle: _sourceLanguage.label,
                      body: _transcript,
                      speakerTurns: _speakerTurns,
                    )
                  : _TextPanel(
                      title: 'Transcript',
                      subtitle: _sourceLanguage.label,
                      body: _transcript,
                      speakerTurns: _speakerTurns,
                    );

              return SingleChildScrollView(
                controller: _resultsScrollController,
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  children: <Widget>[
                    topSection,
                    const SizedBox(height: 18),
                    outputSection,
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCommandDeck(ThemeData theme, {required bool isWide}) {
    return Column(
      children: <Widget>[
        _FrostedPanel(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Control Deck',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _SignalPill(
                    label: _isWarmingUp
                        ? 'SYNC'
                        : _isRecording
                        ? 'LIVE'
                        : 'IDLE',
                    color: _isWarmingUp
                        ? const Color(0xFFF59E0B)
                        : _isRecording
                        ? const Color(0xFF34D399)
                        : const Color(0xFF64748B),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _LanguageSelectorCard(
                sourceLanguage: _sourceLanguage,
                items: _currentSourceLanguages,
                isBusy: _isRecording || _isWarmingUp,
                onSourceChanged: (language) async {
                  setState(() {
                    _sourceLanguage = language;
                  });
                  _appendLog(
                    category: _LogCategory.system,
                    message:
                        'Source language changed to ${language.label} on Soniox Real-Time API.',
                  );
                  await _warmUpPipeline();
                },
              ),
              const SizedBox(height: 18),
              _ProviderConfigCard(
                controller: _sonioxApiKeyController,
                isBusy: _isRecording || _isWarmingUp,
                diarizationEnabled: _sonioxSpeakerDiarizationEnabled,
                onDiarizationChanged: (value) async {
                  setState(() {
                    _sonioxSpeakerDiarizationEnabled = value;
                  });
                  _appendLog(
                    category: _LogCategory.system,
                    message:
                        'Soniox speaker diarization ${value ? 'enabled' : 'disabled'}.',
                  );
                  await _warmUpPipeline();
                },
                onSubmitted: (_) => unawaited(_warmUpPipeline()),
              ),
              const SizedBox(height: 18),
              _MonitorPanel(
                statusMessage: _statusMessage ?? '',
                waveformLevels: _waveformLevels,
                isRecording: _isRecording,
                onToggleRecording: _isWarmingUp ? null : _toggleRecording,
              ),
              const SizedBox(height: 18),
              _TerminalLogPanel(
                logs: _logs,
                scrollController: _logScrollController,
                height: isWide ? 420 : 340,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProviderConfigCard extends StatelessWidget {
  const _ProviderConfigCard({
    required this.controller,
    required this.isBusy,
    required this.diarizationEnabled,
    required this.onDiarizationChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool isBusy;
  final bool diarizationEnabled;
  final ValueChanged<bool> onDiarizationChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0A141D),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF163041)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Soniox Session',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Paste a Soniox API key to try the hosted real-time engine. Soniox recommends temporary keys for client apps.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF94A3B8),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            enabled: !isBusy,
            obscureText: true,
            onSubmitted: onSubmitted,
            decoration: const InputDecoration(
              labelText: 'Soniox API key',
              hintText: 'soniox_...',
            ),
          ),
          const SizedBox(height: 10),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: diarizationEnabled,
            onChanged: isBusy ? null : onDiarizationChanged,
            title: const Text('Enable speaker diarization'),
            subtitle: const Text(
              'Show speaker-labeled turns when Soniox returns diarization metadata.',
            ),
          ),
        ],
      ),
    );
  }
}

enum _LogCategory { system, capture, segment, decode, success, error }

class _LogEntry {
  const _LogEntry({
    required this.timestamp,
    required this.category,
    required this.message,
  });

  final DateTime timestamp;
  final _LogCategory category;
  final String message;
}

class _FrostedPanel extends StatelessWidget {
  const _FrostedPanel({
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xCC0E1A24),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF1E293B)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x4D020617),
            blurRadius: 28,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _MonitorPanel extends StatelessWidget {
  const _MonitorPanel({
    required this.statusMessage,
    required this.waveformLevels,
    required this.isRecording,
    required this.onToggleRecording,
  });

  final String statusMessage;
  final List<double> waveformLevels;
  final bool isRecording;
  final Future<void> Function()? onToggleRecording;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0A141D),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF163041)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'Live Monitor',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isRecording
                      ? const Color(0x2234D399)
                      : const Color(0x221E293B),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isRecording
                        ? const Color(0xFF34D399)
                        : const Color(0xFF475569),
                  ),
                ),
                child: Text(
                  isRecording ? 'REC' : 'STBY',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: isRecording
                        ? const Color(0xFF86EFAC)
                        : const Color(0xFF94A3B8),
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            statusMessage,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF94A3B8),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF061018),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF143042)),
            ),
            child: WaveformBar(
              levels: waveformLevels,
              isRecording: isRecording,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onToggleRecording,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(58),
                backgroundColor: isRecording
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF10B981),
                foregroundColor: const Color(0xFF04130F),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              icon: Icon(
                isRecording ? Icons.stop_circle_outlined : Icons.mic_rounded,
              ),
              label: Text(isRecording ? 'Stop Recording' : 'Start Recording'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageSelectorCard extends StatelessWidget {
  const _LanguageSelectorCard({
    required this.sourceLanguage,
    required this.items,
    required this.isBusy,
    required this.onSourceChanged,
  });

  final AppLanguage sourceLanguage;
  final List<AppLanguage> items;
  final bool isBusy;
  final ValueChanged<AppLanguage> onSourceChanged;

  @override
  Widget build(BuildContext context) {
    return _LanguageDropdown(
      label: 'Transcribe in',
      value: sourceLanguage,
      enabled: !isBusy,
      items: items,
      onChanged: onSourceChanged,
    );
  }
}

class _LanguageDropdown extends StatelessWidget {
  const _LanguageDropdown({
    required this.label,
    required this.value,
    required this.enabled,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final AppLanguage value;
  final bool enabled;
  final List<AppLanguage> items;
  final ValueChanged<AppLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<AppLanguage>(
      initialValue: value,
      dropdownColor: const Color(0xFF0F1A23),
      decoration: InputDecoration(labelText: label),
      items: items
          .map(
            (language) => DropdownMenuItem<AppLanguage>(
              value: language,
              child: Text(language.label),
            ),
          )
          .toList(),
      onChanged: enabled
          ? (language) {
              if (language != null) {
                onChanged(language);
              }
            }
          : null,
    );
  }
}

class _TerminalLogPanel extends StatelessWidget {
  const _TerminalLogPanel({
    required this.logs,
    required this.scrollController,
    required this.height,
  });

  final List<_LogEntry> logs;
  final ScrollController scrollController;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: height,
      child: _FrostedPanel(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  'Activity Log',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                const _WindowChromeDots(),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Live event stream from capture and streaming decode.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF050B10),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFF163041)),
                ),
                child: logs.isEmpty
                    ? const Center(
                        child: Text(
                          'No events yet.',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontFamily: 'monospace',
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        reverse: false,
                        itemCount: logs.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 14, color: Color(0xFF102231)),
                        itemBuilder: (BuildContext context, int index) {
                          return _LogLine(entry: logs[index]);
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry});

  final _LogEntry entry;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 13.5,
          height: 1.45,
          color: Color(0xFFE2E8F0),
        ),
        children: <InlineSpan>[
          TextSpan(
            text: '[${_formatTime(entry.timestamp)}] ',
            style: const TextStyle(color: Color(0xFF64748B)),
          ),
          TextSpan(
            text: '${entry.category.label} ',
            style: TextStyle(
              color: entry.category.color,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: entry.message),
        ],
      ),
    );
  }

  static String _formatTime(DateTime timestamp) {
    final hours = timestamp.hour.toString().padLeft(2, '0');
    final minutes = timestamp.minute.toString().padLeft(2, '0');
    final seconds = timestamp.second.toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}

extension on _LogCategory {
  String get label => switch (this) {
    _LogCategory.system => 'SYS',
    _LogCategory.capture => 'MIC',
    _LogCategory.segment => 'VAD',
    _LogCategory.decode => 'ASR',
    _LogCategory.success => 'OK ',
    _LogCategory.error => 'ERR',
  };

  Color get color => switch (this) {
    _LogCategory.system => const Color(0xFF38BDF8),
    _LogCategory.capture => const Color(0xFFA78BFA),
    _LogCategory.segment => const Color(0xFFF59E0B),
    _LogCategory.decode => const Color(0xFF22C55E),
    _LogCategory.success => const Color(0xFF4ADE80),
    _LogCategory.error => const Color(0xFFFB7185),
  };
}

class _TextPanel extends StatelessWidget {
  const _TextPanel({
    required this.title,
    required this.subtitle,
    required this.body,
    required this.speakerTurns,
  });

  final String title;
  final String subtitle;
  final String body;
  final List<SpeakerTurn> speakerTurns;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _FrostedPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 10),
              _SignalPill(
                label: subtitle.toUpperCase(),
                color: const Color(0xFF38BDF8),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 220),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF09131C),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFF163041)),
            ),
            child: speakerTurns.isNotEmpty
                ? _SpeakerTurnList(turns: speakerTurns)
                : Text(
                    body.isEmpty ? 'Waiting for audio...' : body,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      height: 1.65,
                      color: const Color(0xFFF8FAFC),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SpeakerTurnList extends StatelessWidget {
  const _SpeakerTurnList({required this.turns});

  final List<SpeakerTurn> turns;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: turns
          .map(
            (turn) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _SignalPill(
                    label: turn.speakerLabel.toUpperCase(),
                    color: const Color(0xFFF59E0B),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    turn.text,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      height: 1.65,
                      color: const Color(0xFFF8FAFC),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _WindowChromeDots extends StatelessWidget {
  const _WindowChromeDots();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: <Widget>[
        _Dot(color: Color(0xFFFB7185)),
        SizedBox(width: 6),
        _Dot(color: Color(0xFFFBBF24)),
        SizedBox(width: 6),
        _Dot(color: Color(0xFF4ADE80)),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _SignalPill extends StatelessWidget {
  const _SignalPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          fontSize: 12,
        ),
      ),
    );
  }
}
