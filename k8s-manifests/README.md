# Kubernetes Manifests

## demo-app.yaml

A demo app that displays which node each pod runs on.
Used to check that pods keep serving during a version rollback or node replacement.

```bash
make test-app     # deploy
make app-status   # check pods and nodes
make app-open     # http://localhost:8080
make app-watch    # watch pod status live
```

The Service is ClusterIP. LoadBalancer costs money, so access it through port-forward.

## EBS Volume Example

`storageclass.yaml`, `pvc.yaml` and `example-pod.yaml` demonstrate EBS dynamic provisioning.

The EBS CSI Driver is installed by Terraform as an EKS add-on, so no separate install is needed.
The IRSA role is created in `terraform/iam.tf` as well.

```bash
kubectl apply -f storageclass.yaml
kubectl apply -f pvc.yaml
kubectl apply -f example-pod.yaml

kubectl get pvc ebs-pvc
kubectl get pv
```

If the PVC does not reach `Bound`, check the IRSA setup.

```bash
kubectl -n kube-system logs deploy/ebs-csi-controller -c csi-provisioner
```

## Cleanup

```bash
kubectl delete -f example-pod.yaml -f pvc.yaml -f storageclass.yaml
make clean-test-app
```

A leftover PV keeps its EBS volume alive and billing. `make destroy` deletes PVs before
running terraform destroy.
