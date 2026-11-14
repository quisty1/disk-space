# Disk Space

[English](#english) · [Русский](#русский)

## English

A native utility for Apple Silicon Macs running macOS 14 or later. It scans the startup disk, shows large and old files, and lets you move selected personal files to Trash.

### Use the app

Open `Disk Space.app`, then choose **Scan Disk** or press **⌘R**. The overview shows what the app could read under the current macOS permissions. In **Files**, switch between large and old files, sort the list, and review your selection before moving anything to Trash. Emptying Trash is a separate step in Finder. Use **⌘,** for settings or **⌘.** to stop a scan.

### Build from source

Install the macOS Command Line Tools with Swift 6.2 or later. No full Xcode installation or third-party packages are required.

```sh
./check.sh
./build.sh
open ".build/Disk Space.app"
```

The build uses an ad hoc signature. The checks use temporary files, including one Trash and restore operation. Scan results stay in memory; language and theme persist in macOS preferences.

## Русский

**Место на диске / Disk Space**

Нативная утилита для macOS 14 и новее на Apple Silicon. Приложение показывает использование загрузочного диска и позволяет перемещать выбранные личные файлы в Корзину.

### Запуск

Распакуйте архив приложения и откройте `Disk Space.app`. Выберите «Сканировать диск» или нажмите ⌘R. Если macOS попросит разрешение на доступ к папке, выберите нужный вариант. При ограниченном доступе вкладка «Обзор» покажет, какие области удалось прочитать. Полный доступ к диску можно выдать отдельно в системных настройках.

Во вкладке «Файлы» можно переключаться между крупными и старыми файлами, сортировать таблицу и выделять несколько строк. Фильтр «Можно в Корзину» показывает личные файлы, доступные для перемещения. Проверьте список в окне подтверждения. Для фактического освобождения места очистите Корзину в Finder.

Настройки языка и оформления открываются по ⌘,. Сканирование можно остановить по ⌘..

### Сборка и проверки

Для сборки используются Swift 6.2 или новее и macOS Command Line Tools. Xcode и сторонние пакеты не требуются.

```sh
./check.sh
./build.sh
open ".build/Disk Space.app"
```

Сборка подписывается локальной ad hoc-подписью. Проверки создают временные файлы, проверяют сканирование и один раз перемещают тестовый файл в Корзину с последующим восстановлением. Результаты сканирования хранятся в памяти приложения, а язык и тема — в стандартных настройках macOS.
