# -*- coding: utf-8 -*-
"""Initialize git repo and create initial commit using dulwich."""
import os
from dulwich import porcelain
from dulwich.repo import Repo

REPO = r"C:\Users\Administrator\AppData\Local\Doubao\User Data\Default\.doubao\agent_mode\workspace\FolderMount"

os.environ.setdefault("GIT_AUTHOR_NAME", "FolderMount")
os.environ.setdefault("GIT_AUTHOR_EMAIL", "foldermount@example.com")
os.environ.setdefault("GIT_COMMITTER_NAME", "FolderMount")
os.environ.setdefault("GIT_COMMITTER_EMAIL", "foldermount@example.com")

try:
    repo = Repo(REPO)
except Exception:
    repo = porcelain.init(REPO)
config = repo.get_config()
config.set(("user",), "name", "FolderMount")
config.set(("user",), "email", "foldermount@example.com")
config.write_to_path()
porcelain.add(repo, ["."])
commit_id = porcelain.commit(
    repo,
    message="Initial commit: FolderMount iOS - LAN IP folder mount manager (SMB/WebDAV)",
)
print("commit:", commit_id.decode("utf-8")[:12])
print("branch:", porcelain.active_branch(repo).decode("utf-8"))

