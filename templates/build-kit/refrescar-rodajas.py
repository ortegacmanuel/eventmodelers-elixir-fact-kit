#!/usr/bin/env python3
"""Repuebla `.build-kit/.slices/` con las definiciones COMPLETAS.

El bucle lo hace solo, pero con el endpoint **resumen** (`/slicedata/slices`),
que devuelve seis campos: sin `fields`, sin `events`, sin `specifications`. Un
agente no puede construir con eso.

Esto usa `/slicedata?contextName=`, que devuelve la definición entera, y nombra
las carpetas con la MISMA regla que el bucle —`title` sin espacios, en
minúsculas, conservando tildes y `·`— para que no queden duplicadas.
"""
import json, os, shutil, sys, urllib.parse, urllib.request

cfg = json.load(open('.eventmodelers/config.json'))
ctx = json.load(open('.build-kit/.slices/current_context.json'))['name']
base, org, board = cfg['baseUrl'], cfg['organizationId'], cfg['boardId']

url = f"{base}/api/org/{org}/boards/{board}/slicedata?contextName={urllib.parse.quote(ctx)}&format=json"
req = urllib.request.Request(url, headers={
    'x-token': cfg['token'], 'x-board-id': board, 'x-user-id': 'refrescar-rodajas'})
slices = json.load(urllib.request.urlopen(req, timeout=60))['slices']

destino = f'.build-kit/.slices/{ctx}'
if os.path.isdir(destino):
    for d in os.listdir(destino):
        if os.path.isdir(f'{destino}/{d}'):
            shutil.rmtree(f'{destino}/{d}')
os.makedirs(destino, exist_ok=True)
json.dump({"name": ctx}, open(f'{destino}/context.json', 'w'), ensure_ascii=False, indent=2)

indice = []
for i, s in enumerate(slices):
    # La misma regla que `fetchAndPersistSlices` en lib/ralph.js.
    folder = (s.get('title') or s['id']).replace(' ', '').lower()
    os.makedirs(f'{destino}/{folder}', exist_ok=True)
    sj = {k: v for k, v in s.items() if k != 'index'}
    json.dump(sj, open(f'{destino}/{folder}/slice.json', 'w'), ensure_ascii=False, indent=2)
    indice.append({"id": s['id'], "slice": s['title'], "index": i, "folder": folder,
                   "contextName": ctx, **sj})
json.dump({"slices": indice}, open(f'{destino}/index.json', 'w'), ensure_ascii=False, indent=2)

for e in indice:
    ruta = f"{destino}/{e['folder']}/slice.json"
    print(f"  {e['status']:9} {os.path.getsize(ruta):>7} bytes  {e['slice']}")
print(f"\n{len(indice)} rodajas del contexto «{ctx}» con definición completa")
