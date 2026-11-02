"""Select an available simulator by family; print its unambiguous UDID."""
import argparse
import json
import subprocess
import sys


def select_device(inventory, family):
    for runtime, devices in inventory.get("devices", {}).items():
        if ".iOS-" not in runtime:
            continue
        for device in devices:
            if device.get("isAvailable") and device.get("name", "").startswith(family + " "):
                return device
    raise ValueError(f"No available {family} simulator in the installed iOS runtimes")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--family", choices=("iPhone", "iPad"), default="iPhone")
    args = parser.parse_args()
    inventory = json.loads(subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "--json"], text=True))
    try:
        device = select_device(inventory, args.family)
    except ValueError as error:
        parser.exit(2, str(error) + "\n")
    print(f"Using simulator: {device['name']} ({device['udid']})", file=sys.stderr)
    print(device["udid"])


if __name__ == "__main__":
    main()
