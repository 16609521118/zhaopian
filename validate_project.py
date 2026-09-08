# -*- coding: utf-8 -*-
"""Validate FolderMount project integrity."""
import os
import re
import sys

ROOT = r"C:\Users\Administrator\AppData\Local\Doubao\User Data\Default\.doubao\agent_mode\workspace\FolderMount"
PBX = os.path.join(ROOT, "FolderMount.xcodeproj", "project.pbxproj")
SRC = os.path.join(ROOT, "FolderMount")

errors = []
warnings = []

# 1. pbxproj 括号平衡
text = open(PBX, encoding="utf-8").read()
assert text.startswith("// !$*UTF8*$!")
depth = 0
in_string = False
i = 0
while i < len(text):
    c = text[i]
    if in_string:
        if c == "\\":
            i += 2
            continue
        if c == '"':
            in_string = False
        i += 1
        continue
    if c == '"':
        in_string = True
    elif c == "{":
        depth += 1
    elif c == "}":
        depth -= 1
        if depth < 0:
            errors.append("pbxproj: unbalanced braces")
            break
    i += 1
if depth != 0:
    errors.append(f"pbxproj: unbalanced braces, depth={depth}")

# 2. 每个 PBXFileReference path 存在于磁盘
refs = re.findall(r"path = ([^;]+);", text)
missing = []
for path in refs:
    p = path.strip().strip('"')
    if p == "FolderMount.app":
        continue
    # 找到引用它的分组路径是复杂的，直接全盘搜索文件名
    hits = []
    for dirpath, _, files in os.walk(SRC):
        if os.path.basename(p) in files or os.path.basename(p) in dirpath:
            hits.append(os.path.join(dirpath, os.path.basename(p)))
    if not hits:
        missing.append(p)
if missing:
    errors.append(f"pbxproj 引用的文件在磁盘缺失: {missing}")

# 3. 磁盘上的 Swift 文件是否都被 pbxproj 引用
expected = []
for dirpath, _, files in os.walk(SRC):
    if "Assets.xcassets" in dirpath:
        continue
    for f in files:
        if f.endswith(".swift"):
            expected.append(f)
unreferenced = [f for f in expected if f not in text]
if unreferenced:
    errors.append(f"磁盘上的 Swift 文件未被 pbxproj 引用: {unreferenced}")

# 4. SPM 依赖存在
for token in ["XCRemoteSwiftPackageReference", "XCSwiftPackageProductDependency", "amosavian/AMSMB2"]:
    if token not in text:
        errors.append(f"pbxproj 缺少 SPM 配置: {token}")

# 5. Sources phase 条目数 = Swift 文件数
source_build_files = len(re.findall(r"\.swift in Sources \*/;", text))
if source_build_files != len(expected):
    warnings.append(f"Sources phase 条目 {source_build_files} != Swift 文件 {len(expected)}")

# 6. 关键文件存在
for f in ["codemagic.yaml", ".gitignore", "README.md", os.path.join("FolderMount", "Info.plist"),
          os.path.join("FolderMount", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")]:
    if not os.path.exists(os.path.join(ROOT, f)):
        errors.append(f"缺少文件: {f}")

print("Swift files:", len(expected))
print("PBXBuildFile entries:", text.count("isa = PBXBuildFile"))
print("Errors:", errors if errors else "none")
print("Warnings:", warnings if warnings else "none")
sys.exit(1 if errors else 0)
