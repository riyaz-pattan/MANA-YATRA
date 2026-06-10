# Razorpay ProGuard rules — required for Android release builds
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keepattributes JavascriptInterface
-keepattributes *Annotation*
-dontwarn com.razorpay.**
-keep class com.razorpay.** {*;}
-optimizations !method/inlining/*
-keepclasseswithmembers class * {
  public void onPayment*(...);
}

# Keep SMS User Consent classes
-keep class com.google.android.gms.auth.api.phone.** { *; }
