"""扫描版本控制中的高置信度凭据形态；不是完整安全审计。"""
import re
import subprocess
from pathlib import Path

paths = subprocess.check_output(["git", "ls-files", "-z"]).decode().split("\0")
patterns = [
    re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    re.compile(rb"(?:ghp_|github_pat_)[A-Za-z0-9_]{30,}"),
    re.compile(rb"AKIA[A-Z0-9]{16}"),
    re.compile(rb"postgres(?:ql)?://[^\s/:]+:[^\s/@]+@"),
]
bad = []
for name in filter(None, paths):
    path = Path(name)
    if path.name == ".env" or path.suffix in {".jks", ".keystore"} or path.name == "key.properties":
        bad.append(name)
        continue
    data = path.read_bytes()
    if any(pattern.search(data) for pattern in patterns):
        bad.append(name)
if bad:
    # 只报告文件名，不输出匹配值。
    raise SystemExit("FAIL 潜在敏感文件：" + ", ".join(bad))
print("PASS 已跟踪文件未发现本地环境文件、私钥、令牌或含密码数据库连接串")
