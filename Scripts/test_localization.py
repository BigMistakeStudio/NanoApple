# SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
# SPDX-License-Identifier: GPL-3.0-only

"""Check translation coverage and printf argument compatibility."""

from collections import Counter
import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "NanoApple/Resources/Localizable.xcstrings"
FORMAT = re.compile(r"%(?:(\d+)\$)?[-+ #0]*(?:\d+)?(?:\.\d+)?(lld|llu|ld|lu|d|u|f|@)")


def arguments(value):
    result = Counter()
    index = 1
    for match in FORMAT.finditer(value.replace("%%", "")):
        position, kind = match.groups()
        result[(int(position) if position else index, kind)] += 1
        index += 1
    return result


class LocalizationChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = json.loads(CATALOG.read_text())

    def test_every_catalog_entry_has_english(self):
        self.assertEqual(self.catalog["sourceLanguage"], "fr")
        for key, item in self.catalog["strings"].items():
            with self.subTest(key=key):
                unit = item.get("localizations", {}).get("en", {}).get("stringUnit", {})
                self.assertEqual(unit.get("state"), "translated")
                self.assertTrue(unit.get("value"))

    def test_format_arguments_are_preserved(self):
        for key, item in self.catalog["strings"].items():
            with self.subTest(key=key):
                localizations = item.get("localizations", {})
                french = localizations.get("fr", {}).get("stringUnit", {}).get("value", key)
                english = localizations.get("en", {}).get("stringUnit", {}).get("value", "")
                self.assertEqual(arguments(french), arguments(english))

    def test_explicit_swift_lookups_have_english(self):
        for path in (ROOT / "NanoApple").rglob("*.swift"):
            for key in re.findall(r'String\(\s*localized:\s*"([^"\n]+)"', path.read_text()):
                with self.subTest(file=str(path.relative_to(ROOT)), key=key):
                    self.assertIn("en", self.catalog["strings"][key]["localizations"])


if __name__ == "__main__":
    unittest.main()
