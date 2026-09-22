# Linux healthcheck

Chạy healthcheck bằng một lệnh duy nhất:

```bash
./linux-healthcheck.sh
```

Luồng chạy rất đơn giản:

```text
linux-healthcheck.sh
  ├─ config/defaults.sh  : ngưỡng cảnh báo và đường dẫn lưu dữ liệu
  ├─ checks/*.sh         : từng nhóm healthcheck
  ├─ lib/core.sh         : log, baseline và tổng kết kết quả
  └─ exit 0 / 1 / 2      : HEALTHY / WARNING / CRITICAL
```

Mỗi file trong `checks/` chỉ phụ trách một mảng: CPU, memory, filesystem,
disk I/O, network, process, hardware hoặc system log.

`config/targets.conf` là nơi khai báo những gì thực sự quan trọng với hệ thống:
service systemd, HTTP health endpoint, TCP dependency và file đánh dấu backup
thành công. Các check này được đưa vào báo cáo `APPLICATION & BACKUP`.

Để tự chạy báo cáo lúc 07:00 hằng ngày, dùng các template trong
[`systemd/`](systemd/README.md).

Không cần sửa source để đổi ngưỡng. Ghi đè bằng biến môi trường, ví dụ:

```bash
DISK_WARN=85 IOWAIT_WARN=25 ./linux-healthcheck.sh
```
