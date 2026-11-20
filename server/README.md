# Neon Arena 排行榜服务器（Cloudflare Workers + D1）

游戏的在线排行榜后端。代码在 `src/index.js`，数据库结构在 `schema.sql`。
免费额度（Workers 每天 10 万次请求；D1 每天 500 万行读取、10 万行写入、5 GB 存储）对这个游戏绰绰有余。
榜单查询只读 `bests` 表里需要的那几行（每个玩家每个榜一行），不会随成绩条数增长。

## 第一次部署（约 10 分钟）

以下命令都在 `server/` 目录里运行。

1. **注册 Cloudflare 账号**：https://dash.cloudflare.com/sign-up （免费，不需要绑卡）。
2. **安装依赖**：
   ```bash
   npm install
   ```
3. **登录**（会打开浏览器让你授权，密钥保存在你自己的电脑上，不要发给别人）：
   ```bash
   npx wrangler login
   ```
4. **创建数据库**：
   ```bash
   npx wrangler d1 create neon-arena
   ```
   命令会打印一个 `database_id`，把它复制到 `wrangler.toml` 里替换 `00000000-0000-0000-0000-000000000000`。
5. **建表**：
   ```bash
   npm run db:init:remote
   ```
6. **部署**：
   ```bash
   npm run deploy
   ```
   最后会打印网址，形如 `https://neon-arena-leaderboard.<你的子域>.workers.dev`。
   用浏览器打开 `<网址>/api`，看到 `{"ok":true,...}` 就成功了。
7. **告诉游戏这个网址**：把它填进 `scripts/net.gd` 顶部的 `API_URL`，重新导出、发布游戏。
   填好之前，游戏里不会出现排行榜按钮，其他一切照常。

## 日常

- **改了服务器代码**：`npm run deploy`。
- **开新赛季**：把 `wrangler.toml` 里的 `SEASON` 加 1 再部署。旧赛季的数据保留在数据库里，只是不再显示。
- **允许新的网页地址调用**：改 `ALLOWED_ORIGINS`（逗号分隔）。`localhost` / `127.0.0.1` 总是允许，方便本地测试。
- **删除作弊成绩**：
  ```bash
  npx wrangler d1 execute neon-arena --remote --command "UPDATE runs SET flagged = 1 WHERE player_id = '<玩家ID>'; DELETE FROM bests WHERE player_id = '<玩家ID>'"
  ```
  查某人的 ID：`... --command "SELECT id, name FROM players WHERE name LIKE '%昵称%'"`。
- **看最近的成绩**：`... --command "SELECT * FROM runs ORDER BY id DESC LIMIT 20"`。

## 本地测试

```bash
npm run db:init:local
npm run dev            # http://127.0.0.1:8787
npm test               # 另开一个终端，跑接口测试
```
网页版游戏地址后面加 `?api=http://127.0.0.1:8787` 就会连本地服务器。

## 联机合作房间

联机用的 Durable Objects 已写在 `wrangler.toml` 里，`npm run deploy` 时会一起创建，免费版就能用。
**如果你在加联机之前已经部署过**，需要再运行一次 `npm run db:init:remote`，补上限制建房频率的表，然后 `npm run deploy`。

## TapTap 版

TapTap 版用导出预设「TapTap」打包（带 `taptap` 特性标签），和网页版共用这台服务器，排行榜、联机互通。

- **允许 TapTap 的网页地址**：`wrangler.toml` 的 `ALLOWED_ORIGINS` 已经加上 TapTap 常见域名，支持 `https://*.taptap.cn` 这样的通配写法。如果自测时排行榜连不上，运行 `npx wrangler tail`，在手机上打开游戏，日志里的 `rejected_origin` 就是被拒的地址，把它加进 `ALLOWED_ORIGINS` 后重新部署。
- **国内访问**：`*.workers.dev` 在国内经常连不上。最稳的办法是用一个**已备案**的自有域名（例如 `api.你的域名.cn`）在 Cloudflare 里绑定到这个 Worker（Workers → 设置 → 域和路由 → 添加自定义域），然后把 `scripts/net.gd` 里的 `API_URL_TAPTAP` 改成这个地址，再导出 TapTap 版。留空时，TapTap 版沿用 `API_URL`。
- **玩家名**：TapTap 版不让玩家打字，名字由游戏随机生成（如「霓虹猎手42」），点名字按钮换一个。服务器对所有名字再过滤一遍：拒绝网址、5 位以上连续数字（手机号、QQ 号）和屏蔽词。要追加屏蔽词，在 `[vars]` 里加 `NAME_BLOCKLIST = "词1,词2"`，然后部署。
- 改完服务器代码后要 `npm run deploy` 才会生效。

## 防作弊说明

网页游戏的代码对玩家可见，没法做到完全防作弊，这里只挡住随手改分：
- 每局开始向服务器领一次性编号，提交时必须带上，且只能用一次。
- 每台设备有自己的密钥，别人不能冒用你的身份提交。
- 服务器用自己的时钟核对这局的时长；分数、波次、击杀、时长不合理的成绩会被标记，不进榜。
- 每个玩家每小时最多开 40 局，每个 IP 每小时最多 200 局。
