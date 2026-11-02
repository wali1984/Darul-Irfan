import unittest

from select_simulator import select_device


class SimulatorSelectionTests(unittest.TestCase):
    def test_selects_requested_family_and_skips_unavailable_devices(self):
        inventory = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-0": [
            {"name": "iPad Pro (11-inch)", "isAvailable": False, "udid": "missing"},
            {"name": "iPhone 17", "isAvailable": True, "udid": "phone"},
            {"name": "iPad Pro (13-inch)", "isAvailable": True, "udid": "tablet"},
        ]}}
        self.assertEqual(select_device(inventory, "iPhone")["udid"], "phone")
        self.assertEqual(select_device(inventory, "iPad")["udid"], "tablet")

    def test_does_not_fall_back_to_phone_when_tablet_is_missing(self):
        inventory = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-0": [
            {"name": "iPhone 17", "isAvailable": True, "udid": "phone"},
        ]}}
        with self.assertRaisesRegex(ValueError, "No available iPad"):
            select_device(inventory, "iPad")

    def test_ignores_non_ios_runtime(self):
        inventory = {"devices": {"com.apple.CoreSimulator.SimRuntime.tvOS-26-0": [
            {"name": "iPad renamed TV", "isAvailable": True, "udid": "tv"},
        ]}}
        with self.assertRaises(ValueError):
            select_device(inventory, "iPad")


if __name__ == "__main__":
    unittest.main()
