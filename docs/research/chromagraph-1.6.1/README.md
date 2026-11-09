# Chromagraph Camera (yCam) 1.6.1

Разбор IPA `yCam-decrypted-1-3-0.ipa` (bundle `com.ChromaticApplications.yCam`, iOS 17+). Смотрел Info.plist, строки и
символы бинарника, 26 Metal-шейдеров из `default.metallib` (биткод AIR, разобран через `llvmlite` на LLVM 14) и
дизассемблер arm64. Код и ассеты приложения здесь не лежат, кроме пары LUT для ARRI (см. ниже).

## Что это за приложение

RAW-камера: снимает только DNG, а «взгляд» (LUT, зерно, halation, кривая) накладывается при проявке, в видоискателе его
нет. Видео и Log отсутствуют. Есть виджет, расширение для Lock Screen / кнопки Action (`CaptureWithYCamIntent`),
Apple Watch, ночная серия кадров со склейкой, брекетинг, определение пятна на линзе (iOS 26), архив RAW в zip,
«Recently Deleted», импорт RAW из «Фото».

## Конвейер проявки (шейдеры)

`encodeLogC` / `decodeLogCUnclamped` → `preHalationExposureLogC` → coneBlur (halation) → `gradeFusedNoHalation`
(насыщенность, плечо/пята `shoulderToe`, tetrahedral-выборка из LUT) → `postHalationLUTGrainFinal` (зерно).
LUT лежит в LogC3 AWG.

## Два LUT и ползунок Crossover

В бандле два куба 65³: `yCam_LogC3_AWG_to_sRGB_ff_65_v002.cube` (A) и
`yCam_LUT_reverseCrossover_LogC3_AWG_to_sRGB_ff_65^3_v001.cube` (B).

- Выбор не зависит от температуры кадра. Это ручной ползунок «Crossover» (вкладка Color: Balance / Saturation / Crossover),
  диапазон −1…+1.
- Вес A равен `(v + 1) / 2`, обрезан в 0…1. При весе меньше 1 грузится B. Ядро `bakeAtanContrastIntoLUT` запекает
  `w·A + (1 − w)·B`, потом на результат идёт атан-кривая контраста (`atanContrast`, `atanPivot`).
- A и B зеркальны: у A тёплые света и холодные тени, у B наоборот. Среднее почти нейтрально (разница красного и синего
  около ±0.01 по серой оси).
- `wbAdaptWarmPreserve` / `wbAdaptCoolPreserve` / `wbAdaptPivotKelvin` относятся к балансу белого RAW, а не к этим LUT.

Не выяснено: значение Crossover по умолчанию (по симметрии диапазона и нейтральному среднему считаю его нулём).

## Что взято в RCamera

Пресет ARRI (`preset-11`): оба LUT в `App/Resources/LUTs/arri-a.lut` и `arri-b.lut` (8-битные `.lut`, 1 МБ каждый), ползунок
Crossover, вход переводится в LogC3 AWG (`ArriLook`). Остальное из списка возможностей пока не сделано.
