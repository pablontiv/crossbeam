---
estado: Specified
tipo: task
---
# T017: Alinear `yamllint` y `actionlint` en line-length=160

**Outcome**: [O01 Sanitize CI reusables](README.md)
**Contribuye a**: eliminar la fuente principal de fallas internas de CI en crossbeam (≈5 de 9 fallas históricas por workflows violando sus propias reglas).

## Preserva

- INV1: workflows que hoy pasan siguen pasando tras el alineamiento.
  - Verificar: corrida CI de crossbeam tras el cambio retorna success.

## Contexto

Hoy el CI interno de crossbeam ejecuta yamllint + actionlint. Las reglas están desalineadas:
- `.yamllint.yml` declara `line-length: max 160 (warning)`.
- Actionlint (configurado o por default) exige line-length=80.

Resultado: workflows redactados respetando 160 fallan actionlint. Estandarizar en **160** (consistente con la realidad práctica de YAML con expressions).

## Alcance

**In**:
1. Verificar y/o ajustar `.yamllint.yml` para `line-length: { max: 160 }`.
2. Configurar actionlint con line-length=160 (vía flag, config file `actionlint.yaml`, o `.github/actionlint.yaml`).
3. Re-ejecutar CI interno y confirmar que workflows actualmente shipped pasan sin warnings de line-length.

**Out**:
- No reformatear masivamente workflows existentes para acortar líneas.
- No cambiar otras reglas de yamllint/actionlint no relacionadas a line-length.

## Estado inicial esperado

- `.yamllint.yml` con line-length=160 (warning).
- Actionlint efectivo con límite más corto, provocando fallas.

## Criterios de Aceptación

- Ambas configs declaran line-length=160 (o flag equivalente). Verificable por grep en sus respectivos archivos.
- CI interno (`gh run list --repo pablontiv/crossbeam --workflow ci.yml --limit 3`) retorna `conclusion=success` post-cambio.
- En los logs del último run, no hay fallas atribuibles a line-length.

## Fuente de verdad

- `/home/shared/crossbeam/.yamllint.yml`
- `/home/shared/crossbeam/.github/actionlint.yaml` (crear si no existe)
- `/home/shared/crossbeam/.github/workflows/ci.yml`
