/* StrawWU built-in dock — cleanroom GJS, no third-party extension API. */
import Clutter from 'gi://Clutter';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

export default class StrawWUDockExtension extends Extension {
    enable() {
        this._dock = new St.BoxLayout({
            name: 'strawwuDock',
            reactive: true,
            track_hover: true,
            vertical: false,
            x_align: Clutter.ActorAlign.CENTER,
            y_align: Clutter.ActorAlign.END,
            style_class: 'strawwu-dock',
        });

        Main.layoutManager.addChrome(this._dock, {
            affectsInputRegion: false,
            trackFullscreen: true,
        });

        this._monitorId = Main.layoutManager.connect('monitors-changed', () => {
            this._positionDock();
        });
        this._positionDock();
    }

    _positionDock() {
        const monitor = Main.layoutManager.primaryMonitor;
        const height = 48;

        this._dock.set({
            width: monitor.width,
            height,
        });
        this._dock.set_position(monitor.x, monitor.y + monitor.height - height);
    }

    disable() {
        if (this._monitorId) {
            Main.layoutManager.disconnect(this._monitorId);
            this._monitorId = null;
        }

        if (this._dock) {
            this._dock.destroy();
            this._dock = null;
        }
    }
}
