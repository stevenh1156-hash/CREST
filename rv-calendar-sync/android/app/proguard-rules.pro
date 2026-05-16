# Retrofit / OkHttp
-keepattributes Signature, InnerClasses, EnclosingMethod
-keepattributes RuntimeVisibleAnnotations, RuntimeVisibleParameterAnnotations
-keepattributes AnnotationDefault
-keep,allowobfuscation,allowshrinking interface retrofit2.Call
-keep,allowobfuscation,allowshrinking class retrofit2.Response

# kotlinx.serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keep,includedescriptorclasses class com.rvsync.android.**$$serializer { *; }
-keepclassmembers class com.rvsync.android.** {
    *** Companion;
}
-keepclasseswithmembers class com.rvsync.android.** {
    kotlinx.serialization.KSerializer serializer(...);
}
