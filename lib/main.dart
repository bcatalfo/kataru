import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_vertexai/firebase_vertexai.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';
import 'package:googleapis/texttospeech/v1.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kataru',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red[700]!),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Kataru'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String _currentSentence = '';
  String _currentSentenceTranslation = '';
  String _nativeLanguage = 'en-US'; // Default to English (US)
  String _targetLanguage = 'ja-JP'; // Default to Japanese
  List<String> _sentences = [];
  List<String> _translations = [];
  int _sentenceIndex = 0;
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<File> _audioFiles = [];
  bool _isPlaying = false;
  bool _showTranslations = false;
  String _narrationSessionId = '';
  String _difficultyLevel = 'A1';
  final List<String> _difficultyLevels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

  final List<Map<String, String>> _languages = [
    {'name': 'English (US) 🇺🇸', 'code': 'en-US'},
    {'name': 'Japanese 🇯🇵', 'code': 'ja-JP'},
    {'name': 'Spanish (Spain) 🇪🇸', 'code': 'es-ES'},
    {'name': 'Mandarin Chinese (Simplified) 🇨🇳', 'code': 'zh-CN'},
    {'name': 'Mandarin Chinese (Traditional) 🇹🇼', 'code': 'zh-TW'},
    {'name': 'Korean 🇰🇷', 'code': 'ko-KR'},
    {'name': 'French 🇫🇷', 'code': 'fr-FR'},
    {'name': 'German 🇩🇪', 'code': 'de-DE'},
    {'name': 'Portuguese (Brazil) 🇧🇷', 'code': 'pt-BR'},
    {'name': 'Russian 🇷🇺', 'code': 'ru-RU'},
    {'name': 'Hindi 🇮🇳', 'code': 'hi-IN'},
    {'name': 'Italian 🇮🇹', 'code': 'it-IT'},
  ];
  final _scopes = [TexttospeechApi.cloudPlatformScope];
  late final TexttospeechApi _textToSpeechApi;

  @override
  void initState() {
    super.initState();
    _initializeTTS();
    _generateNewStory();
  }

  Future<void> _initializeTTS() async {
    final jsonCredentials = await DefaultAssetBundle.of(context)
        .loadString('assets/service_account_key.json');
    final credentials =
        ServiceAccountCredentials.fromJson(json.decode(jsonCredentials));
    final authClient = await clientViaServiceAccount(credentials, _scopes);
    _textToSpeechApi = TexttospeechApi(authClient);
  }

  Future<void> _generateNewStory() async {
    // Change the narration session ID to stop any ongoing narration
    setState(() {
      _narrationSessionId = DateTime.now().millisecondsSinceEpoch.toString();
      _isPlaying = false;
      _audioFiles.clear();
      _sentences.clear();
      _translations.clear();
    });

    // Stop the current audio player
    await _audioPlayer.stop();

    // Generate the new story
    final model =
        FirebaseVertexAI.instance.generativeModel(model: 'gemini-1.5-flash');
    final prompt = [
      Content.text(
          'Create a unique, short story in $_targetLanguage for language learning beginners at $_difficultyLevel level. Each sentence should be separated by a newline character "\\n". Translate the story into $_nativeLanguage. Format the output with the story first, followed by "|SEPARATOR|", and then the translation.')
    ];
    final response = await model.generateContent(prompt);

    debugPrint('Generated Story: ${response.text}');

    // Process and clean up the response text
    final parts = response.text?.split('|SEPARATOR|') ?? [];
    final storyPart =
        parts.isNotEmpty ? parts[0].replaceAll(r'\n', '\n').trim() : '';
    final translationPart =
        parts.length > 1 ? parts[1].replaceAll(r'\n', '\n').trim() : '';

    debugPrint('Story Part: $storyPart');
    debugPrint('Translation Part: $translationPart');

    setState(() {
      _sentences = _splitSentences(storyPart);
      _translations = _splitSentences(translationPart);
      _sentenceIndex = 0;
      _currentSentence = _sentences.isNotEmpty ? _sentences[0] : '';
      _currentSentenceTranslation =
          _showTranslations && _translations.isNotEmpty ? _translations[0] : '';
    });

    debugPrint('Sentences: $_sentences');
    debugPrint('Translations: $_translations');

    await _generateAudioFiles();
    await _narrateCurrentSentence(_narrationSessionId);
  }

  List<String> _splitSentences(String text) {
    return text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s != '\\')
        .toList();
  }

  Future<void> _generateAudioFiles() async {
    _audioFiles.clear();
    final tempDir = await getTemporaryDirectory();

    for (int i = 0; i < _sentences.length; i++) {
      final sentence = _sentences[i];

      await _synthesizeAudio(sentence, _targetLanguage,
          _getVoiceForLanguage(_targetLanguage), tempDir, i);
    }

    debugPrint('Generated audio files: $_audioFiles');
  }

  String _getVoiceForLanguage(String languageCode) {
    switch (languageCode) {
      case 'ja-JP':
        return 'ja-JP-Neural2-B'; // Japanese (Female)
      case 'en-US':
        return 'en-US-Neural2-D'; // English US (Male)
      case 'es-ES':
        return 'es-ES-Neural2-A'; // Spanish Spain (Female)
      case 'zh-CN':
        return 'cmn-CN-Wavenet-A'; // Mandarin Chinese Simplified (Female)
      case 'zh-TW':
        return 'cmn-TW-Wavenet-A'; // Mandarin Chinese Traditional (Female)
      case 'ko-KR':
        return 'ko-KR-Neural2-A'; // Korean (Female)
      case 'fr-FR':
        return 'fr-FR-Neural2-A'; // French (Female)
      case 'de-DE':
        return 'de-DE-Neural2-A'; // German (Female)
      case 'pt-BR':
        return 'pt-BR-Neural2-A'; // Portuguese Brazil (Female)
      case 'ru-RU':
        return 'ru-RU-Wavenet-A'; // Russian (Female)
      case 'hi-IN':
        return 'hi-IN-Neural2-A'; // Hindi (Female)
      case 'it-IT':
        return 'it-IT-Neural2-A'; // Italian (Female)
      default:
        return 'en-US-Wavenet-D'; // Default to English US (Male)
    }
  }

  Future<void> _synthesizeAudio(String text, String languageCode,
      String voiceName, Directory tempDir, int index) async {
    if (text.isEmpty) return;

    final input = SynthesisInput(text: text);
    final voice =
        VoiceSelectionParams(languageCode: languageCode, name: voiceName);
    final audioConfig = AudioConfig(audioEncoding: 'MP3');
    final response = await _textToSpeechApi.text.synthesize(
        SynthesizeSpeechRequest(
            input: input, voice: voice, audioConfig: audioConfig));

    if (response.audioContent != null) {
      final bytes = Uint8List.fromList(response.audioContentAsBytes);
      final file = File('${tempDir.path}/$index.mp3');
      await file.writeAsBytes(bytes);
      _audioFiles.add(file);
    }
  }

  Future<void> _narrateCurrentSentence(String sessionId) async {
    if (_audioFiles.isEmpty ||
        _sentenceIndex >= _sentences.length ||
        sessionId != _narrationSessionId) return;

    final sentenceFile = _audioFiles[_sentenceIndex];

    try {
      await _audioPlayer.play(DeviceFileSource(sentenceFile.path));
      setState(() {
        _isPlaying = true;
      });

      // Wait for the audio to complete
      await _audioPlayer.onPlayerComplete.first;

      if (sessionId != _narrationSessionId)
        return; // Exit if the session ID has changed

      setState(() {
        _isPlaying = false;
      });

      if (_sentenceIndex < _sentences.length - 1) {
        debugPrint('index: $_sentenceIndex');
        setState(() {
          _sentenceIndex++;
          _currentSentence = _sentences[_sentenceIndex];
          _currentSentenceTranslation =
              _showTranslations && _translations.isNotEmpty
                  ? _translations[_sentenceIndex]
                  : '';
        });
        await _narrateCurrentSentence(sessionId);
      } else {
        debugPrint('Starting over');
        // Repeat the story from the beginning
        setState(() {
          _sentenceIndex = 0;
          _currentSentence = _sentences[0];
          _currentSentenceTranslation =
              _showTranslations && _translations.isNotEmpty
                  ? _translations[0]
                  : '';
        });
        await _narrateCurrentSentence(sessionId);
      }
    } catch (e) {
      print('Error playing audio file: $e');
    }
  }

  void _pauseAudio() {
    _audioPlayer.pause();
    setState(() {
      _isPlaying = false;
    });
  }

  void _resumeAudio() {
    _audioPlayer.resume();
    setState(() {
      _isPlaying = true;
    });
  }

  void _previousSentence() {
    if (_sentenceIndex > 0) {
      setState(() {
        _narrationSessionId = DateTime.now().millisecondsSinceEpoch.toString();
        _sentenceIndex--;
        _currentSentence = _sentences[_sentenceIndex];
        _currentSentenceTranslation =
            _showTranslations && _translations.isNotEmpty
                ? _translations[_sentenceIndex]
                : '';
      });

      _audioPlayer.stop();
      _narrateCurrentSentence(_narrationSessionId);
    }
  }

  void _nextSentence() {
    if (_sentenceIndex < _sentences.length - 1) {
      setState(() {
        _narrationSessionId = DateTime.now().millisecondsSinceEpoch.toString();
        _sentenceIndex++;
        _currentSentence = _sentences[_sentenceIndex];
        _currentSentenceTranslation =
            _showTranslations && _translations.isNotEmpty
                ? _translations[_sentenceIndex]
                : '';
      });

      _audioPlayer.stop();
      _narrateCurrentSentence(_narrationSessionId);
    }
  }

  void _toggleTranslations() {
    setState(() {
      _showTranslations = !_showTranslations;
      _currentSentenceTranslation =
          _showTranslations && _translations.isNotEmpty
              ? _translations[_sentenceIndex]
              : '';
    });
  }

  void _showDifficultyDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Difficulty Level'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: _difficultyLevels.map((level) {
              return RadioListTile<String>(
                title: Text(level),
                value: level,
                groupValue: _difficultyLevel,
                onChanged: (String? value) {
                  setState(() {
                    _difficultyLevel = value!;
                  });
                  _generateNewStory();
                  Navigator.of(context).pop();
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('Settings'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Native Language:'),
                  DropdownButton<String>(
                    value: _nativeLanguage,
                    onChanged: (String? newValue) {
                      setState(() {
                        _nativeLanguage = newValue!;
                      });
                    },
                    items: _languages.map<DropdownMenuItem<String>>(
                        (Map<String, String> language) {
                      return DropdownMenuItem<String>(
                        value: language['code'],
                        child: Text(language['name']!),
                      );
                    }).toList(),
                  ),
                  const Text('Target Language:'),
                  DropdownButton<String>(
                    value: _targetLanguage,
                    onChanged: (String? newValue) {
                      setState(() {
                        _targetLanguage = newValue!;
                      });
                      _generateNewStory();
                    },
                    items: _languages.map<DropdownMenuItem<String>>(
                        (Map<String, String> language) {
                      return DropdownMenuItem<String>(
                        value: language['code'],
                        child: Text(language['name']!),
                      );
                    }).toList(),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Close'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _currentSentence,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _currentSentenceTranslation,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 20, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: _showDifficultyDialog,
                    child: Text(_difficultyLevel,
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _previousSentence,
                  ),
                  IconButton(
                    icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                    onPressed: _isPlaying ? _pauseAudio : _resumeAudio,
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: _nextSentence,
                  ),
                  IconButton(
                    icon: const Icon(Icons.translate),
                    onPressed: _toggleTranslations,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _generateNewStory,
                child: const Text('Generate New Story'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
