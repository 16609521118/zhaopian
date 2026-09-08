# -*- coding: utf-8 -*-
"""Rough syntax check: bracket balance for all Swift files."""
import os

SRC = r"C:\Users\Administrator\AppData\Local\Doubao\User Data\Default\.doubao\agent_mode\workspace\FolderMount\FolderMount"
issues = []


def check(path, text):
    stack = []
    in_str = False
    in_line_comment = False
    in_block_comment = False
    i = 0
    while i < len(text):
        c = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if in_line_comment:
            if c == "\n":
                in_line_comment = False
            i += 1
            continue
        if in_block_comment:
            if c == "*" and nxt == "/":
                in_block_comment = False
                i += 2
                continue
            i += 1
            continue
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if c == "/" and nxt == "/":
            in_line_comment = True
            i += 2
            continue
        if c == "/" and nxt == "*":
            in_block_comment = True
            i += 2
            continue
        if c == '"':
            in_str = True
            i += 1
            continue
        if c in "({[":
            stack.append(c)
        elif c in ")}]":
            pairs = {"(": ")", "{": "}", "[": "]"}
            if not stack or pairs[stack[-1]] != c:
                issues.append("{}: unbalanced at offset {}".format(path, i))
                return
            stack.pop()
        i += 1
    if stack:
        issues.append("{}: unclosed {}".format(path, stack))


count = 0
for dirpath, _, files in os.walk(SRC):
    if "Assets.xcassets" in dirpath:
        continue
    for f in files:
        if f.endswith(".swift"):
            p = os.path.join(dirpath, f)
            check(p, open(p, encoding="utf-8").read())
            count += 1

print("swift files checked:", count)
print("issues:", issues if issues else "none")
