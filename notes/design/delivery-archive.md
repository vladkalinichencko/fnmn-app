# Поставка статьи одним tar

## Задача

Mac отдаёт подготовленную статью одним JSON: поля `ImportPackage` и `files`, где каждая картинка лежит строкой base64. Этот формат идёт в трёх местах: ответ `GET /jobs/{id}/package`, файлы `deliveries/<hash>.json` из `prepare_browser_library.py` (около 1,8 ГБ на 1471 поставку, почти всё картинки) и папка FNMN в iCloud, куда их копирует `publish_library.py`. Приложение читает поставку целиком в память (`MacServiceClient.package`, `LibraryFile.BrowserDelivery`) и декодирует каждую картинку, а base64 раздувает картинки на треть. Решено: одна поставка — один несжатый tar, внутри первым `package.json`, за ним файлы по их относительным путям; готовые поставки один раз перегоняются на Mac, приложение читает только новый формат. Выбранный вручную `.json` остаётся пакетом без файлов.

## Использование

Приложение, подготовка по ссылке:

```swift
let archive = try await mac.port.delivery(of: job.id, connection: connection)   // tar во временной папке
try await library.store(archive: archive)
```

Приложение, папка FNMN и выбранный файл:

```swift
for url in deliveries where url.pathExtension == "tar" {
    next = try storeArticle(archive: url, into: next)
}
```

Mac, адаптер и задание:

```python
delivery = import_link(url, folders, LIVE, report)      # Delivery(package: dict, files: dict[str, bytes])
write_delivery(job_folder / "delivery.tar", delivery)
```

Mac, перегон уже готовых поставок:

```python
package, files = read_delivery(path)          # и старый <hash>.json с base64 — только в repackage
package["folders"] = row["folders"]
write_delivery(path.with_suffix(".tar"), Delivery(package, files))
```

## Форма

FNMNCore:

```swift
/// One prepared material as the Mac delivers it: an uncompressed USTAR archive whose first entry is
/// `package.json` and whose other entries are the files its Markdown names, by their relative paths.
/// It is read in one pass with a fixed buffer, so a delivery never sits in memory whole.
public struct DeliveryArchive {
    public init(url: URL)
    /// Reads the package, then copies every other entry to the file `destination` names for its path.
    public func unpack(filesInto destination: (String) throws -> URL) throws -> ImportPackage  // not implemented
}

extension LibraryFile {
    /// A new revision gets `text.json` and the archive's files; the package enters the catalog.
    public func storeArticle(archive: URL, into snapshot: LibrarySnapshot) throws -> LibrarySnapshot  // not implemented
}
```

`storeArticle(_ package:files:into:)` с `[String: Data]` уходит: у картинок один путь в библиотеку, через архив. `storeBrowserLibrary` читает `deliveries/*.tar`, `storePicked` принимает `.tar` и `.json`. `MacServicePort.package(of:)` становится `delivery(of:) -> URL` поверх `URLSession.download`, ответ пишется на диск, а не в `Data`.

Mac:

```python
@dataclass
class Delivery:
    package: dict               # ImportPackage без files
    files: dict[str, bytes]

def package(url, content, folders) -> Delivery
def write_delivery(path: Path, delivery: Delivery) -> None   # USTAR, package.json первым, запись через .incoming
def read_delivery(path: Path) -> Delivery                    # tar; старый .json с base64 понимает только он
```

`jobs.Job.package: dict` становится `Job.delivery: Path` во временной папке сервиса, `GET /jobs/{id}/package` отдаёт `FileResponse(media_type="application/x-tar")`. `prepare_browser_library.py` пишет `<hash>.tar`, `--repackage` переводит каждый `<hash>.json` в `<hash>.tar` и удаляет JSON. `publish_library.py` не меняется: копирует папку `deliveries` целиком.

Архив знает только `DeliveryArchive` на одной стороне и `write_delivery`/`read_delivery` на другой. Каталог библиотеки видит `ImportPackage` и пути файлов; как они уложены в поставке, он не знает. Пути проверяет `LibraryFile.articleFile`, как сейчас: запись за пределы папки статьи — ошибка.

## Решение

Формат выбран из двух: папка на поставку с отдельными файлами и один tar. Tar взят потому, что и iCloud, и сеть получают один файл на материал, а обе стороны читают и пишут его потоком. Абстракция источника в приложении — это сам архив на диске: у него один формат и один читатель, поэтому протокол источника с одной реализацией не заводится.

## Принятые компромиссы

- Принимаем свой разбор USTAR в FNMNCore (заголовок 512 байт, размер в восьмеричной записи, выравнивание данных до 512) в обмен на отсутствие зависимости: в iOS нет открытого API для tar.
- Принимаем ограничение USTAR на длину пути (имя до 100 символов, вместе с префиксом до 255) в обмен на то, что читатель не разбирает заголовки PAX. Mac пишет `format=tarfile.USTAR_FORMAT` и падает на слишком длинном пути, а не пишет PAX молча.
- Принимаем разовый перегон 1,8 ГБ на Mac в обмен на один путь чтения в приложении.

## Альтернативы

- Папка на поставку (`package.json` и файлы рядом): в iCloud несколько тысяч файлов вместо 1471, по сети запрос на каждую картинку.
- Протокол `ArticleSource` с адаптерами для Mac и папки: при одном формате на диске второй реализации нет, протокол только добавил бы слой.

## Открытые вопросы и риски

- Задания на Mac держат поставки во временной папке, пока сервис работает; удалять ли `delivery.tar` после того, как телефон её забрал, или хватает перезапуска сервиса?

## Первый шаг

`DeliveryArchive` с тестом на архив из `tarfile` (package.json, вложенный путь, пустой файл, файл ровно в 512 байт) и `write_delivery`/`read_delivery` с тестом круга на Mac.
