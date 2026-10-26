#!/usr/bin/env python3
"""Packs src/ into Roblox files you can open or insert in Studio.

Outputs (in ../build):
  ArenaFPS.rbxlx              full place - File > Open in Studio
  ArenaFPS_Shared.rbxmx       ReplicatedStorage/Shared folder
  ArenaFPS_Server.rbxmx       ServerScriptService/Server script
  ArenaFPS_Client.rbxmx       StarterPlayerScripts/Client local script

File naming follows Rojo conventions:
  init.server.lua -> the folder becomes a Script
  init.client.lua -> the folder becomes a LocalScript
  name.lua        -> ModuleScript
  folder          -> Folder
"""

from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
OUT = ROOT / "build"

HEADER = (
    '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
    'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n'
)

_ref = [0]


def ref():
    _ref[0] += 1
    return f"RBX{_ref[0]:08X}"


def cdata(text):
    if "]]>" in text:
        raise ValueError("source contains ]]> which cannot go in CDATA")
    return f"<![CDATA[{text}]]>"


def item(class_name, name, props="", children="", indent=1):
    pad = "\t" * indent
    return (
        f'{pad}<Item class="{class_name}" referent="{ref()}">\n'
        f"{pad}\t<Properties>\n"
        f'{pad}\t\t<string name="Name">{escape(name)}</string>\n'
        f"{props}"
        f"{pad}\t</Properties>\n"
        f"{children}"
        f"{pad}</Item>\n"
    )


def source_prop(text, indent):
    pad = "\t" * (indent + 2)
    return f'{pad}<ProtectedString name="Source">{cdata(text)}</ProtectedString>\n'


def script_class(filename):
    if filename.endswith(".server.lua"):
        return "Script", filename[: -len(".server.lua")]
    if filename.endswith(".client.lua"):
        return "LocalScript", filename[: -len(".client.lua")]
    if filename.endswith(".lua"):
        return "ModuleScript", filename[: -len(".lua")]
    return None, None


def build_node(path, indent):
    """Returns XML for a file or directory."""
    if path.is_file():
        cls, name = script_class(path.name)
        if not cls:
            return ""
        text = path.read_text(encoding="utf-8")
        return item(cls, name, source_prop(text, indent), "", indent)

    init = None
    for candidate in ("init.server.lua", "init.client.lua", "init.lua"):
        if (path / candidate).exists():
            init = path / candidate
            break

    children = "".join(
        build_node(child, indent + 1)
        for child in sorted(path.iterdir())
        if child != init
    )

    if init:
        cls, _ = script_class(init.name)
        text = init.read_text(encoding="utf-8")
        return item(cls, path.name, source_prop(text, indent), children, indent)
    return item("Folder", path.name, "", children, indent)


def bool_prop(name, value, indent):
    return f'{chr(9) * (indent + 2)}<bool name="{name}">{"true" if value else "false"}</bool>\n'


def token_prop(name, value, indent):
    return f'{chr(9) * (indent + 2)}<token name="{name}">{value}</token>\n'


def build_place():
    services = []

    services.append(item("Workspace", "Workspace", "", "", 1))

    services.append(
        item("Players", "Players", bool_prop("CharacterAutoLoads", False, 1), "", 1)
    )

    services.append(
        item(
            "ReplicatedStorage",
            "ReplicatedStorage",
            "",
            "".join(build_node(p, 2) for p in sorted((SRC / "ReplicatedStorage").iterdir())),
            1,
        )
    )

    services.append(
        item(
            "ServerScriptService",
            "ServerScriptService",
            "",
            "".join(build_node(p, 2) for p in sorted((SRC / "ServerScriptService").iterdir())),
            1,
        )
    )

    player_scripts = item(
        "StarterPlayerScripts",
        "StarterPlayerScripts",
        "",
        "".join(
            build_node(p, 3)
            for p in sorted((SRC / "StarterPlayer" / "StarterPlayerScripts").iterdir())
        ),
        2,
    )
    starter_props = (
        bool_prop("EnableMouseLockOption", False, 1)
        + token_prop("CameraMode", 1, 1)  # LockFirstPerson
    )
    services.append(item("StarterPlayer", "StarterPlayer", starter_props, player_scripts, 1))

    services.append(item("Teams", "Teams", "", "", 1))

    return HEADER + "".join(services) + "</roblox>\n"


def build_model(path):
    return HEADER + build_node(path, 1) + "</roblox>\n"


def main():
    OUT.mkdir(exist_ok=True)
    outputs = {
        "ArenaFPS.rbxlx": build_place(),
        "ArenaFPS_Shared.rbxmx": build_model(SRC / "ReplicatedStorage" / "Shared"),
        "ArenaFPS_Server.rbxmx": build_model(SRC / "ServerScriptService" / "Server"),
        "ArenaFPS_Client.rbxmx": build_model(SRC / "StarterPlayer" / "StarterPlayerScripts" / "Client"),
    }
    for name, content in outputs.items():
        (OUT / name).write_text(content, encoding="utf-8")
        print(f"wrote build/{name} ({len(content):,} bytes)")


if __name__ == "__main__":
    main()
