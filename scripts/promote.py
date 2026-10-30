import argparse
import re
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('repository')
parser.add_argument('environment', choices=['staging', 'production'])
parser.add_argument('tag')
parser.add_argument('digest')
args = parser.parse_args()

if not re.fullmatch(r'v\d+\.\d+\.\d+-[0-9a-f]{12}', args.tag):
    parser.error('Expected vX.Y.Z-12charsha')

if not re.fullmatch(r'sha256:[0-9a-f]{64}', args.digest):
    parser.error('Invalid OCI digest')

p = Path(args.repository) / 'environments' / args.environment / 'values.yaml'
s = p.read_text()

s, n = re.subn(
    r'^  digest:.*$',
    f'  digest: "{args.digest}"',
    s,
    flags=re.M,
)
assert n == 1, 'Expected exactly one image.digest'

if re.search(r'^  tag:', s, re.M):
    s, n = re.subn(
        r'^  tag:.*$',
        f'  tag: "{args.tag}"',
        s,
        flags=re.M,
    )
    assert n == 1
else:
    s = s.replace(
        f'  digest: "{args.digest}"',
        f'  tag: "{args.tag}"\n  digest: "{args.digest}"',
        1,
    )

p.write_text(s)
