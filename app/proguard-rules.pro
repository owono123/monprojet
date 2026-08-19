# Le pont JavaScript est appelé par réflexion depuis la WebView : ne pas l'obfusquer.
-keepclassmembers class com.monprojet.ia.bridge.** {
    @android.webkit.JavascriptInterface <methods>;
}
