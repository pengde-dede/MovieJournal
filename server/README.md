# 影片资料试用服务

使用 JDK 17 或更新版本在此目录执行 `mvn package`。将生成的 `target/moviejournal-catalog-0.1.0.jar` 安装到 `/opt/moviejournal-catalog/catalog.jar`，并将 `deploy/moviejournal-catalog.service` 安装到 `/etc/systemd/system/`。

在仅 root 可读写的 `/etc/moviejournal/catalog.env` 中设置 `TMDB_API_KEY`（TMDB v3 密钥）、`MOVIEJOURNAL_TRIAL_SECRET`（使用 `openssl rand -hex 32` 生成）和 `MOVIEJOURNAL_TRIAL_INVITES`（以逗号分隔、每个使用 `openssl rand -hex 16` 生成）。`TMDB_API_HOST` 默认是 `api.themoviedb.org`，也支持 `api.tmdb.org`。移除已发放的邀请码并重启服务，可以撤销对应的会话。

使用 `sudo systemctl daemon-reload` 和 `sudo systemctl enable --now moviejournal-catalog` 启动。服务默认在 `127.0.0.1:18771` 监听。`GET /api/health` 可用于检查进程。对外部署时，使用具有受信任证书的 HTTPS 反向代理转发 `/api/`；避免记录请求体或 Authorization 请求头。

Mac 客户端可以在设置中填写 HTTPS 服务地址和邀请码。试用会话有效期为 7 天，到期后可用有效邀请码再次激活。当前服务仅处理搜索和获取影片资料的请求，观影记录保存在客户端。
