# PDF Nova release (R8) rules.

# google_mlkit_text_recognition references every script's options class.
# PDF Nova ships only Latin (built in) and Devanagari; the others are
# intentionally absent.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
