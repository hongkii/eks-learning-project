# Kubernetes 매니페스트

## demo-app.yaml

파드가 어느 노드에서 도는지 화면에 표시하는 데모 앱이다.
버전 롤백이나 노드 교체 중 파드가 계속 동작하는지 확인할 때 쓴다.

```bash
make test-app     # 배포
make app-status   # 파드와 노드 확인
make app-open     # http://localhost:8080
make app-watch    # 파드 상태 실시간 관찰
```

Service 는 ClusterIP 다. LoadBalancer 는 과금되므로 port-forward 로 접근한다.

## EBS 볼륨 예제

`storageclass.yaml`, `pvc.yaml`, `example-pod.yaml` 로 EBS 동적 프로비저닝을 확인한다.

EBS CSI Driver 는 Terraform 이 EKS 애드온으로 설치하므로 별도 설치가 필요 없다.
IRSA 역할도 `terraform/iam.tf` 에서 만들어진다.

```bash
kubectl apply -f storageclass.yaml
kubectl apply -f pvc.yaml
kubectl apply -f example-pod.yaml

kubectl get pvc ebs-pvc
kubectl get pv
```

PVC 가 `Bound` 가 되지 않으면 IRSA 설정을 확인한다.

```bash
kubectl -n kube-system logs deploy/ebs-csi-controller -c csi-provisioner
```

## 삭제

```bash
kubectl delete -f example-pod.yaml -f pvc.yaml -f storageclass.yaml
make clean-test-app
```

PV 가 남으면 EBS 볼륨이 삭제되지 않아 과금이 이어진다. `make destroy` 가 정리한다.
