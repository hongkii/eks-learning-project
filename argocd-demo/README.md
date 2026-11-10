# argocd-demo

Manifests that the Argo CD Applications in `gitops/` deploy.

| Path | Application | Sync |
| --- | --- | --- |
| `env/auto` | `app-auto` | automated, prune |
| `env/manual` | `app-manual` | manual |

`env/manual` reads `base/replacements/greeting.yaml`, which is outside its kustomization root,
so it builds only with `--load-restrictor LoadRestrictionsNone`.

```bash
kubectl kustomize argocd-demo/env/manual                                       # fails
kubectl kustomize --load-restrictor LoadRestrictionsNone argocd-demo/env/manual  # builds
```
