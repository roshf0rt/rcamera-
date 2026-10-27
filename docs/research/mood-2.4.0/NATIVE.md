# Нативный слой mood 2.4.0

Источник: `CamX` (Mach-O arm64). Имена классов и импорты — из строк и таблиц символов, поведение — по декомпиляции там, где Ghidra её дала (раздел «Ghidra» ниже). Swift-символы в бинарнике в основном обрезаны, поэтому имена типов взяты из `_TtC4CamX…` (mangled ObjC-имена Swift-классов).

## Классы модуля CamX

Вид и управление камерой:
- `CameraView`, `RCTCameraViewManager` (RN-мост), `CameraController`, `CaptureController`, `CameraControllerDelegate` (протокол)
- `MetalViewFinderController`, `PreviewMetalView`, `LiveMetalBlur`, `MoodGaussianBlur`, `MoodBoxBlur`
- `CaptureTimer`, `VolumeButtonHandler`, `AnalyticThrottler`
- `ImagePreviewFilterController`, `FilterController`, `FilterPreview`, `ImageCache`

Съёмка с глубиной:
- `BokehPipeline`, `DepthEffectPreview`, `LiveDepthAccumulator`, `LiveDepthGPUAccumulator`, `MoodCIFocusGainMapFilter`

Core Image фильтры (префикс `Mood…`, плюс несколько общих):

| Фильтр | Назначение (по имени) |
|---|---|
| `MoodCIGrainFilter` | зерно |
| `MoodCIDiffuseHalationFilter` | halation, вариант с диффузией |
| `MoodCIDiffuseBloomFilter` | bloom с диффузией |
| `MoodCIChromeDensityFilter` | плотность хромированной плёнки (`chromeEffect`) |
| `MoodCIDynamicRangeFilter` | динамический диапазон (`dynamicRange`) |
| `MoodCIColorControlsFilter` | яркость, контраст, насыщенность |
| `MoodCIAberrationFilter`, `ChromaticAberration` | хроматическая аберрация |
| `MoodCIDebandFilter` | подавление бандинга |
| `MoodCIFadeMuteFilter` | `fadeAmount` и `muteAmount` |
| `MoodCILightenFilter`, `MoodCIBloomFilter`, `MoodCIBlurFilter`, `MoodCIDiffuseFilter` | осветление, bloom, размытие |
| `RGBChannelToneCurve`, `RGBChannelBrightnessAndContrast`, `RGBChannelCompositing` | тоновые кривые по каналам |
| `MoodCIHdrGainMapFromImage`, `GainMapToIsoMapFilter` | HDR: gain map и перевод в ISO-карту |
| `MoodCIJPEGV3Filter` | экспорт JPEG (версия 3 пайплайна) |
| `CIAddBorder` | рамка |

Фото и файлы: `SDPhotosHelper` (библиотека Фото), `ImagePickerDelegate`, `PhotoDataCustomizer`, `PHPhotoLibrary`, `PHAssetCreationRequest`.

Прочее: `VolumeButtonHandler` (громкость), `DeferringEdgesViewController` (отложенные системные жесты), `MemoryMonitor`, `PeakMemoryTracker`, `LogOverlay`, `SharedLogOverlay` (отладка).

## Используемые системные фреймворки (по импортам)

- **Камера и видео:** `AVCaptureSession`, `AVCaptureVideoDataOutput`, `AVCapturePhotoOutput`, `AVCaptureDepthDataOutput` (через `setDepthDataDelivery…`), `AVCaptureDevice` с типами `BuiltInWideAngle`, `UltraWide`, `Telephoto`, `DualCamera`, `DualWideCamera`, `TrueDepthCamera`, `TripleCamera`.
- **Фото:** `CIRAWFilter` (RAW), `isAppleProRAWSupported`, `setAppleProRAWEnabled`, `CIColor`, `CIVector`, `CIRenderDestination`.
- **Metal:** `MTKView`, `MTLTextureDescriptor`, `CIKernel`, `CIColorKernel`.
- **Vision:** `VNImageRequestHandler`, `VNRequest`, `VNPixelBufferObservation` (вероятно, маска переднего плана для боке).
- **Датчики:** `CMMotionManager` (уровень), `CTTelephonyNetworkInfo` (сеть для Sentry), `DCDevice` (DeviceCheck).
- **Безопасность:** `LAContext` (LocalAuthentication, блокировка приложения).
- **Покупки:** `SKPaymentQueue`, `SKProductsRequest`, `SKProduct`.
- **Мониторинг:** `MXMetricManager`, `MXCrashDiagnostic`, `MXHangDiagnostic` (MetricKit).
- **Веб:** `WKWebView` (онбординг или справка).
- **Геопозиция:** `getLastLocation`, `requestLocationAccuracy` (в JS-слое через нативный модуль).

## Селекторы, которые важны для функций

- Кнопка Camera Control: `captureControlTouched`, `captureControlDidChange`.
- Камера: `setAspectRatio:`, `setAutoFocus:`, `setActiveDepthDataFormat:`, `setActiveVideoMinFrameDuration:`, `setAlwaysDiscardsLateVideoFrames:`, `setZeroShutterLag…` (через `isZeroShutterLagSupported`), `isFastCapturePrioritizationSupported`.
- Видео: `isVideoHDRSupported`, `isVideoStabilizationSupported`, `setAutomaticallyAdjustsVideoHDREnabled:`.
- Рамка: `setBorderBlockColor:`, `setBorderBlockEndColor:`, `setBorderBlockStartColor:`, `setBorderBlockWidth:`, `setBorderBlockStartWidth:`, `setBorderBlockEndWidth:`, `setBorderBlur:`, `setBloomAspectX:`, `setBloomAspectY:`.
- Громкость: `disableSystemVolumeHandler`, `isAdjustingInitialVolume`.
- Вспомогательное: `getInterfaceOrientation`, `isDisplayZoomed`, `isHighTextContrastEnabled:`.

## Ghidra

`rea analyze --provider ghidra` на `CamX` (Ghidra 12.1.4, arm64, ~1 час) дал обзор бинарника:

- 67 сегментов, включая `__text` на ~7.7 МБ, `__objc_methlist`, `__swift5_fieldmd`, `__swift5_typeref`;
- 58 659 процедур и 93 800 строк, найденных анализом;
- образ загружен с базой `0x100000000`.

Декомпиляция отдельных функций (фильтры, капчура, LUT) в этой версии не выполнялась: обзор не возвращает тела функций, а `rea decompile` по адресам нужен отдельно. Поэтому описание поведения фильтров выше опирается на имена классов и импорты, а не на код. Если нужна точность по формулам, следующий шаг — `rea decompile` по адресам `MoodCIGrainFilter`, `MoodCIDiffuseHalationFilter` и `BokehPipeline`.

Из-за ограничения JS-слой описан по `hbc-decompiler` (сырой вывод, см. `DATA_MODEL.md`), а не по исходникам.
