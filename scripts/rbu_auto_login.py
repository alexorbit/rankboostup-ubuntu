#!/usr/bin/env python3
"""Automate RankBoostup login via Chrome DevTools Protocol.

This helper connects to a headless Chrome instance, fills the login form
using the provided credentials and exits once an authenticated session is
established. The browser profile used by the Chrome instance will then
contain the required cookies for subsequent launches.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import select
import socket
import ssl
import struct
import sys
import time
import urllib.parse
import urllib.request
from typing import Any, Callable, Dict, Optional


class WebSocketError(RuntimeError):
    pass


class TimeoutError(RuntimeError):
    pass


class WebSocketClient:
    def __init__(self, url: str, timeout: float) -> None:
        self._url = url
        self._timeout = timeout
        self._sock: Optional[socket.socket] = None
        self._buffer = bytearray()
        self._connect()

    def _connect(self) -> None:
        parsed = urllib.parse.urlparse(self._url)
        if parsed.scheme not in {"ws", "wss"}:
            raise WebSocketError(f"Unsupported WebSocket scheme: {parsed.scheme}")

        host = parsed.hostname or "127.0.0.1"
        port = parsed.port or (443 if parsed.scheme == "wss" else 80)
        path = parsed.path or "/"
        if parsed.query:
            path += f"?{parsed.query}"

        raw_sock = socket.create_connection((host, port), timeout=self._timeout)
        if parsed.scheme == "wss":
            context = ssl.create_default_context()
            raw_sock = context.wrap_socket(raw_sock, server_hostname=host)

        key = base64.b64encode(os.urandom(16)).decode("ascii")
        headers = (
            f"GET {path} HTTP/1.1\r\n"
            f"Host: {host}:{port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n"
        )
        raw_sock.sendall(headers.encode("ascii"))

        response = bytearray()
        start = time.time()
        while b"\r\n\r\n" not in response:
            remaining = self._timeout - (time.time() - start)
            if remaining <= 0:
                raise TimeoutError("Timed out waiting for WebSocket handshake")
            ready, _, _ = select.select([raw_sock], [], [], remaining)
            if not ready:
                raise TimeoutError("Timed out waiting for WebSocket handshake")
            chunk = raw_sock.recv(4096)
            if not chunk:
                raise WebSocketError("Connection closed during handshake")
            response.extend(chunk)

        header, _, leftover = response.partition(b"\r\n\r\n")
        if b" 101 " not in header:
            raise WebSocketError(
                "Unexpected handshake response: " + header.decode("latin1", "replace")
            )

        self._sock = raw_sock
        self._buffer = bytearray(leftover)

    def close(self) -> None:
        if self._sock is None:
            return
        try:
            self._send_frame(0x8, b"\x03\xe8")
        except Exception:
            pass
        try:
            self._sock.close()
        finally:
            self._sock = None
            self._buffer.clear()

    def _recv_exact(self, size: int, timeout: Optional[float]) -> bytes:
        if size == 0:
            return b""
        data = bytearray()
        if self._buffer:
            take = min(size, len(self._buffer))
            data.extend(self._buffer[:take])
            del self._buffer[:take]
            size -= take
            if size == 0:
                return bytes(data)

        start = time.time()
        assert self._sock is not None
        while size > 0:
            remaining = None if timeout is None else timeout - (time.time() - start)
            if remaining is not None and remaining <= 0:
                raise TimeoutError("Timed out waiting for data")
            self._sock.settimeout(remaining)
            chunk = self._sock.recv(size)
            if not chunk:
                raise WebSocketError("Connection closed unexpectedly")
            data.extend(chunk)
            size -= len(chunk)
        return bytes(data)

    def _read_frame(self, timeout: Optional[float]) -> tuple[int, bytes]:
        header = self._recv_exact(2, timeout)
        first, second = header
        opcode = first & 0x0F
        masked = (second & 0x80) != 0
        length = second & 0x7F

        if length == 126:
            length_bytes = self._recv_exact(2, timeout)
            (length,) = struct.unpack("!H", length_bytes)
        elif length == 127:
            length_bytes = self._recv_exact(8, timeout)
            (length,) = struct.unpack("!Q", length_bytes)

        mask = b""
        if masked:
            mask = self._recv_exact(4, timeout)

        payload = self._recv_exact(length, timeout)
        if masked:
            payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        return opcode, payload

    def _send_frame(self, opcode: int, payload: bytes) -> None:
        assert self._sock is not None
        fin_opcode = 0x80 | (opcode & 0x0F)
        frame = bytearray([fin_opcode])
        mask_bit = 0x80
        length = len(payload)
        if length < 126:
            frame.append(mask_bit | length)
        elif length < (1 << 16):
            frame.append(mask_bit | 126)
            frame.extend(struct.pack("!H", length))
        else:
            frame.append(mask_bit | 127)
            frame.extend(struct.pack("!Q", length))
        mask = os.urandom(4)
        frame.extend(mask)
        masked_payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        frame.extend(masked_payload)
        self._sock.sendall(frame)

    def send_text(self, text: str) -> None:
        self._send_frame(0x1, text.encode("utf-8"))

    def recv_text(self, timeout: Optional[float]) -> Optional[str]:
        deadline = None if timeout is None else time.time() + timeout
        while True:
            remaining = None if deadline is None else max(0, deadline - time.time())
            opcode, payload = self._read_frame(remaining)
            if opcode == 0x8:
                return None
            if opcode == 0x9:  # ping
                self._send_frame(0xA, payload)
                continue
            if opcode == 0xA:  # pong
                continue
            if opcode == 0x1:
                return payload.decode("utf-8")


class DevToolsClient:
    def __init__(self, ws_url: str, timeout: float) -> None:
        self._ws = WebSocketClient(ws_url, timeout)
        self._timeout = timeout
        self._next_id = 1
        self._pending_events: list[Dict[str, Any]] = []

    def close(self) -> None:
        self._ws.close()

    def _receive(self, timeout: Optional[float]) -> Optional[Dict[str, Any]]:
        raw = self._ws.recv_text(timeout)
        if raw is None:
            return None
        try:
            return json.loads(raw)
        except json.JSONDecodeError as exc:
            raise WebSocketError(f"Invalid JSON from DevTools: {exc}") from exc

    def send(self, method: str, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        message_id = self._next_id
        self._next_id += 1
        payload = {"id": message_id, "method": method}
        if params:
            payload["params"] = params
        self._ws.send_text(json.dumps(payload))

        deadline = time.time() + self._timeout
        while True:
            remaining = max(0, deadline - time.time())
            message = self._receive(remaining)
            if message is None:
                raise WebSocketError("Connection closed while waiting for response")
            if "id" in message:
                if message["id"] == message_id:
                    if "error" in message:
                        raise WebSocketError(json.dumps(message["error"]))
                    return message.get("result", {})
                else:
                    self._pending_events.append(message)
            else:
                self._pending_events.append(message)
            if remaining <= 0:
                raise TimeoutError(f"Timed out waiting for response to {method}")

    def poll_event(self, method: str, timeout: float) -> Optional[Dict[str, Any]]:
        deadline = time.time() + timeout
        while True:
            for idx, evt in enumerate(self._pending_events):
                if evt.get("method") == method:
                    return self._pending_events.pop(idx)
            remaining = deadline - time.time()
            if remaining <= 0:
                return None
            message = self._receive(remaining)
            if message is None:
                return None
            if "id" in message:
                self._pending_events.append(message)
            else:
                self._pending_events.append(message)


def wait_for(condition: Callable[[], Any], timeout: float, interval: float = 0.5) -> Any:
    deadline = time.time() + timeout
    last_exception: Optional[BaseException] = None
    while time.time() < deadline:
        try:
            value = condition()
            if value:
                return value
        except Exception as exc:  # pylint: disable=broad-except
            last_exception = exc
        time.sleep(interval)
    if last_exception:
        raise last_exception
    return None


def fetch_json(url: str, timeout: float) -> Any:
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=timeout) as response:  # type: ignore[arg-type]
        return json.load(response)


def find_page_ws(port: int, timeout: float) -> str:
    deadline = time.time() + timeout
    url = f"http://127.0.0.1:{port}/json/list"
    while time.time() < deadline:
        try:
            pages = fetch_json(url, timeout=2)
        except Exception:
            time.sleep(0.2)
            continue
        for page in pages:
            if page.get("type") == "page" and page.get("webSocketDebuggerUrl"):
                return page["webSocketDebuggerUrl"]
        time.sleep(0.2)
    raise TimeoutError("Timed out waiting for page target")


def find_browser_ws(port: int, timeout: float) -> Optional[str]:
    try:
        version = fetch_json(f"http://127.0.0.1:{port}/json/version", timeout=timeout)
    except Exception:
        return None
    return version.get("webSocketDebuggerUrl")


def evaluate_js(devtools: DevToolsClient, expression: str) -> Any:
    result = devtools.send(
        "Runtime.evaluate",
        {
            "expression": expression,
            "returnByValue": True,
            "awaitPromise": False,
            "userGesture": True,
        },
    )
    if "exceptionDetails" in result:
        details = result["exceptionDetails"]
        exception = details.get("exception", {})
        text = exception.get("description") or exception.get("value") or details.get("text")
        if not text:
            text = json.dumps(details, ensure_ascii=False)
        raise WebSocketError(f"JavaScript evaluation failed: {text}")
    value = result.get("result", {})
    return value.get("value") if "value" in value else value.get("description")


def ensure_runtime_ready(devtools: DevToolsClient, timeout: float) -> None:
    def _ready() -> bool:
        try:
            state = evaluate_js(devtools, "document.readyState")
        except WebSocketError:
            return False
        return state in ("interactive", "complete")

    wait_for(_ready, timeout)


def perform_login(devtools: DevToolsClient, email: str, password: str, timeout: float) -> str:
    def has_session() -> bool:
        try:
            cookie_state = evaluate_js(devtools, "document.cookie || ''") or ""
            path = evaluate_js(devtools, "location.pathname || ''") or ""
            return "sessionid=" in cookie_state or path.startswith("/dashboard")
        except WebSocketError:
            return False

    if has_session():
        return "already-authenticated"

    if not wait_for(
        lambda: evaluate_js(
            devtools,
            "Boolean(document.querySelector('form.form-signin')) || location.pathname.indexOf('/dashboard') === 0",
        ),
        timeout=timeout,
        interval=0.5,
    ):
        return "missing-login-form"

    if has_session():
        return "already-authenticated"

    fill_result = evaluate_js(
        devtools,
        (
            "(() => {"
            "  const form = document.querySelector('form.form-signin');"
            "  if (!form) return 'no-form';"
            "  if (!window.Ladda) {"
            "    window.Ladda = { create: () => ({ start() {}, stop() {} }) };"
            "  }"
            "  const userInput = form.querySelector(\"input[name='username']\") || form.querySelector('#username');"
            "  const passwordInput = form.querySelector(\"input[name='password']\") || form.querySelector(\"input[type='password']\");"
            "  if (!userInput || !passwordInput) return 'missing-fields';"
            f"  userInput.focus(); userInput.value = {json.dumps(email)};"
            "  userInput.dispatchEvent(new Event('input', { bubbles: true }));"
            f"  passwordInput.focus(); passwordInput.value = {json.dumps(password)};"
            "  passwordInput.dispatchEvent(new Event('input', { bubbles: true }));"
            "  const submit = form.querySelector(\"button[type='submit']\") || form.querySelector('button');"
            "  if (typeof form.submit === 'function') {"
            "    form.submit();"
            "  } else if (typeof form.requestSubmit === 'function') {"
            "    if (submit) { form.requestSubmit(submit); } else { form.requestSubmit(); }"
            "  } else if (submit && typeof submit.click === 'function') {"
            "    submit.click();"
            "  } else {"
            "    return 'no-submit';"
            "  }"
            "  return 'submitted';"
            "})()"
        ),
    )

    if fill_result not in {"submitted", "already-authenticated"}:
        return f"form-error:{fill_result}"

    def wait_for_session() -> bool:
        try:
            cookies = evaluate_js(devtools, "document.cookie || ''") or ""
            path = evaluate_js(devtools, "location.pathname || ''") or ""
            if "sessionid=" in cookies:
                return True
            if path.startswith("/dashboard"):
                return True
            error_text = evaluate_js(
                devtools,
                "(() => { const el = document.querySelector('.alert, .alert-danger, .errorlist');"
                " return el ? el.innerText : ''; })()",
            )
            if error_text and any(word in error_text.lower() for word in ("invalid", "incorrect")):
                raise WebSocketError(error_text)
            return False
        except WebSocketError as exc:
            raise exc
        except Exception:
            return False

    if wait_for(wait_for_session, timeout=timeout, interval=0.5):
        return "success"

    error_hint = evaluate_js(
        devtools,
        "(() => { const el = document.querySelector('.alert, .alert-danger, .errorlist');"
        " return el ? el.innerText : ''; })()",
    ) or "unknown"
    return f"timeout:{error_hint.strip()}"


def main() -> int:
    parser = argparse.ArgumentParser(description="RankBoostup headless auto-login helper")
    parser.add_argument("--port", type=int, required=True, help="Remote debugging port exposed by Chrome")
    parser.add_argument("--email", required=True, help="RankBoostup login email/username")
    parser.add_argument("--password", required=True, help="RankBoostup login password")
    parser.add_argument("--timeout", type=float, default=45.0, help="Maximum time in seconds to wait for login")
    args = parser.parse_args()

    try:
        page_ws = find_page_ws(args.port, timeout=args.timeout)
    except TimeoutError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    devtools = DevToolsClient(page_ws, timeout=args.timeout)
    try:
        devtools.send("Runtime.enable")
        devtools.send("Page.enable")
        ensure_runtime_ready(devtools, timeout=min(10.0, args.timeout))
        status = perform_login(devtools, args.email, args.password, timeout=args.timeout)
        if status == "success":
            print("Automatic login completed successfully.")
        elif status == "already-authenticated":
            print("Chrome profile already contains an authenticated RankBoostup session.")
        else:
            print(f"ERROR: Automatic login failed ({status}).", file=sys.stderr)
            return 3
    finally:
        devtools.close()

    browser_ws = find_browser_ws(args.port, timeout=5.0)
    if browser_ws:
        try:
            browser_client = DevToolsClient(browser_ws, timeout=5.0)
            try:
                browser_client.send("Browser.close")
            finally:
                browser_client.close()
        except Exception:
            pass

    return 0


if __name__ == "__main__":
    sys.exit(main())
