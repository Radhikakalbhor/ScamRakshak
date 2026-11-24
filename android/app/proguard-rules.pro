# QR scanner (mobile_scanner 7.0.1 -> ML Kit barcode-scanning 17.3.0).
# ML Kit creates its component registrars (BarcodeRegistrar, VisionCommonRegistrar,
# CommonComponentRegistrar) by reflection from AndroidManifest meta-data, using the no-arg
# constructor. R8 (full mode, release builds) kept the class names but removed those constructors,
# so no barcode component was registered and BarcodeScanning.getClient() threw
# "Attempt to invoke virtual method ... on a null object reference" for both the live camera
# and analyzeImage. mobile_scanner's consumer rule (-keep class com.google.mlkit.* { *; })
# only covers the top-level package, not com.google.mlkit.**.
# Keep ML Kit's reflectively created registrars and Firebase components
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
-keep class com.google.firebase.auth.** { *; }
-keep class com.google.android.gms.auth.api.** { *; }
