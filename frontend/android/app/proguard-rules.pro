# google_mlkit_text_recognition ships optional script-specific recognizers (Chinese,
# Devanagari, Japanese, Korean) as separate dependencies. We only use the default
# (Latin) recognizer, so those classes are absent at compile time — tell R8 not to
# fail the build over references to them.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
