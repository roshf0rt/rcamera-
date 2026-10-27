# Анализ iOS-приложения Lampa 2.1.5 (com.lampa.photo)

Источник: `com.lampa.photo-2.1.5.ipa` (Google Drive, файл 168ORbj0jXN3urKGiHoSd8BiM-_ZMyUmm), 79 422 523 байт, sha256 `ee002a3910725d15e8ee41ef2e01ef206534c6880c6a10ac76aafe7596ab7e91`.
Инструмент: REA (`morluto/rea`, версия 6.8.0), собран из исходников; команда `inspect-artifact` и инвентаризация IPA.

## 0. Ограничения анализа (важно)

- **Декомпиляции нет.** Для псевдокода нужен Hopper, Ghidra или IDA. На машине их нет (`rea doctor`: hopper/ghidra/ida/jadx/kuna не настроены). Все выводы о поведении сделаны по **именам символов, строкам и структуре пакета**, а не по коду функций. Это гипотезы с указанием основания, а не подтверждённая логика.
- Бинарник не выполнялся (статический анализ).
- Имена классов Swift взяты из mangled-строк (`$s…`). Тела функций по ним не восстановлены.
- Строки в основном английские. Русской локализации в строках основного бинарника я не обнаружил.

## 1. Что это за приложение

Lampa, нативное iOS-приложение **камеры/фото-редактора** (по строкам: `CaptureLib`, `PhotoEditor`, `Ironstone`, `Darkroom`).

- Bundle ID: `com.lampa.photo`, версия `2.1.5` (build 81), минимум iOS 17.0, только iPhone, только arm64.
- Язык: Swift + Objective-C (в зависимостях).
- Разрешения: камера, микрофон (запись видео), библиотека фото (чтение и запись), геолокация «прикрепить к фото».
- Есть Live Activity / виджет и Lock Screen extension (`LockScreenExtension.appex`) с `LockScreenCaptureInfo`.
- `LSApplicationQueriesSchemes = ['instagram']`: приложение проверяет, установлен ли Instagram (вероятно, для шаринга).
- Фоновых режимов нет (`UIBackgroundModes` отсутствует). `NSAppTransportSecurity` не задан, значит HTTPS по умолчанию.
- Внутренние исходники собирались на машине разработчика `/Users/teplonogov/Developer/Projects/frames/Lampa/` (`App/`, `BottomCards/`, `Modules/Legacy_CameraModule/`). Это путь из отладочной информации, не утверждение о владельце.

## 2. Структура пакета

Всего 386 файлов и 387 occurrences в инвентаризации (REA: 366 узлов, 386 рёбер).

| Категория (REA artifact_kind) | Количество |
|---|---|
| container (IPA/вложенные архивы/директории) | 118 |
| plist | 116 |
| resource (ассеты, видео, LUT, шейдеры) | 69 |
| framework (фреймворки и SPM-продукты) | 63 |
| executable (Mach-O) | 21 |

### Исполняемые Mach-O (21)

- **Основной:** `Lampa.app/Lampa`, 13.4 МБ, arm64, PIE.
- **Расширения:** `PlugIns/LampaWidgetExtension.appex` (виджет), `Extensions/LockScreenExtension.appex` (экран блокировки).
- **Собственные фреймворки:** `Onboarding` (281 КБ), `Storage` (4.4 МБ), `Scrooge` (1.0 МБ), `Gearwheel` (355 КБ).
- **Сторонние:** Firebase (Analytics, GoogleAppMeasurement и др.), Facebook SDK (`FBSDKCoreKit`, `FBAEMKit`, universal-бинарники), `GoogleAdsOnDeviceConversion`.
- **SPM-пакеты с хэш-именами** (`*_PackageProduct`): `AnalyticsClient`, `CameraSettings`, `DeviceKit`, `KeychainAccess`, `PushClient`, `SnapKit`, `UIFoundation`.

### Ресурсы, которые важны для смысла приложения

- `Ironstone_Ironstone.bundle` содержит **37 файлов `.lut`** (в первой версии отчёта я насчитал около 20 по обрезанному списку) (`amber_2.6`, `graphite_1.2`, `helios_appleLog_1.0`, `dew_movie`, `pixel_2.8`, `sp_4` и др.) и `default.metallib`. Это LUT-цветокоррекция, эмуляция плёнки/камер (Apple Log, non-log) и **Metal-шейдеры**.
- `Scrooge_Scrooge.bundle` (9 МБ) — крупный ассет-пакет (вероятно, экран paywall/профилей).
- `Darkroom_Darkroom.bundle`, `Onboarding_Onboarding.bundle`, `GalleryModule_PhotoLibraryModule.bundle`.
- Медиа в комплекте: `warm_up.DNG` (10 МБ, сырой кадр для прогрева), `profiles.mp4`, `helios.mp4`, `emulsia.mp4`, `dew.mp4`, `widget_video.mp4` — демо-видео для профилей/тарифов.
- `LampaStoreConfig.storekit` — локальная конфигурация StoreKit для тестирования покупок.
- `CoFoRobert-Regular.otf` — шрифт.

## 3. Модульная архитектура (по mangled-именам Swift)

Группировка по числу упоминаний в бинарнике:

1. **CaptureLib** (самый большой модуль, ~6800 упоминаний) — ядро камеры.
2. **PhotoLibraryModule** / **GalleryModule** — галерея, просмотр, экран библиотеки, баннеры.
3. **Lampa** — корень приложения: `CaptureAppContext`, `FeaturesView`, вход в приложение.
4. **Ironstone** — конвейер обработки изображения и видео на Metal.
5. **Darkroom** — обработка фото-ассетов (`AsyncProcessor`, `PhotoAssetResaver`, профили).
6. **PhotoEditor** — редактор: `RenderController`, `ControlsView`, `EditingState`, `HistogramView`.
7. **Storage** — сервисы хранения: `CapturesService`, `ProjectsService`, `CaptureFilesService`, `ProjectFilesService`, `LockScreenCaptureInfo`.
8. **Scrooge** — монетизация: `PaywallSource`, `ProductId`, `ShowcaseProfileController`, `SummerPaywallController`, `AppStoreRate`.
9. **CameraSettings** — модель профилей камеры (`ProfileModel`).
10. **Onboarding** — `WelcomeViewController`, `PermissionsController`.
11. **RemotePushes** — `PushNotificationsRegistrar` (APNs/FCM).
12. **Gearwheel** — `OpticalDeviceVM` (вероятно, выбор линз/оптических устройств).
13. **AnalyticsClient** и **Analytics** — аналитика и атрибуция (см. раздел 6).

### Главное в CaptureLib (камера)

Паттерны видны по именам: MVVM, конечный автомат, стор состояний.

- **Ввод и состояние:** `CameraViewModelImpl` (495 упоминаний), `CameraStateMachine`, `CameraStateAnimator`, `ToolsStateStore` (стор инструментов, похожий на Redux).
- **Управление камерой:** `CameraController`, `CameraRotationTracker`, `DigitalZoomManager`, `FocalLengthStack`, `LensPicker`, `LensButtonView`, `OpticalLensButtonView`, `FrontLensButton`, `ExposureControl`, `LegacyExposureControl`, `FlashBarButton`, `TimerPanel`, `LevelView`.
- **Съёмка и запись:** `CamcorderButton`, `CamcorderSlider`, `MovieCapturer`, `LegacyShotButton`, `SavingManager` (`saveAssetData`, `saveVideo(url:)`).
- **Эффекты:** `CameraEffectExecutor`, `SceneView`, `SceneBlurOverlay`, `EVBubbleView`.
- **Профили:** `ProfilesButton`, `ProfileCardView`, `ProfileCardConfig`.
- **Подсказки и пэйволл:** `SwipeHint`, `SwipeHintCoverView`, `SnapsCounter`, `LockBadgeView`, `MembershipBanner`, `LaunchDestination` (варианты `Paywall`, `Showcase`).
- **Быстрый просмотр:** `QuickPreviewController`, `QuickPreviewTransition`.

Лейауты и ассеты (`CameraViewModelImpl`, `CameraController`) организованы по схеме «экран камеры = контроллер + ViewModel + набор кнопок/панелей».

### Модуль Ironstone (пайплайн изображения)

`RawConfiguration`, `ProcessingService`, `TextureView`, `ViewfinderProcessor`, `RawImage`, `OnePassVideoGrader`, `FilmGrain`.

Это **живой предпросмотр с цветокоррекцией через Metal**: в кадр применяются LUT и зерно плёнки, есть ветка для видео (`OnePassVideoGrader`) и обработка RAW (`RawImage`, `RawConfiguration`). Тот факт, что `warm_up.DNG` включён в пакет, подтверждает работу с RAW.

## 4. Принцип работы приложения (по путям данных)

Ниже — выведенный из структуры порядок работы. Точная последовательность вызовов не восстановлена, так как нет декомпиляции.

1. **Запуск.** Основной бинарник `Lampa` поднимает `CaptureAppContext`. Firebase инициализируется через `FirebaseAppDelegateProxyEnabled` (прокси AppDelegate). Удалённая конфигурация через Firebase Remote Config (`CustomSignalValue`, `RolloutAssignment`, `EncodedRollout`).
2. **Онбординг.** `Onboarding`: приветствие и запрос разрешений (камера, микрофон, фото, геолокация), обрабатываются через `PermissionsController`.
3. **Экран камеры (CaptureLib).** `CameraViewModelImpl` получает поток кадров от `CameraController`. Состояние меняется через `CameraStateMachine`. Инструменты (вспышка, таймер, экспозиция, зум, линзы, уровень) хранятся в `ToolsStateStore`.
4. **Предпросмотр.** Кадр проходит через `Ironstone`: LUT, зерно, цветокоррекция на Metal, вывод в `TextureView`/`ViewfinderProcessor`.
5. **Съёмка.** Фото: `LegacyShotButton` / shot-кнопка, затем `SavingManager.saveAssetData`. Видео: `MovieCapturer` (очереди `com.lampa.movie_capturer.buffer_queue` и `movie_queue`), затем `SavingManager.saveVideo(url:)`. Финализация — очередь `com.lampa.finalizeRecording`. Поток захвата — `com.lampa.capture_session.queue`, стриминг — `com.lampa.stream.queue`.
6. **Сохранение.** `Storage`: `CapturesService`, `CaptureFilesService`, `ProjectsService`, `ProjectFilesService`. Файлы идут в `PhotoLibraryModule`/фотобиблиотеку (`NSPhotoLibraryAddUsageDescription`). Для виджета и экрана блокировки пишется `LockScreenCaptureInfo`.
7. **Постобработка.** `Darkroom` (`AsyncProcessor`, `PhotoAssetResaver`) пересохраняет ассеты с профилями. `PhotoEditor` даёт редактирование: `RenderController`, слайдеры, гистограмма (`HistogramView`), переключатели и `EditingState`.
8. **Галерея.** `PhotoLibraryModule` и `GalleryModule` показывают сохранённые кадры, баннер членства (`BFBanner`), быстрый просмотр.
9. **Монетизация.** `Scrooge`: `PaywallSource` (откуда открыт пэйвол) и `ProductId` (ID покупок), `ShowcaseProfileController`. Покупки через StoreKit. Проверка транзакций и отчёты в `APMInAppPurchaseTransactionReporter` и `APMDatabase` (есть защита от дубликатов по fingerprint и subscription ID).
10. **Уведомления.** `RemotePushes`: `PushNotificationsRegistrar` регистрирует токен через APNs и FCM (`fcmregistrations.googleapis.com`).
11. **Виджет и Lock Screen.** `LampaWidgetExtension` и `LockScreenExtension` читают общую информацию о съёмке (`LockScreenCaptureInfo`) через общее хранилище.

## 5. Сеть и внешние сервисы

Хосты, найденные в бинарнике:

- **Firebase / Google:** `firebaseinstallations`, `firebaseremoteconfig` (включая realtime), `firebaselogging`, `firebase-settings.crashlytics.com`, `reports.crashlytics.com`, `update.crashlytics.com`, `fcmregistrations`, `fcmtoken`, `iid.googleapis.com`, `device-provisioning.googleapis.com`.
- **Аналитика/атрибуция:** `app-analytics-services.com`, `app-analytics-services-att.com`, `app-ads-services.com` (поддомены `odm`, `muf`, `odf`), `%@.app-analytics-services.com` (подстановка по ключу). Что именно за вендор, по строкам не установлено.
- **Apple:** `api-adservices.apple.com` (Apple Search Ads attribution), `ocsp.apple.com`, `apple.com`.
- **Google Ads:** `googleadservices.com`, `GoogleAdsOnDeviceConversion`.
- **Прочее:** `goo.gl` (короткие ссылки, вероятно Firebase Dynamic Links), `dummyapiverylong-dummy.google.com` (строка-заглушка).

Наружу не выходит ничего, кроме перечисленного, в основном это Firebase и реклама/атрибуция. Собственного API приложения в строках я не нашёл.

## 6. Аналитика и покупки

- Фреймворк `AnalyticsClient` и классы с префиксом `APM` (`APMAnalytics`, `APMInAppPurchaseProductCache`, `APMInAppPurchaseTransactionReporter`, `APMLifetimeValueRecorder`, `APMDatabase`, `APMEClient`). Это внутренности **Google App Measurement** (`APM` = App Measurement, часть Firebase Analytics), а не отдельный SDK: он собирает события покупок (`productID`, `transactionID`, `isFreeTrial`, `isIntroductoryOffer`, `subscriptionExpirationDate`, `environment`, `isVerified`) и считает LTV (`LifetimeValueRecorder`). Первоначально я не смог определить вендора; это исправлено по отчётам из папки на Drive.
- Firebase Analytics дополнительно логирует `logTransactionWithProductID`.
- Paywall-эксперименты: в логах есть `Paywall experiment registration failed/skipped`, то есть эксперименты пэйволла идут через Remote Config.
- Модель членства: `MembershipBanner`, `getMembershipButton`, `membershipView`, `noMembershipToast`. Варианты: подписка (`isFreeTrial`, `isIntroductoryOffer`, `subscriptionExpirationDate`) и разовые покупки.

## 7. Приватность и разрешения

- В `PrivacyInfo.xcprivacy` приложения и во всех фреймворках есть манифесты приватности Apple (требование App Store).
- `NSPrivacyTrackingDomains` задан, `SKAdNetworkItems` задан — приложение участвует в атрибуции рекламы (SKAdNetwork).
- В Info.plist `FacebookAutoLogAppEventsEnabled` включён, а `FacebookAdvertiserIDCollectionEnabled` отключён; по декомпиляции `AppLaunchManager.prepare` выставляет `isAdvertiserTrackingEnabled = false`. Значит, сбор рекламного идентификатора Facebook SDK по конфигурации выключен (в первой версии отчёта я написал обратное, это было неверно).
- `ITSAppUsesNonExemptEncryption` задан, значит экспортное заявление есть.
- Геолокация используется только для прикрепления к фото (`NSLocationWhenInUseUsageDescription`).

## 8. Что дальше (чтобы получить код, а не имена)

1. Установить Ghidra 12.1+ или Hopper, задать `GHIDRA_INSTALL_DIR` или `HOPPER_LAUNCHER_PATH`, затем `rea decompile-all` / `rea function`. Основной объект разбора — бинарник `Lampa`: в его строках найдены символы `CaptureLib`, `PhotoLibraryModule`, `Ironstone`, `Darkroom`, `Scrooge`. Отдельные фреймворки (`Storage`, `Scrooge`, `Gearwheel`, `Onboarding`) тоже стоит разбирать по отдельности.
2. Через `rea decode-interface-builder` декодировать `.storyboardc` и `.nib` (`LaunchScreen`, Onboarding).
3. `rea inspect-asset-catalog` для `Assets.car` (`Scrooge`, `Onboarding`, `Darkroom`) — там строки UI, иконки и текст тарифов.
4. `rea demangle-swift` для полного списка Swift-символов, если нужны точные сигнатуры.
5. `rea inspect-apple-ips` и `rea inspect-dart-aot` не применимы (нет crash-отчётов и Flutter).

## 9. Итог

Lampa — нативная iOS-камера с профессиональными возможностями: цветокоррекция по LUT и Metal, эмуляция плёнки, RAW (DNG), профили камеры, видеозапись с очередями, редактор с гистограммой, виджет и Lock Screen. Монетизация — подписка и пэйвол с Remote Config-экспериментами и отдельным SDK для отчётов о покупках. Аналитика и атрибуция — Firebase, Facebook SDK, SKAdNetwork и `APM`-SDK.

Все выводы о поведении — гипотезы по символам и структуре пакета. Подтвердить их можно через декомпиляцию (раздел 8).
