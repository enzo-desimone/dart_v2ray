# Android Guide

This guide covers Android-specific setup for `dart_v2ray`.

<application
android:name=".MyApplication"
android:label="@string/app_name"
android:icon="@mipmap/ic_launcher"
android:extractNativeLibs="true">
. . .
</application>

Set minSdkVersion to >= 23. Ensure your minSdkVersion and targetSdkVersion match plugin and Play Store requirements.

Google Play note: apps that modify network traffic may require a privacy policy and additional disclosure in the store listing.

Add the attribute android:extractNativeLibs="true" to the