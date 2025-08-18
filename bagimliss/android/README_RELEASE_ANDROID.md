Android Release Build Guide

1) Create a keystore (once)
   keytool -genkeypair -v -keystore keystore/release.keystore -alias upload -keyalg RSA -keysize 2048 -validity 10000

2) Create android/key.properties from template
   Copy android/key.properties.example -> android/key.properties and fill passwords.

3) Update applicationId if needed (unique package name)
   File: android/app/build.gradle.kts
   applicationId = "com.bagimliss.app"  # change to your final id before store release

4) Build App Bundle (for Play Store)
   flutter build appbundle --release

5) Test locally / Internal testing
   - Upload AAB to Play Console -> Internal testing track

Notes
- Keep the keystore out of version control.
- For automated CI, pass signing info via environment variables or CI secrets.
