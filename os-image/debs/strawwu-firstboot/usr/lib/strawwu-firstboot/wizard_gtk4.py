"""GTK4 + libadwaita six-step first-boot wizard."""

from __future__ import annotations

import subprocess
import webbrowser
from pathlib import Path
from typing import Any

try:
    import gi

    gi.require_version("Gtk", "4.0")
    gi.require_version("Adw", "1")
    from gi.repository import Adw, GLib, Gtk  # type: ignore[import-untyped]
except ImportError as exc:
    raise ImportError("python3-gi with GTK4 and libadwaita is required") from exc

from core import load_manifest
from i18n import load_catalog, t


class FirstbootApp(Adw.Application):
    def __init__(self, prefs: dict[str, Any], steps: list[str]) -> None:
        super().__init__(application_id="xyz.wastebase.StrawWUFirstboot")
        self.prefs = dict(prefs)
        self.steps = steps
        self.catalog = load_catalog(str(self.prefs.get("locale", "zh_TW.UTF-8")))
        self.win: Adw.ApplicationWindow | None = None
        self.assistant: Adw.Assistant | None = None
        self.locale_combo: Gtk.ComboBoxText | None = None
        self.bug_opt_in: Gtk.CheckButton | None = None
        self.analytics_opt_in: Gtk.CheckButton | None = None

    def do_activate(self) -> None:
        self.win = Adw.ApplicationWindow(application=self, title=t(self.catalog, "app_title"))
        self.win.set_default_size(640, 480)
        self.assistant = Adw.Assistant()
        self.assistant.connect("close", self._on_close)
        self.assistant.connect("cancel", self._on_cancel)

        builders = {
            "welcome": self._page_welcome,
            "language": self._page_language,
            "privacy": self._page_privacy,
            "flathub": self._page_flathub,
            "desktop": self._page_desktop,
            "finish": self._page_finish,
        }
        for step_id in self.steps:
            builder = builders.get(step_id)
            if builder:
                self.assistant.append(builder())

        self.win.set_content(self.assistant)
        self.win.present()

    def _page_shell(self, step_id: str, title_key: str, body_key: str) -> Adw.AssistantPage:
        page = Adw.AssistantPage()
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        box.set_margin_top(24)
        box.set_margin_bottom(24)
        box.set_margin_start(24)
        box.set_margin_end(24)

        title = Gtk.Label(label=t(self.catalog, title_key), xalign=0)
        title.add_css_class("title-1")
        title.set_wrap(True)
        box.append(title)

        body = Gtk.Label(label=t(self.catalog, body_key), xalign=0, wrap=True)
        body.add_css_class("body")
        box.append(body)

        page.set_child(box)
        page.set_title(t(self.catalog, title_key))
        page.set_name(step_id)
        return page

    def _page_welcome(self) -> Adw.AssistantPage:
        return self._page_shell("welcome", "step_welcome_title", "step_welcome_body")

    def _page_language(self) -> Adw.AssistantPage:
        page = self._page_shell("language", "step_language_title", "step_language_body")
        box = page.get_child()
        assert isinstance(box, Gtk.Box)

        self.locale_combo = Gtk.ComboBoxText()
        self.locale_combo.append("zh_TW.UTF-8", t(self.catalog, "locale_zh_tw"))
        self.locale_combo.append("en_US.UTF-8", t(self.catalog, "locale_en_us"))
        current = str(self.prefs.get("locale", "zh_TW.UTF-8"))
        self.locale_combo.set_active_id(current)
        self.locale_combo.connect("changed", self._on_locale_changed)
        box.append(self.locale_combo)
        return page

    def _on_locale_changed(self, combo: Gtk.ComboBoxText) -> None:
        locale_id = combo.get_active_id()
        if locale_id:
            self.prefs["locale"] = locale_id
            self.catalog = load_catalog(locale_id)

    def _page_privacy(self) -> Adw.AssistantPage:
        page = self._page_shell("privacy", "step_privacy_title", "step_privacy_body")
        box = page.get_child()
        assert isinstance(box, Gtk.Box)

        manifest = load_manifest()
        legal = manifest.get("legal", {}) if isinstance(manifest.get("legal"), dict) else {}

        links = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        for key, label_key in (("privacy", "link_privacy"), ("eula", "link_eula")):
            path = legal.get(key)
            if path:
                btn = Gtk.Button(label=t(self.catalog, label_key))
                btn.connect("clicked", self._open_legal, str(path))
                links.append(btn)
        box.append(links)

        self.bug_opt_in = Gtk.CheckButton(label=t(self.catalog, "opt_bug_upload"))
        self.bug_opt_in.set_active(bool(self.prefs.get("bug_upload_opt_in", False)))
        box.append(self.bug_opt_in)

        self.analytics_opt_in = Gtk.CheckButton(label=t(self.catalog, "opt_analytics"))
        self.analytics_opt_in.set_active(bool(self.prefs.get("analytics_opt_in", False)))
        box.append(self.analytics_opt_in)
        return page

    def _open_legal(self, _btn: Gtk.Button, path: str) -> None:
        uri = Path(path).as_uri()
        try:
            subprocess.run(["xdg-open", path], check=False)
        except OSError:
            webbrowser.open(uri)

    def _page_flathub(self) -> Adw.AssistantPage:
        return self._page_shell("flathub", "step_flathub_title", "step_flathub_body")

    def _page_desktop(self) -> Adw.AssistantPage:
        return self._page_shell("desktop", "step_desktop_title", "step_desktop_body")

    def _page_finish(self) -> Adw.AssistantPage:
        return self._page_shell("finish", "step_finish_title", "step_finish_body")

    def _collect_prefs(self) -> dict[str, Any]:
        if self.locale_combo:
            locale_id = self.locale_combo.get_active_id()
            if locale_id:
                self.prefs["locale"] = locale_id
        if self.bug_opt_in:
            self.prefs["bug_upload_opt_in"] = self.bug_opt_in.get_active()
        if self.analytics_opt_in:
            self.prefs["analytics_opt_in"] = self.analytics_opt_in.get_active()
        self.prefs["completed_steps"] = list(self.steps)
        return self.prefs

    def _on_close(self, _assistant: Adw.Assistant) -> None:
        self._result = self._collect_prefs()
        if self.win:
            self.win.close()

    def _on_cancel(self, _assistant: Adw.Assistant) -> None:
        self._result = None
        if self.win:
            self.win.close()


def run_wizard_ui(prefs: dict[str, Any], steps: list[str]) -> dict[str, Any] | None:
    app = FirstbootApp(prefs, steps)
    app._result = None  # noqa: SLF001
    app.run(None)
    return app._result  # noqa: SLF001
