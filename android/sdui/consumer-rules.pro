# Consumer ProGuard/R8 rules shipped to apps that depend on `:sdui`.
#
# kotlinx.serialization relies on generated `$serializer` companions being kept.
# The AGP + kotlinx-serialization tooling adds most rules automatically, but we
# keep the models' serializers explicitly so aggressive host-app shrinking never
# strips the SDUI contract types.
-keep,includedescriptorclasses class dev.sdui.**$$serializer { *; }
-keepclassmembers class dev.sdui.** {
    *** Companion;
}
-keepclasseswithmembers class dev.sdui.** {
    kotlinx.serialization.KSerializer serializer(...);
}
