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
    // Step 1: Generate an idea for the story
    final idea = await _generateStoryIdea();

    // Step 2: Turn the idea into detailed chapter outlines
    final chapterOutlines = await _createChapters(idea);

    // Step 3: Fill out each chapter
    final difficultyDescription = _getDifficultyDescription();
    final chapters = await _generateChapters(
        chapterOutlines, difficultyDescription, idea['title'], idea['outline']);

    // Step 4: Check for coherence and fix errors
    final improvedStory = await _checkAndImproveStory(chapters.join('\n\n'),
        idea['title'], idea['outline'], difficultyDescription);

    // Store the preloaded story without translation
    _preloadedStory = {
      'storyPart': improvedStory,
      'translationPart': '', // No translation part for now
    };

    // Preload audio files with a unique identifier
    final uniqueId = DateTime.now().millisecondsSinceEpoch.toString();
    await _preloadAudioFiles(improvedStory, uniqueId);
  }

  Future<Map<String, dynamic>> _generateStoryIdea() async {
    if (_selectedGenres.isEmpty) {
      _selectedGenres = genres.toList();
    }

    final targetLanguage = _languages
        .firstWhere((lang) => lang['code'] == _targetLanguage)['name']!;

    final shuffledGenres = _selectedGenres.toList()..shuffle();
    final randomGenre = shuffledGenres.first;

    final difficultyDescription = _getDifficultyDescription();

    String characterRequirement = '';
    if (_targetLanguage == 'zh-TW') {
      characterRequirement =
          'Use Traditional Chinese characters and the Chinese used in Taiwan. Do not use Simplified Chinese characters.';
    }

    final promptText =
        'Generate a unique story idea in $targetLanguage. $difficultyDescription '
        'Include a captivating title and an outline for each part of the five-act structure. '
        'Format the response as follows:\n'
        'Title: [insert title]\n'
        'Exposition: [insert exposition here]\n'
        'Inciting Incident: [insert inciting incident here]\n'
        'Rising Action: [insert rising action here]\n'
        'Climax: [insert climax here]\n'
        'Falling Action: [insert falling action here]\n'
        'Denouement: [insert denouement here]\n'
        'Do not include romanizations or translations of the content.\n'
        '$characterRequirement'
        'The story should be in the genre of $randomGenre.';

    final model =
        FirebaseVertexAI.instance.generativeModel(model: 'gemini-1.5-pro-001');
    final prompt = [Content.text(promptText)];

    debugPrint('Prompt for Story Idea: $promptText');
    final response = await model.generateContent(prompt);

    debugPrint('Generated Idea: ${response.text}');

    final lines = response.text?.split('\n') ?? [];
    String title = '';
    String exposition = '';
    String incitingIncident = '';
    String risingAction = '';
    String climax = '';
    String fallingAction = '';
    String denouement = '';

    for (int i = 0; i < lines.length; i++) {
      final line = _removeMarkdownSyntax(lines[i].trim());
      debugPrint('Processing line: $line'); // Debug statement

      if (line.startsWith('Title:')) {
        title = line.replaceFirst('Title: ', '').trim();
      } else if (line.startsWith('Exposition:')) {
        exposition = _extractTextBlock(lines, i);
      } else if (line.startsWith('Inciting Incident:')) {
        incitingIncident = _extractTextBlock(lines, i);
      } else if (line.startsWith('Rising Action:')) {
        risingAction = _extractTextBlock(lines, i);
      } else if (line.startsWith('Climax:')) {
        climax = _extractTextBlock(lines, i);
      } else if (line.startsWith('Falling Action:')) {
        fallingAction = _extractTextBlock(lines, i);
      } else if (line.startsWith('Denouement:')) {
        denouement = _extractTextBlock(lines, i);
      }
    }

    debugPrint('Title: $title');
    debugPrint('Exposition: $exposition');
    debugPrint('Inciting Incident: $incitingIncident');
    debugPrint('Rising Action: $risingAction');
    debugPrint('Climax: $climax');
    debugPrint('Falling Action: $fallingAction');
    debugPrint('Denouement: $denouement');

    return {
      'title': title,
      'outline': [
        'Exposition: $exposition',
        'Inciting Incident: $incitingIncident',
        'Rising Action: $risingAction',
        'Climax: $climax',
        'Falling Action: $fallingAction',
        'Denouement: $denouement',
      ],
    };
  }

  String _extractTextBlock(List<String> lines, int startIndex) {
    StringBuffer buffer = StringBuffer();
    for (int i = startIndex + 1; i < lines.length; i++) {
      final line = _removeMarkdownSyntax(lines[i].trim());
      if (line.isEmpty) break;
      buffer.writeln(line);
      debugPrint('Extracting text block: $line'); // Debug statement
    }
    return buffer.toString().trim();
  }

  String _removeMarkdownSyntax(String text) {
    return text.replaceAll('*', '').replaceAll('#', '');
  }

  Future<List<String>> _createChapters(Map<String, dynamic> idea) async {
    final promptText =
        'Given the following story idea, create detailed chapter outlines. '
        'Each chapter outline should specify the key events and developments, and the number of chapters should be between 10 and 15. Format the response as follows:\n'
        'Chapter 1: [outline of chapter 1]\n'
        'Chapter 2: [outline of chapter 2]\n'
        '...\n\n'
        'Story Idea:\n'
        'Title: ${idea['title']}\n'
        'Exposition: ${idea['outline'][0]}\n'
        'Inciting Incident: ${idea['outline'][1]}\n'
        'Rising Action: ${idea['outline'][2]}\n'
        'Climax: ${idea['outline'][3]}\n'
        'Falling Action: ${idea['outline'][4]}\n'
        'Denouement: ${idea['outline'][5]}';

    final model =
        FirebaseVertexAI.instance.generativeModel(model: 'gemini-1.5-pro-001');
    final prompt = [Content.text(promptText)];

    debugPrint('Prompt for Chapter Outlines: $promptText');
    final response = await model.generateContent(prompt);

    debugPrint('Generated Chapters: ${response.text}');
    final lines = response.text?.split('\n') ?? [];
    final chapters = lines
        .where((line) => line.startsWith('Chapter '))
        .map((line) => line.trim())
        .toList();

    return chapters;
  }

  String _getDifficultyDescription() {
    switch (_difficultyLevel) {
      case 'Absolute Beginner':
        return 'Use extremely simple vocabulary, grammar, and sentence complexity.';
      case 'Beginner':
        return 'Use very simple vocabulary, grammar, and sentence complexity.';
      case 'Intermediate':
        return 'Use simple vocabulary, grammar, and sentence complexity.';
      case 'Advanced':
        return 'Use typical vocabulary, grammar, and sentence complexity.';
      case 'Expert':
        return 'Use sophisticated vocabulary, grammar, and sentence complexity.';
      default:
        return 'Use extremely simple vocabulary, grammar, and sentence complexity.';
    }
  }

  Future<List<String>> _generateChapters(List<String> chapterOutlines,
      String difficultyDescription, String title, List<String> outline) async {
    final model =
        FirebaseVertexAI.instance.generativeModel(model: 'gemini-1.5-pro-001');
    List<String> chapters = [];
    String previousChapters = '';

    for (int i = 0; i < chapterOutlines.length; i++) {
      final chapterOutline = chapterOutlines[i];
      final promptText =
          'Based on the following story outline, write a detailed chapter. '
          'Include multiple characters, dialogue, and follow the five-act structure.\n'
          'Title: $title\n'
          'Story Outline: ${outline.join('\n')}\n'
          'Previous Chapters: $previousChapters\n'
          'Current Chapter Outline: $chapterOutline\n'
          '$difficultyDescription';

      final prompt = [Content.text(promptText)];

      debugPrint('Prompt for Chapter: $promptText');
      final response = await model.generateContent(prompt);

      debugPrint('Generated Chapter: ${response.text}');
      final chapter = response.text ?? '';
      chapters.add(chapter);
      previousChapters += chapter + '\n';
    }

    return chapters;
  }

  Future<String> _checkAndImproveStory(String fullStory, String title,
      List<String> outline, String difficultyDescription) async {
    final promptText =
        'Review the following story for coherence and make any necessary improvements:\n'
        'Title: $title\n'
        'Story Outline: ${outline.join('\n')}\n'
        'Full Story:\n$fullStory\n'
        '$difficultyDescription';

    final model =
        FirebaseVertexAI.instance.generativeModel(model: 'gemini-1.5-pro-001');
    final prompt = [Content.text(promptText)];

    debugPrint('Prompt for Checking and Improving Story: $promptText');
    final response = await model.generateContent(prompt);

    debugPrint('Improved Story: ${response.text}');
    return response.text ?? fullStory;
  }

  Future<Map<String, String>> _translateStory(
      List<String> improvedStory, String title, List<String> outline) async {
    final nativeLanguage = _languages
        .firstWhere((lang) => lang['code'] == _nativeLanguage)['name']!;

    List<String> translatedChapters = [];
    String previousChapters = '';

    final model =
        FirebaseVertexAI.instance.generativeModel(model: 'gemini-1.5-pro-001');

    for (final chapter in improvedStory) {
      final promptText =
          'Translate the following chapter into $nativeLanguage, ensuring context and coherence with the rest of the story:\n\n'
          'Story Title: $title\n\n'
          'Story Outline: ${outline.join('\n')}\n\n'
          'Previous Chapters:\n$previousChapters\n\n'
          'Chapter to Translate: $chapter';

      final prompt = [Content.text(promptText)];

      debugPrint('Prompt for Translating Chapter: $promptText');
      final response = await model.generateContent(prompt);

      debugPrint('Translated Chapter: ${response.text}');
      translatedChapters.add(response.text ?? '');
      previousChapters += chapter + '\n\n';
    }

    return {
      'story': improvedStory.join('\n\n'),
      'translation': translatedChapters.join('\n\n'),
    };
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
