#!/usr/bin/env python3
"""Repopulate `.build-kit/.slices/` with the FULL slice definitions.

The loop does this itself, but from the **summary** endpoint
(`/slicedata/slices`), which returns six fields: no `fields`, no `events`, no
`specifications`. An agent cannot build from that — and it's easy to miss,
because the file exists and parses. It's just empty of everything that matters.

This uses `/slicedata?contextName=`, which returns the whole definition, and
names folders with the SAME rule as the loop — `title` with spaces removed,
lowercased, keeping accents and `·` — so it leaves no duplicates behind.
"""
import json, os, shutil, urllib.parse, urllib.request

cfg = json.load(open('.eventmodelers/config.json'))
ctx = json.load(open('.build-kit/.slices/current_context.json'))['name']
base, org, board = cfg['baseUrl'], cfg['organizationId'], cfg['boardId']

url = f"{base}/api/org/{org}/boards/{board}/slicedata?contextName={urllib.parse.quote(ctx)}&format=json"
req = urllib.request.Request(url, headers={
    'x-token': cfg['token'], 'x-board-id': board, 'x-user-id': 'refresh-slices'})
slices = json.load(urllib.request.urlopen(req, timeout=60))['slices']

target = f'.build-kit/.slices/{ctx}'
if os.path.isdir(target):
    for d in os.listdir(target):
        if os.path.isdir(f'{target}/{d}'):
            shutil.rmtree(f'{target}/{d}')
os.makedirs(target, exist_ok=True)
json.dump({"name": ctx}, open(f'{target}/context.json', 'w'), ensure_ascii=False, indent=2)

index = []
for i, s in enumerate(slices):
    # The same rule as `fetchAndPersistSlices` in lib/ralph.js.
    folder = (s.get('title') or s['id']).replace(' ', '').lower()
    os.makedirs(f'{target}/{folder}', exist_ok=True)
    sj = {k: v for k, v in s.items() if k != 'index'}
    json.dump(sj, open(f'{target}/{folder}/slice.json', 'w'), ensure_ascii=False, indent=2)
    index.append({"id": s['id'], "slice": s['title'], "index": i, "folder": folder,
                  "contextName": ctx, **sj})
json.dump({"slices": index}, open(f'{target}/index.json', 'w'), ensure_ascii=False, indent=2)

for e in index:
    path = f"{target}/{e['folder']}/slice.json"
    print(f"  {e['status']:9} {os.path.getsize(path):>7} bytes  {e['slice']}")
print(f"\n{len(index)} slices in context '{ctx}' with full definitions")
