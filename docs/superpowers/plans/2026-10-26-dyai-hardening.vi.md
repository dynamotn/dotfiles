# Kế hoạch triển khai gia cố dyai

> Bản dịch tiếng Việt của [2026-10-26-dyai-hardening.md](2026-10-26-dyai-hardening.md). Khi hai bản lệch nhau, bản tiếng Anh là bản gốc.

> **Dành cho agent thực thi:** SUB-SKILL BẮT BUỘC: Dùng superpowers:subagent-driven-development (khuyến nghị) hoặc superpowers:executing-plans để triển khai kế hoạch này theo từng task. Các bước dùng cú pháp checkbox (`- [ ]`) để theo dõi.

**Mục tiêu:** Làm cho `dyai` trung thực về những gì nó đã cài và những gì mỗi
agent thực sự áp dụng. Các lệnh cài đặt bên ngoài có timeout và được kiểm tra
sau khi chạy. Chỉnh sửa cục bộ không bao giờ bị ghi đè một cách âm thầm. Drift
giữa config và máy được báo cáo khi bắt đầu session. Việc dùng subagent trở
nên hiển thị rõ ràng.

**Kiến trúc:** Bổ sung nhỏ vào `scripts/lib/dyai.sh`, cộng thêm hai lệnh mới
trong `home/dot_local/bin/executable_dyai.tmpl` (`status`,
`enforcement`), một script hook cho Claude, và một dòng rule trong một partial
`ai/`. Mọi ý tưởng đều lấy từ tài liệu Intent Loop 2.2.1, đọc ngày 2026-10-26:
- xác minh bằng đường dẫn, không bằng exit code;
- các initializer bên thứ ba chạy với stdin đã đóng và có giới hạn thời gian;
- báo cáo LOCAL EDITS thay vì ghi đè;
- báo cáo armed so với declared, im lặng khi mọi thứ đều armed;
- một bảng enforcement phân loại từng rule là M (cơ học),
  S (đọc qua skill) hoặc D (chỉ khai báo);
- việc spawn một subagent đã được định tuyến sẽ được thông báo;
- các thay đổi về bảo mật được một reviewer độc lập review.

**Tech Stack:** bash trên dybatpho, `jq`, `yq`, `timeout`, `sha256sum`, bats.

**Spec:** chưa viết. Các quyết định đến từ cuộc trao đổi ngày 2026-10-26.
Live self-test và `dyai eval` phụ thuộc vào crew runner và nằm trong
`2026-10-26-dyai-crew.md` (Task 7 và 8).

## Ràng buộc chung

- Không thêm dependency mới.
- Các hàm giữ dạng `dyai::<verb>` trong `scripts/lib/dyai.sh`, theo đúng kiểu
  doc-comment hiện có. Test đặt trong `scripts/test/dyai.bats` cùng các helper
  `_stub` và `_write_config` của nó, trừ khi task chỉ định file khác.
- Mọi script bị thay đổi đều phải qua được `dyshellint`.
- `dyai install` vẫn không bao giờ được dừng hẳn vì một mục bị lỗi. Nó cảnh
  báo rồi đi tiếp, như hiện nay.
- Hook script chỉ quan sát: không in gì, luôn exit 0, và không bao giờ thay
  đổi một tool call. Đây là contract của `log-skill.sh`.
- Một thay đổi trong `home/.chezmoitemplates/ai/` phải giữ `claude_rules.bats`
  xanh. Kiểm tra template đã render bằng `chezmoi execute-template --source .`.
- Commit message: Conventional Commits, scope `dyai` (hoặc `claude` cho
  hook), và không có trailer ghi công agent.

## Trọng tâm review

1. Một skill CLI exit 0 mà không cài gì sẽ bị báo cáo, không được ghi nhận là
   đã cài. Test ở Task 1.
2. Một installer chờ stdin hoặc bị treo sẽ bị kill sau timeout, và quá trình
   cài đặt tiếp tục. Test ở Task 1.
3. Một file subagent người dùng đã sửa vẫn được giữ qua `dyai install`, kể cả
   khi upstream thay đổi. Test ở Task 2.
4. `dyai status --quiet` không in gì trên một máy đã armed đầy đủ và vẫn
   nhanh (dưới 2 s), vì nó chạy mỗi khi một session Claude bắt đầu. Test ở
   Task 4.
5. Bảng enforcement được sinh ra trong `docs/dyai.md` không thể lệch khỏi
   code. Test ở Task 5.

---

### Task 1: Cài đặt bên ngoài có giới hạn thời gian, kiểm tra bằng đường dẫn

**Files:**
- Sửa: `scripts/lib/dyai.sh` (`setup_marketplaces`, `setup_plugins`,
  `setup_skills`, `setup_installers`, và phần cài project skill trong
  `materialize`)
- Test: `scripts/test/dyai.bats`

**Interfaces:**
- Cung cấp: `dyai::run_external <cmd...>`. Chạy lệnh với stdin đã đóng dưới
  `timeout --kill-after=10 "${DYAI_EXTERNAL_TIMEOUT:-300}"`, và trả về exit
  code của lệnh (124 khi timeout).

Hành vi:
- Mọi lệnh cài đặt bên ngoài đều đi qua `run_external`. Hiện tại gồm
  `claude plugin marketplace add`, `claude plugin install`,
  `bunx … add` (global trong `setup_skills`, scope project trong `materialize`)
  và `bash -c "${cmd}"`. Cả năm lệnh đều đã đóng stdin, nên thay đổi này chỉ
  thêm giới hạn thời gian. `materialize` cũng được thêm bước kiểm tra đường
  dẫn sau khi cài như bên dưới, cho `<project>/.agents/skills/<leaf>`. (Sửa
  2026-10-26: lần đầu bỏ sót lời gọi trong `materialize`, nên một skills CLI
  bị treo vẫn làm treo `dyai use`.)
- `setup_skills`: sau khi `bunx` thành công, thư mục skill phải tồn tại
  (`dybatpho::is dir` đi theo symlink, nên một link hỏng được tính là
  thiếu). Nếu không thì cảnh báo
  `skill <name>: installer reported success but <target> is missing`.
- `setup_plugins`: sau khi cài thành công, đọc lại
  `installed_plugins.json`. Nếu plugin vẫn không có, cảnh báo tương tự.
- Khi một skill được cài và đã xác minh, ghi lại hash nội dung của skill (xem
  `dyai::dir_hash` ở Task 2) vào `~/.cache/dyai/installed/skills/<name>.sha256`.

- [ ] **Bước 1: Viết các test đang fail:**
  - `@test "a skill install that exits 0 but writes nothing is reported"`:
    stub `bunx` exit 0. Assert output có nêu target bị thiếu và không có
    `.sha256` nào được ghi.
  - `@test "a hanging installer is cut off and install continues"`:
    `DYAI_EXTERNAL_TIMEOUT=1`, một lệnh installer `sleep 5`, một installer
    thứ hai thành công. Cái đầu cảnh báo, marker của cái thứ hai được ghi.
  - `@test "an installer reading stdin gets EOF"`: lệnh là `read x`.
    Nó kết thúc ngay lập tức.
- [ ] **Bước 2: Chạy** `bats scripts/test/dyai.bats`. Kỳ vọng: các test mới FAIL.
- [ ] **Bước 3: Triển khai** `run_external` và cho bốn chỗ gọi đi qua nó.
  Thêm các bước kiểm tra sau khi cài.
- [ ] **Bước 4: Chạy** file bats và `dyshellint scripts/lib/dyai.sh`.
  Kỳ vọng: PASS, và mọi test `dyai.bats` hiện có vẫn pass.
- [ ] **Bước 5: Commit** `fix(dyai): time-limit installers and check what they installed`.

### Task 2: Không bao giờ ghi đè chỉnh sửa cục bộ

**Files:**
- Sửa: `scripts/lib/dyai.sh` (`setup_subagents`, `subagent_codex`, cộng thêm
  các helper mới)
- Test: `scripts/test/dyai.bats`

**Interfaces:**
- Cung cấp:
  - `dyai::dir_hash <path>`. In ra một sha256 trên mọi file dưới `path`,
    mỗi file được hash kèm đường dẫn tương đối, theo thứ tự đã sắp xếp. In ra
    hash của file khi `path` là một file.
  - `dyai::installed_hash <kind> <name> [hash]`. In ra hash đã ghi nhận.
    Khi có đối số thứ ba, ghi nó vào
    `~/.cache/dyai/installed/<kind>/<name>.sha256`.
  - `dyai::locally_edited <kind> <name> <dest>`. Exit 0 khi `dest` tồn tại,
    đã có hash được ghi nhận, và `dest` không còn khớp với hash đó.

Hành vi: `setup_subagents` hiện copy đè lên `dest` mỗi khi nó khác với file
đã pin (`! cmp -s` rồi `cp`). Việc đó âm thầm xoá mất chỉnh sửa của người
dùng. Thứ tự mới:
1. Giống file đã pin: không làm gì.
2. `locally_edited`: giữ file và cảnh báo
   `subagent <leaf>: LOCAL EDITS kept; delete <dest> to take the pinned copy`.
3. Ngược lại thì copy và ghi nhận hash.

Quy tắc tương tự áp dụng cho file `.toml` của Codex (kind `codex-agents`).

- [ ] **Bước 1: Viết các test đang fail:**
  - `@test "an edited subagent survives a changed upstream"`: cài, thêm
    một dòng vào `dest`, đổi file đã pin, cài lại. `dest` vẫn còn dòng đã
    thêm và output có `LOCAL EDITS`.
  - `@test "an untouched subagent follows upstream"`: như trên, nhưng không
    sửa. `dest` bằng file đã pin mới.
  - `@test "a subagent installed before hashes existed is replaced once"`:
    không có hash được ghi nhận, `dest` khác. Nó bị thay và hash được ghi
    nhận. Không có hash ghi nhận thì không gì phân biệt được một chỉnh sửa với
    một bản cũ, nên giữ hành vi như hiện nay.
  - `@test "dir_hash changes when a file is renamed"`.
- [ ] **Bước 2: Chạy.** Kỳ vọng: FAIL.
- [ ] **Bước 3: Triển khai** ba helper và thứ tự copy mới.
- [ ] **Bước 4: Chạy** file bats và `dyshellint`. Kỳ vọng: PASS.
- [ ] **Bước 5: Commit** `fix(dyai): keep locally edited subagents`.

### Task 3: Chọn tier model cho từng subagent

**Files:**
- Sửa: `schemas/dyai.schema.yaml` (thêm `models` vào một subagent source)
- Sửa: `home/private_dot_config/dyai/config.yaml.tmpl`
- Sửa: `scripts/lib/dyai.sh` (`setup_subagents`, `subagent_codex`)
- Test: `scripts/test/dyai.bats`, `scripts/test/dyai_schema.bats`

**Interfaces:**
- Sử dụng: thứ tự copy của Task 2. Hash được tính trên nội dung đã viết lại,
  nên một override không bị nhầm là chỉnh sửa cục bộ.
- Cung cấp:
  - Config key `global.subagents[].models`: một map từ tên leaf sang một tier
    trừu tượng, `fast | standard | strong | inherit`.
  - `agents.<name>.model_tiers`: lựa chọn riêng của agent đó cho từng tier,
    hoặc là một chuỗi theo cú pháp của chính agent, hoặc là
    `{model, provider, effort}`. Dạng object dành cho các agent tách riêng
    các trường đó, kể cả provider self-hosted Ollama và LM Studio.
  - `dyai::model_for <agent> <tier>`: in lựa chọn dưới dạng JSON, hoặc không
    in gì.
  - Claude: `model:` được ghi vào frontmatter.
  - Codex: `model`, `model_provider` và `model_reasoning_effort` được ghi
    vào TOML của agent.
  - Một tier mà agent không map thì giữ lựa chọn của upstream.
  (Sửa 2026-10-26: mỗi agent đặt tên model một kiểu. Config dùng chung không
  bao giờ chứa tên model của riêng một agent.)

Config ban đầu: `code-reviewer`, `security-auditor` và `architect-reviewer`
là `strong`; `research-analyst` là `standard`. Claude map
`fast: haiku, standard: sonnet, strong: opus`. Codex chưa được map, vì nó
chưa được cài ở máy này và các key TOML của nó chưa được xác minh.

- [ ] **Bước 1: Viết các test đang fail:**
  - `@test "a models override rewrites the frontmatter"`: file đã pin
    ghi `model: sonnet`, override ghi `opus`. File đã cài ghi
    `model: opus` và phần thân không đổi.
  - `@test "an override is not reported as a local edit"`: cài hai lần.
    Không có cảnh báo `LOCAL EDITS`.
  - Trong `dyai_schema.bats`: `@test "schema rejects an unknown subagent model"`
    với `models: {x: gpt}`.
- [ ] **Bước 2: Chạy.** Kỳ vọng: FAIL.
- [ ] **Bước 3: Triển khai** key schema, khối config và phần viết lại.
- [ ] **Bước 4: Chạy** `bats scripts/test/dyai.bats`, `./scripts/test.sh --dyai`
  và `dyshellint`. Kỳ vọng: PASS.
- [ ] **Bước 5: Commit** `feat(dyai): pin subagent model tiers in the config`.

### Task 4: `dyai status`, armed so với declared

**Files:**
- Tạo: `scripts/lib/dyai_status.sh` (thực tế khi làm: các bước kiểm tra
  phình to hơn `dyai.sh`, nên chúng nằm trong library riêng, được source sau
  nó)
- Sửa: `home/dot_local/bin/executable_dyai.tmpl` (`_spec_status`, `_status`)
- Sửa: `home/private_dot_claude/settings.json.tmpl` (SessionStart)
- Test: `scripts/test/dyai_status.bats`, `scripts/test/claude_settings.bats`
  và fixture của nó `scripts/test/fixtures/claude-settings.expected.json`

**Interfaces:**
- Sử dụng: `locally_edited` và `installed_hash` của Task 2.
- Cung cấp: `dyai_status::main <quiet>`. In một dòng cho mỗi drift dạng
  `<agent> <kind> <name>: <problem>`. Exit 1 khi có bất kỳ drift nào. Với
  `quiet`, một máy sạch không in gì. Dạng CLI: `dyai status [--quiet|-q]`.

Các bước kiểm tra, chỉ cho những agent đã cài:

| kind | khai báo trong | armed khi |
|---|---|---|
| skill | `global.skills` | thư mục tồn tại dưới `~/.agents/skills`; problem `LOCAL EDITS` khi hash khác |
| plugin | `agents.claude.plugins` | key có trong `installed_plugins.json` |
| subagent | `global.subagents` trừ `exclude` | file có trong `~/.claude/agents`; `LOCAL EDITS` như ở Task 2 |
| mcp | `global.mcp` | Claude: `dyai::claude_mcp_current` không rỗng trong mọi config dir; các agent khác: tên server nằm dưới block key mà `dyai::setup_mcp_agents` ghi cho chúng |
| hook | `global.hooks` | gemini `AfterAgent` chứa `dyai-notify`; copilot `hooks/dyai.json` tồn tại; codex `hooks.Stop` đã được đặt |
| policy | `global.policy.permissions` | gemini `policies/dyai.toml`, codex `rules/dyai.rules` và khối `permission` của opencode tồn tại |

Mục hook SessionStart, được thêm vào danh sách hooks của matcher
`startup|resume|clear|compact` hiện có, với `"timeout": 5`. Stdout thường của
một hook SessionStart chỉ đi vào context của model, nên người dùng sẽ không
bao giờ thấy drift. Vì vậy hook bọc một báo cáo không rỗng trong JSON:
`systemMessage` hiển thị nó cho người dùng,
`hookSpecificOutput.additionalContext` giữ cho model được cập nhật. Một máy
sạch vẫn không in gì, và khi thiếu `dyai` hoặc `jq` thì không làm gì cả.
(Sửa 2026-10-26: phiên bản đầu in báo cáo ở dạng thô.)

Các test chạy với một PATH gồm các stub cộng với `jq` và `yq` được link từng
cái một, không bao giờ link cả thư mục của chúng: `yq` thường nằm trong
`~/.local/bin`, cạnh các CLI agent thật, vốn sẽ biến thành các dòng drift
trên máy của developer.

- [ ] **Bước 1: Viết các test đang fail:**
  - `@test "status is silent on an armed machine"`: chạy `dyai::install` với
    stub, rồi `dyai::status quiet`. Output rỗng và exit là 0.
  - `@test "status names a missing skill"`: xoá thư mục skill. Exit 1 và
    có dòng `claude skill alpha: missing`.
  - `@test "status names a locally edited subagent"`.
  - `@test "status skips agents that are not installed"`: không có `gemini`
    trên `PATH`, nên không có dòng gemini nào.
  - `@test "status quiet finishes under 2 seconds"`: đo thời gian lời gọi
    theo mili giây bằng `date +%s%N`. `SECONDS` đếm theo giây nguyên và để
    lọt gần 3 s.
  - `@test "the SessionStart drift hook shows drift to the user and stays quiet when clean"`
    trong `claude_settings.bats`: chạy lệnh hook đã render với một stub
    `dyai`. Drift rỗng thì không in gì; một dòng drift nằm trong
    `systemMessage`.
  - Cập nhật fixture settings của Claude và để `claude_settings.bats` fail,
    rồi pass.
- [ ] **Bước 2: Chạy.** Kỳ vọng: FAIL.
- [ ] **Bước 3: Triển khai** `status`, lệnh CLI và mục hook.
- [ ] **Bước 4: Chạy** `bats scripts/test/dyai.bats scripts/test/claude_settings.bats`,
  `dyshellint`, và `chezmoi execute-template --source . --file home/private_dot_claude/settings.json.tmpl | jq .`.
  Kỳ vọng: PASS và JSON hợp lệ.
- [ ] **Bước 5: Commit** `feat(dyai): report drift between config and agents at session start`.

### Task 5: Bảng enforcement

**Files:**
- Sửa: `scripts/lib/dyai.sh` (bảng dữ liệu cộng với `dyai::enforcement`)
- Sửa: `home/dot_local/bin/executable_dyai.tmpl` (lệnh `enforcement`)
- Sửa: `docs/dyai.md` (khối được sinh ra trong "Permissions in other agents")
- Test: `scripts/test/dyai.bats`

**Interfaces:**
- Cung cấp: `dyai::enforcement`. In ra một bảng Markdown, mỗi agent một dòng
  (claude, codex, gemini, opencode, copilot, agy, hermes). Các cột là
  `approval`, `shell rules`, `path rules`, `stop/input hooks`, `mcp`,
  `subagents`. Mỗi ô là một trong:
  - `M`: được ghi vào config của chính agent, và agent áp dụng nó;
  - `S`: chỉ đến được agent dưới dạng chỉ dẫn (`AGENTS.md`), nên chỉ có hiệu
    lực khi agent hợp tác;
  - `-`: không được chuyển sang.
  Một dòng chú giải theo sau bảng.

Bảng là một TSV heredoc `DYAI_ENFORCEMENT`, đặt trong `dyai.sh` ngay phía
trên `setup_policy`. Điền từng ô theo những gì hàm `setup_*` /
`permissions_*` tương ứng thực sự ghi ra, không theo tài liệu. Các ô đã biết
từ code hiện tại:
- copilot: `shell rules -`, `path rules -`, `approval -`;
- agy: `path rules -`, `stop/input hooks -`;
- opencode: `stop/input hooks -` (plugin hunk của nó không phải stop hook);
- `subagents` là `M` chỉ cho claude và codex, `-` cho các agent còn lại.

Mọi dòng `-` và `S` đều đến từ đoạn chỉ dẫn mà dyai render vào
`AGENTS.md`, nên nó là `S` ở bất cứ đâu agent đọc `AGENTS.md`.

`docs/dyai.md` được thêm
`<!-- dyai:enforcement:start -->…<!-- dyai:enforcement:end -->` chứa
output của lệnh.

- [ ] **Bước 1: Viết các test đang fail:**
  - `@test "enforcement marks copilot shell rules as not carried"`.
  - `@test "enforcement marks claude and codex subagents as mechanical"`.
  - `@test "docs enforcement block matches the command"`: trích khối nằm
    giữa các marker và so sánh với output của `dyai::enforcement`. Việc này
    giữ cho tài liệu khớp với bảng.
  - `@test "enforcement approval, shell and path cells match what the writers produce"`:
    bảng được điền bằng tay, nên chỉ riêng bước kiểm tra tài liệu không bắt
    được một bảng nói sai về code. Stub mọi agent, chạy `setup_policy` và
    `setup_permissions` trên một config có một probe shell rule và một probe
    path rule, rồi với mọi dòng không phải Claude, assert rằng probe của ô `M`
    có trong file của agent đó và probe của ô `S`/`-` thì không. Bỏ qua
    Claude: chezmoi render settings của nó, và `claude_settings.bats` đã bao
    phủ phần đó. Các cột hook, mcp và subagent đã được bao phủ bởi các test
    `setup_hooks`, `setup_mcp_agents` và `setup_subagents`.
- [ ] **Bước 2: Chạy.** Kỳ vọng: FAIL.
- [ ] **Bước 3: Triển khai** bảng và lệnh, rồi dán output vào giữa các
  marker.
- [ ] **Bước 4: Chạy** file bats và `dyshellint`. Kỳ vọng: PASS.
- [ ] **Bước 5: Commit** `docs(dyai): generate what each agent actually enforces`.

### Task 6: Hiển thị việc spawn subagent, review bảo mật độc lập

**Files:**
- Tạo: `home/private_dot_claude/hooks/executable_log-agent.sh`
- Sửa: `home/private_dot_claude/settings.json.tmpl` (PreToolUse `Agent`)
- Sửa: `home/.chezmoitemplates/ai/verification.md.tmpl`
- Test: `scripts/test/claude_hooks.bats`, `scripts/test/claude_settings.bats`
  cùng fixture của nó, `scripts/test/claude_rules.bats`

**Interfaces:**
- Cung cấp: `log-agent.sh`, viết theo contract của `log-skill.sh`. Nó
  ghi thêm
  `{ts, agent: .tool_input.subagent_type, model: .tool_input.model, description: .tool_input.description, cwd, session}`
  vào `${XDG_STATE_HOME:-~/.local/state}/claude/agent-usage.jsonl`, không in
  gì, và exit 0. Một `subagent_type` rỗng được ghi log là
  `general-purpose`, mặc định của harness.

Mục PreToolUse: matcher `Agent`, lệnh `bash ~/.claude/hooks/log-agent.sh`,
`"async": true`, đặt cạnh mục `Skill`.

Dòng rule thêm vào `verification.md.tmpl`, dưới dạng một bullet:
"Một thay đổi trên đường dẫn bảo mật (xử lý credential, permission, hook,
bất cứ thứ gì dưới `secrets/`) được review bởi một subagent mới, không phải
subagent đã viết ra nó. Một bản sửa lỗi bảo mật chỉ được coi là đã chứng minh
khi revert nó làm test của nó fail."

- [ ] **Bước 1: Viết các test đang fail** trong `claude_hooks.bats`:
  - `@test "log-agent records type and model"`: pipe
    `{"tool_input":{"subagent_type":"Explore","model":"haiku","description":"x"},"session_id":"s"}`
    và assert có một dòng JSONL với `agent=="Explore"` và `model=="haiku"`,
    stdout rỗng, exit 0.
  - `@test "log-agent never fails on garbage input"`: pipe `not json`. Exit 0,
    không có output, không file nào được ghi.
  - Cập nhật fixture settings.
- [ ] **Bước 2: Chạy.** Kỳ vọng: FAIL.
- [ ] **Bước 3: Triển khai** hook, mục settings và dòng rule.
- [ ] **Bước 4: Chạy** `bats scripts/test/claude_hooks.bats scripts/test/claude_settings.bats scripts/test/claude_rules.bats`,
  `dyshellint home/private_dot_claude/hooks/executable_log-agent.sh`, và
  render `verification.md.tmpl`. Kỳ vọng: PASS.
- [ ] **Bước 5: Commit** `feat(claude): log every subagent spawn`.

## Ngoài phạm vi (có nêu tên, không làm)

- Chặn một lần spawn không có quyết định định tuyến (ledger hook của Intent
  Loop). Nó trùng với `laya`; log trước, quyết định sau.
- Cài subagent cho Gemini, opencode và Copilot, hiện chưa có cái nào.
- Một subagent source thứ hai (wshobson/agents). Thêm nó dưới dạng một
  `include` có chọn lọc khi Task 2 đã bảo vệ chỉnh sửa cục bộ.
- Cập nhật theo content-hash với `--check` cho skill. Hiện `dyai` không bao
  giờ cập nhật một skill đã cài; các hash của Task 2 là nền tảng cho việc đó.
