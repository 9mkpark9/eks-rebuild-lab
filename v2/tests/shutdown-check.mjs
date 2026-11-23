// 종료 확인 — 요청을 계속 보내는 동안 서비스를 내리고, "처리 중에 끊긴 요청"이 있었는지 센다.
// 서비스의 포트는 밖으로 열려 있지 않으므로 같은 도커 네트워크 안의 컨테이너에서 실행한다:
//
//   docker run --rm -i --network v2_default node:22-alpine node --input-type=module - http://auth:8080 10 \
//       < v2/tests/shutdown-check.mjs &
//   sleep 4; docker stop v2-auth-1; wait
//
// 요청마다 새 연결을 쓴다 (연결을 재사용하면 닫히는 연결에 요청이 실려 결과가 흐려진다).
import http from 'node:http';

const [target, seconds = '10'] = process.argv.slice(2);
const u = new URL(target);
const body = JSON.stringify({ loginId: 'owner270', password: 'test-only' });
const WORKERS = 20;
const tally = {};
const t0 = Date.now();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function one() {
  return new Promise((resolve) => {
    const req = http.request({
      host: u.hostname, port: u.port, path: '/api/auth/login', method: 'POST', agent: false,
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body), Connection: 'close' },
    }, (res) => {
      res.resume();
      res.on('end', () => resolve(`응답 ${res.statusCode}`));
      res.on('error', () => resolve('처리 중 끊김'));
    });
    // 연결된 뒤 응답 없이 끊기면 ECONNRESET(socket hang up). 그 밖의 오류는 서비스가 이미 내려가 접속하지 못한 것이다.
    req.on('error', (e) => resolve(e.code === 'ECONNRESET' || e.code === 'EPIPE' ? '처리 중 끊김' : '내려간 뒤 접속 실패'));
    req.end(body);
  });
}

async function worker() {
  while (Date.now() - t0 < Number(seconds) * 1000) {
    const r = await one();
    tally[r] = (tally[r] ?? 0) + 1;
    if (r === '내려간 뒤 접속 실패') await sleep(100);
  }
}

await Promise.all(Array.from({ length: WORKERS }, worker));
for (const [k, v] of Object.entries(tally).sort()) console.log(`  ${k}: ${v}건`);
console.log(`  → 처리 중 끊긴 요청 ${tally['처리 중 끊김'] ?? 0}건`);
