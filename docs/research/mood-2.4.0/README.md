# mood.camera 2.4.0 (com.alexfox.camx), разбор

Приложение: `CFBundleDisplayName` = **mood**, внутреннее имя бандла `CamX`, версия 2.4.0 (build 560), минимум iOS 16.0, только iPhone (arm64, портрет).

Это вторая ссылка для разбора, после Lampa 2.1.5 (см. `docs/research/lampa-2.1.5`). Здесь всё, что удалось подтвердить статически: REA, Ghidra 12.1.4 по нативному Mach-O, `hbc-decompiler` по Hermes-байткоду JS, строки и метаданные бандла.

## Как получены данные

| Источник | Что дал | Надёжность |
|---|---|---|
| `Info.plist`, `PlugIns/`, `Extensions/`, `Metadata.appintents` | Идентификаторы, расширения (виджет, Locked-расширение), App Intents | Высокая, прямо из файлов |
| `CamX` (Mach-O arm64, 12.9 МБ) через REA + Ghidra | Классы ObjC/Swift, импорт Core Image / AVFoundation / Photos / StoreKit / Vision, селекторы, обзор сегментов (67) и процедур (58 659) | Высокая для имён; тела функций не декомпилировались, см. `NATIVE.md` |
| `main.jsbundle` (Hermes HBC, 3.9 МБ) через `hbc-decompiler` | Схема пресета, таблицы скорости плёнки, контраста, рамок, список регуляторов | Средняя: декомпилятор низкоуровневый, числа сверены с литералами в тексте |
| `LensPresets.bundle/*.json` | Параметры 7 объективов (боке, блики, хром. аберрация) | Высокая, это JSON |
| `assets/` (LUT `.lutenc`, шейдеры `.mtlenc`, зерно `.grainenc`) | Факт наличия, форматы закрыты (зашифрованы) | Содержимое не разбиралось и не извлекалось |

Что не делалось: содержимое зашифрованных LUT и шейдеров не расшифровывалось, изображения (фильтры, иконки, пэттерны, онбординг) не копировались. Для нашей версии используются собственные реализации тех же эффектов, а не их ассеты.

## Устройство приложения (по бандлу)

Это React Native (Hermes) приложение с нативным ядром камеры на Swift и Objective-C:

- **JS-слой** (Hermes): экраны, настройки, пресеты, меню, онбординг, покупки. Навигация через react-navigation, жесты через react-native-gesture-handler, анимации через Reanimated (Worklets), состояние через Nitro-модули. Отчёты об ошибках: Sentry; аналитика, подписки и покупки видны по SDK-именам в бандле.
- **Нативный слой**: `RCTCameraViewManager` / `CameraView` (вид камеры, Swift), `CameraController` и `CaptureController` (сессия, фото и видео), `MetalViewFinderController` и `PreviewMetalView` (видоискатель на Metal), `FilterController` и `ImagePreviewFilterController` (цепочка Core Image фильтров), `BokehPipeline` и `LiveDepthAccumulator` (глубина и боке), `VolumeButtonHandler` (кнопка громкости как затвор), `CaptureTimer`, `LogOverlay`.
- **Расширения**: `LockedWidget` (виджет, `com.apple.widgetkit-extension`) и `LockedExtension` (отдельное расширение с тем же префиксом).
- **App Intents**: `Metadata.appintents` с `extract.actionsdata`. Именно это даёт вход через кнопку Action (в онбординге есть экран «Why I built mood.camera when you press the action button»).

Подробнее по нативной части — в `NATIVE.md`. Полный список функций — в `FEATURES.md`. Схема данных (пресет, скорость, контраст, рамки, объективы) — в `DATA_MODEL.md`.

## Главные принципы

1. **Образ = три оси, а не один пресет.** Пресет в mood собирается из:
   - *Emulation* (`filmStock`): 24 плёнки с цветом и тоном, каждая со своей подписью;
   - *Film speed* (`filmSpeed`): DIGI, 100, 200, 400, 800, 1600, 3200. Это зерно, размер зерна, резкость и хроматическая аберрация;
   - *Contrast* (`contrast`): 10 кривых с параметрами тона (`shadowsAmount`, `midpointAmount`, `highlightsAmount`, `dynamicRange`), насыщенности, выцветания (`fadeAmount`, `muteAmount`) и `filmStrength`.
   У нас сейчас один слой: LUT-пресет плюс зерно и halation. Это главный структурный разрыв.
2. **Всё, что выбрано, можно подправить вручную.** Экран регуляторов построен на свайп-контролах (`SwipeControl`, `SwipeControl2`, `PresetSwipeControl`): Brightness, Contrast, Dynamic range, Saturation, Grain size, H/M/S (света, средние, тени), плюс Emulation.
3. **Рамка как часть образа.** Рамка (border) — градиент от `topColor` к `bottomColor` с цветом подписи `fontColor` и опциональным пэттерном. Для каждой плёнки есть рамка по умолчанию (`defaultForFilmStocks`), режим Auto меняет её по сцене (иконки `borderAuto`, `borderAutoDark`, `borderAutoLight`, `borderAutoFocusVivid`).
4. **Объектив как отдельный слой.** Семь объективов из `LensPresets.bundle` задают форму боке (лепестки, кошачий глаз, овальность, кольцо), виньетку, кривизну поля, блики и хроматическую аберрацию. Работают через карту глубины, там где устройство её отдаёт.
5. **Фото и видео с одной схемой.** Тот же набор параметров применяется к обоим; режимы `virtualDeviceSwitches` и `lensPowers` выбирают камеру по зуму.
6. **Ввод с железа.** Кнопка громкости как затвор (`disableSystemVolumeHandler`), таймер, Action button (App Intent), Camera Control (`captureControlTouched`, `captureControlDidChange`), виджет.

## Что у нас уже есть, что нет

Сверено по `68e9c2e` ветки `claude/camera-state-machine` (см. `FEATURES.md`, колонка «Статус»).
