"""The documentation must not drift from the launcher: links resolve, commands and settings exist."""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PAGES = [ROOT / "README.md", *sorted((ROOT / "docs").glob("*.md"))]
# Set by the launcher for a custom viewer command, not something a user configures.
NOT_SETTINGS = {"ROUVY_SCREEN_URL"}


def read(path):
    return Path(path).read_text(encoding="utf-8")


def anchors(page):
    """Heading anchors the way GitHub derives them."""
    found = set()
    for heading in re.findall(r"^#+ +(.+?) *$", read(page), re.M):
        text = re.sub(r"[^\w\- ]", "", heading.lower().replace("`", ""))
        found.add(text.replace(" ", "-"))
    return found


def launcher_commands():
    main = read(ROOT / "rouvy").split("\nmain() {", 1)[1].split("\n}\n", 1)[0]
    arms = re.findall(r"^    ([a-z_| \-]+)\)", main, re.M)
    return {name.strip() for arm in arms for name in arm.split("|")}


class Docs(unittest.TestCase):
    def test_relative_links_resolve(self):
        for page in PAGES:
            for target in re.findall(r"\]\(([^)\s]+)\)", read(page)):
                if re.match(r"[a-z]+:", target):
                    continue
                path, _, anchor = target.partition("#")
                dest = (page.parent / path).resolve() if path else page
                with self.subTest(page=page.name, link=target):
                    self.assertTrue(dest.exists(), "file does not exist")
                    if anchor:
                        self.assertIn(anchor, anchors(dest))

    def test_every_page_is_linked_from_the_readme(self):
        readme = read(ROOT / "README.md")
        for page in PAGES[1:]:
            self.assertIn(f"(docs/{page.name})", readme)

    def test_settings_table_matches_the_example_file(self):
        in_example = set(re.findall(r"^#(ROUVY_[A-Z_]+)=", read(ROOT / "rouvy.conf.example"), re.M))
        table = read(ROOT / "docs" / "commands.md").split("## Settings", 1)[1].split("\n## ", 1)[0]
        in_table = set(re.findall(r"`(ROUVY_[A-Z_]+)`", table)) - NOT_SETTINGS
        self.assertEqual(in_example, in_table)

    def test_documented_settings_are_read_by_the_launcher_or_compose(self):
        code = read(ROOT / "rouvy") + read(ROOT / "compose.yaml")
        for page in PAGES:
            for setting in set(re.findall(r"\bROUVY_[A-Z_]+\b", read(page))):
                with self.subTest(page=page.name, setting=setting):
                    self.assertIn(setting, code)

    def test_documented_commands_exist(self):
        known = launcher_commands()
        self.assertIn("start", known)
        for page in PAGES:
            for command in set(re.findall(r"`rouvy ([a-z]+)", read(page))):
                with self.subTest(page=page.name, command=command):
                    self.assertIn(command, known)

    def test_every_command_is_documented(self):
        table = read(ROOT / "docs" / "commands.md")
        for command in launcher_commands() - {"_watch", "help", "-h", "--help"}:
            with self.subTest(command=command):
                self.assertIn(f"`rouvy {command}", table)


if __name__ == "__main__":
    unittest.main()
