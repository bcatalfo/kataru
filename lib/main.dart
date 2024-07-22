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
  String _story = 'Press the button to generate a new story.';
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

  final List<Map<String, String>> _languages = [
    {'name': 'English (US)', 'code': 'en-US'},
    {'name': 'Japanese', 'code': 'ja-JP'},
    {'name': 'Spanish (Spain)', 'code': 'es-ES'},
    {'name': 'French', 'code': 'fr-FR'},
    {'name': 'German', 'code': 'de-DE'},
    {'name': 'Italian', 'code': 'it-IT'},
    {'name': 'Mandarin (Simplified)', 'code': 'zh-CN'},
    {'name': 'Mandarin (Traditional)', 'code': 'zh-TW'},
    {'name': 'Korean', 'code': 'ko-KR'},
    {'name': 'Russian', 'code': 'ru-RU'},
    {'name': 'Portuguese (Brazil)', 'code': 'pt-BR'},
    {'name': 'Arabic', 'code': 'ar-XA'},
    {'name': 'Hindi', 'code': 'hi-IN'},
  ];

  final _scopes = [TexttospeechApi.cloudPlatformScope];
  late final TexttospeechApi _textToSpeechApi;

  @override
  void initState() {
    super.initState();
    _initializeTTS();
  }

  Future<void> _initializeTTS() async {
    final jsonCredentials = await DefaultAssetBundle.of(context)
        .loadString('assets/service_account_key.json');
    final credentials =
        ServiceAccountCredentials.fromJson(json.decode(jsonCredentials));
    final authClient = await clientViaServiceAccount(credentials, _scopes);
    _textToSpeechApi = TexttospeechApi(authClient);
  }

  List<String> _splitSentences(String text) {
    return text.split('\n').where((s) => s.trim().isNotEmpty).toList();
  }

  Future<void> _generateNewStory() async {
    final model =
        FirebaseVertexAI.instance.generativeModel(model: 'gemini-1.5-flash');
    final prompt = [
      Content.text(
          'Create a short and simple story in $_targetLanguage for language learning beginners. Each sentence should be separated by a newline character "\\n". Translate the story into $_nativeLanguage. Format the output as: Story: <story in target language>\\n\\nTranslation: <translation in native language>')
    ];
    final response = await model.generateContent(prompt);

    debugPrint('Generated Story: ${response.text}');

    final parts = response.text?.split('Translation: ') ?? [];
    final storyPart = parts.isNotEmpty
        ? parts[0].replaceFirst('Story: ', '').replaceAll('\\n', ' ')
        : '';
    final translationPart =
        parts.length > 1 ? parts[1].replaceAll('\\n', ' ') : '';

    setState(() {
      _story = storyPart;
      _sentences = _splitSentences(storyPart);
      _translations = _splitSentences(translationPart);
      _sentenceIndex = 0;
      _currentSentence = _sentences.isNotEmpty ? _sentences[0] : '';
      _currentSentenceTranslation =
          _translations.isNotEmpty ? _translations[0] : '';
    });

    await _generateAudioFiles();
    _narrateCurrentSentence();
  }

  Future<void> _generateAudioFiles() async {
    _audioFiles.clear();
    final tempDir = await getTemporaryDirectory();

    for (int i = 0; i < _sentences.length; i++) {
      final sentence = _sentences[i];

      await _synthesizeAudio(sentence, _targetLanguage,
          _getVoiceForLanguage(_targetLanguage), tempDir, i);
    }

    print('Generated audio files: $_audioFiles');
  }

  String _getVoiceForLanguage(String languageCode) {
    switch (languageCode) {
      case 'ja-JP':
        return 'ja-JP-Wavenet-A';
      case 'en-US':
        return 'en-US-Wavenet-D';
      // Add other languages and their respective voices here
      default:
        return 'en-US-Wavenet-D'; // Default to English US
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

  Future<void> _narrateCurrentSentence() async {
    if (_audioFiles.isEmpty || _sentenceIndex >= _sentences.length) return;

    final sentenceFile = _audioFiles[_sentenceIndex];

    try {
      await _audioPlayer.play(DeviceFileSource(sentenceFile.path));
      setState(() {
        _isPlaying = true;
      });

      _audioPlayer.onPlayerComplete.listen((event) {
        setState(() {
          _isPlaying = false;
        });
        if (_sentenceIndex < _sentences.length - 1) {
          setState(() {
            _sentenceIndex++;
            _currentSentence = _sentences[_sentenceIndex];
            _currentSentenceTranslation =
                _showTranslations && _translations.isNotEmpty
                    ? _translations[_sentenceIndex]
                    : '';
          });
          _narrateCurrentSentence();
        } else {
          // Repeat the story from the beginning
          setState(() {
            _sentenceIndex = 0;
            _currentSentence = _sentences[0];
            _currentSentenceTranslation =
                _showTranslations && _translations.isNotEmpty
                    ? _translations[0]
                    : '';
          });
          _narrateCurrentSentence();
        }
      });
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
        _sentenceIndex--;
        _currentSentence = _sentences[_sentenceIndex];
        _currentSentenceTranslation =
            _showTranslations && _translations.isNotEmpty
                ? _translations[_sentenceIndex]
                : '';
      });

      _audioPlayer.stop();
      _narrateCurrentSentence();
    }
  }

  void _nextSentence() {
    if (_sentenceIndex < _sentences.length - 1) {
      setState(() {
        _sentenceIndex++;
        _currentSentence = _sentences[_sentenceIndex];
        _currentSentenceTranslation =
            _showTranslations && _translations.isNotEmpty
                ? _translations[_sentenceIndex]
                : '';
      });

      _audioPlayer.stop();
      _narrateCurrentSentence();
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

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
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
      body: Center(
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
    );
  }
}
