# Схема данных mood 2.4.0

Ниже значения, которые удалось прочитать из декомпилированного JS (`main.jsbundle`). Числа сверены с литералами в коде. Где декомпилятор спутал переменные, это помечено как «уточнить».

## Пресет (полная схема)

Объект, который хранится и передаётся между JS и нативным слоем. Все поля числовые, кроме строк `id`, `name`, `filmStock`, `monoTint`.

| Поле | По умолчанию | Смысл |
|---|---|---|
| `id`, `name` | — | идентификатор и название пользовательского пресета |
| `filmStock` | `stock` | Emulation: одна из 24 плёнок |
| `tint`, `temp` | 0, 0 | баланс: зелёно-пурпурный и сине-жёлтый |
| `contrast` | 1 | множитель контраста |
| `grainStrength` | 0 | сила зерна |
| `grainSize` | 1 | размер зерна (шаг 1…4) |
| `grainRoughness` | 0.2 | шероховатость зерна |
| `chromaticAberrationStrength` | 0 | хроматическая аберрация по краю кадра |
| `bloomRadius` | 25 | радиус свечения (bloom) |
| `bloomIntensity` | 0 | сила свечения |
| `fadeAmount` | 0 | подъём чёрных к серому (выцветание) |
| `muteAmount` | 0 | приглушение насыщенности |
| `shadowsAmount` / `midpointAmount` / `highlightsAmount` | 0 | тональные регуляторы S / M / H |
| `sharpness` | 0 | резкость (отрицательные значения мягчат) |
| `detail` | 0 | детализация |
| `saturation` | 1 | насыщенность |
| `postExposure` | 0 | экспозиция после кривой, в стопах |
| `filmStrength` | 1 | сила эмуляции плёнки (смешивание с исходником) |
| `halationStrength` | 0 | halation версии 1 |
| `halationSize` | 25 | размер halation |
| `halationv2Passes` | 0 | проходы halation версии 2 |
| `halationv3Strength` / `halationv3Spread` / `halationv3Blur` | 0 | halation версии 3 |
| `bloomv3Strength` / `bloomv3Spread` / `bloomv3Blur` / `bloomv3MaskShadow` | 0 / 0 / 0 / 0.1 | bloom версии 3, маска теней 0.1 |
| `monoTint` | `''` | тон для чёрно-белых плёнок |
| `hue` | 0 | поворот оттенка |
| `dynamicRange` | 1 | динамический диапазон (кривая HDR-подобного сжатия) |
| `chromeEffect` | 0.25 | эффект хромированной плёнки (chrome) |
| `randomize` | 0 | случайные отклонения (для «Random») |

Версии halation и bloom разделены: в приложении три поколения одного эффекта. Для нас это важно: мы выбираем одну реализацию (см. `FEATURES.md`).

## Скорость плёнки (`filmSpeed`)

Задаёт зерно, резкость и хроматическую аберрацию. Значения из блока с `chromaticAberrationStrength`:

| Скорость | `grainStrength` | `grainSize` | `sharpness` | `chromaticAberrationStrength` | Описание в приложении |
|---|---|---|---|---|---|
| DIGI | 0 | 1 | 0 | 0 | Natural sharpness with no film grain. |
| 100 | 0.2 | 1 | 0 | 0 | Natural sharpness, ultra fine grain. |
| 200 | 0.3 | 2 | 0 | 0.5 | Subtle film artifacts, fine grain. |
| 400 | 0.3 | 3 | −0.05 | 1 | Subtly lower sharpness, moderate grain. |
| 800 | 0.5 | 3 | −0.1 | 2 | Reduced sharpness, high grain. |
| 1600 | 0.5 | 4 | −0.2 | 2 (уточнить) | Low sharpness, increased grain. |
| 3200 | 0.7 | 4 | −0.3 | 4 | Coarse grain, pronounced artifacts. |

Дополнительные уровни `extraSettings` для фильтров скорости: Off 0, Low 0.1 (в другом блоке 0.15), Medium 0.2, High 0.4. Они меняют halation и bloom поверх скорости; точная привязка уточняется.

## Контраст (`contrast`)

Каждая кривая — набор параметров, применяемых поверх плёнки. Вторая колонка — что выбирает кривую.

| Кривая | `contrast` | `postExposure` | `shadows` | `midpoint` | `highlights` | `fade` | `mute` | `saturation` | `filmStrength` |
|---|---|---|---|---|---|---|---|---|---|
| neutral | 1 | 0 | 0 | −0.05 | 0 | 0.03 | 0.03 | 1 | 1 |
| softer | 1 | 0 | 0 | 0 | 0 | 0.08 | 0.08 | 1.15 | 1 |
| refined | 1 | −0.1 | 0 | 0 | 0 | 0.03 | 0.03 | 1.075 | 0.66 |
| pro | 1.1 | −0.05 | 0 | 0 | −0.1 | 0 | 0 | 1.15 | 0.66 |
| dynamic | 1.1 | 0.05 | 0 | 0 | −0.05 | 0.03 | 0.03 | 1 | 1 |
| bright | 0.85 | 0.3 | −0.05 | −0.05 | −0.15 | 0.015 | 0.015 | 1.075 | 1 |
| faded | 1.1 | 0 | 0 | −0.05 | 0 | 0.15 | 0.15 | 0.85 | 1 |
| ultra | 1.2 | 0 | 0 | −0.05 | −0.05 | 0.06 | 0.06 | 1.075 | 1 |
| crush | 1.3 | −0.1 | −0.05 | 0.05 | 0 | 0 | 0 | 1 | 1 |
| expired | 0.9 | −0.05 | 0 | 0 | −0.05 | 0.23 | 0.08 | 0.85 | 1 |

Поля `dynamicRange`: у каждой кривой есть уровень из шкалы `{EXT+: 1.5, HIGH: 1, MED: 0.666, LOW: 0.333, ZERO: 0}`. В декомпилированном коде присвоение перепутано, поэтому конкретные уровни по кривым помечены «уточнить». Общее правило: `crush` и `ultra` сильнее сжимают диапазон, `bright` и `dynamic` расширяют света.

## Регуляторы (ручная правка)

Тип контрола `SwipeControl2`, ключ в скобках:

- Brightness (`postExposure`), Contrast (`contrast`), Dynamic range (`dynamicRange`), Saturation (`saturation`), Grain size (`grainSize`)
- H (`highlightsAmount`), M (`midpointAmount`), S (`shadowsAmount`)
- Остальные ключи из схемы без своих подписей в бандле: `tint`, `temp`, `hue`, `fadeAmount`, `muteAmount`, `halationStrength`, `grainStrength`, `filmStrength`, `chromaticAberrationStrength`, `bloomIntensity`, `monoTint`.
- `SwipeControl` (без 2) — выбор Emulation (`filmStock`).
- `SwipeControlGroup` — группа регуляторов.

## Рамка (border)

Около 30 рамок. У каждой:
- `topColor` и `bottomColor`: градиент рамки, например `#FDCF52 → #B834CA`;
- `fontColor`: цвет подписи на рамке, `#000000` или `#ffffff`;
- `pattern`: текстура поверх градиента (`pattern1…6` в `assets/custom`);
- `defaultForFilmStocks`: список плёнок, для которых эта рамка выбирается по умолчанию. Например `['gold']`.

Свойства нативного бордера (ObjC): `setBorderBlockColor`, `setBorderBlockEndColor`, `setBorderBlockStartColor`, `setBorderBlockWidth`, `setBorderBlur`, `setBloomAspectX`, `setBloomAspectY`. То есть рамка состоит из блоков с шириной и цветом по краям, размытие и bloom по осям.

## Объективы (`LensPresets.bundle`)

Семь файлов `animor, helion, hexon, lumar, petzval, solis, trinity`. Поля:

`name`, `displayName`, `description`, `order`, `bladeCount` (лепестки диафрагмы, 0 = круг), `catsEye`, `catsEyeEdge`, `catsEyeBias` (кошачий глаз), `vignette`, `vignetteStart`, `ovality` (овальность боке), `bokehAngle`, `ring`, `ringWidth`, `ringRimMinPx` (кольцо, «ринг»), `swirl` (закрутка), `fieldCurvature` (кривизна поля), `blanketBlur`, `depthInfluence` (насколько глубина влияет на блюр), `highlightSpread`, `flareStrength`, `aberration`, `aberrationLateral`, `aberrationLateralGate`, `aberrationHue`, `aberrationSaturation`.

Пример `lumar` (отображаемое имя LUMA): «Soft, dream like bokeh, with no hard edges.» `bladeCount` 0, `ring` −0.95, `swirl` 0.15, `depthInfluence` 1.0.

## Камеры и зум

Ключи `virtualDeviceSwitches`, `lensPowers`, `lensConversionFactor`, `minimumPortraitZoom`, `maximumPortraitZoom`, `nativeZoomConversionFactor`, `zoomLevels`, `minZoom`, `maxZoom` и названия устройств `AVCaptureDeviceTypeBuiltIn…` (Wide, UltraWide, Telephoto, DualWide, Dual, TrueDepth, Triple) с полем `hasDepthSupport`. Логика выбора объектива по зуму похожа на нашу, см. `FEATURES.md`.
