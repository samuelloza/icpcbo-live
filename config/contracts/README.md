# Contratos JSON

Este archivo documenta el formato de las actualizaciones firmadas. No es
configuración del sitio.

Reglas comunes:
- JSON UTF-8 canónico: claves ordenadas, sin espacios extra y con `\n` final.
- Tamaño máximo: 8 KiB.
- Sin campos desconocidos.
- IDs: `[A-Za-z0-9._-]{1,64}` y nunca `..`.
- Timestamps en UTC con sufijo `Z`.
- Nonce: 16 bytes aleatorios en base64url sin `=`.

## Archivos

| Schema | Uso | Emisor → receptor |
|---|---|---|
| `update-manifest.schema.json` | `updates/manifest.json` (+ `.sig` Ed25519 en base64) | host de release → ISO |

Los `.schema.json` son referencia.
