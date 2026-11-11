// 부하 테스트 구간 보고서: 인스턴스별 CPU·메모리·크레딧, ALB 지표, Locust 한계 지점, 비용.
// bash deploy/aws.sh report <프로필> 이 START·END(유닉스 초)와 함께 실행한다. 결과: build/report-<프로필>-<시각>.md
//
// 비용은 두 가지로 낸다.
//  1) 추정: 실제로 켜져 있던 리소스 × 서울 리전 온디맨드 단가 × 테스트 시간 + 측정된 ALB LCU + T3 초과 크레딧 (바로 나옴)
//  2) 실제: Cost Explorer (Project 태그). 비용 할당 태그 활성화와 최대 24시간 지연이 있어 다음 날 다시 돌리면 채워진다.
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const CLIENT = process.env.CLIENT || "vet01";
const PROFILE = process.env.PROFILE || "stress";
const REGION = process.env.AWS_REGION || "ap-northeast-2";
const ROOT = process.env.ROOT || process.cwd();
const START = Number(process.env.START);
const END = Number(process.env.END);
const KRW = Number(process.env.KRW_PER_USD || 1400); // 환율 (원/달러). KRW_PER_USD=1380 처럼 바꿀 수 있다
let AWS = process.env.AWS || "aws";
const m = AWS.match(/^\/([a-zA-Z])\/(.*)$/); // Git Bash 경로(/c/...) → Windows 경로(C:/...)
if (m) AWS = `${m[1].toUpperCase()}:/${m[2]}`;

if (!START || !END || END <= START) {
  console.error("START/END 가 올바르지 않습니다");
  process.exit(1);
}
const BUILD = join(ROOT, "build");
mkdirSync(BUILD, { recursive: true });

function aws(args, { json = true, quiet = false } = {}) {
  try {
    const out = execFileSync(AWS, [...args, "--region", REGION, ...(json ? ["--output", "json"] : [])], {
      encoding: "utf8", maxBuffer: 64 * 1024 * 1024, windowsHide: true, stdio: ["ignore", "pipe", "pipe"],
    });
    return json ? JSON.parse(out || "null") : out;
  } catch (e) {
    if (!quiet) console.error(`[aws ${args.slice(0, 2).join(" ")}] ${String(e.stderr || e.message).trim().split("\n").pop()}`);
    return null;
  }
}

// ── 서울(ap-northeast-2) 온디맨드 단가 (USD). 문서 11장 표와 같은 값 ──
const PRICE = {
  ec2: { "t4g.nano": 0.0052, "t3.nano": 0.0065, "t4g.micro": 0.0104, "t4g.small": 0.0208, "t3.micro": 0.013, "t3.small": 0.026, "t3.medium": 0.052, "t3.large": 0.104, "m7i.large": 0.1239 },
  alb: 0.0225,             // ALB 1개 시간당
  lcu: 0.008,              // LCU 시간당
  nat: 0.059,              // NAT Gateway 시간당 (+ GB당 0.059, 테스트 트래픽은 NAT를 지나지 않음)
  rds: { "db.t3.micro": 0.026, "db.t3.small": 0.052, "db.t3.medium": 0.104 }, // 단일 AZ. Multi-AZ 는 2배
  rdsStorageGbMonth: 0.131, // gp3, 단일 AZ. Multi-AZ 는 2배
  cache: { "cache.t3.micro": 0.025, "cache.t3.small": 0.05 },
  ipv4: 0.005,             // 공인 IPv4 1개 시간당
  ebsGbMonth: 0.0912,      // gp3
  surplusPerVcpuHour: 0.05, // T3 unlimited 초과 크레딧 (Linux). 크레딧 1 = vCPU 1분
  cwAlarmMonth: 0.1, cwDashboardMonth: 3, cwMetricMonth: 0.3, secretMonth: 0.4,
};
const HOURS_MONTH = 730;

// ── 스택 출력 ──
function outputs(stack) {
  const r = aws(["cloudformation", "describe-stacks", "--stack-name", `${CLIENT}-${stack}`], { quiet: true });
  const o = {};
  for (const x of r?.Stacks?.[0]?.Outputs || []) o[x.OutputKey] = x.OutputValue;
  return o;
}
const was = outputs("was"), web = outputs("web");
const app = [
  { label: "web-a", id: web.WebInstanceA }, { label: "web-c", id: web.WebInstanceC },
  { label: "was-a", id: was.WasInstanceA }, { label: "was-c", id: was.WasInstanceC },
  { label: "locust", id: outputs("loadgen").LocustInstanceId },   // 부하 생성기가 먼저 한계에 닿지 않았는지 확인용
].filter((x) => x.id);
const webTgFull = (web.WebTgArn || "").split(":").pop();   // targetgroup/vet01-tg-web/...
const extAlb = web.ExternalAlbFullName, intAlb = was.InternalAlbFullName;

// ── 켜져 있는 인스턴스 (Project 태그, 없으면 이름 접두어) ──
let inst = aws(["ec2", "describe-instances", "--filters", `Name=tag:Project,Values=${CLIENT}`, "Name=instance-state-name,Values=running"]);
let list = (inst?.Reservations || []).flatMap((r) => r.Instances);
if (!list.length) {
  inst = aws(["ec2", "describe-instances", "--filters", `Name=tag:Name,Values=${CLIENT}-*`, "Name=instance-state-name,Values=running"]);
  list = (inst?.Reservations || []).flatMap((r) => r.Instances);
}
const instances = list.map((i) => ({
  id: i.InstanceId, type: i.InstanceType,
  name: (i.Tags || []).find((t) => t.Key === "Name")?.Value || i.InstanceId,
  vcpu: (i.CpuOptions?.CoreCount || 1) * (i.CpuOptions?.ThreadsPerCore || 1),
  ebsGb: 8,
}));
for (const a of app) a.type = instances.find((i) => i.id === a.id)?.type || "?";

const db = aws(["rds", "describe-db-instances", "--db-instance-identifier", `${CLIENT}-db`], { quiet: true })?.DBInstances?.[0];
const cache = aws(["elasticache", "describe-replication-groups", "--replication-group-id", `${CLIENT}-cache`], { quiet: true })?.ReplicationGroups?.[0];
const natCount = (aws(["ec2", "describe-nat-gateways", "--filter", `Name=tag:Project,Values=${CLIENT}`, "Name=state,Values=available"], { quiet: true })?.NatGateways || []).length
  || (aws(["ec2", "describe-nat-gateways", "--filter", "Name=state,Values=available", `Name=vpc-id,Values=${outputs("network").VpcId || "none"}`], { quiet: true })?.NatGateways || []).length;
const eipCount = (aws(["ec2", "describe-addresses", "--filters", `Name=tag:Project,Values=${CLIENT}`], { quiet: true })?.Addresses || []).length;
const albCount = [extAlb, intAlb].filter(Boolean).length;

// ── CloudWatch 지표 (1분) ──
const iso = (s) => new Date(s * 1000).toISOString();
const q = [];
const add = (id, ns, name, dims, stat, period = 60, label = id) =>
  q.push({ Id: id, Label: label, ReturnData: true, MetricStat: { Metric: { Namespace: ns, MetricName: name, Dimensions: dims }, Period: period, Stat: stat } });
app.forEach((a, n) => {
  const d = [{ Name: "InstanceId", Value: a.id }];
  add(`cpu${n}`, "AWS/EC2", "CPUUtilization", d, "Average");
  add(`cpumax${n}`, "AWS/EC2", "CPUUtilization", d, "Maximum");
  add(`mem${n}`, "CWAgent", "mem_used_percent", d, "Maximum");
  add(`surplus${n}`, "AWS/EC2", "CPUSurplusCreditsCharged", d, "Sum", 300);
  add(`balance${n}`, "AWS/EC2", "CPUCreditBalance", d, "Minimum", 300);
});
if (extAlb) {
  const d = [{ Name: "LoadBalancer", Value: extAlb }];
  add("req", "AWS/ApplicationELB", "RequestCount", d, "Sum");
  add("t5xx", "AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", d, "Sum");
  add("e5xx", "AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", d, "Sum");
  add("p95", "AWS/ApplicationELB", "TargetResponseTime", d, "p95");
  add("lcuext", "AWS/ApplicationELB", "ConsumedLCUs", d, "Average");
  if (webTgFull) {
    const t = [...d, { Name: "TargetGroup", Value: webTgFull }];
    add("webunhealthy", "AWS/ApplicationELB", "UnHealthyHostCount", t, "Maximum");
    add("webhealthy", "AWS/ApplicationELB", "HealthyHostCount", t, "Minimum");
    add("webreqpt", "AWS/ApplicationELB", "RequestCountPerTarget", t, "Sum");
  }
}
if (intAlb) {
  const d = [{ Name: "LoadBalancer", Value: intAlb }];
  add("p95int", "AWS/ApplicationELB", "TargetResponseTime", d, "p95");
  add("lcuint", "AWS/ApplicationELB", "ConsumedLCUs", d, "Average");
}
add("dbcpu", "AWS/RDS", "CPUUtilization", [{ Name: "DBInstanceIdentifier", Value: `${CLIENT}-db` }], "Average");
add("dbconn", "AWS/RDS", "DatabaseConnections", [{ Name: "DBInstanceIdentifier", Value: `${CLIENT}-db` }], "Maximum");

const series = {};
const qfile = join(BUILD, "report-queries.json");
writeFileSync(qfile, JSON.stringify(q));
let token = null;
do {
  const r = aws(["cloudwatch", "get-metric-data", "--metric-data-queries", `file://${qfile}`,
    "--start-time", iso(START), "--end-time", iso(END), "--scan-by", "TimestampAscending",
    ...(token ? ["--next-token", token] : [])]);
  if (!r) break;
  for (const res of r.MetricDataResults) {
    const s = (series[res.Id] ||= new Map());
    res.Timestamps.forEach((t, i) => s.set(t, res.Values[i]));
  }
  token = r.NextToken;
} while (token);

const vals = (id) => [...(series[id]?.values() || [])];
const avg = (a) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : null);
const max = (a) => (a.length ? Math.max(...a) : null);
const min = (a) => (a.length ? Math.min(...a) : null);
const sum = (a) => a.reduce((x, y) => x + y, 0);
const f = (v, d = 1) => (v == null ? "-" : v.toFixed(d));
const usd = (v) => `$${v.toFixed(4)}`;
const won = (v) => `${Math.round(v * KRW).toLocaleString("ko-KR")}원`;

// ── 비용 추정 ──
const hours = (END - START) / 3600;
const rows = []; // [항목, 수량, 시간당 USD, 구간 USD]
const line = (name, qty, hourly, extra = 0) => rows.push([name, qty, hourly, hourly * hours + extra]);
const byType = {};
for (const i of instances) (byType[i.type] ||= []).push(i.name);
for (const [t, names] of Object.entries(byType)) {
  const p = PRICE.ec2[t];
  line(`EC2 ${t} (${names.sort().join(", ")})`, names.length, (p ?? 0) * names.length);
  if (p == null) console.error(`단가 없음: ${t} — PRICE.ec2 에 추가하세요`);
}
const ebsGb = instances.reduce((s, i) => s + i.ebsGb, 0);
line("EBS gp3 (루트 볼륨)", `${ebsGb}GB`, (ebsGb * PRICE.ebsGbMonth) / HOURS_MONTH);
const lcuExt = avg(vals("lcuext")) || 0, lcuInt = avg(vals("lcuint")) || 0;
line("ALB (외부·내부)", albCount, PRICE.alb * albCount);
rows.push([`ALB LCU (측정 평균 외부 ${f(lcuExt, 2)} · 내부 ${f(lcuInt, 2)})`, "-", (lcuExt + lcuInt) * PRICE.lcu, (lcuExt + lcuInt) * PRICE.lcu * hours]);
line("NAT Gateway", natCount, PRICE.nat * natCount);
if (db) {
  const base = PRICE.rds[db.DBInstanceClass] ?? 0, k = db.MultiAZ ? 2 : 1;
  line(`RDS ${db.DBInstanceClass} ${db.MultiAZ ? "Multi-AZ" : "단일 AZ"}`, 1, base * k);
  line(`RDS 스토리지 ${db.AllocatedStorage}GB`, "-", (db.AllocatedStorage * PRICE.rdsStorageGbMonth * k) / HOURS_MONTH);
}
if (cache) {
  const nodes = cache.MemberClusters?.length || 1;
  line(`ElastiCache ${cache.CacheNodeType}`, nodes, (PRICE.cache[cache.CacheNodeType] ?? 0) * nodes);
}
const ipv4 = (extAlb ? 2 : 0) + natCount + eipCount; // 외부 ALB는 AZ마다 1개
line("공인 IPv4 (외부 ALB 2 + NAT + EIP)", ipv4, PRICE.ipv4 * ipv4);
const alarmCount = (aws(["cloudwatch", "describe-alarms", "--alarm-name-prefix", `${CLIENT}-`], { quiet: true })?.MetricAlarms || []).length;
const cwMonth = alarmCount * PRICE.cwAlarmMonth + PRICE.cwDashboardMonth
  + app.length * 7 * PRICE.cwMetricMonth   // 세부 모니터링(1분) EC2 기본 지표 약 7개
  + app.length * 2 * PRICE.cwMetricMonth   // 에이전트 mem·disk
  + 3 * PRICE.secretMonth;                 // Secrets Manager 3개
line(`모니터링 (경보 ${alarmCount}, 대시보드 1, 세부·에이전트 지표, 비밀 3)`, "-", cwMonth / HOURS_MONTH);
const credits = app.map((a, n) => ({ ...a, surplus: sum(vals(`surplus${n}`)) }));
const surplusTotal = sum(credits.map((c) => c.surplus));
const surplusUsd = (surplusTotal / 60) * PRICE.surplusPerVcpuHour;
rows.push([`T3 초과 크레딧 (과부하로 기준 성능 초과, 총 ${f(surplusTotal, 1)} 크레딧)`, "-", 0, surplusUsd]);

const hourlyTotal = rows.reduce((s, r) => s + r[2], 0);
const windowTotal = rows.reduce((s, r) => s + r[3], 0);
const ec2Window = rows.filter((r) => r[0].startsWith("EC2") || r[0].startsWith("T3")).reduce((s, r) => s + r[3], 0);

// ── Cost Explorer (실제 청구, 선택) ──
const day = (s) => new Date(s * 1000).toISOString().slice(0, 10);
const ceEnd = day(END + 86400);
const filt = join(BUILD, "report-ce-filter.json");
writeFileSync(filt, JSON.stringify({ Tags: { Key: "Project", Values: [CLIENT] } }));
const ce = aws(["ce", "get-cost-and-usage", "--time-period", `Start=${day(START)},End=${ceEnd}`, "--granularity", "DAILY",
  "--metrics", "UnblendedCost", "--filter", `file://${filt}`, "--group-by", "Type=DIMENSION,Key=SERVICE"], { quiet: true });

// ── Locust 요약 ──
const sumFile = join(BUILD, `loadtest-${PROFILE}-summary.txt`);
function decode(buf) { // Windows aws.exe 는 SSM 출력을 CP949로 내보낸다. UTF-8 이 아니면 CP949(EUC-KR)로 읽는다
  try { return new TextDecoder("utf-8", { fatal: true }).decode(buf); } catch { return new TextDecoder("euc-kr").decode(buf); }
}
const locust = existsSync(sumFile) ? decode(readFileSync(sumFile)).replace(/\r/g, "") : "";
const limitLine = (locust.match(/^LIMIT: .*$/m) || ["LIMIT: (Locust 요약 없음 — bash deploy/aws.sh loadstatus " + PROFILE + ")"])[0];

// ── 보고서 ──
const kst = (s) => new Date(s * 1000 + 9 * 3600 * 1000).toISOString().replace("T", " ").slice(0, 16);
const L = [];
L.push(`# 부하 테스트 보고서 — ${PROFILE} (오토스케일링 없음: WEB ${app.filter((a) => a.label.startsWith("web")).length} · WAS ${app.filter((a) => a.label.startsWith("was")).length} 고정)`);
L.push("");
L.push(`- 구간: ${kst(START)} ~ ${kst(END)} KST (${(hours * 60).toFixed(0)}분)`);
const waitFile = join(BUILD, `loadtest-${PROFILE}.wait`);
if (existsSync(waitFile)) L.push(`- Locust 대기 시간 배율: ${readFileSync(waitFile, "utf8").trim()}`);
L.push(`- 한계 지점: ${limitLine.replace(/^LIMIT: /, "")}`);
L.push(`- 외부 ALB 요청 ${Math.round(sum(vals("req"))).toLocaleString()}건, 대상 5xx ${Math.round(sum(vals("t5xx")))}건, ALB 5xx ${Math.round(sum(vals("e5xx")))}건, 응답 시간 p95 최대 ${f((max(vals("p95")) ?? 0) * 1000, 0)}ms (WAS p95 최대 ${f((max(vals("p95int")) ?? 0) * 1000, 0)}ms)`);
L.push(`- WEB 대상: 정상 최소 ${f(min(vals("webhealthy")), 0)}대, 비정상 최대 ${f(max(vals("webunhealthy")), 0)}대, 대상당 요청 최대 ${f(max(vals("webreqpt")), 0)}건/분`);
L.push(`- RDS CPU 평균 ${f(avg(vals("dbcpu")))}% · 최대 ${f(max(vals("dbcpu")))}%, DB 연결 최대 ${f(max(vals("dbconn")), 0)}`);
L.push("");
L.push("## 인스턴스별 부하");
L.push("");
L.push("| 인스턴스 | ID | 유형 | CPU 평균 % | CPU 최대 % | 메모리 최대 % | 크레딧 최저 잔량 | 초과 과금 크레딧 |");
L.push("|---|---|---|---:|---:|---:|---:|---:|");
app.forEach((a, n) => L.push(`| ${a.label} | ${a.id} | ${a.type} | ${f(avg(vals(`cpu${n}`)))} | ${f(max(vals(`cpumax${n}`)))} | ${f(max(vals(`mem${n}`)))} | ${f(min(vals(`balance${n}`)))} | ${f(credits[n].surplus)} |`));
L.push("");
L.push("## 비용");
L.push("");
L.push(`환율 ${KRW}원/달러 (KRW_PER_USD 로 변경). 단가는 서울 리전 온디맨드, 세금 별도.`);
L.push("");
L.push("| 항목 | 수량 | 시간당 | 테스트 구간 |");
L.push("|---|---:|---:|---:|");
for (const r of rows) L.push(`| ${r[0]} | ${r[1]} | ${usd(r[2])} | ${usd(r[3])} (${won(r[3])}) |`);
L.push(`| **합계** | | **${usd(hourlyTotal)}** (${won(hourlyTotal)}) | **${usd(windowTotal)}** (${won(windowTotal)}) |`);
L.push("");
L.push(`- 이 중 EC2(인스턴스 + 초과 크레딧): ${usd(ec2Window)} (${won(ec2Window)})`);
L.push(`- 이 구성을 켜 둘 때: 하루 ${usd(hourlyTotal * 24)} (${won(hourlyTotal * 24)}), 한 달(730시간) ${usd(hourlyTotal * HOURS_MONTH)} (${won(hourlyTotal * HOURS_MONTH)}) — LCU는 이번 측정 평균 기준`);
L.push(`- 빠진 것: 데이터 전송(Locust→ALB 응답, GB당 약 0.01달러), CloudWatch Logs 수집량, S3 요청. 짧은 테스트에서는 몇 원 수준이다.`);
L.push("");
L.push("### Cost Explorer 실제 청구 (Project 태그)");
L.push("");
if (ce?.ResultsByTime) {
  let tot = 0;
  L.push("| 날짜 | 서비스 | USD |");
  L.push("|---|---|---:|");
  for (const t of ce.ResultsByTime) for (const g of t.Groups || []) {
    const v = Number(g.Metrics.UnblendedCost.Amount); if (v < 0.00005) continue;
    tot += v; L.push(`| ${t.TimePeriod.Start} | ${g.Keys[0]} | ${v.toFixed(4)} |`);
  }
  L.push(`| | **합계** | **${tot.toFixed(4)}** (${won(tot)}) |`);
  if (tot === 0) L.push("\n아직 0원입니다. 비용 할당 태그(Project)가 활성화되지 않았거나 집계 지연(최대 24시간)입니다. 내일 `bash deploy/aws.sh report " + PROFILE + "` 을 다시 실행하세요.");
} else {
  L.push("조회하지 못했습니다(Cost Explorer 권한 없음 또는 미활성). 위의 추정값을 쓰거나, 관리자에게 Billing 콘솔에서 Project 태그별 비용을 요청하세요.");
}
L.push("");
L.push("## 분 단위 추이");
L.push("");
L.push(`| 시각(KST) | 요청/분 | p95 ms | 5xx | WEB 정상/비정상 | ${app.map((a) => `${a.label} CPU%`).join(" | ")} | RDS CPU% |`);
L.push(`|---|---:|---:|---:|---:|${app.map(() => "---:").join("|")}|---:|`);
const times = [...new Set(Object.values(series).flatMap((s) => [...s.keys()]))].filter((t) => series.cpu0?.has(t) || series.req?.has(t)).sort();
for (const t of times) {
  const g = (id) => series[id]?.get(t);
  const s = Date.parse(t) / 1000;
  L.push(`| ${kst(s).slice(11)} | ${f(g("req"), 0)} | ${f(g("p95") == null ? null : g("p95") * 1000, 0)} | ${f((g("t5xx") ?? 0) + (g("e5xx") ?? 0), 0)} | ${f(g("webhealthy"), 0)}/${f(g("webunhealthy"), 0)} | ${app.map((a, n) => f(g(`cpu${n}`))).join(" | ")} | ${f(g("dbcpu"))} |`);
}
if (locust) {
  L.push("");
  L.push("## Locust 요약");
  L.push("");
  L.push("```");
  L.push(locust.trim());
  L.push("```");
}

const stamp = kst(Math.floor(Date.now() / 1000)).replace(/[-: ]/g, "").slice(0, 12);
const file = join(BUILD, `report-${PROFILE}-${stamp}.md`);
writeFileSync(file, L.join("\n") + "\n", "utf8");
console.log(L.join("\n"));
console.log(`\n저장: ${file}`);
