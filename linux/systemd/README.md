# Chạy báo cáo tự động mỗi sáng bằng systemd timer

1. Đặt thư mục `linux` vào server, ví dụ `/opt/health-check/linux`.
2. Điền các service, endpoint và backup marker thật trong `config/targets.conf`.
3. Chép hai file `.example` vào `/etc/systemd/system/`, bỏ đuôi `.example`.
4. Nếu thư mục cài đặt khác `/opt/health-check/linux`, sửa `WorkingDirectory` và
   `ExecStart` trong file service.
5. Kích hoạt timer:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now linux-healthcheck.timer
sudo systemctl list-timers linux-healthcheck.timer
```

Timer chạy lúc 07:00 mỗi ngày. `Persistent=true` đảm bảo một lần chạy bị lỡ khi
server tắt sẽ được chạy sau khi server lên lại. Báo cáo vẫn nằm trong
`/var/log/linux-healthcheck/healthcheck-YYYY-MM-DD.log`, hoặc ở đường dẫn bạn
đặt qua `HC_LOG_DIR`.
