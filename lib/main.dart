import 'dart:async';
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

class _MyHomePageState extends State<MyHomePage> with TickerProviderStateMixin {
  bool _isInitialLoad = true;
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
  bool _isStoryLoading = false;
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
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  Map<String, dynamic>? _preloadedStory;
  List<File> _preloadedAudioFiles = [];

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
  final List<String> genres = [
    "Action",
    "Adventure",
    "Classic",
    "Comedies",
    "Documentaries",
    "Dramas",
    "Horror",
    "Romantic",
    "Sci-fi",
    "Fantasy",
    "Sports",
    "Thrillers",
    "Historical",
    "Mystery",
    "Supernatural",
    "Crime",
    "Slice of Life"
  ];

  List<String> _selectedGenres = [];

  @override
  void initState() {
    super.initState();
    _initializeTTS();
    _loadPreferences().then((_) {
      _loadInterstitialAd();
      // Preload the first story
      _preloadNextStory().then((_) {
        // Display the preloaded story and narrate it
        _displayPreloadedStory().then((_) {
          setState(() {
            _isInitialLoad = false; // Initial load complete
          });
          // Preload the next story in the background
          _preloadNextStory();
        });
      });
    });

    // Initialize the animation controller and animations
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -1),
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    _fadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    _interstitialAd?.dispose();
    super.dispose();
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('nativeLanguage', _nativeLanguage);
    prefs.setString('targetLanguage', _targetLanguage);
    prefs.setString('difficultyLevel', _difficultyLevel);
    prefs.setStringList('selectedGenres', _selectedGenres);
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nativeLanguage = prefs.getString('nativeLanguage') ?? 'en-US';
      _targetLanguage = prefs.getString('targetLanguage') ?? 'ja-JP';
      _difficultyLevel =
          prefs.getString('difficultyLevel') ?? 'Absolute Beginner';
      _selectedGenres =
          prefs.getStringList('selectedGenres') ?? genres.toList();

      if (_selectedGenres.isEmpty) {
        _selectedGenres = genres.toList();
      }
    });
  }

  void _showInterstitialAd() {
    if (_interstitialAd != null) {
      _interstitialAd!.show();
    } else {
      // Load a new ad if the current ad is null
      _loadInterstitialAd();
    }
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
              // Resume story playing after the ad is dismissed
              _displayPreloadedStory().then((_) {
                _preloadNextStory().then((_) {
                  setState(() {
                    _isStoryLoading = false;
                  });
                  // Reset the animation controller after the story is generated
                  _animationController.reset();
                });
              });
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

  Future<void> _initializeTTS() async {
    final jsonCredentials = await DefaultAssetBundle.of(context)
        .loadString('assets/service_account_key.json');
    final credentials =
        ServiceAccountCredentials.fromJson(json.decode(jsonCredentials));
    final authClient = await clientViaServiceAccount(credentials, _scopes);
    _textToSpeechApi = TexttospeechApi(authClient);
  }

  Future<void> _playNextStory() async {
    if (_isStoryLoading) {
      // If a story is already being loaded, do nothing.
      return;
    }

    // Stop the current audio player
    await _audioPlayer.stop();

    // Start the animation and wait for it to finish
    await _animationController.forward();

    // Set the state to indicate loading
    setState(() {
      _isStoryLoading = true;
    });

    // Show interstitial ad randomly
    if (Random().nextInt(20) == 0 && _isInterstitialAdReady) {
      _showInterstitialAd();
      return; // Do not generate a story now, it will be handled in the ad callback
    }

    // Reset the narration session ID for the new story
    _narrationSessionId = DateTime.now().millisecondsSinceEpoch.toString();

    // Display the preloaded story without waiting for narration to complete
    await _displayPreloadedStory();

    // Preload the next story in parallel
    _preloadNextStory().then((_) {
      // Reset loading state after preloading
      setState(() {
        _isStoryLoading = false;
      });
    });
  }

  Future<void> _displayPreloadedStory() async {
    if (_preloadedStory == null) {
      setState(() {
        _isStoryLoading = false;
      });
      return;
    }

    setState(() {
      _sentences = _splitSentences(_preloadedStory!['storyPart']);
      _translations = _splitSentences(_preloadedStory!['translationPart']);
      _sentenceIndex = 0;
      _currentSentence = _sentences.isNotEmpty ? _sentences[0] : '';
      _currentSentenceTranslation =
          _showTranslations && _translations.isNotEmpty ? _translations[0] : '';
      _audioFiles = List<File>.from(_preloadedAudioFiles);
      _preloadedStory = null; // Clear preloaded story after using
    });

    debugPrint('Sentences: $_sentences');
    debugPrint('Translations: $_translations');

    // Reset the animation controller after the story is displayed
    _animationController.reset();

    // Narrate the current sentence without blocking
    _narrateCurrentSentence(_narrationSessionId);
  }

  Future<void> _preloadNextStory() async {
    final promptText = _buildPromptText();

    final model =
        FirebaseVertexAI.instance.generativeModel(model: 'gemini-1.5-flash');

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

    _preloadedStory = {
      'storyPart': storyPart,
      'translationPart': translationPart,
    };

    // Preload audio files with a unique identifier
    final uniqueId = DateTime.now().millisecondsSinceEpoch.toString();
    await _preloadAudioFiles(storyPart, uniqueId);
  }

  String _buildPromptText() {
    if (_selectedGenres.isEmpty) {
      _selectedGenres = genres.toList();
    }

    final targetLanguageName = _languages
        .firstWhere((lang) => lang['code'] == _targetLanguage)['name'];
    final nativeLanguageName = _languages
        .firstWhere((lang) => lang['code'] == _nativeLanguage)['name'];

    final shuffledGenres = _selectedGenres.toList()..shuffle();
    final randomGenre = shuffledGenres.first;

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

    return 'Create a unique and interesting $randomGenre story in $targetLanguageName at a $_difficultyLevel difficulty level. This story is for learners of the language. $difficultyDescription Ensure that the story is grammatically correct and do not include pronunciations or Roman alphabet transcriptions in parentheses. Each sentence should be separated by a newline character "\\n". Translate the story into $nativeLanguageName. Format the output with the story first, followed by "|SEPARATOR|", and then the translation.';
  }

  Future<void> _preloadAudioFiles(String storyPart, String uniqueId) async {
    _preloadedAudioFiles.clear();
    final sentences = _splitSentences(storyPart);
    final tempDir = await getTemporaryDirectory();

    for (int i = 0; i < sentences.length; i++) {
      final sentence = sentences[i];
      final file = await _synthesizeAudio(sentence, _targetLanguage,
          _getVoiceForLanguage(_targetLanguage), tempDir, uniqueId, i);
      if (file != null) {
        _preloadedAudioFiles.add(file);
      }
    }

    debugPrint('Preloaded audio files: $_preloadedAudioFiles');
  }

  List<String> _splitSentences(String text) {
    return text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s != '\\')
        .toList();
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

  Future<File?> _synthesizeAudio(String text, String languageCode,
      String voiceName, Directory tempDir, String uniqueId, int index) async {
    if (text.isEmpty) return null;

    final input = SynthesisInput(text: text);
    final voice =
        VoiceSelectionParams(languageCode: languageCode, name: voiceName);
    final audioConfig = AudioConfig(audioEncoding: 'MP3');
    final response = await _textToSpeechApi.text.synthesize(
        SynthesizeSpeechRequest(
            input: input, voice: voice, audioConfig: audioConfig));

    if (response.audioContent != null) {
      final bytes = Uint8List.fromList(response.audioContentAsBytes);
      final file = File('${tempDir.path}/$uniqueId-$index.mp3');
      await file.writeAsBytes(bytes);
      return file;
    }

    return null;
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
              heightFactor: 0.9,
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
                        const SizedBox(height: 16),
                        const Text('Genres:'),
                        GridView.count(
                          shrinkWrap: true,
                          crossAxisCount: 2,
                          childAspectRatio: 4,
                          children: genres.map((String genre) {
                            return CheckboxListTile(
                              title: Text(genre),
                              value: _selectedGenres.contains(genre),
                              onChanged: (bool? value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedGenres.add(genre);
                                  } else if (_selectedGenres.length > 1) {
                                    _selectedGenres.remove(genre);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'At least one genre must be selected.')),
                                    );
                                  }
                                  _savePreferences();
                                });
                              },
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
      body: GestureDetector(
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity! < 0) {
            debugPrint('Swipe up detected');
            _playNextStory();
          }
        },
        child: Container(
          color: Colors.transparent, // Ensure the container is tappable
          child: Column(
            children: [
              Spacer(flex: 4), // Equal flex value for the top spacer
              Expanded(
                flex: 6, // Increased flex value for the main content
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_isInitialLoad) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(width: 10),
                                const Text("Loading story..."),
                              ],
                            ),
                          ] else ...[
                            SelectableText(
                              _currentSentence,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              _currentSentenceTranslation,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 20,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            Spacer(flex: 1), // Spacer for balance
                            if (_isStoryLoading) ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const CircularProgressIndicator(),
                                  const SizedBox(width: 10),
                                  const Text("Loading next story..."),
                                ],
                              ),
                            ] else ...[
                              const Text(
                                "Swipe up for a new story",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ],
                          Spacer(
                              flex:
                                  1), // Equal flex value for the bottom spacer
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Row(
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
