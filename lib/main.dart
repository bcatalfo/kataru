import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'firebase_options.dart';
import 'package:firebase_vertexai/firebase_vertexai.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:googleapis/texttospeech/v1.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  MobileAds.instance.initialize();
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
  InterstitialAd? _interstitialAd;
  bool _isInterstitialAdReady = false;
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
  String _difficultyLevel = 'Absolute Beginner';
  final List<String> _difficultyLevels = [
    'Absolute Beginner',
    'Beginner',
    'Easy',
    'Intermediate',
    'Advanced',
    'Expert'
  ];

  final List<Map<String, String>> _languages = [
    {'name': 'English (US) 🇺🇸', 'code': 'en-US'},
    {'name': 'Japanese 🇯🇵', 'code': 'ja-JP'},
    {'name': 'Spanish (Spain) 🇪🇸', 'code': 'es-ES'},
    {'name': 'Mandarin Chinese (Simplified Characters) 🇨🇳', 'code': 'zh-CN'},
    {'name': 'Mandarin Chinese (Traditional Characters) 🇹🇼', 'code': 'zh-TW'},
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
    _loadPreferences();
    _generateNewStory();
    _loadInterstitialAd();
  }

  @override
  void dispose() {
    _interstitialAd?.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nativeLanguage = prefs.getString('nativeLanguage') ?? 'en-US';
      _targetLanguage = prefs.getString('targetLanguage') ?? 'ja-JP';
      _difficultyLevel =
          prefs.getString('difficultyLevel') ?? 'Absolute Beginner';
    });
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('nativeLanguage', _nativeLanguage);
    prefs.setString('targetLanguage', _targetLanguage);
    prefs.setString('difficultyLevel', _difficultyLevel);
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: 'ca-app-pub-3940256099942544/4411468910',
      request: AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialAdReady = true;
          _interstitialAd!.setImmersiveMode(true);
          _interstitialAd!.fullScreenContentCallback =
              FullScreenContentCallback(
            onAdShowedFullScreenContent: (InterstitialAd ad) {
              // Pause audio when the ad is shown
              _pauseAudio();
            },
            onAdDismissedFullScreenContent: (InterstitialAd ad) {
              // Generate the new story after the ad is dismissed
              _generateAndDisplayNewStory();
              ad.dispose();
              _loadInterstitialAd(); // Load a new ad
            },
            onAdFailedToShowFullScreenContent:
                (InterstitialAd ad, AdError error) {
              ad.dispose();
              _loadInterstitialAd(); // Load a new ad
            },
          );
        },
        onAdFailedToLoad: (error) {
          _isInterstitialAdReady = false;
          // Handle the error
        },
      ),
    );
  }

  void _showInterstitialAd() {
    if (_interstitialAd != null) {
      _interstitialAd!.show();
    } else {
      // Load a new ad if the current ad is null
      _loadInterstitialAd();
    }
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
    // Stop the current audio player
    await _audioPlayer.stop();

    // Show interstitial ad randomly
    if (Random().nextInt(2) == 0 && _isInterstitialAdReady) {
      _showInterstitialAd();
      return; // Do not generate a story now, it will be handled in the ad callback
    }
    _generateAndDisplayNewStory();
  }

  Future<void> _generateAndDisplayNewStory() async {
    // Change the narration session ID to stop any ongoing narration
    setState(() {
      _narrationSessionId = DateTime.now().millisecondsSinceEpoch.toString();
      _isPlaying = false;
      _audioFiles.clear();
      _sentences.clear();
      _translations.clear();
    });

    // Generate the new story
    final model =
        FirebaseVertexAI.instance.generativeModel(model: 'gemini-1.5-flash');
    final List<String> genres = [
      "adventure",
      "romance",
      "mystery",
      "historical fiction",
      "science fiction",
      "fantasy",
      "horror",
      "thriller",
      "comedy",
      "drama",
      "slice of life",
      "mythology",
      "fairy tale",
      "travel",
      "food and cooking",
      "sports",
      "music",
      "art",
      "technology",
      "environmental",
      "cultural exploration",
      "family and relationships",
      "friendship",
      "hero's journey",
      "coming of age",
      "holiday and celebrations",
      "workplace stories",
      "school and education",
      "health and wellness",
      "animals and nature",
      "urban life",
      "rural life",
      "supernatural",
      "crime and detective",
      "war and conflict",
      "exploration and discovery",
      "space exploration",
      "time travel",
      "magical realism",
      "folklore",
      "legends",
      "dystopian",
      "utopian",
      "post-apocalyptic",
      "cyberpunk",
      "steampunk",
      "noir",
      "political intrigue",
      "psychological",
      "self-discovery",
      "moral dilemmas",
      "social issues",
      "philosophical",
      "spiritual journeys"
    ];

    final targetLanguageName = _languages
        .firstWhere((lang) => lang['code'] == _targetLanguage)['name'];
    final nativeLanguageName = _languages
        .firstWhere((lang) => lang['code'] == _nativeLanguage)['name'];
    final randomGenre = (genres..shuffle()).first;

    String difficultyDescription;

    switch (_difficultyLevel) {
      case 'Absolute Beginner':
        difficultyDescription =
            'Use very simple vocabulary and short sentences.';
        break;
      case 'Beginner':
        difficultyDescription = 'Use simple vocabulary and short sentences.';
        break;
      case 'Intermediate':
        difficultyDescription = 'Use moderate vocabulary and sentence length.';
        break;
      case 'Advanced':
        difficultyDescription = 'Use complex vocabulary and longer sentences.';
        break;
      case 'Expert':
        difficultyDescription =
            'Use very complex vocabulary and intricate sentences.';
        break;
      default:
        difficultyDescription = 'Use simple vocabulary and short sentences.';
    }

    final promptText =
        'Create a unique and interesting $randomGenre story in $targetLanguageName at a $_difficultyLevel difficulty level. This story is for learners of the language. $difficultyDescription Ensure that the story is grammatically correct and do not include pronunciations or Roman alphabet transcriptions in parentheses. Each sentence should be separated by a newline character "\\n". Translate the story into $nativeLanguageName. Format the output with the story first, followed by "|SEPARATOR|", and then the translation.';

    final prompt = [Content.text(promptText)];

    debugPrint('prompt: $promptText');
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

  void _showSettingsDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return FractionallySizedBox(
              heightFactor:
                  0.9, // Adjust this value to cover more or less of the screen
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('Settings'),
                  actions: [
                    TextButton(
                      child: const Text('Close'),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Native Language:'),
                        DropdownButton<String>(
                          value: _nativeLanguage,
                          onChanged: (String? newValue) {
                            setState(() {
                              _nativeLanguage = newValue!;
                              _savePreferences();
                            });
                          },
                          isExpanded: true,
                          items: _languages.map<DropdownMenuItem<String>>(
                              (Map<String, String> language) {
                            return DropdownMenuItem<String>(
                              value: language['code'],
                              child: Text(language['name']!),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        const Text('Target Language:'),
                        DropdownButton<String>(
                          value: _targetLanguage,
                          onChanged: (String? newValue) {
                            setState(() {
                              _targetLanguage = newValue!;
                              _savePreferences();
                            });
                            _generateNewStory();
                          },
                          isExpanded: true,
                          items: _languages.map<DropdownMenuItem<String>>(
                              (Map<String, String> language) {
                            return DropdownMenuItem<String>(
                              value: language['code'],
                              child: Text(language['name']!),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        const Text('Difficulty Level:'),
                        DropdownButton<String>(
                          value: _difficultyLevel,
                          onChanged: (String? newValue) {
                            setState(() {
                              _difficultyLevel = newValue!;
                              _savePreferences();
                            });
                            _generateNewStory();
                          },
                          isExpanded: true,
                          items: _difficultyLevels
                              .map<DropdownMenuItem<String>>((String level) {
                            return DropdownMenuItem<String>(
                              value: level,
                              child: Text(level),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
                      SelectableText(
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
      ),
    );
  }
}
