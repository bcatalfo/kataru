from firebase_admin import initialize_app
from firebase_functions import https_fn
from google.cloud import firestore, storage, texttospeech_v1 as texttospeech
import vertexai
from vertexai.generative_models import GenerativeModel
import uuid
import json
import flask

# Initialize Firebase
initialize_app()
app = flask.Flask(__name__)

def build_prompt_text(native_language, target_language, genre, difficulty_level):
    difficulty_descriptions = {
        'Absolute Beginner': 'Use extremely simple vocabulary and grammar.',
        'Beginner': 'Use very simple vocabulary and grammar.',
        'Intermediate': 'Use simple vocabulary and grammar.',
        'Advanced': 'Use typical vocabulary and grammar.',
        'Expert': 'Use sophisticated vocabulary and grammar.'
    }

    difficulty_description = difficulty_descriptions.get(difficulty_level, 'Use extremely simple vocabulary and grammar.')

    example_output = '''
    {
        "story": [
            {
                "sentence": {
                    "children": [
                        {
                            "type": "word",
                            "text": "今日",
                            "transliteration": "kyou",
                            "translation": "today"
                        },
                        {
                            "type": "word",
                            "text": "は",
                            "transliteration": "wa",
                            "translation": "(topic marker)"
                        },
                        {
                            "type": "word",
                            "text": "天気",
                            "transliteration": "tenki",
                            "translation": "weather"
                        },
                        {
                            "type": "word",
                            "text": "が",
                            "transliteration": "ga",
                            "translation": "(subject marker)"
                        },
                        {
                            "type": "word",
                            "text": "いい",
                            "transliteration": "ii",
                            "translation": "good"
                        },
                        {
                            "type": "word",
                            "text": "です",
                            "transliteration": "desu",
                            "translation": "(polite ending)"
                        },
                        {
                            "type": "punctuation",
                            "text": "。"
                        },
                        {
                            "type": "translation",
                            "text": "The weather is good today."
                        }
                    ]
                }
            },
            {
                "sentence": {
                    "children": [
                        {
                            "type": "word",
                            "text": "明日",
                            "transliteration": "ashita",
                            "translation": "tomorrow"
                        },
                        {
                            "type": "word",
                            "text": "も",
                            "transliteration": "mo",
                            "translation": "also"
                        },
                        {
                            "type": "word",
                            "text": "晴れる",
                            "transliteration": "hareru",
                            "translation": "will be sunny"
                        },
                        {
                            "type": "word",
                            "text": "でしょう",
                            "transliteration": "deshou",
                            "translation": "probably"
                        },
                        {
                            "type": "punctuation",
                            "text": "。"
                        },
                        {
                            "type": "translation",
                            "text": "It will probably be sunny tomorrow too."
                        }
                    ]
                }
            }
        ]
    }
    '''

    return (f'Write a story in {target_language}. {difficulty_description} '
            f'The story should be in the genre of {genre}. '
            f'Format the output in JSON format. Here is an example, in this case the story is in Japanese and the translation '
            f'is in English, but for you the story needs to be in {target_language} and the translation in {native_language} '
            f'{example_output}')

@app.route('/generate_story', methods=['POST'])
def generate_story():
    print("Request received")

    # Parse the request parameters
    request_json = flask.request.get_json()
    print(f"Request JSON: {json.dumps(request_json, indent=2)}")

    native_language = request_json.get('native_language')
    target_language = request_json.get('target_language')
    genre = request_json.get('genre')
    difficulty_level = request_json.get('difficulty_level')
    voice = request_json.get('voice')

    print(f"Parsed parameters: native_language={native_language}, target_language={target_language}, genre={genre}, difficulty_level={difficulty_level}, voice={voice}")

    # Build the prompt text
    prompt_text = build_prompt_text(native_language, target_language, genre, difficulty_level)
    print(f"Generated prompt text: {prompt_text}")

    # Initialize Vertex AI
    vertexai.init(project="kataru-b341b", location="us-central1")
    model = GenerativeModel(model_name="gemini-pro")

    # Generate story using Vertex AI
    response = model.generate_content(prompt_text)
    print(f"Raw response from Vertex AI: {response.text}")

    if not response.text:
        return flask.jsonify({'error': 'Empty response from Vertex AI'}), 500

    # Clean up the response by removing the ```json and ``` markers
    cleaned_response_text = response.text.strip("```json").strip("```").strip()

    try:
        story = json.loads(cleaned_response_text)
    except json.JSONDecodeError as e:
        print(f"JSONDecodeError: {e}")
        return flask.jsonify({'error': 'Failed to decode JSON response'}), 500

    print(f"Decoded story: {json.dumps(story, indent=2)}")

    # Initialize Firestore client
    db = firestore.Client()

    # Initialize Text-to-Speech client
    tts_client = texttospeech.TextToSpeechClient()

    # Initialize Cloud Storage client
    storage_client = storage.Client()
    bucket_name = 'kataru-b341b.appspot.com'
    bucket = storage_client.bucket(bucket_name)

    # Process each sentence and convert to speech
    for sentence in story["story"]:
        print(f"Processing sentence: {json.dumps(sentence, indent=2)}")
        text = ''.join([child["text"] for child in sentence.get("children", []) if child["type"] != "punctuation"])
        input_text = texttospeech.SynthesisInput(text=text)
        voice_params = texttospeech.VoiceSelectionParams(language_code=target_language, name=voice)
        audio_config = texttospeech.AudioConfig(audio_encoding=texttospeech.AudioEncoding.MP3)

        tts_response = tts_client.synthesize_speech(input=input_text, voice=voice_params, audio_config=audio_config)
        print(f"Generated audio for text: {text}")

        # Save audio to Cloud Storage
        blob_name = f"{uuid.uuid4()}.mp3"
        blob = bucket.blob(blob_name)
        blob.upload_from_string(tts_response.audio_content, content_type='audio/mpeg')
        print(f"Uploaded audio to Cloud Storage: gs://{bucket_name}/{blob_name}")

        # Add audio link to sentence
        sentence['audio_link'] = f"gs://{bucket_name}/{blob_name}"

    # Attach metadata
    metadata = {
        'native_language': native_language,
        'target_language': target_language,
        'genre': genre,
        'difficulty_level': difficulty_level,
        'voice': voice
    }
    story['metadata'] = metadata

    # Save story to Firestore
    doc_ref = db.collection('stories').document()
    doc_ref.set(story)
    print(f"Saved story to Firestore: {doc_ref.path}")

    # Return the document location
    return flask.jsonify({'document_path': doc_ref.path})

@https_fn.on_request()
def httpsflaskexample(req: https_fn.Request) -> https_fn.Response:
    with app.request_context(req.environ):
        return app.full_dispatch_request()