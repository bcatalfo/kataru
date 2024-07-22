import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_vertexai/firebase_vertexai.dart';

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
  String _story = 'Swipe down to generate a new story.';
  String _nativeLanguage = 'English';
  String _targetLanguage = 'Japanese';

  final List<String> _languages = [
    'English',
    'Japanese',
    'Spanish',
    'French',
    'German',
    'Italian',
    'Mandarin (Simplified)',
    'Mandarin (Traditional)',
    'Korean',
    'Russian',
    'Portuguese',
    'Arabic',
    'Hindi',
    'Bengali',
    'Punjabi',
    'Javanese',
    'Vietnamese',
    'Turkish',
    'Thai',
    'Polish',
    'Dutch',
    'Greek',
    'Czech',
    'Swedish',
    'Hungarian',
    'Finnish',
    'Danish',
    'Norwegian',
    'Hebrew',
    'Malay',
    'Indonesian',
    'Filipino',
    'Swahili',
    'Zulu',
    'Hausa',
    'Yoruba',
    'Amharic',
    'Nepali',
    'Sinhala',
    'Telugu',
    'Tamil',
    'Marathi',
    'Gujarati',
    'Kannada',
    'Malayalam',
    'Urdu',
    'Persian',
    'Pashto',
    'Burmese',
    'Khmer',
    'Lao',
    'Mongolian',
    'Uzbek',
    'Kazakh',
    'Tajik',
    'Turkmen',
    'Kurdish',
    'Serbian',
    'Croatian',
    'Bosnian',
    'Slovak',
    'Slovenian',
    'Bulgarian',
    'Romanian',
    'Ukrainian',
    'Belarusian',
    'Lithuanian',
    'Latvian',
    'Estonian',
    'Icelandic',
    'Maltese',
    'Luxembourgish',
    'Albanian',
    'Georgian',
    'Armenian',
    'Azerbaijani'
  ];

  Future<void> _generateNewStory() async {
    final model =
        FirebaseVertexAI.instance.generativeModel(model: 'gemini-1.5-flash');
    final prompt = [
      Content.text(
          'Write a simple story in $_targetLanguage and translate it into $_nativeLanguage.')
    ];
    final response = await model.generateContent(prompt);

    setState(() {
      _story = response.text ?? 'No story generated';
    });
  }

  @override
  void initState() {
    super.initState();
    _generateNewStory();
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
              DropdownButton<String>(
                value: _nativeLanguage,
                onChanged: (String? newValue) {
                  setState(() {
                    _nativeLanguage = newValue!;
                  });
                },
                items: _languages.map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
              ),
              DropdownButton<String>(
                value: _targetLanguage,
                onChanged: (String? newValue) {
                  setState(() {
                    _targetLanguage = newValue!;
                  });
                },
                items: _languages.map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
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
                _generateNewStory();
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
      body: RefreshIndicator(
        onRefresh: _generateNewStory,
        child: Center(
          child: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  _story,
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
