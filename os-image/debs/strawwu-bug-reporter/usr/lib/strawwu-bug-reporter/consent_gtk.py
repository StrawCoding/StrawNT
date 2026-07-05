"""GTK consent dialog for StrawWU bug reporting."""

from __future__ import annotations

import sys
from pathlib import Path

try:
    import gi

    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk  # type: ignore[import-untyped]
except ImportError:
    Gtk = None  # type: ignore[misc, assignment]

from bundle import create_bundle, validate_bundle


COLLECTION_ITEMS = (
    "StrawWU VERSION 與 kernel 資訊",
    "最近 24 小時 journal（已過濾敏感內容）",
    "dmesg 與 lsblk 摘要",
    "/var/log/strawwu/*.log（若存在）",
    "App Registry 摘要（不含 /home 檔案）",
)


def run_consent_dialog() -> int:
    if Gtk is None:
        print("ERROR: GTK3 (python3-gi) not available", file=sys.stderr)
        return 1

    result = {"bundle": None, "upload": False, "notes": ""}

    dialog = Gtk.Dialog(title="StrawWU 問題回報", modal=True)
    dialog.set_default_size(520, 420)
    dialog.set_border_width(12)

    content = dialog.get_content_area()
    content.set_spacing(8)

    intro = Gtk.Label(
        label=(
            "建立本地診斷 bundle（.strawwu-bug）。\n"
            "預設僅儲存於本機，不會自動上傳。"
        ),
        xalign=0,
        wrap=True,
    )
    content.pack_start(intro, False, False, 0)

    list_box = Gtk.ListBox()
    list_box.set_selection_mode(Gtk.SelectionMode.NONE)
    for item in COLLECTION_ITEMS:
        row = Gtk.ListBoxRow()
        row.add(Gtk.Label(label=f"• {item}", xalign=0))
        list_box.add(row)
    content.pack_start(list_box, False, False, 0)

    notes_label = Gtk.Label(label="問題描述（選填）：", xalign=0)
    content.pack_start(notes_label, False, False, 0)
    notes_entry = Gtk.TextView()
    notes_entry.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
    notes_entry.set_size_request(-1, 80)
    scrolled = Gtk.ScrolledWindow()
    scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
    scrolled.add(notes_entry)
    content.pack_start(scrolled, True, True, 0)

    upload_check = Gtk.CheckButton(
        label="我同意將此 bundle 上傳至 StrawWU（需另行設定端點；預設關閉）",
    )
    upload_check.set_active(False)
    content.pack_start(upload_check, False, False, 0)

    dialog.add_button("取消", Gtk.ResponseType.CANCEL)
    dialog.add_button("建立 bundle", Gtk.ResponseType.OK)

    dialog.show_all()
    response = dialog.run()

    if response == Gtk.ResponseType.OK:
        buf = notes_entry.get_buffer()
        start, end = buf.get_bounds()
        result["notes"] = buf.get_text(start, end, False).strip()
        result["upload"] = upload_check.get_active()

        out = Path.home() / "strawwu-report.strawwu-bug"
        try:
            path = create_bundle(
                out,
                notes=result["notes"],
                upload_consent=result["upload"],
            )
            errors = validate_bundle(path)
            if errors:
                _show_error("\n".join(errors))
                dialog.destroy()
                return 1
            msg = f"已建立：{path}"
            if result["upload"]:
                msg += "\n\n上傳同意已記錄；遠端端點將於後續版本設定。"
            _show_info(msg)
            result["bundle"] = path
        except OSError as exc:
            _show_error(str(exc))
            dialog.destroy()
            return 1

    dialog.destroy()
    return 0 if result["bundle"] else 1


def _show_info(message: str) -> None:
    if Gtk is None:
        return
    dlg = Gtk.MessageDialog(
        message_type=Gtk.MessageType.INFO,
        buttons=Gtk.ButtonsType.OK,
        text="StrawWU 問題回報",
        secondary_text=message,
    )
    dlg.run()
    dlg.destroy()


def _show_error(message: str) -> None:
    if Gtk is None:
        print(message, file=sys.stderr)
        return
    dlg = Gtk.MessageDialog(
        message_type=Gtk.MessageType.ERROR,
        buttons=Gtk.ButtonsType.OK,
        text="建立 bundle 失敗",
        secondary_text=message,
    )
    dlg.run()
    dlg.destroy()
