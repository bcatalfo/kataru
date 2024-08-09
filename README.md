# kataru

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## How to deploy google cloud functions
Run the command
```shell
gcloud functions deploy httpsflaskexample --memory=512MB --runtime=python312 --trigger-http --allow-unauthenticated --timeout=300s --cpu=1
```

## How to test API
1. Open Postman
2. Set the URL to https://httpsflaskexample-xlb2i3qzwa-uc.a.run.app/generate_story
3. In the Headers add the key Content-Type with value application/json
4. In the body put something like
```json
{
    "native_language": "English",
    "target_language": "Japanese",
    "genre": "Fantasy",
    "difficulty_level": "Beginner",
    "voice": "ja-JP-Standard-A"
}
```
5. Submit it as a POST request

## How to set up the Python virtual environment
Enter the commands
```shell
cd /Users/bcatalfo/dev/kataru/functions
rm -rf venv
python3.12 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
firebase deploy --only functions
```
Note that the last command deploys the Google Cloud Functions using the Firebase CLI- I stopped doing it this way, so I could set a memory limit
I should probably see if there is a way of setting a memory limit with the Firebase CLI