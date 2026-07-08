#!/usr/bin/env bash
# POST-UX: strawwu-gtk-theme + strawwu-icon-theme dark theme curation preflight.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/tests/preflight/lib/common.sh"

GTK_DEB="${REPO_ROOT}/os-image/debs/strawwu-gtk-theme"
ICON_DEB="${REPO_ROOT}/os-image/debs/strawwu-icon-theme"
SESSION_DEB="${REPO_ROOT}/os-image/debs/strawwu-session"
BRANDING="${REPO_ROOT}/os-image/config/branding"
THEMES_DIR="${BRANDING}/themes"
BASELINE="${BASELINES_DIR}/ux-theme-curation-baseline.json"
ACCENT="#14B8A6"
BG="#0A0E14"

echo "=== POST-UX theme curation preflight ==="
require_plan "strawwu-ux-theme-curation-plan.md"
require_plan "strawwu-post-mvp-roadmap.md"
require_file "${PLANS_DIR}/kickoff/POST-UX-theme-curation.md" "kickoff POST-UX"
require_file "${THEMES_DIR}/theme-manifest.yaml" "theme curation manifest"
require_file "${THEMES_DIR}/README.md" "theme curation README"
require_file "${BRANDING}/usr/share/themes/StrawWU-Dark/index.theme" "StrawWU-Dark index.theme"
require_file "${BRANDING}/usr/share/themes/StrawWU-Dark/gtk-3.0/gtk.css" "StrawWU-Dark gtk-3.0"
require_file "${BRANDING}/usr/share/themes/StrawWU-Dark/gtk-4.0/gtk.css" "StrawWU-Dark gtk-4.0"
require_file "${BRANDING}/usr/share/themes/StrawWU-Dark/gnome-shell/gnome-shell.css" "StrawWU-Dark gnome-shell"
require_file "${BRANDING}/source/strawwu-colors.md" "strawwu-colors.md"

if grep -q "${ACCENT}" "${BRANDING}/usr/share/themes/StrawWU-Dark/gtk-3.0/gtk.css"; then
    pass "gtk-3.0 uses Teal accent ${ACCENT}"
else
    fail "gtk-3.0 missing Teal accent ${ACCENT}"
fi

if grep -q "${BG}" "${BRANDING}/usr/share/themes/StrawWU-Dark/gtk-3.0/gtk.css" \
    || grep -q "#0F1318" "${BRANDING}/usr/share/themes/StrawWU-Dark/gtk-3.0/gtk.css"; then
    pass "gtk-3.0 uses deep dark background"
else
    fail "gtk-3.0 missing dark background color"
fi

if grep -q 'resource:///com/ubuntu/themes' "${BRANDING}/usr/share/themes/StrawWU-Dark/gtk-3.0/gtk.css"; then
    fail "gtk-3.0 still uses snap resource:// imports"
else
    pass "gtk-3.0 uses filesystem imports"
fi

OVERRIDE="${BRANDING}/usr/share/glib-2.0/schemas/99_strawwu-branding.gschema.override"
require_file "${OVERRIDE}" "branding gschema override"
if grep -q "gtk-theme='StrawWU-Dark'" "${OVERRIDE}" \
    && grep -q "color-scheme='prefer-dark'" "${OVERRIDE}"; then
    pass "branding gschema sets StrawWU-Dark + prefer-dark"
else
    fail "branding gschema missing dark theme defaults"
fi

# --- strawwu-gtk-theme ---
require_file "${GTK_DEB}/DEBIAN/control" "strawwu-gtk-theme control"
require_file "${GTK_DEB}/build-deb.sh" "strawwu-gtk-theme build-deb.sh"
require_file "${GTK_DEB}/usr/share/strawwu/gtk-theme/gtk-theme-manifest.yaml" "gtk-theme manifest"

if grep -q 'yaru-theme-gtk' "${GTK_DEB}/DEBIAN/control"; then
    pass "gtk-theme depends on yaru-theme-gtk"
else
    fail "gtk-theme missing yaru-theme-gtk dependency"
fi

# --- strawwu-icon-theme ---
require_file "${ICON_DEB}/DEBIAN/control" "strawwu-icon-theme control"
require_file "${ICON_DEB}/build-deb.sh" "strawwu-icon-theme build-deb.sh"
require_file "${ICON_DEB}/usr/share/strawwu/icon-theme/icon-theme-manifest.yaml" "icon-theme manifest"

if grep -q 'yaru-theme-icon' "${ICON_DEB}/DEBIAN/control"; then
    pass "icon-theme depends on yaru-theme-icon"
else
    fail "icon-theme missing yaru-theme-icon dependency"
fi

# --- strawwu-session gsettings ---
SESSION_GSCHEMA="${SESSION_DEB}/usr/share/glib-2.0/schemas/99_strawwu-session.gschema.override"
require_file "${SESSION_GSCHEMA}" "strawwu-session gschema override"
if grep -q "gtk-theme='StrawWU-Dark'" "${SESSION_GSCHEMA}" \
    && grep -q "color-scheme='prefer-dark'" "${SESSION_GSCHEMA}" \
    && grep -q "accent-color='teal'" "${SESSION_GSCHEMA}"; then
    pass "strawwu-session gschema dark defaults"
else
    fail "strawwu-session gschema missing dark defaults"
fi

if grep -q 'strawwu-gtk-theme' "${SESSION_DEB}/debian/control" \
    && grep -q 'strawwu-icon-theme' "${SESSION_DEB}/debian/control"; then
    pass "strawwu-session depends on theme packages"
else
    fail "strawwu-session missing theme package deps"
fi

DESKTOP_CONTROL="${REPO_ROOT}/os-image/debs/strawwu-desktop/debian/control"
if grep -q 'strawwu-gtk-theme' "${DESKTOP_CONTROL}" \
    && grep -q 'strawwu-icon-theme' "${DESKTOP_CONTROL}"; then
    pass "strawwu-desktop recommends theme packages"
else
    fail "strawwu-desktop missing theme package recommends"
fi

TARGET_MANIFEST="${REPO_ROOT}/os-image/debs/strawwu-target-setup/usr/share/strawwu/target-setup/target-manifest.yaml"
for pkg in strawwu-gtk-theme strawwu-icon-theme; do
    if grep -q "${pkg}" "${TARGET_MANIFEST}"; then
        pass "target-manifest includes ${pkg}"
    else
        fail "target-manifest missing ${pkg}"
    fi
done

if grep -q 'strawwu-gtk-theme' "${REPO_ROOT}/os-image/scripts/build-os-debs.sh" \
    && grep -q 'strawwu-icon-theme' "${REPO_ROOT}/os-image/scripts/build-os-debs.sh"; then
    pass "build-os-debs includes theme packages"
else
    fail "build-os-debs missing theme packages"
fi

# --- build deb artifacts ---
for deb_pkg in strawwu-gtk-theme strawwu-icon-theme; do
    deb_dir="${REPO_ROOT}/os-image/debs/${deb_pkg}"
    if [[ -x "${deb_dir}/build-deb.sh" ]]; then
        STRAWWU_VERSION="${VERSION}" bash "${deb_dir}/build-deb.sh" >/dev/null
    fi
    deb_file="$(ls -1 "${deb_dir}/output"/${deb_pkg}_"${VERSION}"_all.deb 2>/dev/null | head -1)"
    if [[ -n "${deb_file}" && -f "${deb_file}" ]]; then
        pass "${deb_pkg} deb artifact"
        listing="$(dpkg-deb -c "${deb_file}" 2>/dev/null || true)"
        case "${deb_pkg}" in
            strawwu-gtk-theme)
                if grep -q 'themes/StrawWU-Dark' <<< "${listing}"; then
                    pass "${deb_pkg} deb contains StrawWU-Dark theme"
                else
                    fail "${deb_pkg} deb missing StrawWU-Dark theme"
                fi
                ;;
            strawwu-icon-theme)
                if grep -q 'distributor-logo' <<< "${listing}"; then
                    pass "${deb_pkg} deb contains distributor-logo"
                else
                    fail "${deb_pkg} deb missing distributor-logo"
                fi
                ;;
        esac
    else
        fail "${deb_pkg} deb artifact missing"
    fi
done

if python3 "${GTK_DEB}/tests/test-gtk-theme.py" -q 2>/dev/null || python3 "${GTK_DEB}/tests/test-gtk-theme.py"; then
    pass "strawwu-gtk-theme python tests"
else
    fail "strawwu-gtk-theme python tests"
fi

if python3 "${ICON_DEB}/tests/test-icon-theme.py" -q 2>/dev/null || python3 "${ICON_DEB}/tests/test-icon-theme.py"; then
    pass "strawwu-icon-theme python tests"
else
    fail "strawwu-icon-theme python tests"
fi

if python3 "${SESSION_DEB}/tests/test-session.py"; then
    pass "strawwu-session unit tests (theme gschema)"
else
    fail "strawwu-session unit tests"
fi

baseline_content="$(STRAWWU_BASELINE_VERSION="${VERSION}" python3 - <<'PY'
import json, os

version = os.environ["STRAWWU_BASELINE_VERSION"]
data = {
    "schema": "strawwu-ux-theme-curation-baseline/v1",
    "stage": "post-ux-theme-curation",
    "version": version,
    "default_mode": "dark",
    "packages": {
        "gtk": "strawwu-gtk-theme",
        "icon": "strawwu-icon-theme",
    },
    "theme": "StrawWU-Dark",
    "icon_theme": "Yaru-prussiangreen-dark",
    "accent": "#14B8A6",
    "background": "#0A0E14",
    "gsettings": {
        "gtk-theme": "StrawWU-Dark",
        "icon-theme": "Yaru-prussiangreen-dark",
        "color-scheme": "prefer-dark",
        "accent-color": "teal",
    },
    "session_gschema": "os-image/debs/strawwu-session/usr/share/glib-2.0/schemas/99_strawwu-session.gschema.override",
    "branding_gschema": "os-image/config/branding/usr/share/glib-2.0/schemas/99_strawwu-branding.gschema.override",
    "theme_manifest": "os-image/config/branding/themes/theme-manifest.yaml",
    "deferred": ["light-theme-variant", "hub-appearance-panel"],
}
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
)"
write_json_if_changed "${BASELINE}" "${baseline_content}"

preflight_exit "POST-UX theme curation"
