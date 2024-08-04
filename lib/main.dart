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

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final themeString = prefs.getString('themeMode') ?? 'system';
    setState(() {
      _themeMode = _stringToThemeMode(themeString);
    });
  }

  ThemeMode _stringToThemeMode(String themeString) {
    switch (themeString) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> _saveThemePreference(ThemeMode themeMode) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('themeMode', _themeModeToString(themeMode));
  }

  String _themeModeToString(ThemeMode themeMode) {
    switch (themeMode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      default:
        return 'system';
    }
  }

  void _changeTheme(ThemeMode themeMode) {
    setState(() {
      _themeMode = themeMode;
      _saveThemePreference(themeMode);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kataru',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red[700]!),
        useMaterial3: true,
      ),
      darkTheme: ThemeData.dark(),
      themeMode: _themeMode,
      home: MyHomePage(
        title: 'Kataru',
        onThemeChanged: _changeTheme,
        themeMode: _themeMode,
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({
    super.key,
    required this.title,
    required this.onThemeChanged,
    required this.themeMode,
  });

  final String title;
  final Function(ThemeMode) onThemeChanged;
  final ThemeMode themeMode;

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
  bool _showTranslations = true;
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
    {'name': 'Afrikaans (South Africa) 🇿🇦', 'code': 'af-ZA'},
    {'name': 'Arabic 🇦🇪', 'code': 'ar-XA'},
    {'name': 'Basque (Spain) 🇪🇸', 'code': 'eu-ES'},
    {'name': 'Bengali (India) 🇮🇳', 'code': 'bn-IN'},
    {'name': 'Bulgarian (Bulgaria) 🇧🇬', 'code': 'bg-BG'},
    {'name': 'Catalan (Spain) 🇪🇸', 'code': 'ca-ES'},
    {'name': 'Chinese (Hong Kong) 🇭🇰', 'code': 'yue-HK'},
    {'name': 'Czech (Czech Republic) 🇨🇿', 'code': 'cs-CZ'},
    {'name': 'Danish (Denmark) 🇩🇰', 'code': 'da-DK'},
    {'name': 'Dutch (Belgium) 🇧🇪', 'code': 'nl-BE'},
    {'name': 'Dutch (Netherlands) 🇳🇱', 'code': 'nl-NL'},
    {'name': 'English (Australia) 🇦🇺', 'code': 'en-AU'},
    {'name': 'English (India) 🇮🇳', 'code': 'en-IN'},
    {'name': 'English (UK) 🇬🇧', 'code': 'en-GB'},
    {'name': 'English (US) 🇺🇸', 'code': 'en-US'},
    {'name': 'Filipino (Philippines) 🇵🇭', 'code': 'fil-PH'},
    {'name': 'Finnish (Finland) 🇫🇮', 'code': 'fi-FI'},
    {'name': 'French (Canada) 🇨🇦', 'code': 'fr-CA'},
    {'name': 'French (France) 🇫🇷', 'code': 'fr-FR'},
    {'name': 'Galician (Spain) 🇪🇸', 'code': 'gl-ES'},
    {'name': 'German (Germany) 🇩🇪', 'code': 'de-DE'},
    {'name': 'Greek (Greece) 🇬🇷', 'code': 'el-GR'},
    {'name': 'Gujarati (India) 🇮🇳', 'code': 'gu-IN'},
    {'name': 'Hebrew (Israel) 🇮🇱', 'code': 'he-IL'},
    {'name': 'Hindi (India) 🇮🇳', 'code': 'hi-IN'},
    {'name': 'Hungarian (Hungary) 🇭🇺', 'code': 'hu-HU'},
    {'name': 'Icelandic (Iceland) 🇮🇸', 'code': 'is-IS'},
    {'name': 'Indonesian (Indonesia) 🇮🇩', 'code': 'id-ID'},
    {'name': 'Italian (Italy) 🇮🇹', 'code': 'it-IT'},
    {'name': 'Japanese (Japan) 🇯🇵', 'code': 'ja-JP'},
    {'name': 'Kannada (India) 🇮🇳', 'code': 'kn-IN'},
    {'name': 'Korean (South Korea) 🇰🇷', 'code': 'ko-KR'},
    {'name': 'Latvian (Latvia) 🇱🇻', 'code': 'lv-LV'},
    {'name': 'Lithuanian (Lithuania) 🇱🇹', 'code': 'lt-LT'},
    {'name': 'Malay (Malaysia) 🇲🇾', 'code': 'ms-MY'},
    {'name': 'Malayalam (India) 🇮🇳', 'code': 'ml-IN'},
    {'name': 'Mandarin Chinese (China) 🇨🇳', 'code': 'cmn-CN'},
    {'name': 'Mandarin Chinese (Taiwan) 🇹🇼', 'code': 'cmn-TW'},
    {'name': 'Marathi (India) 🇮🇳', 'code': 'mr-IN'},
    {'name': 'Norwegian (Norway) 🇳🇴', 'code': 'nb-NO'},
    {'name': 'Polish (Poland) 🇵🇱', 'code': 'pl-PL'},
    {'name': 'Portuguese (Brazil) 🇧🇷', 'code': 'pt-BR'},
    {'name': 'Portuguese (Portugal) 🇵🇹', 'code': 'pt-PT'},
    {'name': 'Punjabi (India) 🇮🇳', 'code': 'pa-IN'},
    {'name': 'Romanian (Romania) 🇷🇴', 'code': 'ro-RO'},
    {'name': 'Russian (Russia) 🇷🇺', 'code': 'ru-RU'},
    {'name': 'Serbian (Cyrillic) 🇷🇸', 'code': 'sr-RS'},
    {'name': 'Slovak (Slovakia) 🇸🇰', 'code': 'sk-SK'},
    {'name': 'Spanish (Spain) 🇪🇸', 'code': 'es-ES'},
    {'name': 'Spanish (US) 🇺🇸', 'code': 'es-US'},
    {'name': 'Swedish (Sweden) 🇸🇪', 'code': 'sv-SE'},
    {'name': 'Tamil (India) 🇮🇳', 'code': 'ta-IN'},
    {'name': 'Telugu (India) 🇮🇳', 'code': 'te-IN'},
    {'name': 'Thai (Thailand) 🇹🇭', 'code': 'th-TH'},
    {'name': 'Turkish (Turkey) 🇹🇷', 'code': 'tr-TR'},
    {'name': 'Ukrainian (Ukraine) 🇺🇦', 'code': 'uk-UA'},
    {'name': 'Vietnamese (Vietnam) 🇻🇳', 'code': 'vi-VN'}
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
        FirebaseVertexAI.instance.generativeModel(model: 'gemini-1.5-pro-001');

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

    // Remove "##" from the beginning of the story and translation using regex
    final cleanedStoryPart = storyPart.replaceAll(RegExp(r'^##\s*'), '');
    final cleanedTranslationPart =
        translationPart.replaceAll(RegExp(r'^##\s*'), '');

    _preloadedStory = {
      'storyPart': cleanedStoryPart,
      'translationPart': cleanedTranslationPart,
    };

    // Preload audio files with a unique identifier
    final uniqueId = DateTime.now().millisecondsSinceEpoch.toString();
    await _preloadAudioFiles(cleanedStoryPart, uniqueId);
  }

  String _buildPromptText() {
    if (_selectedGenres.isEmpty) {
      _selectedGenres = genres.toList();
    }

    final targetLanguage = _languages
        .firstWhere((lang) => lang['code'] == _targetLanguage)['name']!;
    final nativeLanguage = _languages
        .firstWhere((lang) => lang['code'] == _nativeLanguage)['name']!;

    final shuffledGenres = _selectedGenres.toList()..shuffle();
    final randomGenre = shuffledGenres.first;

    String difficultyDescription;

    switch (_difficultyLevel) {
      case 'Absolute Beginner':
        difficultyDescription = 'Use extremely simple vocabulary and grammar.';
        break;
      case 'Beginner':
        difficultyDescription = 'Use very simple vocabulary and grammar.';
        break;
      case 'Intermediate':
        difficultyDescription = 'Use simple vocabulary and grammar.';
        break;
      case 'Advanced':
        difficultyDescription = 'Use typical vocabulary and grammar.';
        break;
      case 'Expert':
        difficultyDescription = 'Use sophisticated vocabulary and grammar.';
        break;
      default:
        difficultyDescription = 'Use extremely simple vocabulary and grammar.';
    }

    String characterRequirement = '';
    if (_targetLanguage == 'cmn-TW') {
      characterRequirement =
          'Use Traditional Chinese characters and the Chinese used in Taiwan. Do not use Simplified Chinese characters. ';
    } else if (_targetLanguage == 'cmn-CN') {
      characterRequirement =
          'Use Simplified Chinese characters and the Chinese used in mainland China. Do not use Traditional Chinese characters. ';
    }

    return 'Write a story in $targetLanguage. $difficultyDescription '
        'The story should be in the genre of $randomGenre. '
        '$characterRequirement'
        'Each sentence must be separated by a newline character "\n". Translate the story into $nativeLanguage. '
        'Format the output with the story first, followed by "|SEPARATOR|", and then the translation.';
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
      case 'af-ZA':
        return 'af-ZA-Standard-A'; // Afrikaans (South Africa) - Female
      case 'ar-XA':
        return 'ar-XA-Standard-A'; // Arabic - Female
      case 'eu-ES':
        return 'eu-ES-Standard-A'; // Basque (Spain) - Female
      case 'bn-IN':
        return 'bn-IN-Standard-A'; // Bengali (India) - Female
      case 'bg-BG':
        return 'bg-BG-Standard-A'; // Bulgarian (Bulgaria) - Female
      case 'ca-ES':
        return 'ca-ES-Standard-A'; // Catalan (Spain) - Female
      case 'yue-HK':
        return 'yue-HK-Standard-A'; // Chinese (Hong Kong) - Female
      case 'cs-CZ':
        return 'cs-CZ-Standard-A'; // Czech (Czech Republic) - Female
      case 'da-DK':
        return 'da-DK-Standard-A'; // Danish (Denmark) - Female
      case 'nl-BE':
        return 'nl-BE-Standard-A'; // Dutch (Belgium) - Female
      case 'nl-NL':
        return 'nl-NL-Standard-A'; // Dutch (Netherlands) - Female
      case 'en-AU':
        return 'en-AU-Standard-A'; // English (Australia) - Female
      case 'en-IN':
        return 'en-IN-Standard-A'; // English (India) - Female
      case 'en-GB':
        return 'en-GB-Standard-A'; // English (UK) - Female
      case 'en-US':
        return 'en-US-Standard-A'; // English (US) - Male
      case 'fil-PH':
        return 'fil-PH-Standard-A'; // Filipino (Philippines) - Female
      case 'fi-FI':
        return 'fi-FI-Standard-A'; // Finnish (Finland) - Female
      case 'fr-CA':
        return 'fr-CA-Standard-A'; // French (Canada) - Female
      case 'fr-FR':
        return 'fr-FR-Standard-A'; // French (France) - Female
      case 'gl-ES':
        return 'gl-ES-Standard-A'; // Galician (Spain) - Female
      case 'de-DE':
        return 'de-DE-Standard-A'; // German (Germany) - Female
      case 'el-GR':
        return 'el-GR-Standard-A'; // Greek (Greece) - Female
      case 'gu-IN':
        return 'gu-IN-Standard-A'; // Gujarati (India) - Female
      case 'he-IL':
        return 'he-IL-Standard-A'; // Hebrew (Israel) - Female
      case 'hi-IN':
        return 'hi-IN-Standard-A'; // Hindi (India) - Female
      case 'hu-HU':
        return 'hu-HU-Standard-A'; // Hungarian (Hungary) - Female
      case 'is-IS':
        return 'is-IS-Standard-A'; // Icelandic (Iceland) - Female
      case 'id-ID':
        return 'id-ID-Standard-A'; // Indonesian (Indonesia) - Female
      case 'it-IT':
        return 'it-IT-Standard-A'; // Italian (Italy) - Female
      case 'ja-JP':
        return 'ja-JP-Standard-A'; // Japanese (Japan) - Female
      case 'kn-IN':
        return 'kn-IN-Standard-A'; // Kannada (India) - Female
      case 'ko-KR':
        return 'ko-KR-Standard-A'; // Korean (South Korea) - Female
      case 'lv-LV':
        return 'lv-LV-Standard-A'; // Latvian (Latvia) - Male
      case 'lt-LT':
        return 'lt-LT-Standard-A'; // Lithuanian (Lithuania) - Male
      case 'ms-MY':
        return 'ms-MY-Standard-A'; // Malay (Malaysia) - Female
      case 'ml-IN':
        return 'ml-IN-Standard-A'; // Malayalam (India) - Female
      case 'cmn-CN':
        return 'cmn-CN-Standard-A'; // Mandarin Chinese (China) - Female
      case 'cmn-TW':
        return 'cmn-TW-Standard-A'; // Mandarin Chinese (Taiwan) - Female
      case 'mr-IN':
        return 'mr-IN-Standard-A'; // Marathi (India) - Female
      case 'nb-NO':
        return 'nb-NO-Standard-A'; // Norwegian (Norway) - Female
      case 'pl-PL':
        return 'pl-PL-Standard-A'; // Polish (Poland) - Female
      case 'pt-BR':
        return 'pt-BR-Standard-A'; // Portuguese (Brazil) - Female
      case 'pt-PT':
        return 'pt-PT-Standard-A'; // Portuguese (Portugal) - Female
      case 'pa-IN':
        return 'pa-IN-Standard-A'; // Punjabi (India) - Female
      case 'ro-RO':
        return 'ro-RO-Standard-A'; // Romanian (Romania) - Female
      case 'ru-RU':
        return 'ru-RU-Standard-A'; // Russian (Russia) - Female
      case 'sr-RS':
        return 'sr-RS-Standard-A'; // Serbian (Cyrillic) - Female
      case 'sk-SK':
        return 'sk-SK-Standard-A'; // Slovak (Slovakia) - Female
      case 'es-ES':
        return 'es-ES-Standard-A'; // Spanish (Spain) - Female
      case 'es-US':
        return 'es-US-Standard-A'; // Spanish (US) - Female
      case 'sv-SE':
        return 'sv-SE-Standard-A'; // Swedish (Sweden) - Female
      case 'ta-IN':
        return 'ta-IN-Standard-A'; // Tamil (India) - Female
      case 'te-IN':
        return 'te-IN-Standard-A'; // Telugu (India) - Female
      case 'th-TH':
        return 'th-TH-Standard-A'; // Thai (Thailand) - Female
      case 'tr-TR':
        return 'tr-TR-Standard-A'; // Turkish (Turkey) - Female
      case 'uk-UA':
        return 'uk-UA-Standard-A'; // Ukrainian (Ukraine) - Female
      case 'vi-VN':
        return 'vi-VN-Standard-A'; // Vietnamese (Vietnam) - Female
      default:
        return 'en-US-Standard-A'; // Default to English (US) - Male
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
      // Start playing the audio file
      await _audioPlayer.play(DeviceFileSource(sentenceFile.path));
      if (!_isPlaying) {
        setState(() {
          _isPlaying = true;
        });
      }

      // Wait for the audio to complete
      await _audioPlayer.onPlayerComplete.first;

      if (sessionId != _narrationSessionId)
        return; // Exit if the session ID has changed

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
      debugPrint('Error playing audio file: $e');
    }
  }

  void _pauseAudio() {
    _audioPlayer.pause();
    if (_isPlaying) {
      setState(() {
        _isPlaying = false;
      });
    }
  }

  void _resumeAudio() {
    _audioPlayer.resume();
    if (!_isPlaying) {
      setState(() {
        _isPlaying = true;
      });
    }
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
                        const Text('Theme:'),
                        Wrap(
                          spacing: 8.0,
                          children: [
                            ChoiceChip(
                              label: const Text('System Default'),
                              selected: widget.themeMode == ThemeMode.system,
                              onSelected: (bool selected) {
                                if (selected) {
                                  widget.onThemeChanged(ThemeMode.system);
                                }
                              },
                            ),
                            ChoiceChip(
                              label: const Text('Light'),
                              selected: widget.themeMode == ThemeMode.light,
                              onSelected: (bool selected) {
                                if (selected) {
                                  widget.onThemeChanged(ThemeMode.light);
                                }
                              },
                            ),
                            ChoiceChip(
                              label: const Text('Dark'),
                              selected: widget.themeMode == ThemeMode.dark,
                              onSelected: (bool selected) {
                                if (selected) {
                                  widget.onThemeChanged(ThemeMode.dark);
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
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
                          physics: NeverScrollableScrollPhysics(),
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

  void _breakDownSentence() async {
    _pauseAudio(); // Pause the story
    _showLoadingDialog(); // Show loading indicator
    final breakdown = await _getSentenceBreakdown(
        _currentSentence); // Get breakdown from Gemini
    Navigator.of(context).pop(); // Close loading indicator
    _showBreakdownDialog(breakdown); // Show breakdown in a dialog
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Row(
            children: const [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text("Loading explanation..."),
            ],
          ),
        );
      },
    );
  }

  void _showBreakdownDialog(String breakdown) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Sentence Breakdown'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SelectableText(_removeMarkdownSyntax(breakdown)),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
                _playCurrentSentenceFromBeginning(); // Play the sentence from the beginning
              },
            ),
          ],
        );
      },
    );
  }

  void _playCurrentSentenceFromBeginning() {
    setState(() {
      _narrationSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    });
    _audioPlayer.stop().then((_) {
      _narrateCurrentSentence(_narrationSessionId);
    });
  }

  Future<String> _getSentenceBreakdown(String sentence) async {
    // Use Gemini API to get the breakdown of the sentence
    final model =
        FirebaseVertexAI.instance.generativeModel(model: 'gemini-1.5-pro-001');
    final prompt =
        'Break down the following sentence in ${_nativeLanguage}, providing romanizations only once for words in languages that do not use the Roman alphabet, and explaining the meaning and grammatical function of each word while avoiding explanations of obvious punctuation like commas: "$sentence"';
    final response = await model.generateContent([Content.text(prompt)]);
    return response.text ?? 'No breakdown available';
  }

  String _removeMarkdownSyntax(String text) {
    return text.replaceAll('*', '').replaceAll('#', '');
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
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: SlideTransition(
                position: _slideAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                        Text(
                          '${_sentenceIndex + 1} / ${_sentences.length}',
                          style: const TextStyle(
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SelectableText(
                          _currentSentence,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                          ),
                        ),
                        const SizedBox(height: 20),
                        SelectableText(
                          _currentSentenceTranslation,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(
                            height:
                                20), // Space between translation and swipe up
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
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.help_outline),
              onPressed: _breakDownSentence,
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
      ),
    );
  }
}
