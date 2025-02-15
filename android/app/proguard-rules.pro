# Prevent R8 from stripping TensorFlow Lite GPU classes
-dontwarn org.tensorflow.lite.**
-keep class org.tensorflow.lite.gpu.GpuDelegateFactory$Options { *; }
-keep class org.tensorflow.lite.gpu.GpuDelegate { *; }
