# Grove

Grove — карта места на диске для macOS. Программа обходит выбранную папку или том и сразу показывает, чем занято место: чем больше плитка, тем больше папка или файл. Пока идёт обход, карта обновляется, так что крупные объекты видны ещё до окончания сканирования.

Grove is a macOS disk map. It scans a folder or volume and draws each item as a tile sized by the space it occupies. The map updates while the scan is still running.

## Скачать

Готовую программу можно [скачать с GitHub](https://github.com/TrueGeologist/grove/releases/latest): файл `Grove-1.1.0-macOS.zip`. Распакуйте архив и перенесите `Grove.app` в «Программы».

При первом запуске macOS может написать, что разработчик не опознан. Правый щелчок по Grove → «Открыть». Если этого мало: Системные настройки → Конфиденциальность и безопасность → «Всё равно открыть».

Сборка в архиве сделана для Apple Silicon и Intel.

## Без интернета

Grove работает без подключения к интернету. Обход диска, карта и список остаются на этом компьютере. Имена файлов, пути и размеры никуда не отправляются: смотреть сеть программе нечем, сервера у неё нет. Разрешения нужны только для чтения ваших папок на этом Mac.

## Что умеет

- Живой обход диска. Размеры появляются по мере чтения каталогов, а не одним списком в конце.
- Карта папок. Площадь плитки — это место, которое объект занимает на диске.
- Вложенный просмотр. Двойной щелчок или кнопка «Открыть папку» заходит внутрь. Цепочка имён сверху возвращает на уровень выше.
- Список крупных элементов слева и полоска свободного места на томе.
- Переход к объекту в Finder.
- Быстрый просмотр по клавише Пробел.
- Перемещение в Корзину. После удаления карта уменьшается сразу. Домашнюю папку и системные каталоги целиком удалить нельзя.
- Фильтр по имени, в том числе внутри вложенных папок.
- Цвет по типу файла: видео, фото, архивы, документы, код, программы, образы дисков.
- Русский и английский интерфейс — по языку системы.

Размер на карте — это занятое место на диске (выделенные блоки), то есть сколько примерно освободится после удаления. Если файл почти не занимает места, хотя его логический размер большой (клон APFS или файл, не загруженный из iCloud), Grove показывает оба числа.

## Требования

- macOS 14 или новее
- [Command Line Tools для Xcode](https://developer.apple.com/xcode/resources/) — их достаточно, полное приложение Xcode не нужно

Проверка:

```bash
xcode-select --install
swift --version
```

Сборка поддерживает Apple Silicon и Intel. Готовое приложение получается под ту архитектуру, на которой вы его собрали.

## Сборка и запуск

```bash
git clone https://github.com/TrueGeologist/grove.git
cd grove
./build.sh
open build/Grove.app
```

`./build.sh` создаёт `build/Grove.app`, подписывает его локальной подписью и печатает путь к приложению. Папка `build/` в репозиторий не входит.

Если macOS отказывается открыть скачанное приложение и пишет, что разработчик не опознан, откройте Grove через контекстное меню: правый щелчок по `Grove.app` → «Открыть». Для своей сборки через `./build.sh` этот шаг обычно не нужен.

## Как пользоваться

1. На стартовом экране выберите домашнюю папку, Загрузки, Документы, Рабочий стол, диск или любую другую папку (⌘O).
2. Дождитесь, пока крупные плитки проявятся. Обход можно остановить и пользоваться уже построенной картой.
3. Щелчок выбирает объект. Повторный щелчок по выбранной папке или двойной щелчок открывает её.
4. «В Finder» показывает файл или папку там, где они лежат (⇧⌘R).
5. «В Корзину» спрашивает подтверждение и убирает объект (⌘⌫). Восстановить его можно из Корзины.
6. Поле фильтра оставляет на карте только совпадения по имени.
7. Пробел открывает быстрый просмотр выбранного файла.

Недавние папки запоминаются на этом Mac и показываются на стартовом экране.

## Разрешения

Grove читает только то, что разрешено вашей учётной записи. Без этих разрешений часть папок останется закрытой, и карта будет неполной.

- «Документы», «Рабочий стол» и «Загрузки» macOS спрашивает отдельно при первом заходе. Нажмите «Разрешить», иначе эти папки не попадут в обход.
- Почта, сообщения и данные других пользователей видны только с полным доступом к диску. Grove само в этот список не попадает: Системные настройки → Конфиденциальность и безопасность → Полный доступ к диску → «+» → выберите Grove в «Программах» и включите переключатель. После этого закройте Grove (⌘Q) и откройте снова, затем запустите обход ещё раз.

Если закрытые папки встретились во время обхода, Grove пишет, сколько каталогов не удалось прочитать, и даёт ссылку в настройки. Остальная карта при этом остаётся рабочей.

Симлинки программа не разворачивает, а на другой том не переходит. Каждый диск выбирается отдельно на стартовом экране.

## Разработка

Исходники лежат в `Sources/`. Обход каталогов использует `getattrlistbulk`. Карта строится алгоритмом squarified treemap и рисуется через SwiftUI Canvas.

Проверка раскладки и скорости обхода:

```bash
swiftc -O -parse-as-library -swift-version 5 -D GROVE_BENCH \
  -sdk "$(xcrun --show-sdk-path)" \
  -target "$(uname -m)-apple-macosx14.0" \
  -framework SwiftUI -framework AppKit -framework QuickLookUI \
  Sources/*.swift -o build/grove-bench
./build/grove-bench "$HOME/Downloads"
```

## Лицензия

[MIT](LICENSE). Программой можно пользоваться, копировать и изменять её.

---

## English

Grove shows what is using space on a Mac. Pick a folder or disk, and the window fills with tiles while the scan runs. Larger tiles are larger items.

### Download

The built app is on the [latest GitHub release](https://github.com/TrueGeologist/grove/releases/latest): `Grove-1.1.0-macOS.zip`. Unzip it and move `Grove.app` to Applications.

The zip includes both Apple Silicon and Intel. The first launch may say the developer cannot be verified. Right-click Grove and choose Open. If macOS still blocks it, use System Settings → Privacy & Security → Open Anyway.

### Offline

Grove does not use the network. The scan, the map, and the list stay on this Mac. File names, paths, and sizes are not sent anywhere: the app has no server and no network code. Permission prompts exist only so it can read folders on this computer. An internet connection is not required.

### Features

- Live scan, with the map updating before the walk finishes
- Tile area equals allocated disk space
- Drill into a folder and move back through the path bar
- Largest-items list and free-space meter
- Reveal in Finder, Quick Look, and Move to Trash
- Name filter, including matches inside subfolders
- File-type colors
- Russian or English UI, following the system language

Allocated size is what deletion is likely to free. When a file’s logical size is much larger than its disk size, both numbers are shown.

### Requirements

macOS 14 or later, plus Xcode Command Line Tools (`xcode-select --install`). A full Xcode install is not required. The build targets the architecture of the machine you build on.

### Build

```bash
git clone https://github.com/TrueGeologist/grove.git
cd grove
./build.sh
open build/Grove.app
```

If macOS blocks a downloaded copy because the developer cannot be verified, right-click `Grove.app` and choose Open.

### Permissions

Grove only reads what your account is allowed to read. Without the prompts below, some folders stay closed and the map is incomplete.

- macOS asks separately the first time Grove opens Documents, Desktop, or Downloads. Choose Allow, or those folders are skipped.
- Mail, Messages, and other users’ data need Full Disk Access. Grove does not appear there by itself: System Settings → Privacy & Security → Full Disk Access → +, choose Grove in Applications, and turn it on. Quit Grove (⌘Q), open it again, and scan once more.

Unreadable folders are counted in the window; the rest of the map still works. Symbolic links are not followed, and a scan stays on the volume where it started.

### License

[MIT](LICENSE).
