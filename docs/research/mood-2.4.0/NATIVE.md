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

Раздел заполняется по результатам `rea analyze --provider ghidra` (см. `docs/research/mood-2.4.0/README.md`, раздел «Как получены данные»). Если результата нет, остаются только имена и импорты выше.
