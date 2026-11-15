#!/usr/bin/env python3
"""Подключает подпись релизной сборки. Запускать из папки shell.

Нужны переменные окружения:
  KEYSTORE_FILE      путь к файлу ключа (.jks), уже расшифрованному
  KEYSTORE_PASSWORD  пароль от ключа (он же пароль хранилища)
Алиас ключа зашит: zadacho.
"""
import os
import re
import sys
from pathlib import Path


def die(msg):
    print('::error::' + msg)
    sys.exit(1)


ks = os.environ.get('KEYSTORE_FILE', '')
pw = os.environ.get('KEYSTORE_PASSWORD', '')
if not ks or not Path(ks).is_file():
    die('Файл ключа не найден. Проверьте секрет KEYSTORE_BASE64 в настройках репозитория.')
if not pw:
    die('Не задан секрет KEYSTORE_PASSWORD в настройках репозитория.')

android = Path('android')
if not android.is_dir():
    die('Папка android не найдена: скрипт нужно запускать из папки shell')

(android / 'key.properties').write_text(
    'storePassword=%s\nkeyPassword=%s\nkeyAlias=zadacho\nstoreFile=%s\n' % (pw, pw, Path(ks).resolve()),
    encoding='utf-8',
)

HEAD_GROOVY = '''def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.withInputStream { keystoreProperties.load(it) }
}

'''
SIGN_GROOVY = '''    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile file(keystoreProperties['storeFile'])
            storePassword keystoreProperties['storePassword']
        }
    }

'''
HEAD_KTS = '''import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

'''
SIGN_KTS = '''    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

'''

done = False
for name, head, sign, rel in (
    ('build.gradle', HEAD_GROOVY, SIGN_GROOVY, 'signingConfig signingConfigs.release'),
    ('build.gradle.kts', HEAD_KTS, SIGN_KTS, 'signingConfig = signingConfigs.getByName("release")'),
):
    gp = android / 'app' / name
    if not gp.exists():
        continue
    t = gp.read_text(encoding='utf-8')
    if 'key.properties' in t:
        done = True
        continue
    t, n1 = re.subn(r'^android\s*\{', lambda m: head + 'android {', t, count=1, flags=re.M)
    t, n2 = re.subn(r'^(\s*)buildTypes\s*\{', lambda m: sign + m.group(0), t, count=1, flags=re.M)
    t, n3 = re.subn(r'signingConfig\s*=?\s*signingConfigs[.\w]*(?:\.debug|\(\s*"debug"\s*\))', rel, t)
    if not (n1 and n2 and n3):
        die('Не удалось подключить подпись в %s (блоки: android=%d, buildTypes=%d, release=%d)' % (name, n1, n2, n3))
    gp.write_text(t, encoding='utf-8')
    done = True

if not done:
    die('Не найден android/app/build.gradle для подключения подписи')
print('Подпись подключена: сборка будет подписана ключом zadacho')
