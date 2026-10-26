#!/usr/bin/env python3
"""Lightweight Luau sanity checker (no Lua install needed).

Checks every .lua file under the given directory for:
  * unterminated strings / comments
  * unbalanced (), {}, []
  * unbalanced blocks: function/if/for/while/do/repeat vs end/until
  * 'then' / 'do' in the right places
  * C-style operators that Luau does not support (!=, &&, ||)
  * names that are used but never declared anywhere in the file and are not
    known Roblox/Luau globals (catches most typos)

It is not a full parser. It catches structural mistakes, not type errors.
"""

import re
import sys
from pathlib import Path

KEYWORDS = {
    "and", "break", "continue", "do", "else", "elseif", "end", "false", "for",
    "function", "if", "in", "local", "nil", "not", "or", "repeat", "return",
    "then", "true", "until", "while", "export", "type",
}

GLOBALS = {
    "game", "workspace", "script", "plugin", "shared", "_G", "require", "print",
    "warn", "error", "assert", "pcall", "xpcall", "typeof", "type", "tostring",
    "tonumber", "pairs", "ipairs", "next", "select", "unpack", "setmetatable",
    "getmetatable", "rawget", "rawset", "rawequal", "rawlen", "tick", "time",
    "wait", "delay", "spawn", "os", "math", "string", "table", "task",
    "coroutine", "utf8", "bit32", "debug", "buffer", "Vector3", "Vector2",
    "CFrame", "Color3", "BrickColor", "UDim", "UDim2", "Enum", "Instance",
    "Random", "TweenInfo", "NumberSequence", "NumberSequenceKeypoint",
    "ColorSequence", "ColorSequenceKeypoint", "NumberRange", "Ray",
    "RaycastParams", "OverlapParams", "PhysicalProperties", "Rect", "Region3",
    "Faces", "Axes", "DateTime", "Font", "self", "gcinfo", "newproxy",
}

TOKEN_RE = re.compile(
    r"""
    (?P<ws>\s+)
  | (?P<longcomment>--\[(?P<lceq>=*)\[)
  | (?P<comment>--[^\n]*)
  | (?P<longstring>\[(?P<lseq>=*)\[)
  | (?P<string>"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')
  | (?P<badstring>["'])
  | (?P<number>0[xX][0-9a-fA-F_]+|0[bB][01_]+|\d[\d_]*(?:\.[\d_]*)?(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<op>\.\.\.|\.\.=|\.\.|==|~=|<=|>=|\+=|-=|\*=|/=|//=|//|%=|\^=|->|::|!=|&&|\|\||[-+*/%^#<>=(){}\[\];:,.@?|&!~])
    """,
    re.VERBOSE,
)


def tokenize(src, errors):
    tokens = []
    pos = 0
    line = 1
    n = len(src)
    while pos < n:
        m = TOKEN_RE.match(src, pos)
        if not m:
            errors.append(f"line {line}: unexpected character {src[pos]!r}")
            pos += 1
            continue
        kind = m.lastgroup
        text = m.group(0)
        if kind in ("longcomment", "longstring"):
            eq = m.group("lceq") if kind == "longcomment" else m.group("lseq")
            close = "]" + eq + "]"
            end = src.find(close, m.end())
            if end == -1:
                errors.append(f"line {line}: unterminated long {'comment' if kind == 'longcomment' else 'string'}")
                return tokens
            text = src[pos:end + len(close)]
            if kind == "longstring":
                tokens.append(("string", text, line))
            line += text.count("\n")
            pos = end + len(close)
            continue
        if kind == "badstring":
            errors.append(f"line {line}: unterminated string")
            pos = src.find("\n", pos)
            if pos == -1:
                break
            continue
        if kind == "string" and text.startswith(("`",)):
            pass
        if kind not in ("ws", "comment"):
            tokens.append((kind, text, line))
        line += text.count("\n")
        pos = m.end()
    return tokens


def check_interpolated(src, errors):
    # Backtick strings are not used in this project; flag them so the
    # tokenizer's simplifications stay valid.
    for i, l in enumerate(src.split("\n"), 1):
        stripped = l.split("--", 1)[0]
        if "`" in stripped:
            errors.append(f"line {i}: backtick string (unsupported by this checker)")


def check_file(path):
    src = path.read_text(encoding="utf-8")
    errors = []
    check_interpolated(src, errors)
    tokens = tokenize(src, errors)

    # Brackets.
    pairs = {")": "(", "}": "{", "]": "["}
    stack = []
    for kind, text, line in tokens:
        if kind != "op":
            continue
        if text in "({[" and len(text) == 1:
            stack.append((text, line))
        elif text in ")}]" and len(text) == 1:
            if not stack or stack[-1][0] != pairs[text]:
                errors.append(f"line {line}: unmatched {text!r}")
            else:
                stack.pop()
        elif text in ("!=", "&&", "||"):
            errors.append(f"line {line}: '{text}' is not Luau")
    for text, line in stack:
        errors.append(f"line {line}: unclosed {text!r}")

    # Blocks.
    blocks = []
    expect_do = []  # pending 'for'/'while' waiting for their 'do'
    expect_then = 0
    prev = None
    for i, (kind, text, line) in enumerate(tokens):
        if kind != "name":
            prev = (kind, text)
            continue
        is_field = prev is not None and prev[0] == "op" and prev[1] in (".", ":")
        if is_field:
            prev = (kind, text)
            continue
        if text == "function":
            blocks.append(("function", line))
        elif text in ("if",):
            blocks.append(("if", line))
            expect_then += 1
        elif text == "elseif":
            if not blocks or blocks[-1][0] != "if":
                errors.append(f"line {line}: 'elseif' outside if")
            expect_then += 1
        elif text == "then":
            if expect_then <= 0:
                errors.append(f"line {line}: unexpected 'then'")
            else:
                expect_then -= 1
        elif text == "else":
            if not blocks or blocks[-1][0] != "if":
                errors.append(f"line {line}: 'else' outside if")
        elif text in ("for", "while"):
            blocks.append((text, line))
            expect_do.append(text)
        elif text == "do":
            if expect_do:
                expect_do.pop()
            else:
                blocks.append(("do", line))
        elif text == "repeat":
            blocks.append(("repeat", line))
        elif text == "until":
            if not blocks or blocks[-1][0] != "repeat":
                errors.append(f"line {line}: 'until' without repeat")
            else:
                blocks.pop()
        elif text == "end":
            if not blocks:
                errors.append(f"line {line}: extra 'end'")
            elif blocks[-1][0] == "repeat":
                errors.append(f"line {line}: 'end' closes repeat (needs until)")
                blocks.pop()
            else:
                blocks.pop()
        prev = (kind, text)
    for name, line in blocks:
        errors.append(f"line {line}: '{name}' block never closed")
    if expect_do:
        errors.append("missing 'do' after for/while")
    if expect_then:
        errors.append("missing 'then' after if/elseif")

    # Undeclared names (file-wide approximation).
    declared = set()
    for i, (kind, text, line) in enumerate(tokens):
        if kind == "name" and text == "local":
            j = i + 1
            if j < len(tokens) and tokens[j][1] == "function":
                j += 1
            while j < len(tokens) and tokens[j][0] == "name":
                declared.add(tokens[j][1])
                j += 1
                if j < len(tokens) and tokens[j][1] == ",":
                    j += 1
                    continue
                break
        if kind == "name" and text == "function":
            j = i + 1
            if j < len(tokens) and tokens[j][0] == "name":
                declared.add(tokens[j][1])
                j += 1
                while j < len(tokens) and tokens[j][1] in (".", ":"):
                    j += 2
            # parameters
            if j < len(tokens) and tokens[j][1] == "(":
                j += 1
                while j < len(tokens) and tokens[j][1] != ")":
                    if tokens[j][0] == "name":
                        declared.add(tokens[j][1])
                    j += 1
        if kind == "name" and text == "for":
            j = i + 1
            while j < len(tokens) and tokens[j][1] not in ("=", "in"):
                if tokens[j][0] == "name":
                    declared.add(tokens[j][1])
                j += 1

    for i, (kind, text, line) in enumerate(tokens):
        if kind != "name" or text in KEYWORDS or text in declared or text in GLOBALS:
            continue
        prev_tok = tokens[i - 1] if i > 0 else None
        next_tok = tokens[i + 1] if i + 1 < len(tokens) else None
        if prev_tok and prev_tok[1] in (".", ":", "::"):
            continue
        if next_tok and next_tok[1] == "=" and prev_tok and prev_tok[1] in ("{", ","):
            continue  # table constructor key
        errors.append(f"line {line}: '{text}' is used but never declared (global?)")

    return errors


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    files = sorted(root.rglob("*.lua"))
    total = 0
    lines = 0
    for path in files:
        lines += path.read_text(encoding="utf-8").count("\n") + 1
        errors = check_file(path)
        # de-duplicate
        seen = []
        for e in errors:
            if e not in seen:
                seen.append(e)
        for e in seen:
            print(f"{path}: {e}")
        total += len(seen)
    print(f"checked {len(files)} files, {lines} lines, {total} problem(s)")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
