# Frontend — DreamLab (Flutter, iOS)

Клиент mock-AI-генератора. Работает против локального бэкенда из `../backend`
(FastAPI). Полное описание архитектуры, границы клиент/сервер и продуктовых
решений — в [README.md](../README.md) в корне репозитория.

## Run

```bash
flutter pub get
flutter run -d "iPhone 16"        # iOS Simulator
```

Адрес бэкенда по умолчанию — `http://127.0.0.1:8000` (симулятор видит
хост-машину по loopback). Поменять без пересборки: **Settings → Connection →
Server URL** → *Test connection*. Для реального устройства укажите LAN-IP
хоста (`http://192.168.x.x:8000`); в `ios/Runner/Info.plist` уже включён
`NSAllowsLocalNetworking` (иначе ATS режет plaintext HTTP).

## Test

```bash
flutter test                                  # unit-тесты
flutter analyze                               # 0 issues
flutter test integration_test/screencast_test.dart -d <simulator-id>
```

Integration-сценарий проходит по реальному UI (генерация → ошибка → *Try again* →
пейвол → покупка → Settings → History) — он же используется для записи
демо-скринкаста.

## Структура

```
lib/
  main.dart / app.dart   # bootstrap, DI-контейнер, тема, MultiBlocListener
  core/
    api/api_client.dart  # dio-обёртка: любой ответ → DTO или AppFailure
    config/app_config.dart
    errors/failures.dart  # типизированные ошибки (Network/Timeout/402/…)
    theme/app_theme.dart  # светлая тема
    widgets/app_widgets.dart
  data/
    dto/api_models.dart   # парсинг ответов + защита от битых payload
    local/history_store.dart  # sqflite-история (переживает рестарт и оффлайн)
    local/image_store.dart   # PNG-файлы: хранится имя, путь резолвится на лету
    local/prefs.dart      # userId, server URL, кэш тира подписки, кэш каталога
    repositories/repositories.dart
  di/app_container.dart
  features/
    generate/  # bloc, экран Create, виджеты опций, пейвол
    history/   # bloc, список, детализация
    settings/  # bloc, экран Settings
    subscription/ # bloc: tier с сервера + мгновенная отрисовка из кэша
  router/app_router.dart # 3 таба (go_router) + детализация поверх шелла
integration_test/
  screencast_test.dart    # сценарий демо-скринкаста
```

## Стек

`flutter_bloc`, `go_router`, `dio`, `sqflite`, `path_provider`,
`shared_preferences`, `intl`, `integration_test`. Без codegen (bloc без
`build_runner`). Версии: Flutter 3.41 / Dart 3.11.
