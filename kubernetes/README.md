# Kubernetes daily healthcheck

Chạy script **một lần** trên một control-plane node có quyền đọc cluster:

```bash
sudo KUBECONFIG=/etc/rancher/rke2/rke2.yaml \
  bash /opt/scripts/healthcheck-system/kubernetes/kubernetes-healthcheck.sh
```

Với RKE2, script tự nhận `/etc/rancher/rke2/rke2.yaml` và binary kubectl nếu
cron chạy bằng root.

## Cron lúc 07:10

Mở root crontab bằng `sudo crontab -e` và thêm:

```cron
10 7 * * * KUBECONFIG=/etc/rancher/rke2/rke2.yaml /bin/bash /opt/scripts/healthcheck-system/kubernetes/kubernetes-healthcheck.sh >/dev/null 2>>/var/log/kubernetes-healthcheck/cron-errors.log
```

Report được ghi tại `/var/log/kubernetes-healthcheck/kubernetes-healthcheck-YYYY-MM-DD.log`.

## Cấu hình workload đặc thù

Sửa `config/targets.conf` để bỏ qua namespace test, kiểm tra hourly/daily
etcd snapshot, hoặc tắt Longhorn check khi cluster không dùng Longhorn. Khi
đặt marker thành `true`, backup script phải tạo file `SUCCESS` trong cùng thư
mục với `snapshot.db` chỉ sau khi backup hoàn tất.
