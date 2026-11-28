import argparse
import fcntl
import json
import os
import re
import sys
import tempfile
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import unquote, urlencode, urljoin, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

from bs4 import BeautifulSoup


BASE = {
    "wallhaven": "https://wallhaven.cc",
    "motionbgs": "https://motionbgs.com",
    "moewalls": "https://moewalls.com",
}
PAGE_HOSTS = {
    "wallhaven": {"wallhaven.cc"},
    "motionbgs": {"motionbgs.com", "www.motionbgs.com"},
    "moewalls": {"moewalls.com", "www.moewalls.com"},
}
MEDIA_HOSTS = {
    "wallhaven": {"w.wallhaven.cc", "th.wallhaven.cc"},
    "motionbgs": PAGE_HOSTS["motionbgs"],
    "moewalls": PAGE_HOSTS["moewalls"] | {"go.moewalls.com", "cdn.moewalls.com"},
}
PAGE_PATTERNS = {
    "wallhaven": r"/w/([a-z0-9]{6})/?",
    "motionbgs": r"/([a-z0-9][a-z0-9-]{0,199})/?",
    "moewalls": r"/([a-z0-9-]{1,40}/[a-z0-9-]{1,200})/?",
}
DOCUMENT_LIMIT = 4 * 1024 * 1024
PREVIEW_LIMIT = 24 * 1024 * 1024
DOWNLOAD_LIMIT = 300 * 1024 * 1024
CACHE_BYTES = 120 * 1024 * 1024
CACHE_ITEMS = 32
PAGE_LIMIT = 1000
ITEM_LIMIT = 48
TIMEOUT = 10
TRANSFER_DEADLINE = 90
IMAGE_TYPES = {"jpg": "image/jpeg", "png": "image/png", "webp": "image/webp"}
VIDEO_TYPES = {"mp4": "video/mp4", "webm": "video/webm"}


class CatalogError(Exception):
    pass


def allowed_url(url, hosts):
    parsed = urlsplit(url)
    if (
        parsed.scheme != "https"
        or parsed.netloc.lower() not in hosts
        or any(character.isspace() or character == "\\" for character in url)
    ):
        raise CatalogError("Provider returned an unexpected URL")
    return parsed


class ProviderRedirects(HTTPRedirectHandler):
    def __init__(self, provider, hosts):
        self.provider = provider
        self.hosts = hosts

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if self.provider == "moewalls" and urlsplit(newurl).hostname == "motionbgs.com":
            raise CatalogError("MoeWalls now redirects to MotionBGs")
        allowed_url(newurl, self.hosts)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def open_url(provider, url, hosts, referer=None):
    allowed_url(url, hosts)
    headers = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) Firefox/140.0"}
    if referer:
        headers["Referer"] = referer
    response = build_opener(ProviderRedirects(provider, hosts)).open(
        Request(url, headers=headers), timeout=TIMEOUT
    )
    if response.status != 200:
        response.close()
        raise CatalogError("Provider did not return a complete response")
    return response


def document(provider, url):
    with open_url(provider, url, PAGE_HOSTS[provider]) as response:
        if response.headers.get_content_type() not in {"text/html", "application/json"}:
            raise CatalogError("Provider returned an unexpected document")
        payload = bytearray()
        for chunk in response_chunks(response, DOCUMENT_LIMIT):
            payload.extend(chunk)
        return bytes(payload), response.url


def response_chunks(response, limit):
    declared_size = response.headers.get("Content-Length")
    expected_size = int(declared_size) if declared_size is not None else None
    if expected_size is not None and not 0 < expected_size <= limit:
        raise CatalogError("Provider response exceeds the size limit or is empty")
    deadline = time.monotonic() + TRANSFER_DEADLINE
    received = 0
    while chunk := response.read1(64 * 1024):
        received += len(chunk)
        if time.monotonic() > deadline:
            raise CatalogError("Provider transfer timed out")
        if received > limit:
            raise CatalogError("Provider response exceeds the size limit")
        yield chunk
    if received == 0 or (expected_size is not None and received != expected_size):
        raise CatalogError("Provider response is incomplete")


def page_identity(provider, url):
    parsed = allowed_url(url, PAGE_HOSTS[provider])
    match = re.fullmatch(PAGE_PATTERNS[provider], parsed.path)
    if not match or parsed.query or parsed.fragment:
        raise CatalogError("Invalid wallpaper page")
    return match[1].replace("/", "~")


def item(identifier, title, thumbnail, page_url, motion, width=0, height=0):
    return {
        "id": identifier,
        "title": title.strip()[:240] or identifier,
        "thumbnail": thumbnail,
        "pageUrl": page_url,
        "motion": motion,
        "width": width,
        "height": height,
    }


def wallhaven_search(query, page):
    parameters = urlencode(
        {"q": query, "page": page, "purity": "100", "sorting": "date_added"}
    )
    payload, _ = document(
        "wallhaven", f"{BASE['wallhaven']}/api/v1/search?{parameters}"
    )
    data = json.loads(payload)
    items = []
    for entry in data["data"][:ITEM_LIMIT]:
        identifier = entry["id"]
        page_url = entry["url"]
        thumbnail = entry["thumbs"]["small"]
        try:
            if page_identity("wallhaven", page_url) != identifier:
                continue
            allowed_url(thumbnail, MEDIA_HOSTS["wallhaven"])
        except CatalogError:
            continue
        title = f"Wallpaper {identifier}"
        items.append(
            item(
                identifier,
                title,
                thumbnail,
                page_url,
                False,
                entry["dimension_x"],
                entry["dimension_y"],
            )
        )
    return items, page < data["meta"]["last_page"]


def motionbgs_search(query, page):
    provider = "motionbgs"
    base = BASE[provider]
    if query:
        url = f"{base}/search?{urlencode({'q': query, 'page': page})}"
    else:
        url = f"{base}/{page}/" if page > 1 else base
    html, effective_url = document(provider, url)
    tag = re.fullmatch(r"/(tag:[a-z0-9-]+)/?", urlsplit(effective_url).path)
    if tag and page > 1:
        html, effective_url = document(provider, f"{base}/{tag[1]}/{page}/")
    soup = BeautifulSoup(html, "html.parser")
    items = []
    seen = set()
    for link in soup.select("a[href]"):
        image = link.select_one("img")
        title = link.select_one(".ttl")
        if not image or not title:
            continue
        thumbnail = urljoin(
            effective_url, image.get("data-src") or image.get("src") or ""
        )
        if not re.search(r"/media/[0-9]+/", urlsplit(thumbnail).path):
            continue
        page_url = urljoin(effective_url, link["href"])
        try:
            identifier = page_identity(provider, page_url)
            allowed_url(thumbnail, MEDIA_HOSTS[provider])
        except CatalogError:
            continue
        if identifier in seen:
            continue
        seen.add(identifier)
        dimensions = re.search(r"\.(\d{3,5})x(\d{3,5})\.", urlsplit(thumbnail).path)
        width, height = (
            (int(dimensions[1]), int(dimensions[2])) if dimensions else (0, 0)
        )
        items.append(
            item(
                identifier,
                title.get_text(" ", strip=True),
                thumbnail,
                page_url,
                True,
                width,
                height,
            )
        )
        if len(items) >= ITEM_LIMIT:
            break
    has_more = any(
        link.get_text(strip=True) == "Next" for link in soup.select("a[href]")
    )
    return items, bool(items and has_more)


def moewalls_search(query, page):
    provider = "moewalls"
    url = f"{BASE[provider]}/page/{page}/"
    if query:
        url += f"?{urlencode({'s': query})}"
    try:
        html, effective_url = document(provider, url)
    except HTTPError as error:
        if error.code == 404 and page > 1:
            return [], False
        raise
    soup = BeautifulSoup(html, "html.parser")
    items = []
    seen = set()
    for article in soup.select("article"):
        link = article.select_one("a[href]")
        image = article.select_one("img")
        if not link or not image:
            continue
        page_url = urljoin(effective_url, link["href"])
        thumbnail = urljoin(
            effective_url, image.get("data-src") or image.get("src") or ""
        )
        try:
            identifier = page_identity(provider, page_url)
            allowed_url(thumbnail, MEDIA_HOSTS[provider])
        except CatalogError:
            continue
        if identifier in seen or not urlsplit(thumbnail).path.startswith(
            "/wp-content/"
        ):
            continue
        seen.add(identifier)
        heading = article.select_one(".entry-title")
        title = (
            heading.get_text(" ", strip=True)
            if heading
            else link.get("title") or image.get("alt") or ""
        )
        resolution = article.select_one(".entry-resolutions a")
        dimensions = (
            re.search(r"(\d{3,5})\s*[x×]\s*(\d{3,5})", resolution.get_text())
            if resolution
            else None
        )
        width, height = (
            (int(dimensions[1]), int(dimensions[2])) if dimensions else (0, 0)
        )
        items.append(item(identifier, title, thumbnail, page_url, True, width, height))
        if len(items) >= ITEM_LIMIT:
            break
    has_more = any(
        re.fullmatch(
            rf"/page/{page + 1}/?", urlsplit(urljoin(effective_url, link["href"])).path
        )
        for link in soup.select("a[href]")
    )
    return items, bool(items and has_more)


def resolve_media(provider, identifier, page_url, preview):
    if provider == "wallhaven":
        payload, _ = document(provider, f"{BASE[provider]}/api/v1/w/{identifier}")
        wallpaper = json.loads(payload)["data"]
        if wallpaper["id"] != identifier:
            raise CatalogError("Provider returned a different wallpaper")
        return wallpaper["thumbs"]["large"] if preview else wallpaper["path"]

    html, effective_url = document(provider, page_url)
    if page_identity(provider, effective_url) != identifier:
        raise CatalogError("Provider returned a different wallpaper")
    soup = BeautifulSoup(html, "html.parser")
    if preview:
        source = soup.select_one("video source[src], video[src]")
        if source:
            return urljoin(effective_url, source["src"])
    elif provider == "motionbgs":
        link = soup.select_one("a[href^='/dl/4k/']") or soup.select_one(
            "a[href^='/dl/hd/']"
        )
        if link:
            return urljoin(effective_url, link["href"])
    else:
        button = soup.select_one("#moe-download[data-url]")
        if button and button["data-url"].strip():
            return "https://go.moewalls.com/download.php?" + urlencode(
                {"video": unquote(button["data-url"])}
            )
    raise CatalogError("Provider did not supply the requested media")


def media_extension(header, expected_types):
    signatures = {
        "jpg": header.startswith(b"\xff\xd8\xff"),
        "png": header.startswith(b"\x89PNG\r\n\x1a\n"),
        "webp": header.startswith(b"RIFF") and header[8:12] == b"WEBP",
        "mp4": len(header) >= 16 and header[4:8] == b"ftyp",
        "webm": header.startswith(b"\x1a\x45\xdf\xa3") and b"webm" in header[:256],
    }
    for extension in expected_types:
        if signatures[extension]:
            return extension
    raise CatalogError("Provider returned invalid wallpaper media")


def xdg_directory(variable, fallback):
    configured = Path(os.environ.get(variable, ""))
    return configured if configured.is_absolute() else Path.home() / fallback


def existing_media(directory, identifier, expected_types, limit):
    for extension in expected_types:
        path = directory / f"{identifier}.{extension}"
        if (
            path.is_file()
            and not path.is_symlink()
            and 0 < path.stat().st_size <= limit
        ):
            try:
                with path.open("rb") as reader:
                    if media_extension(reader.read(256), expected_types) == extension:
                        return path
            except CatalogError:
                continue
    return None


def prune_cache(cache, keep):
    cached = sorted(
        (
            path
            for path in cache.glob("*/*")
            if path.is_file() and not path.name.startswith(".")
        ),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    total_size = keep.stat().st_size
    total_items = 1
    for path in cached:
        if path == keep:
            continue
        size = path.stat().st_size
        if total_items >= CACHE_ITEMS or total_size + size > CACHE_BYTES:
            path.unlink()
        else:
            total_items += 1
            total_size += size


def transfer_media(
    provider, url, page_url, directory, identifier, expected_types, limit
):
    temporary_path = None
    try:
        with open_url(
            provider, url, MEDIA_HOSTS[provider], referer=page_url
        ) as response:
            content_type = response.headers.get_content_type()
            if content_type not in {
                *expected_types.values(),
                "application/octet-stream",
            }:
                raise CatalogError("Provider returned an unexpected media type")
            with tempfile.NamedTemporaryFile(
                dir=directory, prefix=".wallpaper-", delete=False
            ) as writer:
                temporary_path = Path(writer.name)
                for chunk in response_chunks(response, limit):
                    writer.write(chunk)
        with temporary_path.open("rb") as reader:
            extension = media_extension(reader.read(256), expected_types)
        if content_type not in {expected_types[extension], "application/octet-stream"}:
            raise CatalogError("Provider media does not match its reported type")
        destination = directory / f"{identifier}.{extension}"
        temporary_path.replace(destination)
        return destination
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def local_media(provider, identifier, page_url, preview):
    if len(identifier) > 242 or page_identity(provider, page_url) != identifier:
        raise CatalogError("Wallpaper ID does not match its page")
    expected_types = IMAGE_TYPES if provider == "wallhaven" else VIDEO_TYPES
    if preview:
        root = (
            xdg_directory("XDG_CACHE_HOME", ".cache") / "impasto" / "wallpaper-previews"
        )
        limit = PREVIEW_LIMIT
    else:
        root = xdg_directory("XDG_DATA_HOME", ".local/share") / "wallpapers" / "Online"
        limit = DOWNLOAD_LIMIT
    directory = root / provider
    directory.mkdir(parents=True, exist_ok=True)
    lock_path = root / ".lock" if preview else directory / ".lock"
    with lock_path.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        pending_directories = [root / name for name in BASE] if preview else [directory]
        for pending_directory in pending_directories:
            for temporary_path in pending_directory.glob(".wallpaper-*"):
                temporary_path.unlink(missing_ok=True)
        path = existing_media(directory, identifier, expected_types, limit)
        if path is None:
            url = resolve_media(provider, identifier, page_url, preview)
            path = transfer_media(
                provider, url, page_url, directory, identifier, expected_types, limit
            )
        if preview:
            path.touch()
            prune_cache(root, path)
    return {"path": str(path)}


def main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    search = commands.add_parser("search")
    search.add_argument("provider", choices=BASE)
    search.add_argument("query")
    search.add_argument("page", type=int)
    for command in ("preview", "download"):
        resolver = commands.add_parser(command)
        resolver.add_argument("provider", choices=BASE)
        resolver.add_argument("identifier")
        resolver.add_argument("page_url")
    arguments = parser.parse_args()
    try:
        if arguments.command == "search":
            if not 1 <= arguments.page <= PAGE_LIMIT or len(arguments.query) > 200:
                raise CatalogError("Search page or query is out of range")
            providers = {
                "wallhaven": wallhaven_search,
                "motionbgs": motionbgs_search,
                "moewalls": moewalls_search,
            }
            items, has_more = providers[arguments.provider](
                arguments.query.strip(), arguments.page
            )
            result = {
                "items": items,
                "hasMore": has_more and arguments.page < PAGE_LIMIT,
            }
        else:
            result = local_media(
                arguments.provider,
                arguments.identifier,
                arguments.page_url,
                arguments.command == "preview",
            )
    except CatalogError as error:
        print(error, file=sys.stderr)
        return 1
    except HTTPError as error:
        print(f"Provider returned HTTP {error.code}", file=sys.stderr)
        return 1
    except (URLError, TimeoutError):
        print("Could not reach the wallpaper provider", file=sys.stderr)
        return 1
    except OSError:
        print("Could not read or write wallpaper data", file=sys.stderr)
        return 1
    except (ValueError, TypeError, KeyError):
        print("Provider returned unexpected wallpaper data", file=sys.stderr)
        return 1
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
