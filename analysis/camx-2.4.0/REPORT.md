# CamX (mood.camera 2.4.0, build 560): анализ IPA

## Статус

- **Ghidra не установлена.** Скачивание с github.com блокируется: `GET https://github.com/NationalSecurityAgency/ghidra/releases` → **403** от прокси, тело: «GitHub access to this repository is not enabled for this session. Use add_repo…». Попытка `add_repo` для `NationalSecurityAgency/ghidra` отклонена автоматическим классификатором. Обход не выполнялся.
- **JDK 21 установлен:** OpenJDK 21.0.12.1 (`/usr/lib/jvm/java-21-openjdk-amd64`).
- **Не выполнено из-за отсутствия Ghidra:** `rea analyze --provider ghidra`, `rea decompile-all`. Псевдокода Ghidra в отчёте **нет**.
- **Подготовлено:** `scripts/run_rea_ghidra.sh` — запускает REA с Ghidra только если заданы `GHIDRA_INSTALL_DIR` и JDK 21 (флаги сверены со справкой `rea` 6.8.0). Без Ghidra скрипт завершается с ошибкой, ничего не запуская.

## Что сделано без Ghidra

- Полный дизассемблинг тел функций (Capstone, ARM64): **31,088** функций, **1,923,743** инструкций.
- Граф вызовов: **65,488** уникальных пар «вызывающий → вызываемый» (`data/edges.csv`).
- Внешние вызовы через import-заглушки: **1,698** разрешённых заглушек; Objective-C селекторы через `__objc_selrefs`.
- Swift-типы и поля из `__swift5_fieldmd` (`data/swift_fieldmd.json`).
- Функции сопоставлены с исходными файлами по строкам утверждений (`data/swift_source_map.csv`): `CamX/MoodCI*.swift`, `GainMapToIsoMapFilter.swift`, `AssetCrypto.swift`.

## Группы функций (признаки: вызовы, селекторы, строки)

| Группа | Функций |
|---|---|
| hermes/react-native | 606 |
| purchases/subscriptions | 409 |
| logging/crash | 132 |
| storage/persistence | 109 |
| ui/swiftui/uikit | 62 |
| network | 45 |
| depth/bokeh/focus | 20 |
| core-image/filters | 19 |
| security/crypto | 13 |
| camera/capture | 11 |
| metal | 10 |
| photos/library | 1 |

## Ограничения

- Это не декомпиляция: поведение описано по вызовам, строкам и полям типов.
- Колонка `label` в `functions.csv` эвристическая (первая подходящая строка функции) и часто не совпадает с назначением функции.
- Metal: в IPA нет `default.metallib`/bitcode, только зашифрованный `Shaders.mtlenc`; `llvm-dis` не применим.
- Ассеты (LUT, зерно, зашифрованные ресурсы), полный дамп декомпилированного JS и полный дизассемблинг не включены в репозиторий.

## Что нужно для полного разбора

1. Разрешить github.com для загрузки `NationalSecurityAgency/ghidra` (Edit → Network access → Limited → Allowed domains, отметить «Allow package managers»; см. https://code.claude.com/docs/en/cloud-environments#network-access), либо положить распакованный Ghidra 12.1.4 в песочницу и указать `GHIDRA_INSTALL_DIR`.
2. Запустить `GHIDRA_INSTALL_DIR=… REA_GHIDRA_STARTUP_TIMEOUT_MS=3000000 scripts/run_rea_ghidra.sh <CamX> <новый каталог>`.

## Файлы

- `data/functions.csv` — все функции: адрес, размер, инструкции, внешние вызовы, селекторы, метка, группы.
- `data/edges.csv` — граф вызовов.  `data/external_calls_top400.json` — самые частые внешние вызовы.
- `data/swift_fieldmd.json`, `data/swift_source_map.csv`, `data/stubs.json`.
- `data/string_xrefs_short.json` — связи строк с функциями (строки длиннее 160 символов исключены).
- `scripts/` — `analyze_all.py`, `xref.py`, `stubs.py`, `fieldmd.py`, `callees.py`, `build_report.py`, `run_rea_ghidra.sh`.
