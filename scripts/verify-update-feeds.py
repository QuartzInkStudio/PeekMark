#!/usr/bin/env python3
"""Validate edition feeds and keep legacy clients on their last safe release."""
import argparse
import hashlib
from pathlib import Path
import plistlib
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
LEGACY_SHA256 = "5e69b5bdc75291fa7b5755f34e35b13cf4e05ea986c7bc7a94201332f26db78d"
FEEDS = {edition: f"https://peekmark.app/{edition}/appcast.xml"
         for edition in ("community", "direct")}


def validate_feeds(root):
    legacy = (root / "docs/appcast.xml").read_bytes()
    if hashlib.sha256(legacy).hexdigest() != LEGACY_SHA256:
        raise ValueError("Legacy appcast must remain frozen. Old Direct and Community clients share it.")
    for edition, url in FEEDS.items():
        channel = ET.parse(root / "docs" / edition / "appcast.xml").getroot().find("channel")
        if channel is None or channel.findtext("link") != url:
            raise ValueError(f"Incorrect {edition} feed identity")
        for item in channel.findall("item"):
            enclosure = item.find("enclosure")
            if enclosure is None or not enclosure.get("url", "").startswith("https://"):
                raise ValueError(f"Missing HTTPS enclosure in {edition} feed")
            if not enclosure.get("{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature"):
                raise ValueError(f"Missing Sparkle signature in {edition} feed")


def validate_app(app, edition):
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info.get("SUFeedURL") != FEEDS[edition] or info.get("PeekMarkDistribution") != edition:
        raise ValueError(f"App does not identify the {edition} update channel")
    if info.get("CFBundleIdentifier") != "app.peekmark.PeekMark":
        raise ValueError("Migration must preserve the existing bundle identifier")
    if edition == "community" and (app / "Contents/Resources/QuickMarkExtensionBootstrap.plist").exists():
        raise ValueError("Community archive contains official extension bootstrap")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path)
    parser.add_argument("--edition", choices=FEEDS)
    args = parser.parse_args()
    if bool(args.app) != bool(args.edition):
        parser.error("--app and --edition must be provided together")
    validate_feeds(ROOT)
    if args.app:
        validate_app(args.app, args.edition)
    print("Update feed isolation verified; legacy feed unchanged.")


if __name__ == "__main__":
    main()
