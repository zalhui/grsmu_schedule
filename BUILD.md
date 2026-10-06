# Сборка и запуск приложения

Приложение написано на Flutter. Android-проект расположен в `flutter_app`.

## Перед началом

Установите:

- Flutter SDK и добавьте каталог `flutter/bin` в `PATH`;
- Android Studio с плагинами **Flutter** и **Dart**;
- Android SDK и Android SDK Platform-Tools через **Android Studio → Settings → Languages & Frameworks → Android SDK**.

В Android Studio откройте **Tools → SDK Manager** и установите рекомендованную платформу Android и Android SDK Build-Tools. Затем откройте терминал и проверьте настройку:

```bash
flutter doctor -v
```

Исправьте пункты Flutter и Android toolchain, которые команда отметит как не настроенные. Для запуска на телефоне включите в его настройках **Для разработчиков → Отладка по USB** и подтвердите запрос доверия компьютеру. Либо создайте эмулятор через **Tools → Device Manager → Create Device** и запустите его.

## Запуск из терминала

Из корня репозитория выполните:

```bash
cd flutter_app
flutter pub get
flutter run
```

Если подключено несколько устройств, сначала посмотрите их идентификаторы и выберите нужное:

```bash
flutter devices
flutter run -d <device-id>
```

Для запуска в режиме отладки через USB подключите телефон до команды `flutter run`.

## Запуск через Android Studio

1. Выберите **File → Open** и откройте каталог `flutter_app` (не весь корень репозитория).
2. Если Android Studio предложит настроить Flutter SDK, укажите путь к каталогу Flutter SDK. Убедитесь, что плагины **Flutter** и **Dart** включены.
3. Дождитесь завершения индексации и загрузки зависимостей. Если зависимости не загрузились автоматически, откройте встроенный Terminal и выполните:

   ```bash
   flutter pub get
   ```

4. Запустите эмулятор в **Tools → Device Manager** или подключите Android-телефон с включённой USB-отладкой.
5. В списке устройств на панели инструментов выберите эмулятор или телефон.
6. Откройте `lib/main.dart` и нажмите зелёную кнопку **Run** рядом с `main()` либо создайте конфигурацию **Flutter** с Dart entrypoint `lib/main.dart` и нажмите **Run**.

При первом запуске Gradle может загружать Android-зависимости; дождитесь завершения сборки. Для последующих запусков выберите устройство и снова нажмите **Run**.

## Сборка APK

### Debug APK для установки и проверки

```bash
cd flutter_app
flutter build apk --debug
```

Файл появится здесь:

```text
flutter_app/build/app/outputs/flutter-apk/app-debug.apk
```

### Release APK

```bash
cd flutter_app
flutter build apk --release
```

Результат:

```text
flutter_app/build/app/outputs/flutter-apk/app-release.apk
```

В текущей конфигурации Release APK подписывается debug-ключом, поэтому он подходит для локальной установки и проверки, но не для публикации в Google Play. Для публикации настройте собственную release-подпись.

Чтобы установить собранный APK на подключённое устройство:

```bash
flutter install
```

## Частые проблемы

- **`flutter: command not found`** — добавьте `flutter/bin` в `PATH`, перезапустите терминал и проверьте `flutter doctor -v`.
- **Устройство не отображается** — выполните `flutter devices`; проверьте USB-отладку, кабель/режим передачи данных и подтверждение RSA на телефоне. Для эмулятора запустите его через Device Manager.
- **Не найдена Java или не подходит версия** — используйте JDK, поставляемый с Android Studio, и проверьте Android toolchain через `flutter doctor -v`.
- **Сборка Android сообщает об отсутствующем SDK или NDK** — установите компоненты через **Android Studio → SDK Manager → SDK Tools**. Версии Android SDK/NDK проекта задаются Flutter и Gradle конфигурацией.
- **Не принята лицензия NDK** — в терминале выполните `flutter doctor --android-licenses` и подтвердите соглашения, затем проверьте результат командой `flutter doctor -v`. Если команда недоступна или сообщает об отсутствующих command-line tools, откройте **Android Studio → SDK Manager → SDK Tools**, включите **Android SDK Command-line Tools (latest)**, нажмите **Apply**, а затем повторите команду лицензий.
- **Зависимости не загружаются** — проверьте интернет-соединение и повторите `flutter pub get` из каталога `flutter_app`.
