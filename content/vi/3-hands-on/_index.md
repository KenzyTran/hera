---
title: "Thực hành"
date: 2025-01-01
weight: 3
chapter: true
pre: "<b>3. </b>"
---

### Thực hành

# Các bước thực hành

Trong phần này, chúng ta sẽ thực hiện các bước chính của workshop.

{{% notice tip %}}
**Trước khi bắt đầu — môi trường chạy lệnh.** Mọi script `bin/*.sh` là **bash**, còn `terraform` / `aws` / `cdk` / `docker` chạy đa nền tảng. Khuyến nghị:

- **macOS / Linux:** dùng terminal mặc định.
- **Windows:** dùng **Git Bash** (đi kèm Git for Windows) hoặc **WSL** để chạy được các script `.sh` y như tài liệu. Hai lưu ý cho Git Bash:
  - Lệnh AWS có tham số bắt đầu bằng `/` (vd `/aws/bedrock-agentcore/...`) sẽ bị Git Bash đổi thành đường dẫn Windows → lỗi `InvalidParameterException`. Thêm `MSYS_NO_PATHCONV=1` trước lệnh đó.
  - Nếu dùng PowerShell thay vì Git Bash: cú pháp biến môi trường khác (`$env:VAR="x"` thay vì `export VAR=x`), và gọi script qua `bash bin/xxx.sh`.
- **Lưu ý chung:** các ô lệnh là copy-paste trực tiếp. Chỗ nào có dạng `<...>` (vd `<your-runtime-id>`) là **placeholder** — thay bằng giá trị thật, **đừng dán nguyên cả dấu `<` `>`** (bash sẽ hiểu `<` là redirect và báo lỗi "No such file or directory").
{{% /notice %}}

{{% children %}}
