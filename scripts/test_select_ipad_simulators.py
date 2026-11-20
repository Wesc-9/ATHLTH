#!/usr/bin/env python3
"""Fixture-based regression checks independent of macOS / xcrun."""
from __future__ import annotations

import unittest

from select_ipad_simulators import matches_size, runtime_version, select_registered_device

IOS_270 = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
IOS_272 = "com.apple.CoreSimulator.SimRuntime.iOS-27-2"
WATCHOS = "com.apple.CoreSimulator.SimRuntime.watchOS-27-0"


def device(name: str, udid: str, state: str = "Shutdown", available: bool = True) -> dict:
    return {"name": name, "udid": udid, "state": state, "isAvailable": available}


class RegisteredIPadSelectionTests(unittest.TestCase):
    def test_names_by_screen_size(self):
        self.assertTrue(matches_size("iPad Pro 11-inch (M4)", 11))
        self.assertTrue(matches_size("iPad (A16)", 11))
        self.assertFalse(matches_size("iPad Pro 13-inch (M4)", 11))
        self.assertTrue(matches_size("iPad Air 13-inch (M2)", 13))
        self.assertFalse(matches_size("iPhone 18 Pro Max", 13))

    def test_prefers_booted_registered_ipad(self):
        payload = {"devices": {IOS_272: [device("iPad Pro 11-inch (M4)", "a")],
                               IOS_270: [device("iPad Air 11-inch (M2)", "b", "Booted")]}}
        self.assertEqual(select_registered_device(payload, 11)["udid"], "b")

    def test_uses_latest_runtime_when_equally_ready(self):
        payload = {"devices": {IOS_272: [device("iPad Pro 11-inch (M4)", "a")],
                               IOS_270: [device("iPad Pro 11-inch (M4)", "b")]}}
        self.assertEqual(select_registered_device(payload, 11)["udid"], "a")

    def test_ignores_unavailable_watch_and_iphone(self):
        payload = {"devices": {WATCHOS: [device("iPad Pro 11-inch (M4)", "w", "Booted")],
                               IOS_270: [device("iPhone 18 Pro", "i", "Booted"),
                                         device("iPad Pro 11-inch (M4)", "u", available=False)]}}
        self.assertIsNone(select_registered_device(payload, 11))

    def test_ignores_creation_or_shutdown_in_progress(self):
        payload = {"devices": {IOS_270: [device("iPad Pro 13-inch (M4)", "a", "Creating"),
                                         device("iPad Pro 13-inch (M4)", "b", "Shutdown")]}}
        self.assertEqual(select_registered_device(payload, 13)["udid"], "b")

    def test_runtime_filter(self):
        self.assertEqual(runtime_version(IOS_272), (27, 2))
        self.assertIsNone(runtime_version(WATCHOS))
        self.assertIsNone(runtime_version("com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4"))


if __name__ == "__main__":
    unittest.main()
