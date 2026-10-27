import json, collections, re, lief, bisect, sys
R=json.load(open('ipa/xrefs.json'))
stubs=json.load(open('report/stubs.json'))
T=json.load(open('report/swift_fieldmd.json'))
by=collections.defaultdict(list)
for r in R:
    if r['fn']: by[r['fn']].append(r['str'])
def clean(s): return ' '.join(s.split())[:110]
def label(fn):
    """Best-effort label of an internal function from its strings."""
    ss=[s for s in by.get(fn,[]) if 4<len(s)<120 and '/Users/' not in s and 'Sentry' not in s and not s.startswith('{')]
    return clean(ss[0]) if ss else None
out=[]
w=out.append
w('# Анализ CamX (mood.camera 2.4.0, build 560)\n')
w('Цель (по умолчанию из шаблона): как устроена камера, обработка фото, хранение данных.\n')
w('## 0. Что выполнено и что нет\n')
w('- Ghidra 12.1.4 недоступна: GitHub возвращает 403 (политика прокси), поэтому шаги REA `analyze --provider ghidra` и `decompile-all` не выполнены.')
w('- Вместо них: парсинг Swift field descriptors, индекс перекрёстных ссылок строк на код (ARM64 ADRP/ADD/LDR), разрешение import-заглушек и вызовов Objective-C селекторов. Это не декомпиляция, а структурный анализ.')
w('- Metal: в IPA нет `default.metallib` и bitcode; есть `Shaders.mtlenc` (зашифрован). Шаг 6 не применим, зашифрованное не расшифровано.')
w('- Ассеты (LUT, зерно, шейдеры, встроенные JSON-профили) в отчёт не выводятся.\n')
w('## 1. Бинарник\n')
b=lief.parse('ipa/x/Payload/CamX.app/CamX')
w(f'- Формат: Mach-O 64-bit, CPU ARM64, файл 12 943 520 байт, сегмент `__TEXT` `0x100000000`.')
w('- Swift: да (сотни типов в `__swift5_*`). Символы внутренних функций вырезаны (strip): 3 423 экспортируемых символа, 31 348 начал функций.')
w('- Linked frameworks (из REA trace-dylib-resolution и LIEF): AVFoundation, Accelerate, CoreImage, CoreMedia, CoreVideo, CoreLocation, CoreMotion, Photos, PhotosUI, StoreKit, Vision, Metal, MetalKit, UIKit, SwiftUI, AppIntents, LockedCameraCapture (weak), MetricKit, Security, DeviceCheck, CryptoKit, LocalAuthentication, WebKit, MediaPlayer, SQLite, JavaScriptCore (weak), `hermes.framework` (@rpath).\n')
imports=collections.Counter()
for v in stubs.values():
    m=re.match(r'_\$s(\d+)([A-Za-z_]+)', v)
    if m: imports[m.group(2)[:20]]+=1
    elif v.startswith('_$s'): imports['Swift stdlib/runtime']+=1
    elif v.startswith('_objc') or v.startswith('_swift'): imports['ObjC/Swift runtime']+=1
    elif v.startswith('_'): imports['C/libSystem']+=1
w('## 2. Импорты (заглушки, 1 698 разрешено)\n')
w('Топ по модулю Swift/символам: '+', '.join(f'{k}({v})' for k,v in imports.most_common(20))+'.\n')
w('## 3. Swift-типы (`__swift5_fieldmd`, 870 дескрипторов, 3 588 полей)\n')
w('Имена и типы полей читаются из дескрипторов, а не из строк. Типы в виде `So…C` — Objective-C/Core-классы, `?` — опционал, `<sym…>` — ссылка, которую разбирать не стал.\n')
keys=['Bokeh','Depth','Lens','Mood','Preset','Live','Grain','Lut','Shader','Capture','Photo','Video','Focus','Asset','Crypto','Store','Purchase','Subscr','Entitle','Gain','Halation','Bloom','Camera','Matte','Double','Tone','Bench','Timer']
for t in T:
    if any(k in t['type'] for k in keys) and t['type'] and not t['type'].startswith('NitroIap') and 'Purchase' not in t['type'] and 'Subscr' not in t['type'] and 'Sentry' not in t['type']:
        flds=', '.join(f"{f['name']}:{f['type'] or '?'}" for f in t['fields'] if f['name'])[:600]
        w(f"- **{t['type']}** (kind {t['kind']}, {len(t['fields'])} полей): {flds or '—'}")
w('\nВ `kind`: 0 struct, 1 class, 2 enum, 3 multi-payload enum, 7 Core Image filter (класс Swift, наследует CIFilter).\n')
w('## 4. Ключевые функции (по перекрёстным ссылкам строк)\n')
KEY=[('0x1000795a0','Bokeh v2: подготовка базы, DOF, стадии','подтверждено кодом (строки стадий и ветки ошибок), вызовы внешних API подтверждены импортами'),
     ('0x1000ca100','Bokeh v2: рендер/материализация, вывод в CGImage/CVPixelBuffer/MTLTexture','подтверждено строками (`render failed`, `materialise failed`); внутренность не разбирал'),
     ('0x1000c9d90','Загрузка профиля боке и линзы из LensPresets.bundle, fallback на "UNTUNED"','подтверждено строками и логикой fallback'),
     ('0x100086c08','Живое превью глубины: MVB/Metal blur, DepthEffectPreview','подтверждено строками; связь с Metal-ядрами — по имени функции `renderLiveFrameVariableBlur`'),
     ('0x1006bc554','StoreKit: проверка промо-офферов и win-back','подтверждено строками; логика проверки не разбиралась'),
     ('0x100684dec','External purchase notice (iOS 17.4+)','подтверждено строками')]
for a,title,conf in KEY:
    fn=int(a,16); ss=[clean(s) for s in by.get(fn,[]) if len(s)>3][:8]
    w(f'### {title}\n- Адрес: `{a}`\n- Уверенность: {conf}\n- Строки в функции: '+' · '.join(f'`{s}`' for s in ss)+'\n')
w('### Вызовы из ключевых функций (резолв заглушек)\n')
w('Внутренние Swift-функции без имени подписаны по строкам, на которые они ссылаются (косвенный признак, не имя).\n')
w('- `0x1000795a0` вызывает внешние: `os_proc_available_memory` (проверка памяти перед рендером), `CGRectGetWidth/Height/MidX`, `CGAffineTransformMakeScale/Translation/Concat`, `swift_dynamicCast`, `Foundation.Data`, `NSDictionary`, `objc_retain/release`.')
w('- `0x1000ca100` вызывает `String.format` (лог параметров `f/%.2f %.0fmm`), `CGRectIntegral` и вспомогательный `0x1000c9d90` (профиль).')
w('- Вывод: тяжёлый путь — `0x1000795a0` (6 832 инструкции) с большим числом внутренних вызовов; для точных имён нужна декомпиляция.\n')
w('## 5. Поток данных (по строкам и типам, не по декомпиляции)\n')
w('1. Захват: AVFoundation (фото/видео), `CaptureController`, `PhotoCaptureInfo` (orientation, focusPoint, blendPreviewFrame), `CaptureTimer`. Тап по экрану -> `focusPoint`.')
w('2. Глубина и маска: `DepthSource` (Metal texture / CVBuffer), `DepthParams` (upsampler: joint/guided/edgePreserve/bilinear), Vision-матты (`LiveMatte`, `capturedHairMatte`).')
w('3. Подготовка: демозаика RAW, извлечение HDR gain map, карта фокуса (`MoodCIFocusGainMapFilter`, tapLocation).')
w('4. Боке: `BokehPipeline` с `BokehParams` (fNumber, focalLength, bladeCount, highlightHdrBoost…) и `BokehStyle` (aberration, catsEye, ring…). Если portrait-disparity нет, DOF пропускается.')
w('5. Плёнка и цвет: цепочка `MoodCI*` (Grain, DiffuseHalation, DiffuseBloom, DynamicRange, ChromeDensity, ColorControls, Deband, FadeMute, Aberration, JPEGV3). Параметры — в `filterSettings` пресета.')
w('6. Вывод: `CGImage` / `CVPixelBuffer` / `MTLTexture`; экспорт фото и видео.')
w('7. Пресеты и настройки: `Preset` (name, summary, order), `USER_PRESETS_STORAGE_KEY` (AsyncStorage), миграции по `CURRENT_PRESET_VERSION`.\n')
w('## 6. Неизвестные места\n')
w('- Точная цепочка `MoodCI*`-фильтров по порядку вызовов (нужна декомпиляция `0x1000795a0`).')
w('- Как работают зашифрованные ассеты (`AssetCrypto`): механизм известен, ключи и данные не извлекались.')
w('- Внутренние имена Swift-функций (вырезаны); соответствие адресов и методов.')
w('- Сетевой слой: `googleapis.com` (Drive) — что загружается и когда, не проверено.')
w('- Где хранятся фото и пресеты на диске (Documents/AppGroup/Keychain) — нужен поиск по вызовам FileManager/UserDefaults.\n')
w('## 7. Как проверить на устройстве\n')
w('- Захват: записать сетевой и файловый трафик при съёмке (Instruments: File Activity, Network).')
w('- Боке: снимать портрет с включённой и выключенной глубиной; проверить строку `Portrait DOF skipped` в логе (Console.app, фильтр по процессу CamX).')
w('- Память: при низком `os_proc_available_memory` проверить, что рендер откатывается, а не падает.')
w('- Покупки: проверить на sandbox-аккаунте, какие пресеты остаются доступны после истечения подписки.\n')
w('## 8. Метки уверенности\n')
w('- **Подтверждено кодом**: адреса функций, импорты, Swift-поля, строки в функции.')
w('- **Косвенно**: назначение внутренних функций по строкам, которые они используют.')
w('- **Гипотеза**: порядок стадий `MoodCI*` и ветвления, пока не сверены с декомпиляцией.\n')
open('report/REPORT.md','w').write('\n'.join(out))
print('written', len('\n'.join(out)))
