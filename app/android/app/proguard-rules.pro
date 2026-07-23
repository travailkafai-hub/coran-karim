# ONNX Runtime : son code natif (libonnxruntime4j_jni.so) appelle FindClass avec
# les noms de classe ORIGINAUX (ex. "ai/onnxruntime/TensorInfo") depuis
# convertToTensorInfo/convertOrtValueToONNXValue. Si R8 renomme ou supprime ces
# classes, FindClass retourne null -> GetMethodID(null) -> "JNI DETECTED ERROR
# IN APPLICATION: java_class == null" -> SIGABRT, process tue.
# Crash reproduit sur device le 2026-07-23 (stack : convertToTensorInfo+628 ->
# GetMethodID -> abort, sur ai.onnxruntime.OrtSession.run). On garde donc TOUT
# le package intact (noms + membres) pour l'acces JNI par nom.
-keep class ai.onnxruntime.** { *; }
-keepnames class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**
