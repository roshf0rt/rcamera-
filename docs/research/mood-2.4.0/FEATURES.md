# Функции mood 2.4.0 и статус в RCamera

Статусы: **есть** — уже работало до этой сессии; **добавлено** — сделано в этой сессии, не проверено на устройстве; **не сделано** — функция найдена в приложении, в RCamera не реализована (причина в последней колонке).

## Съёмка

| Функция mood | Источник в бандле | Статус в RCamera | Заметка |
|---|---|---|---|
| Фото и видео в одном экране | `CameraView`, `CaptureController` | есть | |
| Сетка | `grid`, `GridOverlay` | есть | |
| Уровень по гироскопу | `CMMotionManager`, `horizon`, `level` | есть | `LevelMonitor` |
| Геолокация в метаданных | `location`, `CLLocation` | есть | `LocationProvider` |
| Зум по объективам | `virtualDeviceSwitches`, `lensPowers`, `zoomLevels` | есть | автоматический выбор, стопы 0.5/1/4 и кроп |
| Кроп 1.5× и 2× | `digital zoom` | есть | |
| Соотношение сторон | `aspectRatio`, `setAspectRatio` | есть | |
| Вспышка | `flash` | есть | |
| Таймер | `timer`, `CaptureTimer` | есть | |
| Зеркало для фронтальной камеры | `mirror` | есть | |
| Видео 1080p/4K, FPS | `fps`, `resolution` | есть | |
| Стабилизация видео | `setVideoStabilization…` | есть | off/standard/cinematic |
| Apple Log | `setAppleProRAWEnabled`, лог-режим | есть | |
| RAW (DNG) | `CIRAWFilter`, `isRawPhoto` | есть | RAW хранится 30 дней |
| HEIC и JPEG | `jpeg`, `heic`, `quality` | есть | HEIC |
| Фокус и экспозиция по тапу | `setAutoFocus`, `setFocusMode`, `setExposureMode` | есть | AE/AF |
| Кнопка громкости как затвор | `VolumeButtonHandler`, `disableSystemVolumeHandler` | добавлено | по умолчанию выключено; без проверки на устройстве |
| Camera Control (кнопка iPhone 16+) | `captureControlTouched`, `captureControlDidChange` | добавлено | iOS 18; без проверки |
| App Intent «Take Photo» (Action button, Shortcuts) | `Metadata.appintents` | добавлено | открывает приложение и снимает |
| Съёмка с задержкой без задержки (zero shutter lag, responsive capture) | `isZeroShutterLagSupported`, `isResponsiveCaptureSupported`, `setFastCapturePrioritization` | не сделано | в нашей схеме фото идёт через 4:3-формат; нужна отдельная проверка |
| Отключение звука затвора | `isShutterSoundSuppressionSupported` | не сделано | в iOS звук отключается не везде, не проверено |
| Портретный режим (фото с глубиной, блюр фона) | `BokehPipeline`, `setDepthDataDelivery…`, режим P | добавлено | `CIDepthBlurEffect` по карте глубины, выбор ƒ-числа; живого блюра в видоискателе нет; без проверки на устройстве |
| Объективы-стили (LUMA и ещё 6) | `LensPresets.bundle` | не сделано | зависит от глубины; параметры описаны в `DATA_MODEL.md` |
| HDR gain map (Ultra HDR) | `CIHdrGainMapFromImage`, `GainMapToIsoMapFilter`, `setAutomaticallyAdjustsVideoHDREnabled`, `hdrHeadroom` | не сделано | нужен вывод gain map в JPEG/HEIC через ImageIO |
| Виджет на экране блокировки | `LockedWidgetExtension.appex` | не сделано | отдельный таргет WidgetKit |
| Locked-расширение | `LockedExtension.appex` | не сделано | отдельный таргет; назначение уточнить |

## Образ (look)

| Функция mood | Статус | Заметка |
|---|---|---|
| 24 плёнки (Emulation: analog, apollo, arizona, calypso, chrome, cine, gold, metro, mono, noir, nord, portra, prologue, stock, taiga, tungsten, vista, xenon, xpro и др.) | есть, другими LUT | у нас 10 пресетов; LUT пользователь загружает сам, встроенных нет |
| Скорости плёнки DIGI…3200 (зерно, размер, резкость, аберрация) | добавлено | `FilmSpeed`; значения из mood |
| 10 контрастных кривых | добавлено | `ContrastCurve`; `dynamicRange` для кривых уточнить |
| Регуляторы Brightness, Contrast, Dynamic range, Saturation, Grain size, H/M/S | добавлено | `Regulator`, редактор пресета |
| Регуляторы Temperature, Tint, Hue, Fade, Mute, Film strength, Sharpness, Fringing, Bloom | добавлено | там же |
| Halation (версия 1) | есть | `halation` с 0 до 100% |
| Halation версии 2 и 3, bloom версии 3 | не сделано | у mood три поколения эффекта; выбрана одна реализация (наша) |
| Mono tint (тон для чёрно-белого) | не сделано | поле `monoTint` есть в схеме, конкретных тонов в бандле не разбирал |
| Chrome-эффект (`chromeEffect`) | не сделано | |
| RGB-кривые (`RGBChannelToneCurve`, `RGBChannelBrightnessAndContrast`, `RGBChannelCompositing`) | не сделано | |
| Debanding (`MoodCIDebandFilter`) | не сделано | |
| Случайный пресет (`randomize`) | не сделано | |
| Пользовательские пресеты (создание, новый пресет через модалку) | добавлено | кнопка New копирует выбранный пресет; удалять можно только свои |
| Меню пресета (контекст, `ContextMenu`) | добавлено | долгое нажатие: Edit, Share (JSON), Delete для своих пресетов |

## Рамка

| Функция mood | Статус | Заметка |
|---|---|---|
| Рамки с градиентом и подписью (около 30 стилей) | добавлено, один стиль | `FrameStyle`, цвета из карточки пресета |
| Рамка по умолчанию для плёнки и режим Auto | добавлено | Auto выбирает рамку по пресету, а не по плёнке: у нас десять пресетов вместо 24 плёнок |
| Пэттерны на рамке (`pattern1…6`) | добавлено | точки, полосы, сетка нарисованы заново; ассеты mood не копировались |
| Рамка на сохранённом фото и при перепроявке | добавлено | в предпросмотре Redevelop рамки нет |
| Выбор динамического диапазона на экране камеры (PRESET, EXT+, HIGH, MED, LOW, ZERO) | добавлено | полоса под верхней панелью, из меню «…» |
| Редактор пресета на трёх вкладках (Emulation, Quality, Tone) с полосой регуляторов | добавлено | `PresetEditor.swift` |
| Карточка «Colour chart» | добавлено | сетка патчей, пересчитанная через текущий look (`ColourChart`) |
| Рамка на видео | не сделано | |

## Интерфейс и жесты

| Функция mood | Статус | Заметка |
|---|---|---|
| Свайп вверх/вниз/влево/вправо | есть | в RCamera есть: вверх — фильтры, вниз — настройки, влево/вправо — фото/видео |
| Свайпы в просмотре фото | есть | |
| Экран регуляторов со свайп-контролами (`SwipeControl2`) | частично | регуляторы в редакторе пресета на трёх вкладках; на экране камеры — только DR |
| Подсказка (info overlay) | не сделано | |
| Онбординг (3 экрана, `onboarding1…3`) | не сделано | |
| Ревью-промпт | не нужно | |
| Тёмная тема, Reduce Motion | есть частично | тёмная тема всегда |

## Не переносим (сознательно)

| Функция mood | Почему |
|---|---|
| Покупки (StoreKit, подписки `monthly2`, `lifetime`), экран тарифов | монетизация; в RCamera не планируется |
| Sentry, Mixpanel и MetricKit | телеметрия; в RCamera не нужна |
| Dev-меню, `LogOverlay`, `MemoryMonitor`, `PeakMemoryTracker` | отладочные инструменты |
| Ассеты (LUT `.lutenc`, шейдеры `.mtlenc`, зерно `.grainenc`, иконки, фото) | зашифрованы или чужие; не извлекались и не используются |

## Что осталось и почему

1. **Глубина и боке + объективы.** Нужен depth-буфер (`AVCaptureDepthDataOutput` на TrueDepth/LiDAR или дуальной камере), маска переднего плана, блюр с формой диафрагмы. Это отдельный блок работы на Metal, его нельзя проверить без устройства с глубиной.
2. **HDR gain map.** Вывод второго слоя (gain map) в HEIC/JPEG через ImageIO; нужна проверка в Фото.
3. **Виджет и Locked-расширение.** Отдельные таргеты в `project.yml`, App Group для данных.
4. **Halation v2/v3 и bloom v3.** Три реализации одного эффекта; взять одну, сравнить на фото.
5. **Экран регуляторов на камере.** Сейчас регуляторы в редакторе пресета; на экране камеры нужен свайп-список как в mood.

## Добавлено после первого раунда

| Функция mood | Статус | Заметка |
|---|---|---|
| Лензы-стили (SOLI, LUMA, TRIO, HELI, PETZ, ANIM, HEXA) | добавлено | виньетка, свечение светов и хроматическая аберрация по параметрам mood; форма боке (лепестки, кошачий глаз, закрутка) не воспроизводится |
| Выбор разрешения фото (12MP и 48MP) | добавлено | опция Resolution в панели; 48MP только там, где формат его отдаёт |
| Рамки-узоры (точки, полосы, сетка) и Auto | добавлено | узоры нарисованы заново |
| Карусель пресетов: New, Edit, Share, Delete | добавлено | Share отдаёт JSON пресета без LUT |
