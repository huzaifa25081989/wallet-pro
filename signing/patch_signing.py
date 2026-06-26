#!/usr/bin/env python3
"""Patch the Flutter-generated android/app/build.gradle to sign release
builds with the Play upload key declared in android/key.properties."""
import re

F = 'android/app/build.gradle'
s = open(F).read()

if 'keystoreProperties' not in s:
    load = (
        'def keystoreProperties = new Properties()\n'
        'def keystorePropertiesFile = rootProject.file("key.properties")\n'
        'if (keystorePropertiesFile.exists()) { '
        'keystoreProperties.load(new FileInputStream(keystorePropertiesFile)) }\n\n'
    )
    s = re.sub(r'android\s*\{', load + 'android {', s, count=1)

    sign = (
        '\n    signingConfigs {\n'
        '        release {\n'
        "            keyAlias keystoreProperties['keyAlias']\n"
        "            keyPassword keystoreProperties['keyPassword']\n"
        "            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null\n"
        "            storePassword keystoreProperties['storePassword']\n"
        '        }\n'
        '    }\n'
    )
    s = s.replace('android {', 'android {\n' + sign, 1)

s = re.sub(r'signingConfig\s*=?\s*signingConfigs\.debug',
           'signingConfig signingConfigs.release', s)

open(F, 'w').write(s)
print('signing config patched into build.gradle')
