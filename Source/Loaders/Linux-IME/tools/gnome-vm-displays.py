#!/usr/bin/env python3
"""Set temporary GNOME Wayland monitor layouts inside the dedicated test guest."""

import argparse
import json
import os
import sys

from gi.repository import Gio, GLib


BUS_NAME = "org.gnome.Mutter.DisplayConfig"
OBJECT_PATH = "/org/gnome/Mutter/DisplayConfig"
INTERFACE = BUS_NAME


def display_call(bus, method, parameters=None):
    return bus.call_sync(BUS_NAME, OBJECT_PATH, INTERFACE, method,
                         parameters, None, Gio.DBusCallFlags.NONE, 10000, None)


def current_state(bus):
    serial, monitors, logical, properties = display_call(bus, "GetCurrentState").unpack()
    return serial, monitors, logical, properties


def mode_for(monitors, connector, width, height):
    for monitor in monitors:
        if monitor[0][0] != connector:
            continue
        for mode in monitor[1]:
            if mode[1:3] == (width, height):
                return monitor[0], mode[0], mode[5]
    raise RuntimeError(f"No {width}x{height} mode for {connector}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("layout", choices=("show", "single", "dual", "dual-mixed"))
    args = parser.parse_args()
    os.environ["DBUS_SESSION_BUS_ADDRESS"] = "unix:path=/run/user/1000/bus"
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    serial, monitors, _, _ = current_state(bus)
    if args.layout != "show":
        first, first_mode, first_scales = mode_for(monitors, "Virtual-1", 1280, 800)
        if 1.0 not in first_scales:
            raise RuntimeError("Virtual-1 lacks 1x scaling")
        logical = [(0, 0, 1.0, 0, True, [(first[0], first_mode, {})])]
        if args.layout != "single":
            second_width, second_height, second_scale = (
                (1920, 1080, 2.0) if args.layout == "dual-mixed"
                else (1024, 768, 1.0))
            second, second_mode, second_scales = mode_for(
                monitors, "Virtual-2", second_width, second_height)
            if second_scale not in second_scales:
                raise RuntimeError(f"Virtual-2 lacks {second_scale}x scaling")
            logical.append((1280, 0, second_scale, 0, False,
                            [(second[0], second_mode, {})]))
        parameters = GLib.Variant("(uua(iiduba(ssa{sv}))a{sv})",
                                  (serial, 1, logical, {}))
        display_call(bus, "ApplyMonitorsConfig", parameters)
        serial, monitors, _, _ = current_state(bus)
    print(json.dumps({"serial": serial,
                      "monitors": [monitor[0][0] for monitor in monitors],
                      "logical": [
                          {"x": item[0], "y": item[1], "scale": item[2],
                           "primary": item[4], "connector": item[5][0][0]}
                          for item in current_state(bus)[2]]}))


if __name__ == "__main__":
    try:
        main()
    except (GLib.Error, RuntimeError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
